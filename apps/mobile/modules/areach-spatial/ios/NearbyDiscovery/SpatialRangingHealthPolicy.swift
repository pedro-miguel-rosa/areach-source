import Foundation

enum SpatialRangingHealthState: String, Equatable {
  case acquiring
  case healthy
  case degraded
  case softRecovering
  case renegotiating
}

enum SpatialRangingHealthRole: String {
  case cameraViewer
  case foregroundProximity
  case backgroundResponder
}

enum SpatialRangingDistanceHealthState: String, Equatable {
  case acquiring
  case healthy
  case degraded
  case softRecovering
  case renegotiating
}

struct SpatialRangingHealthTiming {
  let healthyUsefulMeasurementAge: CFTimeInterval
  let degradedUsefulMeasurementAge: CFTimeInterval
  let softRecoveryTimeout: CFTimeInterval
  let hardRecoveryTimeout: CFTimeInterval
  let recoveryHealthyConfirmationCount: Int
  let maximumSoftRecoveryAttempts: Int
  let minimumHardRecoveryInterval: CFTimeInterval
  let maximumHardRecoveryBackoff: CFTimeInterval
  let healthyDistanceMeasurementAge: CFTimeInterval
  let degradedDistanceMeasurementAge: CFTimeInterval
  let distanceSoftRecoveryTimeout: CFTimeInterval
  let distanceHardRecoveryTimeout: CFTimeInterval
  let distanceRecoveryHealthyConfirmationCount: Int
  let distanceMaximumSoftRecoveryAttempts: Int
  let distanceMinimumHardRecoveryInterval: CFTimeInterval
  let distanceMaximumHardRecoveryBackoff: CFTimeInterval
}

enum SpatialRangingHealthAction: Equatable {
  case wait
  case markDegraded
  case startSoftRecovery
  case startHardRecovery
}

enum SpatialRangingRemovalReason: Equatable {
  case timeout
  case peerEnded
  case unknown
}

enum SpatialRangingRemovalAction: Equatable {
  case softRecovery
  case freshNegotiation
}

enum SpatialRangingFailureDisposition: Equatable {
  case activeHardRecovery
  case activeFreshRetry
  case pendingFreshRetry
  case discard
}

/// Pure mapping for NI delegate failure reasons. The service owns the
/// session/transport side effects; these decisions stay testable without
/// NearbyInteraction.framework.
enum SpatialRangingFailurePolicy {
  static func removalAction(
    for reason: SpatialRangingRemovalReason
  ) -> SpatialRangingRemovalAction {
    reason == .peerEnded ? .freshNegotiation : .softRecovery
  }

  static func invalidationDisposition(
    isActive: Bool,
    isPending: Bool,
    isAlreadyRenegotiating: Bool
  ) -> SpatialRangingFailureDisposition {
    if isActive {
      return isAlreadyRenegotiating
        ? .activeFreshRetry
        : .activeHardRecovery
    }
    if isPending {
      return .pendingFreshRetry
    }
    return .discard
  }
}

enum SpatialRangingRetryKind: String, Equatable {
  case contention
  case transportUnavailable
  case negotiationFailure
}

struct SpatialRangingRetryDecision: Equatable {
  let delay: CFTimeInterval
  let incrementsFailureCount: Bool
}

enum SpatialRangingRetryPolicy {
  static func kind(for reason: String) -> SpatialRangingRetryKind {
    let normalizedReason = reason.lowercased()
    if normalizedReason == "busy"
      || normalizedReason.contains("collision")
      || normalizedReason.contains("capacity")
    {
      return .contention
    }
    if normalizedReason.contains("transport")
      || normalizedReason.contains("request-timeout")
    {
      return .transportUnavailable
    }
    return .negotiationFailure
  }

