import QuartzCore
import simd
import UIKit

/// Estimates which phones deserve the next spatial opportunity before a
/// verified identity exists.  This is intentionally permissive; the matcher
/// remains responsible for rejecting ambiguous identity assignments.
final class SpatialCameraInterestEstimator {
  func estimate(
    world: SpatialWorldSnapshot,
    verifiedPeerIds: Set<String>,
    tentativePeerIds: Set<String>,
    now: CFTimeInterval,
    viewport: SpatialViewportSnapshot,
    projectAtCapture: (simd_float4x4) -> CGPoint?
  ) -> [SpatialCameraInterest] {
    guard viewport.isUsable else {
      return []
    }

    let viewportCenter = CGPoint(
      x: viewport.size.width / 2,
      y: viewport.size.height / 2
    )
    let viewportScale = max(viewport.size.width, viewport.size.height)

    return world.peers.compactMap { peer in
      let quality = peer.quality(at: now)
      let directionalMeasurement = peer.directionalMeasurement(at: now)
      let peerViewportProjection: SpatialDirectionalViewportProjection? = {
        if quality.transformAge
            <= SpatialMeasurementTuning.newMatchMaximumTransformAge,
          let peerPosition = peer.worldTransform.map(Self.worldPosition)
        {
          return SpatialDirectionalAssociationPolicy.viewportProjection(
            for: peerPosition,
            cameraTransform: world.viewer.cameraTransform,
            projectionMatrix: world.viewer.cameraProjectionMatrix,
            viewportSize: viewport.size
          )
        }

        guard let directionalMeasurement else {
          return nil
        }
        return SpatialDirectionalAssociationPolicy.viewportProjection(
          for: directionalMeasurement,
          projectionMatrix: world.viewer.cameraProjectionMatrix,
          viewportSize: viewport.size
        )
      }()
      let projectedPoint: CGPoint? = {
        let projectedByCapture: CGPoint? = {
          guard
            peer.worldTransform != nil,
            quality.transformAge
              <= SpatialMeasurementTuning.newMatchMaximumTransformAge
          else {
            return nil
          }

          return peer.worldTransform.flatMap(projectAtCapture)
        }()
        guard peerViewportProjection?.relation != .outside,
          peerViewportProjection?.relation != .behind
        else {
          return nil
        }
        return projectedByCapture ?? peerViewportProjection?.point
      }()
      let centerScore: Double
      if let projectedPoint {
        let projectedDistance = distance(projectedPoint, viewportCenter)
        let viewportRadius = Double(max(viewportScale * 0.7, 1))
        centerScore = max(0.0, 1.0 - projectedDistance / viewportRadius)
      } else {
        centerScore = 0
      }

      var bestBodyScore = 0.0
      var bestCarryScore = 0.0
      var bestWorldBodyScore = 0.0
      var bestWorldCarryScore = 0.0
      var bestDistanceOnlyScore = 0.0
      var bestDirectionalAlignment = 0.0
      var hasDirectionalCandidate = false
      var hasDirectionalMatch = false
      var isNearBody = false
      var isNearCarryRegion = false

      let peerBearing = {
        if quality.transformAge
            <= SpatialMeasurementTuning.newMatchMaximumTransformAge,
          let peerPosition = peer.worldTransform.map(Self.worldPosition)
        {
          return SpatialDirectionalAssociationPolicy.bearing(
            for: peerPosition,
            cameraTransform: world.viewer.cameraTransform
          )
        }

        return directionalMeasurement?.bearingRadians
      }()
      let directionalAge: CFTimeInterval? = peer.worldTransform != nil
        && quality.transformAge
          <= SpatialMeasurementTuning.newMatchMaximumTransformAge
        ? quality.transformAge
        : directionalMeasurement.map {
          max(0, now - $0.measuredAt)
        }

      if let projectedPoint {
        for detection in world.bodies {
          let bodyScale = max(detection.bodyScale, 60)
          let ownershipBounds = detection.boundingBox.insetBy(
            dx: -bodyScale * 0.32,
            dy: -bodyScale * 0.24
          )
          let bodyDistance = distance(from: projectedPoint, to: ownershipBounds)
          let bodyScore = max(0, 1 - bodyDistance / Double(bodyScale * 0.75))
          bestBodyScore = max(bestBodyScore, bodyScore)
          isNearBody = isNearBody || bodyDistance <= Double(bodyScale * 0.2)

          for region in detection.carryRegions {
            let carryDistance = distance(projectedPoint, region.center)
            let carryScore = max(
              0,
              1 - carryDistance / Double(max(region.radius * 1.5, 1))
            ) * Double(region.confidence)
            bestCarryScore = max(bestCarryScore, carryScore)
            isNearCarryRegion = isNearCarryRegion
              || carryDistance <= Double(max(region.radius, 1))
          }
        }
      }

      if let peerBearing, let directionalAge {
        for detection in world.bodies {
          let bodyBearing = detection.worldGeometry?.bodyPoint.flatMap {
            SpatialDirectionalAssociationPolicy.bearing(
              for: $0.position,
              cameraTransform: world.viewer.cameraTransform
            )
          } ?? SpatialDirectionalAssociationPolicy.bearing(
            for: detection.trackingPoint,
            viewportSize: viewport.size,
            cameraHorizontalProjectionScale:
              world.viewer.cameraHorizontalProjectionScale
          )
          let directionalEvidence = SpatialDirectionalAssociationPolicy.evaluate(
            peerBearingRadians: peerBearing,
            bodyBearingRadians: bodyBearing,
            measurementAge: directionalAge,
            now: now,
            peerViewportProjection: peerViewportProjection
          )
          hasDirectionalCandidate = true
          guard !directionalEvidence.hasHardContradiction else {
            continue
          }

          hasDirectionalMatch = true
          bestDirectionalAlignment = max(
            bestDirectionalAlignment,
            directionalEvidence.alignmentScore
          )
        }
      }

      if quality.transformAge
        <= SpatialMeasurementTuning.newMatchMaximumTransformAge,
        let peerPosition = peer.worldTransform.map(Self.worldPosition)
      {
        for detection in world.bodies {
          if let bodyPoint = detection.worldGeometry?.bodyPoint {
            let bodyDistance = simd_distance(
              peerPosition,
              bodyPoint.position
            )
            let bodyScore = exp(-Double(bodyDistance) / 0.85)
              * Double(max(0, min(1, bodyPoint.quality)))
            bestWorldBodyScore = max(bestWorldBodyScore, bodyScore)
            isNearBody = isNearBody || bodyDistance <= 0.9
          }

          for volume in detection.worldGeometry?.carryVolumes ?? [] {
            let carryScore = volume.proximity(to: peerPosition)
            bestWorldCarryScore = max(bestWorldCarryScore, carryScore)
            isNearCarryRegion = isNearCarryRegion || carryScore >= 0.6
          }
        }
      }

      // A pocketed phone may provide a fresh UWB scalar without a direction.
      // It still deserves a short acquisition opportunity when a current body
      // depth estimate agrees, but this signal is deliberately weaker than a
      // projectable/carry-geometry observation.
      if let peerMeasurement = peer.distanceMeasurement(at: now) {
        for detection in world.bodies {
          guard let bodyMeasurement = Self.bodyMeasurement(
            for: detection,
            cameraTransform: world.viewer.cameraTransform,
            measuredAt: now
          ),
            peerMeasurement.isFresh(
              at: now,
              maximumAge: SpatialMeasurementTuning.newMatchMaximumDistanceAge
            ),
            bodyMeasurement.isFresh(
              at: now,
              maximumAge: SpatialDistanceAssociationTuning.maximumBodyMeasurementAge
            ),
            let comparison = SpatialDistanceAssociationPolicy.compare(
              peer: peerMeasurement,
              body: bodyMeasurement
            )
          else {
            continue
          }

          bestDistanceOnlyScore = max(
            bestDistanceOnlyScore,
            comparison.score
          )
          if comparison.isPhysicallyPlausible,
            comparison.isHighQuality,
            comparison.normalizedResidual <= 1.8
          {
            isNearBody = true
          }
        }
      }

      let directionContradictsVisibleBodies = hasDirectionalCandidate
        && !hasDirectionalMatch
      if directionContradictsVisibleBodies {
        // Equal scalar distances are still useful to schedule another probe,
        // but a peer with a fresh rear/out-of-view direction should not look
        // like a visible body candidate.
        bestBodyScore = 0
        bestCarryScore = 0
        bestWorldBodyScore = 0
        bestWorldCarryScore = 0
        isNearBody = false
        isNearCarryRegion = false
      }

      let freshnessScore = quality.freshness
        * (1 - quality.convergencePenalty * 0.75)
      let isVerified = verifiedPeerIds.contains(peer.peerId)
      let isTentative = tentativePeerIds.contains(peer.peerId)
      let tentativeBonus = isTentative ? 0.12 : 0
      let centerContribution = centerScore * 0.22
      let bodyContribution = max(bestBodyScore, bestWorldBodyScore * 0.95) * 0.38
      let carryContribution = max(bestCarryScore, bestWorldCarryScore) * 0.28
      let distanceOnlyContribution = bestDistanceOnlyScore
        * (directionContradictsVisibleBodies
          ? 0.05
          : projectedPoint == nil ? 0.48 : 0.16)
      let directionalContribution = bestDirectionalAlignment * 0.16
      let freshnessContribution = freshnessScore * 0.12
      let rawScore = centerContribution
        + bodyContribution
        + carryContribution
        + distanceOnlyContribution
        + directionalContribution
        + freshnessContribution
        + tentativeBonus
      let score = max(0.0, min(1.0, rawScore))

      return SpatialCameraInterest(
        isNearBody: isNearBody,
        isNearCarryRegion: isNearCarryRegion,
        isTentative: isTentative,
        isVerified: isVerified,
        measuredAt: now,
        peerId: peer.peerId,
        projectedPoint: projectedPoint,
        score: score
      )
    }
    .sorted {
      if $0.score == $1.score {
        return $0.peerId < $1.peerId
      }

      return $0.score > $1.score
    }
  }

  private static func worldPosition(
    _ transform: simd_float4x4
  ) -> SIMD3<Float> {
    SIMD3<Float>(
      transform.columns.3.x,
      transform.columns.3.y,
      transform.columns.3.z
    )
  }

  private static func bodyMeasurement(
    for detection: SpatialBodyDetection,
    cameraTransform: simd_float4x4,
    measuredAt: CFTimeInterval
  ) -> SpatialDepthMeasurement? {
    if let measurement = detection.bodyDepthMeasurement {
      return measurement
    }

    guard
      let bodyPoint = detection.worldGeometry?.bodyPoint,
      measuredAt.isFinite
    else {
      return nil
    }

    let cameraPosition = worldPosition(cameraTransform)
    let distance = simd_distance(cameraPosition, bodyPoint.position)
    guard distance.isFinite, distance > 0 else {
      return nil
    }

    return SpatialDepthMeasurement(
      distance: distance,
      quality: min(1, max(0, bodyPoint.quality)),
      uncertainty: max(0.35, distance * 0.15),
      source: .vision3D,
      measuredAt: measuredAt
    )
  }
}
