import Foundation
import QuartzCore

/// Scheduler-only tuning is kept in a Foundation/QuartzCore file so the pure
/// allocation policy can be compiled and exercised without UIKit or ARKit.
enum SpatialRangingTuning {
  /// This is the no-measurement grace period. It is not the complete probe
  /// lease: a useful distance-only sample still has to reach the hard deadline
  /// below if camera feedback never classifies it.
  static let probeTimeout: CFTimeInterval = 1.5
  /// Every probe has an absolute deadline, including probes that produce a
  /// distance but never produce a projectable direction.
  static let probeHardDeadline: CFTimeInterval = 2.4
  /// Distance-only probes get a short opportunity for a direction update or a
  /// camera-depth classification before the scheduler makes a decision.
  static let distanceOnlyProbeGracePeriod: CFTimeInterval = 0.65
  static let candidateLeaseDuration: CFTimeInterval = 4.5
  static let verifiedLeaseDuration: CFTimeInterval = 8
  /// Foreground attendee ranging keeps a healthy peer when the queue is
  /// empty, but bounds how long it can occupy a scarce proactive slot while
  /// other eligible attendees are waiting.
  static let foregroundProximityLeaseDuration: CFTimeInterval = 8
  /// After the other phone ends a foreground link, defer proactively claiming
  /// that same edge for one lease so the peer can spend its slot on someone
  /// else. Inbound Camera requests remain admissible during this local defer.
  static let foregroundRemoteStopCooldownDuration: CFTimeInterval =
    foregroundProximityLeaseDuration
  /// Attendee presence can be larger than the hardware working set. Keep
  /// proactive foreground ranging small even if a device learns a larger NI
  /// session limit.
  static let foregroundProximityConcurrentLimit = 3
  static let probePromotionInterest: Double = 0.18
  static let probeEvictionInterest: Double = 0.14
  static let cameraInterestRetentionDuration: CFTimeInterval = 1.2
  /// A verified target remains ranged across short camera-interest dropouts.
  static let verifiedInterestHysteresisDuration: CFTimeInterval = 0.75
  /// A clearly irrelevant verified target releases its scarce session quickly
  /// while its last spatial state remains recoverable.
  static let verifiedInterestReleaseDuration: CFTimeInterval = 0.65
  static let verifiedInterestKeepScore = 0.18
  static let cameraInterestHysteresisDuration: CFTimeInterval = 0.75
  static let schedulerInterval: DispatchTimeInterval = .milliseconds(180)
  static let rangingRequestTimeout: CFTimeInterval = 6
  static let firstAttemptRetryDelay: CFTimeInterval = 0.75
  static let repeatedAttemptRetryDelay: CFTimeInterval = 2
  static let maximumRetryDelay: CFTimeInterval = 30
  /// Busy is expected in a rotating multi-peer pool. Keep retries short while
  /// separating simultaneous peers with deterministic jitter.
  static let contentionRetryBaseDelay: CFTimeInterval = 0.75
  static let contentionRetryMaximumJitter: CFTimeInterval = 0.35
  /// Transport restoration uses its own bounded cadence and shared discovery
  /// refresh gate rather than consuming ranging-failure backoff.
  static let transportRetryBaseDelay: CFTimeInterval = 1.5
  static let transportRetryMaximumJitter: CFTimeInterval = 0.75
  static let negotiationFailureRetryBaseDelay: CFTimeInterval = 1
  /// EDM is optional. If it stops producing useful measurements, fall back
  /// to normal NI before the camera has to wait for identification.
  static let extendedDistanceHealthTimeout: CFTimeInterval = 2.5
  static let extendedDistanceRetryCooldown: CFTimeInterval = 8
  static let extendedDistanceMigrationHysteresis: Double = 0.2

  // Nearby Interaction health is role-specific. Camera viewing needs prompt
  // recovery, while a background responder only observes the link and waits
  // for the remote side to negotiate again.
  static let cameraHealthyUsefulMeasurementAge: CFTimeInterval = 0.9
  static let cameraDegradedUsefulMeasurementAge: CFTimeInterval = 1.25
  static let cameraSoftRecoveryTimeout: CFTimeInterval = 1.8
  static let cameraHardRecoveryTimeout: CFTimeInterval = 2.8
  static let cameraRecoveryHealthyConfirmationCount = 3
  static let cameraMaximumSoftRecoveryAttempts = 1
  static let cameraMinimumHardRecoveryInterval: CFTimeInterval = 2.5
  static let cameraMaximumHardRecoveryBackoff: CFTimeInterval = 30
  static let cameraDistanceHealthyMeasurementAge: CFTimeInterval = 1.6
  static let cameraDistanceDegradedMeasurementAge: CFTimeInterval = 3.2
  static let cameraDistanceSoftRecoveryTimeout: CFTimeInterval = 1.8
  static let cameraDistanceHardRecoveryTimeout: CFTimeInterval = 4.5
  static let cameraDistanceRecoveryHealthyConfirmationCount = 2
  static let cameraDistanceMaximumSoftRecoveryAttempts = 1
  static let cameraDistanceMinimumHardRecoveryInterval: CFTimeInterval = 5
  static let cameraDistanceMaximumHardRecoveryBackoff: CFTimeInterval = 30

