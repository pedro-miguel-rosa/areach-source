#if DEBUG
import CoreGraphics
import Foundation
import QuartzCore
import simd
import UIKit

/// A privacy-preserving, sensor-state fixture for reproducing fusion issues.
/// It contains no camera pixels and is compiled only into DEBUG builds.
struct SpatialReplayFrame: Codable {
  let timestamp: CFTimeInterval
  let viewer: SpatialReplayViewer
  let peers: [SpatialReplayPeer]
  let bodies: [SpatialReplayBody]
  let associations: [SpatialReplayAssociation]
  /// Optional for backwards compatibility with older replay fixtures.
  let renderModes: [String: String]?

  static func decodeSequence(from data: Data) -> [SpatialReplayFrame]? {
    try? JSONDecoder().decode([SpatialReplayFrame].self, from: data)
  }

  /// Rehydrates the sensor portion of a captured frame for matcher tests.
  /// Associations are intentionally omitted so a replay starts from the same
  /// empty matcher state as a fresh camera session. Render modes remain
  /// diagnostic metadata and are not fed back into identity matching.
  func worldSnapshot() -> SpatialWorldSnapshot? {
    guard let viewer = viewer.worldState else {
      return nil
    }

    return SpatialWorldSnapshot(
      viewer: viewer,
      peers: peers.compactMap { $0.spatialState },
      bodies: bodies.compactMap { $0.spatialDetection },
      associations: [],
      timestamp: timestamp
    )
  }
}

struct SpatialReplayViewer: Codable {
  let cameraTransform: [Float]
  /// Optional so older replay captures remain decodable. New captures retain
  /// the exact ARKit viewport projection used by the matcher.
  let cameraProjectionMatrix: [Float]?
  let viewportWidth: Double
  let viewportHeight: Double
  let orientation: Int
  let trackingQuality: String
  let timestamp: CFTimeInterval
  let cameraHorizontalProjectionScale: Float?
}

struct SpatialReplayPeer: Codable {
  let peerId: String
  let userId: String?
  let distance: Float?
  let distanceUpdatedAt: CFTimeInterval?
  let direction: [Float]?
  let horizontalAngle: Float?
  let directionMeasuredAt: CFTimeInterval?
  let distanceUncertainty: Float?
  let distanceSampleCount: Int
  let isRanging: Bool
  let presenceState: String
  let rangingState: String
  let transportState: String
  let lastRangedAt: CFTimeInterval?
  let lastUpdatedAt: CFTimeInterval
  let signalStrength: Double?
  let cameraAssistanceEnabled: Bool
  let measurementTier: String
  let worldTransform: [Float]?
  let worldTransformUpdatedAt: CFTimeInterval?
  let convergence: String
  /// Optional fields keep older DEBUG fixtures decodable while preserving the
  /// raw/display split and health clocks in new captures.
  let rawDistance: Float?
  let rawDistanceUpdatedAt: CFTimeInterval?
  let displayDistance: Float?
  let rawWorldTransform: [Float]?
  let rawWorldTransformUpdatedAt: CFTimeInterval?
  let displayWorldTransform: [Float]?
  let displayWorldTransformUpdatedAt: CFTimeInterval?
  let healthState: String?
  let lastDelegateCallbackAt: CFTimeInterval?
  let lastUsefulMeasurementAt: CFTimeInterval?
  let lastDistanceMeasurementAt: CFTimeInterval?
  let lastDirectionMeasurementAt: CFTimeInterval?
  let lastWorldTransformMeasurementAt: CFTimeInterval?
  let lastTransportPresenceAt: CFTimeInterval?
  let lastAuthenticatedTransportAt: CFTimeInterval?
}

