import CoreGraphics
import Foundation
import simd

/// The small, replayable portion of a Nearby Interaction direction sample
/// that the matcher needs. Raw NINearbyObject values stay at the discovery
/// boundary so the matching policy remains deterministic and testable.
struct SpatialDirectionalMeasurement: Equatable {
  let direction: SIMD3<Float>?
  let horizontalAngle: Float?
  let measuredAt: CFTimeInterval

  /// A direction ray in the local camera/device coordinate system. A
  /// horizontal angle is converted only when NI did not provide the richer
  /// vector measurement.
  var directionVector: SIMD3<Float>? {
    if let direction,
      direction.x.isFinite,
      direction.y.isFinite,
      direction.z.isFinite,
      simd_length(direction) > 0.001
    {
      return direction
    }

    guard let horizontalAngle, horizontalAngle.isFinite else {
      return nil
    }

    return SIMD3<Float>(
      sin(horizontalAngle),
      0,
      -cos(horizontalAngle)
    )
  }

  var bearingRadians: Double? {
    guard let directionVector else {
      return nil
    }

    // Nearby Interaction's local forward direction is -Z. The horizontal
    // bearing is measured clockwise from the device's forward ray.
    return SpatialDirectionalAssociationPolicy.normalizedAngle(
      atan2(Double(directionVector.x), Double(-directionVector.z))
    )
  }

  func isFresh(
    at now: CFTimeInterval,
    maximumAge: CFTimeInterval = SpatialMeasurementTuning.newMatchMaximumDirectionAge
  ) -> Bool {
    guard measuredAt.isFinite, now.isFinite else {
      return false
    }

    return measuredAt <= now
      && now - measuredAt <= maximumAge
      && directionVector != nil
  }
}

enum SpatialDirectionalViewportRelation: String, Equatable {
  case unavailable = "viewport-unavailable"
  case inside = "viewport-inside"
  case nearEdge = "viewport-near-edge"
  case outside = "viewport-outside"
  case behind = "viewport-behind"

  var isInsideVisibleViewport: Bool {
    self == .inside
  }

  /// Near-edge samples are intentionally not identity-authoritative. They
  /// differ from a clear contradiction only so a continuously tracked card
  /// can survive a small amount of projection noise.
  var blocksNewIdentity: Bool {
    self != .inside
  }

  var isHardContradiction: Bool {
    self == .outside || self == .behind
  }
}

struct SpatialDirectionalViewportProjection: Equatable {
  let relation: SpatialDirectionalViewportRelation
  let point: CGPoint?
}

enum SpatialDirectionalAssociationReason: String, Equatable {
  case unavailable = "direction-unavailable"
  case stale = "direction-stale"
  case projectionUnavailable = "direction-projection-unavailable"
  case insideViewport = "direction-inside-viewport"
  case nearViewportEdge = "direction-near-viewport-edge"
  case outsideViewport = "direction-outside-viewport"
  case behindCamera = "direction-behind-camera"
  case bodyAligned = "direction-body-aligned"
  case bodyMismatch = "direction-body-mismatch"
}

struct SpatialDirectionalAssociationResult: Equatable {
  let reason: SpatialDirectionalAssociationReason
  let peerBearingRadians: Double?
  let bodyBearingRadians: Double?
  let angularDifferenceRadians: Double?
  let alignmentScore: Double
  let peerViewportRelation: SpatialDirectionalViewportRelation?

  var hasFreshDirectionalEvidence: Bool {
    peerBearingRadians != nil
      && reason != .unavailable
      && reason != .stale
      && reason != .projectionUnavailable
  }

  var hasViewportAuthority: Bool {
    peerViewportRelation?.isInsideVisibleViewport == true
  }

  var blocksNewIdentity: Bool {
    if let peerViewportRelation {
      return peerViewportRelation.blocksNewIdentity
    }

    return reason == .bodyMismatch
  }