  static let proximityHealthyUsefulMeasurementAge: CFTimeInterval = 1.6
  static let proximityDegradedUsefulMeasurementAge: CFTimeInterval = 2.5
  static let proximitySoftRecoveryTimeout: CFTimeInterval = 3.5
  static let proximityHardRecoveryTimeout: CFTimeInterval = 6
  static let proximityRecoveryHealthyConfirmationCount = 2
  static let proximityMaximumSoftRecoveryAttempts = 1
  static let proximityMinimumHardRecoveryInterval: CFTimeInterval = 5
  static let proximityMaximumHardRecoveryBackoff: CFTimeInterval = 30
  static let proximityDistanceHealthyMeasurementAge: CFTimeInterval = 2.2
  static let proximityDistanceDegradedMeasurementAge: CFTimeInterval = 3.8
  static let proximityDistanceSoftRecoveryTimeout: CFTimeInterval = 2.8
  static let proximityDistanceHardRecoveryTimeout: CFTimeInterval = 6
  static let proximityDistanceRecoveryHealthyConfirmationCount = 2
  static let proximityDistanceMaximumSoftRecoveryAttempts = 1
  static let proximityDistanceMinimumHardRecoveryInterval: CFTimeInterval = 5
  static let proximityDistanceMaximumHardRecoveryBackoff: CFTimeInterval = 30

  static let backgroundHealthyUsefulMeasurementAge: CFTimeInterval = 3
  static let backgroundDegradedUsefulMeasurementAge: CFTimeInterval = 6
  static let backgroundSoftRecoveryTimeout: CFTimeInterval = 6
  static let backgroundHardRecoveryTimeout: CFTimeInterval = 12
  static let backgroundRecoveryHealthyConfirmationCount = 2
  static let backgroundMaximumSoftRecoveryAttempts = 0
  static let backgroundMinimumHardRecoveryInterval: CFTimeInterval = 10
  static let backgroundMaximumHardRecoveryBackoff: CFTimeInterval = 60
  static let backgroundDistanceHealthyMeasurementAge: CFTimeInterval = 3
  static let backgroundDistanceDegradedMeasurementAge: CFTimeInterval = 6
  static let backgroundDistanceSoftRecoveryTimeout: CFTimeInterval = 6
  static let backgroundDistanceHardRecoveryTimeout: CFTimeInterval = 12
  static let backgroundDistanceRecoveryHealthyConfirmationCount = 2
  static let backgroundDistanceMaximumSoftRecoveryAttempts = 0
  static let backgroundDistanceMinimumHardRecoveryInterval: CFTimeInterval = 10
  static let backgroundDistanceMaximumHardRecoveryBackoff: CFTimeInterval = 60

  /// Presence is retained separately from measurement freshness so a quiet
  /// NI stream does not make an authenticated peer disappear immediately.
  static let transportPresenceRetentionDuration: CFTimeInterval = 30
  /// A failed ranging transaction may refresh the fallback transport, but the
  /// refresh is shared and bounded so multiple peers cannot restart discovery
  /// on every scheduler tick.
  static let rangingTransportRefreshInterval: CFTimeInterval = 3
  /// Rebuild only the Bonjour browser after a longer quiet transport stall;
  /// BLE scanning can refresh more frequently without tearing down listeners.
  static let rangingBonjourRefreshInterval: CFTimeInterval = 10
}

/// Tunables for scalar distance association live beside the pure scheduler so
/// the same policy can be exercised by deterministic replay tests.
enum SpatialDistanceAssociationTuning {
  static let minimumCombinedUncertainty: Float = 0.12
  static let minimumCombinedQuality: Float = 0.55
  static let maximumNormalizedResidual: Float = 2.25
  static let maximumBodyMeasurementAge: CFTimeInterval = 0.55
  static let minimumNewConfidence: Double = 0.7
  /// Reacquisition is stricter than first acquisition, but does not pay the
  /// full identity-switch cost because the peer identity was already
  /// verified and only the ephemeral Vision track changed.
  static let minimumReacquisitionConfidence: Double = 0.74
  static let minimumSwitchConfidence: Double = 0.84
  static let minimumNewAmbiguityMargin: Double = 0.24
  static let minimumReacquisitionAmbiguityMargin: Double = 0.28
  static let minimumSwitchAmbiguityMargin: Double = 0.34
  static let initialConfirmationCount = 3
  static let reacquisitionConfirmationCount = 3
  static let switchConfirmationCount = 4
}