struct SpatialReplayBody: Codable {
  let id: String
  let confidence: Float
  let bodyDepth: Float?
  let bodyDepthQuality: Float
  let bodyDepthSampleCount: Int
  let bodyDepthSpread: Float?
  let bodyDepthUncertainty: Float?
  let bodyDepthSource: String?
  let bodyDepthMeasuredAt: CFTimeInterval?
  let bodyScale: Double
  let boundingBox: [Double]
  let carryRegions: [SpatialReplayCarryRegion]
  let joints: [SpatialReplayJoint]
  let labelPoint: [Double]
  let isFreshPose: Bool
  let poseAge: CFTimeInterval
  let poseTimestamp: CFTimeInterval
  let trackingPoint: [Double]
  let trackingVelocity: [Double]
  let hasMotionEstimate: Bool
  let worldGeometry: SpatialReplayWorldGeometry?
}

struct SpatialReplayJoint: Codable {
  let confidence: Float
  let name: String
  let point: [Double]
}

struct SpatialReplayCarryRegion: Codable {
  let center: [Double]
  let confidence: Double
  let kind: String
  let radius: Double
}

struct SpatialReplayWorldGeometry: Codable {
  let bodyPoint: SpatialReplayWorldPoint?
  let carryPoints: [SpatialReplayCarryWorldPoint]
  let carryVolumes: [SpatialReplayCarryWorldVolume]
  let source: String
}

struct SpatialReplayWorldPoint: Codable {
  let position: [Float]
  let quality: Float
}

struct SpatialReplayCarryWorldPoint: Codable {
  let kind: String
  let position: [Float]
  let quality: Float
}

struct SpatialReplayCarryWorldVolume: Codable {
  let kind: String
  let center: [Float]
  let radii: [Float]
  let quality: Float
}

struct SpatialReplayAssociation: Codable {
  let peerId: String
  let userId: String
  let bodyTrackId: String?
  let state: String
  let path: String?
  let mode: String
  let confidence: Double
  let ambiguityMargin: Double
  let evidence: SpatialReplayEvidence?
  let lastUpdatedAt: CFTimeInterval
  let lastBodyEvidenceAt: CFTimeInterval
  let lastSpatialEvidenceAt: CFTimeInterval
}

struct SpatialReplayEvidence: Codable {
  let mode: String
  let screenGeometry: Double
  let carryRegionProximity: Double
  let carryWorldProximity: Double
  let bodyWorldProximity: Double
  let distanceConsistency: Double
  let distanceNormalizedResidual: Double?
  let directionalAlignment: Double?
  let measurementQuality: Double
  let cameraAssistance: Double
  let bodyPoseConfidence: Double
  let peerFreshness: Double
  let poseFreshness: Double
  let motionAgreement: Double
  let continuity: Double
  let switchPenalty: Double
  let hasScreenGeometry: Bool
  let hasCarryRegionProximity: Bool
  let hasCarryWorldProximity: Bool
  let hasBodyWorldProximity: Bool
  let hasDistanceConsistency: Bool
  let hasDirectionalAlignment: Bool?
  let hasDirectionalContradiction: Bool?
  let hasMotionAgreement: Bool
  let hasContinuity: Bool
  /// Optional so captures made before render contradiction diagnostics remain
  /// decodable.
  let hasContradictorySpatialEvidence: Bool?
}

/// Bounded in-memory capture. Callers can encode `frames()` to JSON for a
/// local fixture, then feed that sequence to scheduler/matcher test tooling.
final class SpatialReplayRecorder {
  private let lock = NSLock()
  private let capacity: Int
  private var buffer: [SpatialReplayFrame] = []

  init(capacity: Int = 600) {
    self.capacity = max(1, capacity)
  }

  func record(
    _ world: SpatialWorldSnapshot,
    renderStates: [SpatialRenderTargetState] = []
  ) {
    let renderModes: [String: String]? = renderStates.isEmpty
      ? nil
      : renderStates.reduce(into: [String: String]()) { result, state in
        result[state.peerId] = state.renderMode.rawValue
      }
    let frame = SpatialReplayFrame(
      timestamp: world.timestamp,
      viewer: SpatialReplayViewer(world.viewer),
      peers: world.peers.map {
        SpatialReplayPeer($0, at: world.timestamp)
      },
      bodies: world.bodies.map(SpatialReplayBody.init),
      associations: world.associations.map(SpatialReplayAssociation.init),
      renderModes: renderModes
    )

    lock.lock()
    buffer.append(frame)
    if buffer.count > capacity {
      buffer.removeFirst(buffer.count - capacity)
    }
    lock.unlock()
  }