  var hasHardContradiction: Bool {
    peerViewportRelation?.isHardContradiction == true
      || reason == .outsideViewport
      || reason == .behindCamera
      || reason == .bodyMismatch
  }
}

/// Pure directional and camera-viewport policy shared by matching and
/// camera-interest scheduling. The production path uses the ARKit projection
/// matrix captured for the current viewport. A missing projection matrix is
/// treated as insufficient for a new identity rather than replaced by a
/// guessed field of view.
enum SpatialDirectionalAssociationPolicy {
  static func evaluate(
    peerBearingRadians: Double?,
    bodyBearingRadians: Double?,
    measurementAge: CFTimeInterval?,
    now _: CFTimeInterval,
    peerViewportProjection: SpatialDirectionalViewportProjection? = nil
  ) -> SpatialDirectionalAssociationResult {
    guard peerBearingRadians != nil || peerViewportProjection != nil else {
      return result(reason: .unavailable)
    }

    guard let measurementAge,
      measurementAge.isFinite,
      measurementAge >= 0,
      measurementAge <= SpatialMeasurementTuning.newMatchMaximumDirectionAge
    else {
      return result(
        reason: .stale,
        peerBearingRadians: peerBearingRadians,
        peerViewportRelation: peerViewportProjection?.relation
      )
    }

    let projection = peerViewportProjection

    if let projection {
      switch projection.relation {
      case .unavailable:
        return result(
          reason: .projectionUnavailable,
          peerBearingRadians: peerBearingRadians,
          peerViewportRelation: projection.relation
        )
      case .behind:
        return result(
          reason: .behindCamera,
          peerBearingRadians: peerBearingRadians,
          peerViewportRelation: projection.relation
        )
      case .outside:
        return result(
          reason: .outsideViewport,
          peerBearingRadians: peerBearingRadians,
          peerViewportRelation: projection.relation
        )
      case .nearEdge:
        return result(
          reason: .nearViewportEdge,
          peerBearingRadians: peerBearingRadians,
          peerViewportRelation: projection.relation
        )
      case .inside:
        break
      }
    }

    guard let peerBearingRadians else {
      return result(
        reason: .projectionUnavailable,
        peerViewportRelation: projection?.relation
      )
    }

    guard let bodyBearingRadians else {
      return result(
        reason: .insideViewport,
        peerBearingRadians: peerBearingRadians,
        alignmentScore: 0.5,
        peerViewportRelation: projection?.relation
      )
    }

    let difference = angularDifference(
      peerBearingRadians,
      bodyBearingRadians
    )
    let alignmentScore = max(
      0,
      min(
        1,
        exp(
          -0.5
            * pow(
              difference / SpatialMeasurementTuning.directionalAlignmentTolerance,
              2
            )
        )
      )
    )
    if difference > SpatialMeasurementTuning.directionalBodyMismatchTolerance {
      return result(
        reason: .bodyMismatch,
        peerBearingRadians: peerBearingRadians,
        bodyBearingRadians: bodyBearingRadians,
        angularDifferenceRadians: difference,
        alignmentScore: alignmentScore,
        peerViewportRelation: projection?.relation
      )
    }

    return result(
      reason: .bodyAligned,
      peerBearingRadians: peerBearingRadians,
      bodyBearingRadians: bodyBearingRadians,
      angularDifferenceRadians: difference,
      alignmentScore: alignmentScore,
      peerViewportRelation: projection?.relation
    )
  }

  /// Projects a world-space peer using the same camera pose and viewport
  /// projection used by ARKit. This is the authoritative camera gate.
  static func viewportProjection(
    for worldPosition: SIMD3<Float>,
    cameraTransform: simd_float4x4,
    projectionMatrix: simd_float4x4?,
    viewportSize: CGSize
  ) -> SpatialDirectionalViewportProjection {
    guard let projectionMatrix else {
      return SpatialDirectionalViewportProjection(
        relation: .unavailable,
        point: nil
      )
    }

    let cameraSpacePoint = simd_inverse(cameraTransform)
      * SIMD4<Float>(worldPosition, 1)
    return viewportProjection(
      forCameraSpacePoint: cameraSpacePoint,
      projectionMatrix: projectionMatrix,
      viewportSize: viewportSize
    )
  }