  static func decision(
    for kind: SpatialRangingRetryKind,
    consecutiveFailureCount: Int,
    deterministicJitter: CFTimeInterval
  ) -> SpatialRangingRetryDecision {
    let jitter = max(0, deterministicJitter)
    switch kind {
    case .contention:
      return SpatialRangingRetryDecision(
        delay: SpatialRangingTuning.contentionRetryBaseDelay
          + min(jitter, SpatialRangingTuning.contentionRetryMaximumJitter),
        incrementsFailureCount: false
      )
    case .transportUnavailable:
      return SpatialRangingRetryDecision(
        delay: SpatialRangingTuning.transportRetryBaseDelay
          + min(jitter, SpatialRangingTuning.transportRetryMaximumJitter),
        incrementsFailureCount: false
      )
    case .negotiationFailure:
      let attempt = max(1, consecutiveFailureCount)
      let baseDelay = SpatialRangingTuning.negotiationFailureRetryBaseDelay
        * pow(2, Double(attempt - 1))
      return SpatialRangingRetryDecision(
        delay: min(
          SpatialRangingTuning.maximumRetryDelay,
          baseDelay + min(jitter, 0.9)
        ),
        incrementsFailureCount: true
      )
    }
  }
}

struct SpatialRangingHealthEvaluation: Equatable {
  let action: SpatialRangingHealthAction
  let reason: String
}

/// Pure state and timing rules for Nearby Interaction liveness. Link
/// negotiation remains separate: a session can be in `ranging` while this
/// state is degraded because its delegate is producing no useful samples.
struct SpatialRangingHealth: Equatable {
  var state: SpatialRangingHealthState = .acquiring
  /// Generic NI liveness: distance, direction, or a valid transform.
  /// Kept independent from scalar distance liveness below.
  var distanceState: SpatialRangingDistanceHealthState = .acquiring
  var lastDelegateCallbackAt: CFTimeInterval?
  var lastUsefulMeasurementAt: CFTimeInterval?
  var lastDistanceAt: CFTimeInterval?
  var lastTransformAt: CFTimeInterval?
  var lastDirectionAt: CFTimeInterval?
  var consecutiveUsefulUpdates = 0
  var consecutiveUselessUpdates = 0
  var consecutiveDistanceUpdates = 0
  var softRecoveryAttempts = 0
  var hardRecoveryAttempts = 0
  var distanceSoftRecoveryAttempts = 0
  var distanceHardRecoveryAttempts = 0
  var rangingFailureAttempts = 0
  var recoveryStartedAt: CFTimeInterval?
  var distanceRecoveryStartedAt: CFTimeInterval?
  var lastSoftRecoveryAt: CFTimeInterval?
  var lastHardRecoveryAt: CFTimeInterval?
  var distanceLastSoftRecoveryAt: CFTimeInterval?
  var distanceLastHardRecoveryAt: CFTimeInterval?
  var lastUsefulMeasurementLostAt: CFTimeInterval?
  var lastDistanceLostAt: CFTimeInterval?
  var transactionStartedAt: CFTimeInterval?

  var isRecovering: Bool {
    state == .softRecovering || state == .renegotiating
  }

  var isDistanceRecovering: Bool {
    distanceState == .softRecovering || distanceState == .renegotiating
  }

  func usefulMeasurementAge(at now: CFTimeInterval) -> CFTimeInterval {
    guard let lastUsefulMeasurementAt = currentAttemptTimestamp(
      lastUsefulMeasurementAt
    )
    else {
      return .greatestFiniteMagnitude
    }

    return max(0, now - lastUsefulMeasurementAt)
  }

  func delegateCallbackAge(at now: CFTimeInterval) -> CFTimeInterval {
    guard let lastDelegateCallbackAt else {
      return .greatestFiniteMagnitude
    }

    return max(0, now - lastDelegateCallbackAt)
  }

  func distanceMeasurementAge(at now: CFTimeInterval) -> CFTimeInterval {
    guard let lastDistanceAt = currentAttemptTimestamp(lastDistanceAt) else {
      return .greatestFiniteMagnitude
    }
    return max(0, now - lastDistanceAt)
  }

