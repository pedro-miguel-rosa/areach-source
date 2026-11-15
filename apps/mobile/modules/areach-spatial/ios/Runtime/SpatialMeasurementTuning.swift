import Foundation
import QuartzCore

enum SpatialMeasurementTuning {
  /// A new identity must be based on a recent spatial sample. Older samples
  /// remain useful for recovery, but never regain new-match authority.
  static let newMatchMaximumTransformAge: CFTimeInterval = 1.35
  static let newMatchMaximumDistanceAge: CFTimeInterval = 1.75
  static let newMatchMaximumDirectionAge: CFTimeInterval = 1.35
  /// Identity continuation may use one recent sensor while the other is
  /// temporarily unavailable. Display retention is tuned separately in
  /// `SpatialRenderTuning`.
  static let associationMaximumSingleSensorLoss: CFTimeInterval = 0.75
  static let distanceMedianWindow = 5
  static let distanceEMAAlpha: Float = 0.35
  static let distanceMovingEMAAlpha: Float = 0.78
  static let distanceOutlierFloor: Float = 0.65
  static let distanceMaximumMeasurementGap: CFTimeInterval = 1.0
  static let worldPositionMinimumCutoff: Float = 0.9
  static let worldPositionDerivativeCutoff: Float = 1.2
  static let worldPositionBeta: Float = 0.18
  static let worldPositionMaximumMeasurementGap: CFTimeInterval = 0.75
  static let worldPositionDiscontinuityDistance: Float = 0.9
  static let worldPositionPredictionHorizon: CFTimeInterval = 0.045
  static let worldPositionMaximumPredictionDistance: Float = 0.18
  static let worldPositionMaximumSpeed: Float = 6
  /// Positional rendering is stricter than scalar presence and association
  /// retention. A stale transform may remain in history, but never draws a
  /// solid marker or card position.
  static let renderMaximumTransformAge: CFTimeInterval = 0.55
  /// A small screen-space buffer absorbs noisy projection samples near an
  /// image edge. Samples in this buffer still cannot create a new identity;
  /// the buffer only lets an already continuous association survive briefly.
  static let directionalViewportEdgeToleranceFraction: CGFloat = 0.045
  static let directionalBodyMismatchTolerance = 1.15
  static let directionalAlignmentTolerance = 0.65
  static let minimumDirectionalOwnershipScore = 0.32
}

/// A solid DEV phone marker represents a currently projectable measurement,
/// not merely a peer whose transport identity is still recoverable.
enum SpatialRenderFreshnessPolicy {
  static func canRenderSolidPhoneMarker(
    worldTransformAvailable: Bool,
    transformAge: CFTimeInterval
  ) -> Bool {
    worldTransformAvailable
      && transformAge.isFinite
      && transformAge >= 0
      && transformAge <= SpatialMeasurementTuning.renderMaximumTransformAge
  }

  /// Render-only peer eligibility may use a recent direction/world sample even
  /// when Nearby Interaction is not currently in the strict ranging state
  /// required for a new identity. It is still bounded by measurement age and
  /// never changes identity eligibility.
  static func canUsePeerForFallback(
    worldTransformAvailable: Bool,
    transformAge: CFTimeInterval,
    directionIsFresh: Bool = false,
    distanceIsFresh: Bool
  ) -> Bool {
    (worldTransformAvailable
      && transformAge.isFinite
      && transformAge >= 0
      && transformAge <= SpatialMeasurementTuning.newMatchMaximumTransformAge)
      || directionIsFresh
      || distanceIsFresh
  }
}
