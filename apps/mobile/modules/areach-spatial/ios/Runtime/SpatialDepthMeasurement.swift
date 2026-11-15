import Foundation
import QuartzCore

/// A scalar spatial observation is only useful when its provenance and
/// uncertainty travel with it.  Keeping this value independent from ARKit
/// lets the distance policy be replayed on a Mac without camera hardware.
enum SpatialDepthSource: String {
  case uwbDistance
  case rawSceneDepth
  case smoothedSceneDepth
  case vision3D
  case fallback
}

struct SpatialDepthMeasurement {
  let distance: Float
  let quality: Float
  let uncertainty: Float
  let source: SpatialDepthSource
  /// All freshness comparisons use the process monotonic clock. ARFrame's
  /// session-relative timestamp is kept separately on body detections.
  let measuredAt: CFTimeInterval

  var isFinite: Bool {
    distance.isFinite
      && distance > 0
      && quality.isFinite
      && uncertainty.isFinite
      && uncertainty > 0
      && measuredAt.isFinite
  }

  func isFresh(
    at now: CFTimeInterval,
    maximumAge: CFTimeInterval
  ) -> Bool {
    isFinite && now >= measuredAt && now - measuredAt <= maximumAge
  }
}

struct SpatialDistanceAssociationResult {
  let residual: Float
  let combinedUncertainty: Float
  let normalizedResidual: Float
  let score: Double
  let isPhysicallyPlausible: Bool
  let isHighQuality: Bool
}

/// Shared uncertainty-aware comparison for UWB/body depth evidence.  The
/// matcher and camera-interest estimator both use this exact calculation so a
/// peer cannot be promoted using one distance interpretation and rejected by
/// another.
enum SpatialDistanceAssociationPolicy {
  static func compare(
    peer: SpatialDepthMeasurement,
    body: SpatialDepthMeasurement
  ) -> SpatialDistanceAssociationResult? {
    guard peer.isFinite, body.isFinite else {
      return nil
    }

    let residual = abs(peer.distance - body.distance)
    let combinedUncertainty = max(
      SpatialDistanceAssociationTuning.minimumCombinedUncertainty,
      sqrt(
        pow(max(peer.uncertainty, 0.01), 2)
          + pow(max(body.uncertainty, 0.01), 2)
      )
    )
    let normalizedResidual = residual / combinedUncertainty
    let quality = sqrt(
      max(0, min(1, peer.quality))
        * max(0, min(1, body.quality))
    )
    let score = exp(-0.5 * Double(normalizedResidual * normalizedResidual))
      * Double(quality)

    return SpatialDistanceAssociationResult(
      residual: residual,
      combinedUncertainty: combinedUncertainty,
      normalizedResidual: normalizedResidual,
      score: max(0, min(1, score)),
      isPhysicallyPlausible: normalizedResidual
        <= SpatialDistanceAssociationTuning.maximumNormalizedResidual,
      isHighQuality: quality
        >= SpatialDistanceAssociationTuning.minimumCombinedQuality
    )
  }
}