  func isMeasurementHealthy(
    at now: CFTimeInterval,
    role: SpatialRangingHealthRole
  ) -> Bool {
    usefulMeasurementAge(at: now)
      <= SpatialRangingHealthPolicy.timing(for: role)
        .healthyUsefulMeasurementAge
      && consecutiveUsefulUpdates
        >= SpatialRangingHealthPolicy.timing(for: role)
          .recoveryHealthyConfirmationCount
  }

  func isDistanceMeasurementHealthy(
    at now: CFTimeInterval,
    role: SpatialRangingHealthRole
  ) -> Bool {
    let timing = SpatialRangingHealthPolicy.timing(for: role)
    guard currentAttemptTimestamp(lastDistanceAt) != nil else {
      return false
    }
    return distanceMeasurementAge(at: now) <= timing.healthyDistanceMeasurementAge
  }

  func currentAttemptTimestamp(
    _ timestamp: CFTimeInterval?
  ) -> CFTimeInterval? {
    guard let timestamp else {
      return nil
    }

    guard let transactionStartedAt else {
      return timestamp
    }

    return timestamp >= transactionStartedAt ? timestamp : nil
  }

  mutating func beginTransaction(
    at now: CFTimeInterval,
    state: SpatialRangingHealthState = .acquiring
  ) {
    self.state = state
    distanceState = state == .renegotiating ? .renegotiating : .acquiring
    transactionStartedAt = now
    consecutiveUsefulUpdates = 0
    consecutiveUselessUpdates = 0
    consecutiveDistanceUpdates = 0
    recoveryStartedAt = state == .renegotiating ? now : nil
    distanceRecoveryStartedAt = state == .renegotiating ? now : nil
  }

  /// Records one NI delegate callback. A callback with no finite positive
  /// distance, valid world transform, or direct direction updates only
  /// callback freshness; it cannot reset recovery counters or make the
  /// session healthy.
  @discardableResult
  mutating func recordDelegateCallback(
    at now: CFTimeInterval,
    hasDistance: Bool,
    hasTransform: Bool,
    healthyConfirmationCount: Int,
    hasDirection: Bool = false,
    distanceHealthyConfirmationCount: Int? = nil
  ) -> Bool {
    guard now.isFinite else {
      return false
    }

    lastDelegateCallbackAt = now
    if !hasDistance {
      consecutiveDistanceUpdates = 0
    }
    let hasUsefulMeasurement = SpatialRangingHealthPolicy.hasUsefulMeasurement(
      hasFinitePositiveDistance: hasDistance,
      hasValidWorldTransform: hasTransform,
      hasValidDirection: hasDirection
    )

    guard hasUsefulMeasurement else {
      consecutiveUsefulUpdates = 0
      consecutiveUselessUpdates += 1
      return false
    }

    if hasDistance {
      lastDistanceAt = now
      consecutiveDistanceUpdates += 1
    }
    if hasTransform {
      lastTransformAt = now
    }
    if hasDirection {
      lastDirectionAt = now
    }
    lastUsefulMeasurementAt = now
    consecutiveUsefulUpdates += 1
    consecutiveUselessUpdates = 0
    lastUsefulMeasurementLostAt = nil
    rangingFailureAttempts = 0

    let requiredDistanceConfirmations = max(
      1,
      distanceHealthyConfirmationCount
        ?? SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
          .distanceRecoveryHealthyConfirmationCount
    )
    if hasDistance,
      distanceState != .healthy,
      consecutiveDistanceUpdates >= requiredDistanceConfirmations
    {
      distanceState = .healthy
      distanceRecoveryStartedAt = nil
      distanceSoftRecoveryAttempts = 0
      distanceHardRecoveryAttempts = 0
      distanceLastSoftRecoveryAt = nil
      distanceLastHardRecoveryAt = nil
      lastDistanceLostAt = nil
    }

    if (state == .acquiring || state == .degraded || state == .softRecovering || state == .renegotiating),
      consecutiveUsefulUpdates >= healthyConfirmationCount
    {
      state = .healthy
      recoveryStartedAt = nil
      softRecoveryAttempts = 0
      hardRecoveryAttempts = 0
    }

    return true
  }
}