  func frames() -> [SpatialReplayFrame] {
    lock.lock()
    defer { lock.unlock() }
    return buffer
  }

  func encodedFrames() -> Data? {
    try? JSONEncoder().encode(frames())
  }

  func clear() {
    lock.lock()
    buffer.removeAll(keepingCapacity: true)
    lock.unlock()
  }
}

private extension SpatialReplayViewer {
  init(_ viewer: SpatialViewerState) {
    self.init(
      cameraTransform: SpatialReplayValue.matrix(viewer.cameraTransform),
      cameraProjectionMatrix: viewer.cameraProjectionMatrix.map(
        SpatialReplayValue.matrix
      ),
      viewportWidth: viewer.viewport.size.width,
      viewportHeight: viewer.viewport.size.height,
      orientation: viewer.viewport.orientation.rawValue,
      trackingQuality: viewer.trackingQuality.rawValue,
      timestamp: viewer.timestamp,
      cameraHorizontalProjectionScale: viewer.cameraHorizontalProjectionScale
    )
  }

  var worldState: SpatialViewerState? {
    guard
      let cameraTransform = SpatialReplayValue.matrix(from: cameraTransform),
      let trackingQuality = SpatialViewerTrackingQuality(rawValue: trackingQuality)
    else {
      return nil
    }

    return SpatialViewerState(
      cameraTransform: cameraTransform,
      cameraProjectionMatrix: cameraProjectionMatrix.flatMap(
        SpatialReplayValue.matrix(from:)
      ),
      viewport: SpatialViewportSnapshot(
        size: CGSize(width: viewportWidth, height: viewportHeight),
        orientation: UIInterfaceOrientation(rawValue: orientation) ?? .portrait,
        version: 0,
        updatedAt: timestamp
      ),
      trackingQuality: trackingQuality,
      timestamp: timestamp,
      cameraHorizontalProjectionScale: cameraHorizontalProjectionScale
    )
  }
}

private extension SpatialReplayPeer {
  init(_ peer: NearbyPeerSpatialSnapshot, at timestamp: CFTimeInterval) {
    self.init(
      peerId: peer.peerId,
      userId: peer.identity?.userId,
      distance: peer.distance,
      distanceUpdatedAt: peer.distanceUpdatedAt,
      direction: peer.directionalMeasurement?.direction.map {
        [$0.x, $0.y, $0.z]
      },
      horizontalAngle: peer.directionalMeasurement?.horizontalAngle,
      directionMeasuredAt: peer.directionalMeasurement?.measuredAt,
      distanceUncertainty: peer.distanceUncertainty,
      distanceSampleCount: peer.distanceSampleCount,
      isRanging: peer.isRanging,
      presenceState: peer.presenceState.rawValue,
      rangingState: peer.rangingState.rawValue,
      transportState: peer.transportState.rawValue,
      lastRangedAt: peer.lastRangedAt,
      lastUpdatedAt: peer.lastUpdatedAt,
      signalStrength: peer.signalStrength,
      cameraAssistanceEnabled: peer.cameraAssistanceEnabled,
      measurementTier: peer.measurementTier(at: timestamp).rawValue,
      worldTransform: peer.worldTransform.map(SpatialReplayValue.matrix),
      worldTransformUpdatedAt: peer.worldTransformUpdatedAt,
      convergence: peer.convergence.rawValue,
      rawDistance: peer.rawDistance ?? peer.distance,
      rawDistanceUpdatedAt: peer.rawDistanceUpdatedAt ?? peer.distanceUpdatedAt,
      displayDistance: peer.displayDistance,
      rawWorldTransform: peer.rawWorldTransform
        .map(SpatialReplayValue.matrix)
        ?? peer.worldTransform.map(SpatialReplayValue.matrix),
      rawWorldTransformUpdatedAt: peer.rawWorldTransformUpdatedAt
        ?? peer.worldTransformUpdatedAt,
      displayWorldTransform: peer.displayWorldTransform
        .map(SpatialReplayValue.matrix),
      displayWorldTransformUpdatedAt: peer.displayWorldTransformUpdatedAt,
      healthState: peer.rangingHealth.state.rawValue,
      lastDelegateCallbackAt: peer.lastDelegateCallbackAt,
      lastUsefulMeasurementAt: peer.lastUsefulMeasurementAt,
      lastDistanceMeasurementAt: peer.lastDistanceMeasurementAt,
      lastDirectionMeasurementAt: peer.lastDirectionMeasurementAt,
      lastWorldTransformMeasurementAt: peer.lastWorldTransformMeasurementAt,
      lastTransportPresenceAt: peer.lastTransportPresenceAt,
      lastAuthenticatedTransportAt: peer.lastAuthenticatedTransportAt
    )
  }