  /// Projects a direct NI direction ray. A vector is projected with w = 0,
  /// preserving its ray semantics and avoiding any invented peer distance.
  static func viewportProjection(
    for measurement: SpatialDirectionalMeasurement,
    projectionMatrix: simd_float4x4?,
    viewportSize: CGSize
  ) -> SpatialDirectionalViewportProjection {
    guard let direction = measurement.directionVector else {
      return SpatialDirectionalViewportProjection(
        relation: .unavailable,
        point: nil
      )
    }

    guard let projectionMatrix else {
      return SpatialDirectionalViewportProjection(
        relation: .unavailable,
        point: nil
      )
    }

    let cameraSpaceDirection = SIMD4<Float>(direction, 0)
    return viewportProjection(
      forCameraSpacePoint: cameraSpaceDirection,
      projectionMatrix: projectionMatrix,
      viewportSize: viewportSize,
      isDirection: true
    )
  }

  /// Classifies a projected pixel directly. This keeps edge behavior
  /// deterministic and makes viewport-boundary tests independent of ARKit.
  static func viewportProjection(
    for screenPoint: CGPoint,
    viewportSize: CGSize
  ) -> SpatialDirectionalViewportProjection {
    guard viewportSize.width > 0,
      viewportSize.height > 0,
      screenPoint.x.isFinite,
      screenPoint.y.isFinite
    else {
      return SpatialDirectionalViewportProjection(
        relation: .unavailable,
        point: nil
      )
    }

    return SpatialDirectionalViewportProjection(
      relation: viewportRelation(
        for: screenPoint,
        viewportSize: viewportSize
      ),
      point: screenPoint
    )
  }

  static func bearing(
    for worldPosition: SIMD3<Float>,
    cameraTransform: simd_float4x4
  ) -> Double? {
    let cameraSpace = simd_inverse(cameraTransform)
      * SIMD4<Float>(worldPosition, 1)
    guard cameraSpace.x.isFinite,
      cameraSpace.y.isFinite,
      cameraSpace.z.isFinite,
      abs(cameraSpace.x) > 0.001 || abs(cameraSpace.z) > 0.001
    else {
      return nil
    }

    return normalizedAngle(
      atan2(Double(cameraSpace.x), Double(-cameraSpace.z))
    )
  }

  static func bearing(
    for screenPoint: CGPoint,
    viewportSize: CGSize,
    cameraHorizontalProjectionScale: Float?
  ) -> Double? {
    guard viewportSize.width > 0,
      screenPoint.x.isFinite,
      viewportSize.width.isFinite,
      let cameraHorizontalProjectionScale,
      cameraHorizontalProjectionScale.isFinite,
      cameraHorizontalProjectionScale > 0
    else {
      return nil
    }

    let normalizedX = (screenPoint.x / viewportSize.width) * 2 - 1
    let halfFOV = atan(1 / Double(cameraHorizontalProjectionScale))
    return normalizedAngle(
      atan(normalizedX * tan(halfFOV))
    )
  }

  static func angularDifference(_ lhs: Double, _ rhs: Double) -> Double {
    abs(normalizedAngle(lhs - rhs))
  }

  static func normalizedAngle(_ angle: Double) -> Double {
    guard angle.isFinite else {
      return 0
    }

    var normalized = angle
    while normalized > .pi {
      normalized -= 2 * .pi
    }
    while normalized < -.pi {
      normalized += 2 * .pi
    }
    return normalized
  }