enum SpatialRangingHealthPolicy {
  static func timing(
    for role: SpatialRangingHealthRole
  ) -> SpatialRangingHealthTiming {
    switch role {
    case .cameraViewer:
      return SpatialRangingHealthTiming(
        healthyUsefulMeasurementAge: SpatialRangingTuning.cameraHealthyUsefulMeasurementAge,
        degradedUsefulMeasurementAge: SpatialRangingTuning.cameraDegradedUsefulMeasurementAge,
        softRecoveryTimeout: SpatialRangingTuning.cameraSoftRecoveryTimeout,
        hardRecoveryTimeout: SpatialRangingTuning.cameraHardRecoveryTimeout,
        recoveryHealthyConfirmationCount: SpatialRangingTuning.cameraRecoveryHealthyConfirmationCount,
        maximumSoftRecoveryAttempts: SpatialRangingTuning.cameraMaximumSoftRecoveryAttempts,
        minimumHardRecoveryInterval: SpatialRangingTuning.cameraMinimumHardRecoveryInterval,
        maximumHardRecoveryBackoff: SpatialRangingTuning.cameraMaximumHardRecoveryBackoff,
        healthyDistanceMeasurementAge: SpatialRangingTuning.cameraDistanceHealthyMeasurementAge,
        degradedDistanceMeasurementAge: SpatialRangingTuning.cameraDistanceDegradedMeasurementAge,
        distanceSoftRecoveryTimeout: SpatialRangingTuning.cameraDistanceSoftRecoveryTimeout,
        distanceHardRecoveryTimeout: SpatialRangingTuning.cameraDistanceHardRecoveryTimeout,
        distanceRecoveryHealthyConfirmationCount: SpatialRangingTuning.cameraDistanceRecoveryHealthyConfirmationCount,
        distanceMaximumSoftRecoveryAttempts: SpatialRangingTuning.cameraDistanceMaximumSoftRecoveryAttempts,
        distanceMinimumHardRecoveryInterval: SpatialRangingTuning.cameraDistanceMinimumHardRecoveryInterval,
        distanceMaximumHardRecoveryBackoff: SpatialRangingTuning.cameraDistanceMaximumHardRecoveryBackoff
      )
    case .foregroundProximity:
      return SpatialRangingHealthTiming(
        healthyUsefulMeasurementAge: SpatialRangingTuning.proximityHealthyUsefulMeasurementAge,
        degradedUsefulMeasurementAge: SpatialRangingTuning.proximityDegradedUsefulMeasurementAge,
        softRecoveryTimeout: SpatialRangingTuning.proximitySoftRecoveryTimeout,
        hardRecoveryTimeout: SpatialRangingTuning.proximityHardRecoveryTimeout,
        recoveryHealthyConfirmationCount: SpatialRangingTuning.proximityRecoveryHealthyConfirmationCount,
        maximumSoftRecoveryAttempts: SpatialRangingTuning.proximityMaximumSoftRecoveryAttempts,
        minimumHardRecoveryInterval: SpatialRangingTuning.proximityMinimumHardRecoveryInterval,
        maximumHardRecoveryBackoff: SpatialRangingTuning.proximityMaximumHardRecoveryBackoff,
        healthyDistanceMeasurementAge: SpatialRangingTuning.proximityDistanceHealthyMeasurementAge,
        degradedDistanceMeasurementAge: SpatialRangingTuning.proximityDistanceDegradedMeasurementAge,
        distanceSoftRecoveryTimeout: SpatialRangingTuning.proximityDistanceSoftRecoveryTimeout,
        distanceHardRecoveryTimeout: SpatialRangingTuning.proximityDistanceHardRecoveryTimeout,
        distanceRecoveryHealthyConfirmationCount: SpatialRangingTuning.proximityDistanceRecoveryHealthyConfirmationCount,
        distanceMaximumSoftRecoveryAttempts: SpatialRangingTuning.proximityDistanceMaximumSoftRecoveryAttempts,
        distanceMinimumHardRecoveryInterval: SpatialRangingTuning.proximityDistanceMinimumHardRecoveryInterval,
        distanceMaximumHardRecoveryBackoff: SpatialRangingTuning.proximityDistanceMaximumHardRecoveryBackoff
      )
    case .backgroundResponder:
      return SpatialRangingHealthTiming(
        healthyUsefulMeasurementAge: SpatialRangingTuning.backgroundHealthyUsefulMeasurementAge,
        degradedUsefulMeasurementAge: SpatialRangingTuning.backgroundDegradedUsefulMeasurementAge,
        softRecoveryTimeout: SpatialRangingTuning.backgroundSoftRecoveryTimeout,
        hardRecoveryTimeout: SpatialRangingTuning.backgroundHardRecoveryTimeout,
        recoveryHealthyConfirmationCount: SpatialRangingTuning.backgroundRecoveryHealthyConfirmationCount,
        maximumSoftRecoveryAttempts: SpatialRangingTuning.backgroundMaximumSoftRecoveryAttempts,
        minimumHardRecoveryInterval: SpatialRangingTuning.backgroundMinimumHardRecoveryInterval,
        maximumHardRecoveryBackoff: SpatialRangingTuning.backgroundMaximumHardRecoveryBackoff,
        healthyDistanceMeasurementAge: SpatialRangingTuning.backgroundDistanceHealthyMeasurementAge,
        degradedDistanceMeasurementAge: SpatialRangingTuning.backgroundDistanceDegradedMeasurementAge,
        distanceSoftRecoveryTimeout: SpatialRangingTuning.backgroundDistanceSoftRecoveryTimeout,
        distanceHardRecoveryTimeout: SpatialRangingTuning.backgroundDistanceHardRecoveryTimeout,
        distanceRecoveryHealthyConfirmationCount: SpatialRangingTuning.backgroundDistanceRecoveryHealthyConfirmationCount,
        distanceMaximumSoftRecoveryAttempts: SpatialRangingTuning.backgroundDistanceMaximumSoftRecoveryAttempts,
        distanceMinimumHardRecoveryInterval: SpatialRangingTuning.backgroundDistanceMinimumHardRecoveryInterval,
        distanceMaximumHardRecoveryBackoff: SpatialRangingTuning.backgroundDistanceMaximumHardRecoveryBackoff
      )
    }
  }