  var spatialState: NearbyPeerSpatialSnapshot? {
    guard
      let presenceState = SpatialPeerPresenceState(rawValue: presenceState),
      let rangingState = SpatialPeerRangingState(rawValue: rangingState),
      let transportState = SpatialPeerTransportState(rawValue: transportState),
      let convergence = SpatialCameraAssistanceState(rawValue: convergence)
    else {
      return nil
    }

    let resolvedUserId = userId?.isEmpty == false ? userId : nil
    let identity = resolvedUserId.map {
      NearbyPeerIdentity(
        credential: "replay",
        eventScope: "replay",
        publicKey: nil,
        userId: $0
      )
    }
    var replayHealth = SpatialRangingHealth()
    replayHealth.state = SpatialRangingHealthState(rawValue: healthState ?? "")
      ?? (isRanging && (distance != nil || direction != nil
        || horizontalAngle != nil || worldTransform != nil)
        ? .healthy
        : .acquiring)
    replayHealth.lastDelegateCallbackAt = lastDelegateCallbackAt
    replayHealth.lastUsefulMeasurementAt = lastUsefulMeasurementAt
    replayHealth.lastDistanceAt = lastDistanceMeasurementAt
    replayHealth.lastDirectionAt = lastDirectionMeasurementAt
    replayHealth.lastTransformAt = lastWorldTransformMeasurementAt
    let directionalMeasurement: SpatialDirectionalMeasurement? = {
      let directionVector = self.direction.flatMap(SpatialReplayValue.vector3(from:))
      guard directionVector != nil || horizontalAngle != nil else {
        return nil
      }
      return SpatialDirectionalMeasurement(
        direction: directionVector,
        horizontalAngle: horizontalAngle,
        measuredAt: directionMeasuredAt ?? lastDirectionMeasurementAt ?? lastUpdatedAt
      )
    }()
    return SpatialPeerState(
      distance: distance,
      distanceUpdatedAt: distanceUpdatedAt,
      directionalMeasurement: directionalMeasurement,
      distanceUncertainty: distanceUncertainty,
      distanceSampleCount: distanceSampleCount,
      identity: identity,
      isRanging: isRanging,
      presenceState: presenceState,
      rangingState: rangingState,
      transportState: transportState,
      lastRangedAt: lastRangedAt,
      lastUpdatedAt: lastUpdatedAt,
      peerId: peerId,
      signalStrength: signalStrength,
      cameraAssistanceEnabled: cameraAssistanceEnabled,
      worldTransform: worldTransform.flatMap(SpatialReplayValue.matrix(from:)),
      worldTransformUpdatedAt: worldTransformUpdatedAt,
      convergence: convergence,
      rawDistance: rawDistance ?? distance,
      rawDistanceUpdatedAt: rawDistanceUpdatedAt ?? distanceUpdatedAt,
      rawWorldTransform: (rawWorldTransform ?? worldTransform)
        .flatMap(SpatialReplayValue.matrix(from:)),
      rawWorldTransformUpdatedAt: rawWorldTransformUpdatedAt
        ?? worldTransformUpdatedAt,
      // Older fixtures only had the legacy worldTransform field. Keep those
      // fixtures replayable, while preserving an intentional lack of display
      // state in new captures made during recovery.
      displayWorldTransform: (displayWorldTransform
        ?? (healthState == nil ? worldTransform : nil))
        .flatMap(SpatialReplayValue.matrix(from:)),
      displayWorldTransformUpdatedAt: displayWorldTransformUpdatedAt
        ?? (healthState == nil ? worldTransformUpdatedAt : nil),
      lastDelegateCallbackAt: lastDelegateCallbackAt,
      lastUsefulMeasurementAt: lastUsefulMeasurementAt,
      lastDistanceMeasurementAt: lastDistanceMeasurementAt,
      lastDirectionMeasurementAt: lastDirectionMeasurementAt,
      lastWorldTransformMeasurementAt: lastWorldTransformMeasurementAt,
      lastTransportPresenceAt: lastTransportPresenceAt,
      lastAuthenticatedTransportAt: lastAuthenticatedTransportAt,
      rangingHealth: replayHealth,
      displayDistance: displayDistance
    )
  }
}