  private static func viewportProjection(
    forCameraSpacePoint cameraSpacePoint: SIMD4<Float>,
    projectionMatrix: simd_float4x4,
    viewportSize: CGSize,
    isDirection: Bool = false
  ) -> SpatialDirectionalViewportProjection {
    guard viewportSize.width > 0,
      viewportSize.height > 0,
      cameraSpacePoint.x.isFinite,
      cameraSpacePoint.y.isFinite,
      cameraSpacePoint.z.isFinite,
      cameraSpacePoint.w.isFinite
    else {
      return SpatialDirectionalViewportProjection(
        relation: .unavailable,
        point: nil
      )
    }

    if isDirection {
      if cameraSpacePoint.z > 0.001 {
        return SpatialDirectionalViewportProjection(
          relation: .behind,
          point: nil
        )
      }
      if abs(cameraSpacePoint.z) <= 0.001 {
        return SpatialDirectionalViewportProjection(
          relation: .outside,
          point: nil
        )
      }
    } else if cameraSpacePoint.z > 0.001 {
      return SpatialDirectionalViewportProjection(
        relation: .behind,
        point: nil
      )
    } else if abs(cameraSpacePoint.z) <= 0.001 {
      return SpatialDirectionalViewportProjection(
        relation: .outside,
        point: nil
      )
    }

    let clipPoint = projectionMatrix * cameraSpacePoint
    guard clipPoint.x.isFinite,
      clipPoint.y.isFinite,
      clipPoint.z.isFinite,
      clipPoint.w.isFinite,
      clipPoint.w > 0.0001
    else {
      return SpatialDirectionalViewportProjection(
        relation: isDirection ? .outside : .unavailable,
        point: nil
      )
    }

    let ndcX = clipPoint.x / clipPoint.w
    let ndcY = clipPoint.y / clipPoint.w
    guard ndcX.isFinite, ndcY.isFinite else {
      return SpatialDirectionalViewportProjection(
        relation: .unavailable,
        point: nil
      )
    }

    let point = CGPoint(
      x: CGFloat((Double(ndcX) + 1) * 0.5) * viewportSize.width,
      y: CGFloat((1 - Double(ndcY)) * 0.5) * viewportSize.height
    )
    return SpatialDirectionalViewportProjection(
      relation: viewportRelation(
        for: point,
        viewportSize: viewportSize
      ),
      point: point
    )
  }

  private static func viewportRelation(
    for point: CGPoint,
    viewportSize: CGSize
  ) -> SpatialDirectionalViewportRelation {
    let normalizedX = (point.x / viewportSize.width) * 2 - 1
    let normalizedY = (point.y / viewportSize.height) * 2 - 1
    return viewportRelation(
      forNormalizedX: normalizedX,
      normalizedY: normalizedY
    )
  }

  private static func viewportRelation(
    forNormalizedX normalizedX: Double,
    normalizedY: Double
  ) -> SpatialDirectionalViewportRelation {
    let tolerance = Double(
      SpatialMeasurementTuning.directionalViewportEdgeToleranceFraction * 2
    )
    let outsideX = max(0, abs(normalizedX) - 1)
    let outsideY = max(0, abs(normalizedY) - 1)
    guard outsideX > 0 || outsideY > 0 else {
      return .inside
    }
    guard max(outsideX, outsideY) <= tolerance else {
      return .outside
    }
    return .nearEdge
  }

  private static func result(
    reason: SpatialDirectionalAssociationReason,
    peerBearingRadians: Double? = nil,
    bodyBearingRadians: Double? = nil,
    angularDifferenceRadians: Double? = nil,
    alignmentScore: Double = 0,
    peerViewportRelation: SpatialDirectionalViewportRelation? = nil
  ) -> SpatialDirectionalAssociationResult {
    SpatialDirectionalAssociationResult(
      reason: reason,
      peerBearingRadians: peerBearingRadians,
      bodyBearingRadians: bodyBearingRadians,
      angularDifferenceRadians: angularDifferenceRadians,
      alignmentScore: alignmentScore,
      peerViewportRelation: peerViewportRelation
    )
  }
}