  static func hasUsefulMeasurement(
    hasFinitePositiveDistance: Bool,
    hasValidWorldTransform: Bool,
    hasValidDirection: Bool = false
  ) -> Bool {
    hasFinitePositiveDistance || hasValidWorldTransform || hasValidDirection
  }

  static func evaluate(
    health: SpatialRangingHealth,
    role: SpatialRangingHealthRole,
    now: CFTimeInterval,
    transportNearby: Bool
  ) -> SpatialRangingHealthEvaluation {
    let timing = self.timing(for: role)
    let usefulAge = health.usefulMeasurementAge(at: now)
    let transactionAge = health.transactionStartedAt.map {
      max(0, now - $0)
    } ?? .greatestFiniteMagnitude
    let hasCurrentUsefulMeasurement = usefulAge.isFinite
      && usefulAge <= timing.healthyUsefulMeasurementAge
    let degraded = !hasCurrentUsefulMeasurement
      && usefulAge >= timing.degradedUsefulMeasurementAge

    switch health.state {
    case .acquiring:
      return degraded && transactionAge >= timing.degradedUsefulMeasurementAge
        ? SpatialRangingHealthEvaluation(
          action: .markDegraded,
          reason: "no-useful-measurement-while-acquiring"
        )
        : SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "acquiring"
        )
    case .healthy:
      return degraded
        ? SpatialRangingHealthEvaluation(
          action: .markDegraded,
          reason: "useful-measurement-stale"
        )
        : SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "healthy"
        )
    case .degraded:
      guard transportNearby else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "transport-not-nearby"
        )
      }

      if role == .backgroundResponder {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "background-responder-passive-recovery"
        )
      }

      if health.softRecoveryAttempts < timing.maximumSoftRecoveryAttempts {
        let canRetry = health.lastSoftRecoveryAt.map {
          now - $0 >= min(0.75, timing.softRecoveryTimeout * 0.4)
        } ?? true
        if canRetry {
          return SpatialRangingHealthEvaluation(
            action: .startSoftRecovery,
            reason: "degraded-session-soft-recovery"
          )
        }
      }

      guard let recoveryStartedAt = health.recoveryStartedAt else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "waiting-for-soft-recovery"
        )
      }
      guard now - recoveryStartedAt >= timing.softRecoveryTimeout else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "soft-recovery-window-open"
        )
      }
      return SpatialRangingHealthEvaluation(
        action: .startHardRecovery,
        reason: "soft-recovery-window-expired"
      )
    case .softRecovering:
      if hasCurrentUsefulMeasurement,
        health.consecutiveUsefulUpdates >= timing.recoveryHealthyConfirmationCount
      {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "soft-recovery-measurements-returned"
        )
      }

      guard let recoveryStartedAt = health.recoveryStartedAt else {
        return SpatialRangingHealthEvaluation(
          action: .startHardRecovery,
          reason: "soft-recovery-start-time-missing"
        )
      }
      return now - recoveryStartedAt >= timing.softRecoveryTimeout
        ? SpatialRangingHealthEvaluation(
          action: .startHardRecovery,
          reason: "soft-recovery-timeout"
        )
        : SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "soft-recovery-in-progress"
        )
    case .renegotiating:
      if hasCurrentUsefulMeasurement,
        health.consecutiveUsefulUpdates >= timing.recoveryHealthyConfirmationCount
      {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "fresh-transaction-recovered"
        )
      }

      guard transportNearby,
        let recoveryStartedAt = health.recoveryStartedAt,
        now - recoveryStartedAt >= timing.hardRecoveryTimeout
      else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "renegotiation-in-progress"
        )
      }

      let backoff = min(
        timing.maximumHardRecoveryBackoff,
        timing.minimumHardRecoveryInterval
          * pow(2, Double(max(0, health.hardRecoveryAttempts - 1)))
      )
      guard health.lastHardRecoveryAt.map({ now - $0 >= backoff }) == true else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "hard-recovery-backoff"
        )
      }
      return role == .backgroundResponder
        ? SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "background-responder-passive-recovery"
        )
        : SpatialRangingHealthEvaluation(
          action: .startHardRecovery,
          reason: "fresh-transaction-still-stalled"
        )
    }
  }

  /// Scalar distance liveness is independent from generic NI liveness. Camera
  /// may continue using fresh direction/transform while distance recovers, but
  /// those signals can never refresh or satisfy this policy.
  static func evaluateDistance(
    health: SpatialRangingHealth,
    role: SpatialRangingHealthRole,
    now: CFTimeInterval,
    transportNearby: Bool
  ) -> SpatialRangingHealthEvaluation {
    let timing = self.timing(for: role)
    let distanceAge = health.distanceMeasurementAge(at: now)
    let transactionAge = health.transactionStartedAt.map {
      max(0, now - $0)
    } ?? .greatestFiniteMagnitude
    let distanceOrTransactionAge = health.currentAttemptTimestamp(
      health.lastDistanceAt
    ).map { max(0, now - $0) } ?? transactionAge
    let hasCurrentDistance = health.isDistanceMeasurementHealthy(
      at: now,
      role: role
    )

    switch health.distanceState {
    case .acquiring:
      return !hasCurrentDistance
        && distanceOrTransactionAge >= timing.degradedDistanceMeasurementAge
        ? SpatialRangingHealthEvaluation(
          action: .markDegraded,
          reason: "distance-missing-while-acquiring"
        )
        : SpatialRangingHealthEvaluation(action: .wait, reason: "distance-acquiring")

    case .healthy:
      return !hasCurrentDistance
        && distanceAge >= timing.degradedDistanceMeasurementAge
        ? SpatialRangingHealthEvaluation(
          action: .markDegraded,
          reason: "distance-measurement-stale"
        )
        : SpatialRangingHealthEvaluation(action: .wait, reason: "distance-healthy")

    case .degraded:
      if hasCurrentDistance {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "distance-sample-returned-confirming-recovery"
        )
      }
      guard role != .backgroundResponder else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "background-responder-passive-distance-recovery"
        )
      }
      if health.distanceSoftRecoveryAttempts < timing.distanceMaximumSoftRecoveryAttempts {
        let canRetry = health.distanceLastSoftRecoveryAt.map {
          now - $0 >= min(0.75, timing.distanceSoftRecoveryTimeout * 0.4)
        } ?? true
        if canRetry {
          return SpatialRangingHealthEvaluation(
            action: .startSoftRecovery,
            reason: transportNearby
              ? "distance-stalled-soft-recovery"
              : "distance-stalled-soft-recovery-transport-unavailable"
          )
        }
      }
      let stalledAt = health.distanceRecoveryStartedAt
        ?? health.lastDistanceLostAt
        ?? health.transactionStartedAt
      guard let stalledAt,
        now - stalledAt >= timing.distanceSoftRecoveryTimeout
      else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "distance-soft-recovery-window-open"
        )
      }
      return SpatialRangingHealthEvaluation(
        action: .startHardRecovery,
        reason: transportNearby
          ? "distance-soft-recovery-timeout"
          : "distance-soft-recovery-timeout-transport-unavailable"
      )

    case .softRecovering:
      if hasCurrentDistance {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "distance-recovery-measurements-returned"
        )
      }
      guard let recoveryStartedAt = health.distanceRecoveryStartedAt else {
        return SpatialRangingHealthEvaluation(
          action: .startHardRecovery,
          reason: "distance-soft-recovery-start-time-missing"
        )
      }
      return now - recoveryStartedAt >= timing.distanceSoftRecoveryTimeout
        ? SpatialRangingHealthEvaluation(
          action: .startHardRecovery,
          reason: "distance-soft-recovery-timeout"
        )
        : SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "distance-soft-recovery-in-progress"
        )

    case .renegotiating:
      if hasCurrentDistance {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "fresh-distance-transaction-recovered"
        )
      }
      guard role != .backgroundResponder,
        let recoveryStartedAt = health.distanceRecoveryStartedAt,
        now - recoveryStartedAt >= timing.distanceHardRecoveryTimeout
      else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: role == .backgroundResponder
            ? "background-responder-passive-distance-recovery"
            : "distance-renegotiation-in-progress"
        )
      }
      let backoff = min(
        timing.distanceMaximumHardRecoveryBackoff,
        timing.distanceMinimumHardRecoveryInterval
          * pow(2, Double(max(0, health.distanceHardRecoveryAttempts - 1)))
      )
      guard health.distanceLastHardRecoveryAt.map({ now - $0 >= backoff }) ?? true else {
        return SpatialRangingHealthEvaluation(
          action: .wait,
          reason: "distance-hard-recovery-backoff"
        )
      }
      return SpatialRangingHealthEvaluation(
        action: .startHardRecovery,
        reason: transportNearby
          ? "fresh-distance-transaction-still-stalled"
          : "fresh-distance-transaction-transport-unavailable"
      )
    }
  }
}