private extension SpatialReplayBody {
  init(_ body: SpatialBodyDetection) {
    self.init(
      id: body.id,
      confidence: body.confidence,
      bodyDepth: body.bodyDepth,
      bodyDepthQuality: body.bodyDepthQuality,
      bodyDepthSampleCount: body.bodyDepthSampleCount,
      bodyDepthSpread: body.bodyDepthSpread,
      bodyDepthUncertainty: body.bodyDepthUncertainty,
      bodyDepthSource: body.bodyDepthSource?.rawValue,
      bodyDepthMeasuredAt: body.bodyDepthMeasuredAt,
      bodyScale: body.bodyScale,
      boundingBox: SpatialReplayValue.rect(body.boundingBox),
      carryRegions: body.carryRegions.map(SpatialReplayCarryRegion.init),
      joints: body.joints.map(SpatialReplayJoint.init),
      labelPoint: SpatialReplayValue.point(body.labelPoint),
      isFreshPose: body.isFreshPose,
      poseAge: body.poseAge,
      poseTimestamp: body.poseTimestamp,
      trackingPoint: SpatialReplayValue.point(body.trackingPoint),
      trackingVelocity: SpatialReplayValue.vector(body.trackingVelocity),
      hasMotionEstimate: body.hasMotionEstimate,
      worldGeometry: body.worldGeometry.map(SpatialReplayWorldGeometry.init)
    )
  }

  var spatialDetection: SpatialBodyDetection? {
    guard
      let boundingBox = SpatialReplayValue.rect(from: boundingBox),
      let labelPoint = SpatialReplayValue.point(from: labelPoint),
      let trackingPoint = SpatialReplayValue.point(from: trackingPoint),
      let trackingVelocity = SpatialReplayValue.vector(from: trackingVelocity)
    else {
      return nil
    }

    return SpatialBodyDetection(
      bodyDepth: bodyDepth,
      bodyDepthQuality: bodyDepthQuality,
      bodyDepthSampleCount: bodyDepthSampleCount,
      bodyDepthSpread: bodyDepthSpread,
      bodyDepthUncertainty: bodyDepthUncertainty,
      bodyDepthSource: bodyDepthSource.flatMap(SpatialDepthSource.init(rawValue:)),
      bodyDepthMeasuredAt: bodyDepthMeasuredAt,
      bodyScale: bodyScale,
      boundingBox: boundingBox,
      carryRegions: carryRegions.compactMap(\.spatialRegion),
      confidence: confidence,
      hasMotionEstimate: hasMotionEstimate,
      id: id,
      joints: joints.compactMap(\.spatialJoint),
      labelPoint: labelPoint,
      isFreshPose: isFreshPose,
      poseAge: poseAge,
      poseTimestamp: poseTimestamp,
      trackingPoint: trackingPoint,
      trackingVelocity: trackingVelocity,
      worldGeometry: worldGeometry?.spatialGeometry
    )
  }
}

private extension SpatialReplayJoint {
  init(_ joint: SpatialBodyJoint) {
    self.init(
      confidence: joint.confidence,
      name: joint.name,
      point: SpatialReplayValue.point(joint.point)
    )
  }

  var spatialJoint: SpatialBodyJoint? {
    SpatialReplayValue.point(from: point).map {
      SpatialBodyJoint(confidence: confidence, name: name, point: $0)
    }
  }
}

private extension SpatialReplayCarryRegion {
  init(_ region: SpatialCarryRegion) {
    self.init(
      center: SpatialReplayValue.point(region.center),
      confidence: Double(region.confidence),
      kind: region.kind.rawValue,
      radius: Double(region.radius)
    )
  }

  var spatialRegion: SpatialCarryRegion? {
    guard let center = SpatialReplayValue.point(from: center) else {
      return nil
    }

    return SpatialCarryRegion(
      center: center,
      confidence: CGFloat(confidence),
      radius: CGFloat(radius),
      kind: SpatialCarryRegionKind(rawValue: kind) ?? .generic
    )
  }
}

private extension SpatialReplayWorldGeometry {
  init(_ geometry: SpatialBodyDepthGeometry) {
    self.init(
      bodyPoint: geometry.bodyPoint.map(SpatialReplayWorldPoint.init),
      carryPoints: geometry.carryPoints.map(SpatialReplayCarryWorldPoint.init),
      carryVolumes: geometry.carryVolumes.map(SpatialReplayCarryWorldVolume.init),
      source: geometry.source.rawValue
    )
  }

  var spatialGeometry: SpatialBodyDepthGeometry? {
    guard let source = SpatialBodyGeometrySource(rawValue: source) else {
      return nil
    }

    return SpatialBodyDepthGeometry(
      bodyPoint: bodyPoint?.spatialPoint,
      carryPoints: carryPoints.compactMap(\.spatialPoint),
      carryVolumes: carryVolumes.compactMap(\.spatialVolume),
      source: source
    )
  }
}

private extension SpatialReplayWorldPoint {
  init(_ point: SpatialWorldPoint) {
    self.init(
      position: [point.position.x, point.position.y, point.position.z],
      quality: point.quality
    )
  }

  var spatialPoint: SpatialWorldPoint? {
    SpatialReplayValue.vector3(from: position).map {
      SpatialWorldPoint(position: $0, quality: quality)
    }
  }
}

private extension SpatialReplayCarryWorldPoint {
  init(_ point: SpatialCarryWorldPoint) {
    self.init(
      kind: point.kind.rawValue,
      position: [point.position.x, point.position.y, point.position.z],
      quality: point.quality
    )
  }

  var spatialPoint: SpatialCarryWorldPoint? {
    SpatialReplayValue.vector3(from: position).map {
      SpatialCarryWorldPoint(
        kind: SpatialCarryRegionKind(rawValue: kind) ?? .generic,
        position: $0,
        quality: quality
      )
    }
  }
}

private extension SpatialReplayCarryWorldVolume {
  init(_ volume: SpatialCarryWorldVolume) {
    self.init(
      kind: volume.kind.rawValue,
      center: [volume.center.x, volume.center.y, volume.center.z],
      radii: [volume.radii.x, volume.radii.y, volume.radii.z],
      quality: volume.quality
    )
  }

  var spatialVolume: SpatialCarryWorldVolume? {
    guard
      let center = SpatialReplayValue.vector3(from: center),
      let radii = SpatialReplayValue.vector3(from: radii)
    else {
      return nil
    }

    return SpatialCarryWorldVolume(
      kind: SpatialCarryRegionKind(rawValue: kind) ?? .generic,
      center: center,
      radii: radii,
      quality: quality
    )
  }
}

private extension SpatialReplayAssociation {
  init(_ association: SpatialAssociation) {
    self.init(
      peerId: association.peerId,
      userId: association.userId,
      bodyTrackId: association.bodyTrackId,
      state: association.state.rawValue,
      path: association.path.rawValue,
      mode: association.mode.rawValue,
      confidence: association.confidence,
      ambiguityMargin: association.ambiguityMargin,
      evidence: association.evidence.map(SpatialReplayEvidence.init),
      lastUpdatedAt: association.lastUpdatedAt,
      lastBodyEvidenceAt: association.lastBodyEvidenceAt,
      lastSpatialEvidenceAt: association.lastSpatialEvidenceAt
    )
  }
}

private extension SpatialReplayEvidence {
  init(_ evidence: SpatialAssociationEvidence) {
    self.init(
      mode: evidence.mode.rawValue,
      screenGeometry: evidence.screenGeometry,
      carryRegionProximity: evidence.carryRegionProximity,
      carryWorldProximity: evidence.carryWorldProximity,
      bodyWorldProximity: evidence.bodyWorldProximity,
      distanceConsistency: evidence.distanceConsistency,
      distanceNormalizedResidual: evidence.distanceNormalizedResidual,
      directionalAlignment: evidence.directionalAlignment,
      measurementQuality: evidence.measurementQuality,
      cameraAssistance: evidence.cameraAssistance,
      bodyPoseConfidence: evidence.bodyPoseConfidence,
      peerFreshness: evidence.peerFreshness,
      poseFreshness: evidence.poseFreshness,
      motionAgreement: evidence.motionAgreement,
      continuity: evidence.continuity,
      switchPenalty: evidence.switchPenalty,
      hasScreenGeometry: evidence.hasScreenGeometry,
      hasCarryRegionProximity: evidence.hasCarryRegionProximity,
      hasCarryWorldProximity: evidence.hasCarryWorldProximity,
      hasBodyWorldProximity: evidence.hasBodyWorldProximity,
      hasDistanceConsistency: evidence.hasDistanceConsistency,
      hasDirectionalAlignment: evidence.hasDirectionalAlignment,
      hasDirectionalContradiction: evidence.hasDirectionalContradiction,
      hasMotionAgreement: evidence.hasMotionAgreement,
      hasContinuity: evidence.hasContinuity,
      hasContradictorySpatialEvidence: evidence.hasContradictorySpatialEvidence
    )
  }
}

private enum SpatialReplayValue {
  static func point(from values: [Double]) -> CGPoint? {
    guard values.count == 2 else {
      return nil
    }
    return CGPoint(x: values[0], y: values[1])
  }

  static func point(_ point: CGPoint) -> [Double] {
    [Double(point.x), Double(point.y)]
  }

  static func vector(from values: [Double]) -> CGVector? {
    guard values.count == 2 else {
      return nil
    }
    return CGVector(dx: values[0], dy: values[1])
  }

  static func vector(_ vector: CGVector) -> [Double] {
    [Double(vector.dx), Double(vector.dy)]
  }

  static func rect(from values: [Double]) -> CGRect? {
    guard values.count == 4 else {
      return nil
    }
    return CGRect(
      x: values[0],
      y: values[1],
      width: values[2],
      height: values[3]
    )
  }

  static func rect(_ rect: CGRect) -> [Double] {
    [
      Double(rect.origin.x),
      Double(rect.origin.y),
      Double(rect.size.width),
      Double(rect.size.height),
    ]
  }

  static func matrix(_ matrix: simd_float4x4) -> [Float] {
    [
      matrix.columns.0.x,
      matrix.columns.0.y,
      matrix.columns.0.z,
      matrix.columns.0.w,
      matrix.columns.1.x,
      matrix.columns.1.y,
      matrix.columns.1.z,
      matrix.columns.1.w,
      matrix.columns.2.x,
      matrix.columns.2.y,
      matrix.columns.2.z,
      matrix.columns.2.w,
      matrix.columns.3.x,
      matrix.columns.3.y,
      matrix.columns.3.z,
      matrix.columns.3.w,
    ]
  }

  static func matrix(from values: [Float]) -> simd_float4x4? {
    guard values.count == 16 else {
      return nil
    }

    return simd_float4x4(
      SIMD4(values[0], values[1], values[2], values[3]),
      SIMD4(values[4], values[5], values[6], values[7]),
      SIMD4(values[8], values[9], values[10], values[11]),
      SIMD4(values[12], values[13], values[14], values[15])
    )
  }

  static func vector3(from values: [Float]) -> SIMD3<Float>? {
    guard values.count == 3 else {
      return nil
    }
    return SIMD3(values[0], values[1], values[2])
  }
}
#endif
