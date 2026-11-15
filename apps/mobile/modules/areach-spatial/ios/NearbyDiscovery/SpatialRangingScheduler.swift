import Foundation
import QuartzCore

enum SpatialRangingScheduleRole {
  case cameraViewer
  case foregroundProximity
  case backgroundResponder
  case suspended
}

/// A peer can be present without consuming a Nearby Interaction session. These
/// phases are scheduler state, not an identity claim exposed to JavaScript.
enum SpatialPeerRangingPhase: String {
  case unprobed
  case probing
  case candidate
  case verified
}

struct SpatialRangingSample {
  let peerId: String
  let measuredAt: CFTimeInterval
  let hasWorldTransform: Bool
  let hasDistance: Bool
  let hasDirectionalMeasurement: Bool
}

enum SpatialProbeDecision: String {
  case wait
  case promoteToCandidate
  case evict
}

struct SpatialProbeEvaluation {
  let decision: SpatialProbeDecision
  let reason: String
}

struct SpatialRangingCandidate {
  let peerId: String
  let phase: SpatialPeerRangingPhase
  let isActive: Bool
  let isPending: Bool
  let isLocallyInitiated: Bool
  let isEligible: Bool
  let isVerified: Bool
  let isTentative: Bool
  let isNearVisibleBody: Bool
  let isNearCarryRegion: Bool
  let hasUsefulMeasurement: Bool
  let hasDistanceOnlyMeasurement: Bool
  let hasDirectionalMeasurement: Bool
  let hasProjectableMeasurement: Bool
  let measurementFreshness: Double
  let cameraInterest: Double
  let cameraInterestAge: CFTimeInterval
  let lastCameraRelevantAt: CFTimeInterval?
  let signalStrength: Double?
  let lastRangedAt: CFTimeInterval?
  let leaseStartedAt: CFTimeInterval?
  /// Explicit aliases make the probe lifecycle visible at call sites. The
  /// lease value remains for compatibility with the existing harness.
  let probeStartedAt: CFTimeInterval?
  let firstMeasurementAt: CFTimeInterval?
  let firstDistanceAt: CFTimeInterval?
  let firstProjectableMeasurementAt: CFTimeInterval?
  let probeDeadlineAt: CFTimeInterval?
  let firstUsefulMeasurementAt: CFTimeInterval?
  let expectedInformationGain: Double
  let retryAfter: CFTimeInterval
  /// Health is deliberately carried beside identity phase. A verified peer
  /// can be important while its NI delegate is unhealthy, and a healthy
  /// unverified peer can still be a useful acquisition candidate.
  let healthState: SpatialRangingHealthState
  let distanceHealthState: SpatialRangingDistanceHealthState
  let lastUsefulMeasurementAt: CFTimeInterval?
  let usefulMeasurementAge: CFTimeInterval
  let isMeasurementHealthy: Bool
  let isMeasurementDegraded: Bool
  let isDistanceHealthy: Bool
  let isDistanceDegraded: Bool
  let isRecovering: Bool
  let cameraAssistanceRecovering: Bool

  init(
    peerId: String,
    phase: SpatialPeerRangingPhase,
    isActive: Bool,
    isPending: Bool,
    isLocallyInitiated: Bool = false,
    isEligible: Bool,
    isVerified: Bool,
    isTentative: Bool,
    isNearVisibleBody: Bool,
    isNearCarryRegion: Bool,
    hasUsefulMeasurement: Bool,
    hasDistanceOnlyMeasurement: Bool,
    hasDirectionalMeasurement: Bool = false,
    hasProjectableMeasurement: Bool,
    measurementFreshness: Double,
    cameraInterest: Double,
    cameraInterestAge: CFTimeInterval,
    lastCameraRelevantAt: CFTimeInterval?,
    signalStrength: Double?,
    lastRangedAt: CFTimeInterval?,
    leaseStartedAt: CFTimeInterval?,
    probeStartedAt: CFTimeInterval?,
    firstMeasurementAt: CFTimeInterval?,
    firstDistanceAt: CFTimeInterval?,
    firstProjectableMeasurementAt: CFTimeInterval?,
    probeDeadlineAt: CFTimeInterval?,
    firstUsefulMeasurementAt: CFTimeInterval?,
    expectedInformationGain: Double,
    retryAfter: CFTimeInterval,
    healthState: SpatialRangingHealthState = .healthy,
    lastUsefulMeasurementAt: CFTimeInterval? = nil,
    usefulMeasurementAge: CFTimeInterval = .greatestFiniteMagnitude,
    isMeasurementHealthy: Bool = true,
    isMeasurementDegraded: Bool = false,
    distanceHealthState: SpatialRangingDistanceHealthState = .healthy,
    isDistanceHealthy: Bool = true,
    isDistanceDegraded: Bool = false,
    isRecovering: Bool = false,
    cameraAssistanceRecovering: Bool = false
  ) {
    self.peerId = peerId
    self.phase = phase
    self.isActive = isActive
    self.isPending = isPending
    self.isLocallyInitiated = isLocallyInitiated
    self.isEligible = isEligible
    self.isVerified = isVerified
    self.isTentative = isTentative
    self.isNearVisibleBody = isNearVisibleBody
    self.isNearCarryRegion = isNearCarryRegion
    self.hasUsefulMeasurement = hasUsefulMeasurement
    self.hasDistanceOnlyMeasurement = hasDistanceOnlyMeasurement
    self.hasDirectionalMeasurement = hasDirectionalMeasurement
    self.hasProjectableMeasurement = hasProjectableMeasurement
    self.measurementFreshness = measurementFreshness
    self.cameraInterest = cameraInterest
    self.cameraInterestAge = cameraInterestAge
    self.lastCameraRelevantAt = lastCameraRelevantAt
    self.signalStrength = signalStrength
    self.lastRangedAt = lastRangedAt
    self.leaseStartedAt = leaseStartedAt
    self.probeStartedAt = probeStartedAt
    self.firstMeasurementAt = firstMeasurementAt
    self.firstDistanceAt = firstDistanceAt
    self.firstProjectableMeasurementAt = firstProjectableMeasurementAt
    self.probeDeadlineAt = probeDeadlineAt
    self.firstUsefulMeasurementAt = firstUsefulMeasurementAt
    self.expectedInformationGain = expectedInformationGain
    self.retryAfter = retryAfter
    self.healthState = healthState
    self.lastUsefulMeasurementAt = lastUsefulMeasurementAt
    self.usefulMeasurementAge = usefulMeasurementAge
    self.isMeasurementHealthy = isMeasurementHealthy
    self.isMeasurementDegraded = isMeasurementDegraded
    self.distanceHealthState = distanceHealthState
    self.isDistanceHealthy = isDistanceHealthy
    self.isDistanceDegraded = isDistanceDegraded
    self.isRecovering = isRecovering
    self.cameraAssistanceRecovering = cameraAssistanceRecovering
  }
}

struct SpatialRangingPlan {
  let releasePeerIds: [String]
  let acquirePeerIds: [String]
}

struct SpatialEDMSelectionPlan {
  let bestPeerId: String?
  let candidatePeerId: String?
  let candidateSince: CFTimeInterval?
  let shouldMigrate: Bool
}

enum SpatialInboundAdmissionDecision: Equatable {
  case acceptWithSpareCapacity
  case acceptAfterYield(peerId: String)
  case busy(reason: String)
}

/// Prevents a foreground phone from immediately reclaiming an edge that the
/// other foreground phone just released to range a waiting attendee. This is
/// a local proactive retry delay only; authenticated inbound requests are
/// still admitted by `SpatialRangingAdmissionPolicy`.
enum SpatialForegroundRangingPolicy {
  static func remoteStopRetryDeadline(
    role: SpatialRangingScheduleRole,
    now: CFTimeInterval
  ) -> CFTimeInterval? {
    guard role == .foregroundProximity else {
      return nil
    }
    return now + SpatialRangingTuning.foregroundRemoteStopCooldownDuration
  }
}

struct SpatialRangingSessionRemoval: Equatable {
  let wasActive: Bool
  let wasPending: Bool
  let wasOutbound: Bool

  var hadRangingOwnership: Bool {
    wasActive || wasPending || wasOutbound
  }
}

/// Keeps the service's active, pending, and locally initiated indexes in sync.
/// Each set must be mutated before combining the results: using short-circuit
/// boolean operators around `remove` can leave an outbound owner behind.
enum SpatialRangingSessionOwnership {
  static func insertOutboundAttempt(
    _ peerId: String,
    pendingPeerIds: inout Set<String>,
    outboundPeerIds: inout Set<String>
  ) -> Bool {
    guard
      !pendingPeerIds.contains(peerId),
      !outboundPeerIds.contains(peerId)
    else {
      return false
    }

    pendingPeerIds.insert(peerId)
    outboundPeerIds.insert(peerId)
    return true
  }

  static func removePeer(
    _ peerId: String,
    activePeerIds: inout Set<String>,
    pendingPeerIds: inout Set<String>,
    outboundPeerIds: inout Set<String>
  ) -> SpatialRangingSessionRemoval {
    let wasActive = activePeerIds.remove(peerId) != nil
    let wasPending = pendingPeerIds.remove(peerId) != nil
    let wasOutbound = outboundPeerIds.remove(peerId) != nil
    return SpatialRangingSessionRemoval(
      wasActive: wasActive,
      wasPending: wasPending,
      wasOutbound: wasOutbound
    )
  }

  @discardableResult
  static func removeOrphanedOutboundPeerIds(
    activePeerIds: Set<String>,
    pendingPeerIds: Set<String>,
    outboundPeerIds: inout Set<String>
  ) -> [String] {
    let livePeerIds = activePeerIds.union(pendingPeerIds)
    let orphanedPeerIds = outboundPeerIds.subtracting(livePeerIds).sorted()
    outboundPeerIds.subtract(orphanedPeerIds)
    return orphanedPeerIds
  }
}

/// Separates actual NI capacity from a runtime role's local proactive budget.
/// The service filters and orders yieldablePeerIds before calling this policy.
struct SpatialRangingAdmissionPolicy {
  func decision(
    role: SpatialRangingScheduleRole,
    activeSessionCount: Int,
    pendingSessionCount: Int,
    hardwareCapacity: Int,
    requestingPeerId: String,
    yieldablePeerIds: [String]
  ) -> SpatialInboundAdmissionDecision {
    guard role != .suspended else {
      return .busy(reason: "runtime-suspended")
    }

    let capacity = max(0, hardwareCapacity)
    let occupied = max(0, activeSessionCount) + max(0, pendingSessionCount)
    if occupied < capacity {
      return .acceptWithSpareCapacity
    }

    guard role == .foregroundProximity,
      let peerId = yieldablePeerIds.first(where: { $0 != requestingPeerId })
    else {
      return .busy(reason: "hardware-capacity-exhausted-no-safe-yield")
    }

    return .acceptAfterYield(peerId: peerId)
  }
}

/// Pure scheduler policy. NearbyInteraction session creation remains in the
/// service, while this policy can be exercised with 20+ synthetic peers.
struct SpatialRangingScheduler {
  func evaluateProbe(
    candidate: SpatialRangingCandidate,
    promotionInterest: Double,
    evictionInterest: Double,
    now: CFTimeInterval = CACurrentMediaTime()
  ) -> SpatialProbeEvaluation {
    guard candidate.phase == .probing else {
      return SpatialProbeEvaluation(
        decision: .wait,
        reason: "peer-is-not-probing"
      )
    }

    guard candidate.hasUsefulMeasurement else {
      if probeDeadlineHasElapsed(candidate, now: now) {
        return SpatialProbeEvaluation(
          decision: .evict,
          reason: "probe-deadline-without-measurement"
        )
      }

      return SpatialProbeEvaluation(
        decision: .wait,
        reason: "waiting-for-useful-measurement"
      )
    }

    guard candidate.hasProjectableMeasurement
      || candidate.hasDirectionalMeasurement
    else {
      if candidate.hasDistanceOnlyMeasurement {
        if candidate.isNearVisibleBody
          || candidate.isNearCarryRegion
          || candidate.cameraInterest >= promotionInterest
        {
          return SpatialProbeEvaluation(
            decision: .promoteToCandidate,
            reason: "distance-only-camera-depth-interest"
          )
        }

        if let firstMeasurementAt = candidate.firstMeasurementAt
          ?? candidate.firstDistanceAt
        {
          let measurementAge = max(0, now - firstMeasurementAt)
          if candidate.cameraInterest <= evictionInterest,
            measurementAge >= SpatialRangingTuning.distanceOnlyProbeGracePeriod
          {
            return SpatialProbeEvaluation(
              decision: .evict,
              reason: "distance-only-outside-camera-interest"
            )
          }
        }
      }

      if probeDeadlineHasElapsed(candidate, now: now) {
        return SpatialProbeEvaluation(
          decision: candidate.cameraInterest > evictionInterest
            || candidate.isNearVisibleBody
            || candidate.isNearCarryRegion
            ? .promoteToCandidate
            : .evict,
          reason: "distance-only-probe-deadline"
        )
      }

      return SpatialProbeEvaluation(
        decision: .wait,
        reason: "waiting-for-projectable-measurement"
      )
    }

    if candidate.isVerified
      || candidate.isTentative
      || candidate.isNearVisibleBody
      || candidate.isNearCarryRegion
      || candidate.cameraInterest >= promotionInterest
    {
      return SpatialProbeEvaluation(
        decision: .promoteToCandidate,
        reason: "camera-interest"
      )
    }

    if candidate.cameraInterest <= evictionInterest {
      return SpatialProbeEvaluation(
        decision: .evict,
        reason: "outside-camera-interest"
      )
    }

    // The middle band is deliberately retained for one more scheduler pass.
    // This avoids making identity acquisition depend on a single noisy UWB
    // sample while still allowing the probe timeout to reclaim the slot.
    return SpatialProbeEvaluation(
      decision: .wait,
      reason: "camera-interest-ambiguous"
    )
  }

  func plan(
    candidates: [SpatialRangingCandidate],
    role: SpatialRangingScheduleRole,
    now: CFTimeInterval,
    sessionCapacity: Int,
    outboundCapacity: Int,
    outboundCount: Int,
    probeTimeout: CFTimeInterval,
    candidateLeaseDuration: CFTimeInterval,
    verifiedLeaseDuration: CFTimeInterval,
    probeHardDeadline: CFTimeInterval = SpatialRangingTuning.probeHardDeadline,
    foregroundProximityLeaseDuration: CFTimeInterval = SpatialRangingTuning.foregroundProximityLeaseDuration,
    verifiedInterestKeepScore: Double = SpatialRangingTuning.verifiedInterestKeepScore,
    verifiedInterestHysteresisDuration: CFTimeInterval = SpatialRangingTuning.verifiedInterestHysteresisDuration,
    verifiedInterestReleaseDuration: CFTimeInterval = SpatialRangingTuning.verifiedInterestReleaseDuration
  ) -> SpatialRangingPlan {
    guard role == .cameraViewer || role == .foregroundProximity else {
      return SpatialRangingPlan(releasePeerIds: [], acquirePeerIds: [])
    }

    if role == .foregroundProximity {
      return foregroundProximityPlan(
        candidates: candidates,
        now: now,
        sessionCapacity: sessionCapacity,
        outboundCapacity: outboundCapacity,
        outboundCount: outboundCount,
        probeTimeout: probeTimeout,
        candidateLeaseDuration: candidateLeaseDuration,
        foregroundProximityLeaseDuration: foregroundProximityLeaseDuration,
        probeHardDeadline: probeHardDeadline
      )
    }

    let normalizedCapacity = max(0, sessionCapacity)
    let active = candidates.filter(\.isActive)
    let pending = candidates.filter(\.isPending)
    let waiting = candidates.filter {
      !$0.isActive && !$0.isPending && $0.isEligible && now >= $0.retryAfter
    }
    let hasUnprobedBacklog = role == .cameraViewer
      && waiting.contains { $0.phase == .unprobed }
    let reservedProbeSlots = hasUnprobedBacklog ? 1 : 0
    let capacityForStickyWork = max(
      0,
      normalizedCapacity - reservedProbeSlots
    )

    // Verified work is sticky, followed by a candidate with fresh spatial
    // evidence. The reserve is applied before this list is built so two old
    // verified sessions cannot permanently consume every acquisition slot.
    let stickyIds = Set(
      active
        .filter { candidate in
          guard candidate.phase == .verified || candidate.phase == .candidate else {
            return false
          }

          // Recovery owns the current slot until the fresh transaction has
          // either produced useful measurements or reached its bounded
          // recovery decision. This avoids the scheduler rotating a session
          // out from under the watchdog.
          if candidate.isRecovering {
            return true
          }

          // Identity importance is not a health signal. A stale verified
          // link may be released when it is not currently camera-relevant.
          if candidate.isMeasurementDegraded {
            return false
          }

          // AR tracking can be temporarily unavailable while UWB distance
          // remains useful. Keep a healthy verified session alive so the
          // current camera-assistance configuration can be reattached rather
          // than forcing a new identity acquisition cycle.
          if candidate.cameraAssistanceRecovering {
            return true
          }

          if candidate.phase != .verified {
            return true
          }

          // Foreground proximity is the event's attendee-list mode. It has
          // no camera-interest signal by design, so a verified link must stay
          // sticky while the event remains active. Camera relevance is only
          // used to rotate scarce sessions for the camera viewer.
          if role == .foregroundProximity {
            return true
          }

          return isCameraRelevant(
            candidate,
            now: now,
            keepScore: verifiedInterestKeepScore,
            hysteresisDuration: verifiedInterestHysteresisDuration
          )
        }
        .sorted {
          stickyPriority(for: $0, now: now)
            > stickyPriority(for: $1, now: now)
        }
        .prefix(capacityForStickyWork)
        .map(\.peerId)
    )

    let activeAndPendingCount = active.count + pending.count
    let requiredReleaseCount = max(
      0,
      activeAndPendingCount - capacityForStickyWork
    )
    // A verified session should not be torn down merely because the camera
    // is pointed away when there is no other peer ready to use the slot. With
    // one nearby phone this would release the only useful session, immediately
    // reacquire the same peer, and leave the link in a renegotiation loop while
    // the user is trying to look back at it.
    let hasReplacementOpportunity = !waiting.isEmpty
    let releasable = active
      .filter { candidate in
        guard !stickyIds.contains(candidate.peerId) else {
          return false
        }

        let leaseAge = now - (candidate.leaseStartedAt ?? now)
        switch candidate.phase {
        case .unprobed:
          return false
        case .probing:
          // A useful distance-only sample is not permission to hold a slot
          // forever. Camera feedback may promote it sooner, but this absolute
          // deadline always returns the slot to the acquisition queue.
          return probeDeadlineHasElapsed(
            candidate,
            now: now,
            hardDeadline: probeHardDeadline
          )
            || (!candidate.hasUsefulMeasurement && leaseAge >= probeTimeout)
        case .candidate:
          let candidateMinimumHold = min(
            candidateLeaseDuration * 0.25,
            0.45
          )
          return leaseAge >= candidateLeaseDuration
            || (hasUnprobedBacklog && leaseAge >= candidateMinimumHold)
        case .verified:
          if candidate.isMeasurementDegraded && !candidate.isRecovering {
            return true
          }
          if candidate.cameraAssistanceRecovering {
            return false
          }
          let clearlyOutsideCameraInterest = role == .cameraViewer
            && shouldReleaseVerified(
              candidate,
              now: now,
              keepScore: verifiedInterestKeepScore,
              releaseDuration: verifiedInterestReleaseDuration,
              role: role
            )
          if clearlyOutsideCameraInterest {
            return true
          }

          let hasGoneQuiet = candidate.measurementFreshness < 0.12
            && candidate.cameraInterest < 0.1
          return leaseAge >= verifiedLeaseDuration
            && (hasGoneQuiet || hasUnprobedBacklog)
            && (hasReplacementOpportunity || requiredReleaseCount > 0)
        }
      }
      .sorted {
        let firstPriority = releasePriority(for: $0, now: now)
        let secondPriority = releasePriority(for: $1, now: now)
        if firstPriority != secondPriority {
          return firstPriority < secondPriority
        }

        return ($0.leaseStartedAt ?? 0) < ($1.leaseStartedAt ?? 0)
      }
    let voluntaryReleases = active
      .filter {
        guard hasReplacementOpportunity else {
          return false
        }

        return shouldReleaseVerified(
          $0,
          now: now,
          keepScore: verifiedInterestKeepScore,
          releaseDuration: verifiedInterestReleaseDuration,
          role: role
        )
      }
      .sorted {
        releasePriority(for: $0, now: now)
          < releasePriority(for: $1, now: now)
      }
      .map(\.peerId)
    let releaseOrder = (voluntaryReleases + releasable.map(\.peerId)).reduce(
      into: [String]()
    ) { result, peerId in
      if !result.contains(peerId) {
        result.append(peerId)
      }
    }
    let releaseCount = max(requiredReleaseCount, voluntaryReleases.count)
    let releaseIds = Array(releaseOrder.prefix(releaseCount))

    let availableSessionSlots = max(
      0,
      normalizedCapacity - activeAndPendingCount + releaseIds.count
    )
    let availableOutboundSlots = max(
      0,
      outboundCapacity - outboundCount
    )
    let acquireCount = min(
      availableSessionSlots,
      availableOutboundSlots,
      waiting.count
    )

    let rankedWaiting = waiting.sorted {
      let firstPriority = priority(for: $0, now: now)
      let secondPriority = priority(for: $1, now: now)
      if firstPriority != secondPriority {
        return firstPriority > secondPriority
      }

      let firstLastRanged = $0.lastRangedAt ?? 0
      let secondLastRanged = $1.lastRangedAt ?? 0
      if firstLastRanged != secondLastRanged {
        return firstLastRanged < secondLastRanged
      }

      return $0.peerId < $1.peerId
    }

    // The reserve is a real allocation, not only a priority bonus. Choose an
    // unprobed peer first whenever the camera has a backlog, then use remaining
    // capacity for candidates/verified peers waiting to reacquire.
    let orderedWaiting: [SpatialRangingCandidate]
    if hasUnprobedBacklog {
      let unprobed = rankedWaiting.filter { $0.phase == .unprobed }
      let other = rankedWaiting.filter { $0.phase != .unprobed }
      orderedWaiting = unprobed + other
    } else {
      orderedWaiting = rankedWaiting
    }

    return SpatialRangingPlan(
      releasePeerIds: releaseIds,
      acquirePeerIds: Array(
        orderedWaiting
          .prefix(acquireCount)
          .map(\.peerId)
      )
    )
  }

  private func foregroundProximityPlan(
    candidates: [SpatialRangingCandidate],
    now: CFTimeInterval,
    sessionCapacity: Int,
    outboundCapacity: Int,
    outboundCount: Int,
    probeTimeout: CFTimeInterval,
    candidateLeaseDuration: CFTimeInterval,
    foregroundProximityLeaseDuration: CFTimeInterval,
    probeHardDeadline: CFTimeInterval
  ) -> SpatialRangingPlan {
    let normalizedCapacity = max(0, sessionCapacity)
    let active = candidates.filter(\.isActive)
    let pending = candidates.filter(\.isPending)
    let activeAndPendingCount = active.count + pending.count
    let waiting = candidates.filter {
      !$0.isActive && !$0.isPending && $0.isEligible && now >= $0.retryAfter
    }
    let rangingWork = candidates.filter { $0.isActive || $0.isPending }
    let proactiveWork = rangingWork.filter {
      $0.isLocallyInitiated && ($0.isActive || $0.isPending)
    }
    let nonOutboundCount = max(0, activeAndPendingCount - outboundCount)
    let foregroundOutboundCapacity = min(
      max(0, outboundCapacity),
      max(0, normalizedCapacity - nonOutboundCount)
    )
    let freeSessionSlots = max(0, normalizedCapacity - activeAndPendingCount)
    let freeOutboundSlots = max(0, foregroundOutboundCapacity - outboundCount)
    let immediatelyAvailableSlots = min(freeSessionSlots, freeOutboundSlots)

    let forcedReleaseCount = max(
      max(0, activeAndPendingCount - normalizedCapacity),
      max(0, outboundCount - foregroundOutboundCapacity)
    )
    let proactiveLeaseExpired = proactiveWork.filter { candidate in
      foregroundLeaseElapsed(
        candidate,
        now: now,
        probeTimeout: probeTimeout,
        candidateLeaseDuration: candidateLeaseDuration,
        foregroundProximityLeaseDuration: foregroundProximityLeaseDuration,
        probeHardDeadline: probeHardDeadline
      )
    }
    // Responder links do not consume the local proactive budget. They become
    // rotation candidates only when they fill the actual hardware pool, a
    // waiter exists, and unused local initiation budget could use the freed
    // hardware slot. This preserves healthy spare-capacity responders.
    let canYieldResponderForProactiveWork = freeSessionSlots == 0
      && outboundCount < max(0, outboundCapacity)
    let responderLeaseExpired = canYieldResponderForProactiveWork
      ? rangingWork.filter { !$0.isLocallyInitiated }.filter { candidate in
        foregroundLeaseElapsed(
          candidate,
          now: now,
          probeTimeout: probeTimeout,
          candidateLeaseDuration: candidateLeaseDuration,
          foregroundProximityLeaseDuration: foregroundProximityLeaseDuration,
          probeHardDeadline: probeHardDeadline
        )
      }
      : []
    let leaseExpired = proactiveLeaseExpired + responderLeaseExpired
    let fairReleaseCount = waiting.isEmpty
      ? 0
      : min(
        leaseExpired.count,
        max(0, waiting.count - immediatelyAvailableSlots)
      )
    let orderedForcedReleases = rangingWork.sorted {
      foregroundReleaseOrder($0, $1, now: now)
    }
    let releaseOrder = (
      orderedForcedReleases.prefix(forcedReleaseCount).map(\.peerId)
        + leaseExpired.sorted {
          foregroundReleaseOrder($0, $1, now: now)
        }.map(\.peerId)
    ).reduce(into: [String]()) { result, peerId in
      if !result.contains(peerId) {
        result.append(peerId)
      }
    }
    let releaseCount = max(forcedReleaseCount, fairReleaseCount)
    let releaseIds = Array(releaseOrder.prefix(releaseCount))
    let releasedOutboundCount = releaseIds.filter { peerId in
      proactiveWork.contains { $0.peerId == peerId }
    }.count
    let releasedResponderCount = max(0, releaseIds.count - releasedOutboundCount)
    let availableSessionSlots = max(
      0,
      normalizedCapacity - activeAndPendingCount + releaseIds.count
    )
    let nonOutboundCountAfterRelease = max(
      0,
      nonOutboundCount - releasedResponderCount
    )
    let outboundCapacityAfterRelease = min(
      max(0, outboundCapacity),
      max(0, normalizedCapacity - nonOutboundCountAfterRelease)
    )
    let availableOutboundSlots = max(
      0,
      outboundCapacityAfterRelease - outboundCount + releasedOutboundCount
    )
    let acquireCount = min(
      availableSessionSlots,
      availableOutboundSlots,
      waiting.count
    )
    let orderedWaiting = waiting.sorted {
      let firstLastRangedAt = $0.lastRangedAt ?? -.greatestFiniteMagnitude
      let secondLastRangedAt = $1.lastRangedAt ?? -.greatestFiniteMagnitude
      if firstLastRangedAt != secondLastRangedAt {
        return firstLastRangedAt < secondLastRangedAt
      }
      return $0.peerId < $1.peerId
    }

    return SpatialRangingPlan(
      releasePeerIds: releaseIds,
      acquirePeerIds: Array(orderedWaiting.prefix(acquireCount).map(\.peerId))
    )
  }

  private func foregroundLeaseElapsed(
    _ candidate: SpatialRangingCandidate,
    now: CFTimeInterval,
    probeTimeout: CFTimeInterval,
    candidateLeaseDuration: CFTimeInterval,
    foregroundProximityLeaseDuration: CFTimeInterval,
    probeHardDeadline: CFTimeInterval
  ) -> Bool {
    guard !candidate.isRecovering else {
      return false
    }

    let leaseAge = now - (candidate.leaseStartedAt ?? now)
    switch candidate.phase {
    case .unprobed:
      return leaseAge >= probeTimeout
    case .probing:
      return probeDeadlineHasElapsed(
        candidate,
        now: now,
        hardDeadline: probeHardDeadline
      ) || (!candidate.hasUsefulMeasurement && leaseAge >= probeTimeout)
    case .candidate:
      return leaseAge >= min(
        candidateLeaseDuration,
        foregroundProximityLeaseDuration
      )
    case .verified:
      return leaseAge >= foregroundProximityLeaseDuration
    }
  }

  private func foregroundReleaseOrder(
    _ first: SpatialRangingCandidate,
    _ second: SpatialRangingCandidate,
    now: CFTimeInterval
  ) -> Bool {
    if first.isDistanceDegraded != second.isDistanceDegraded {
      return first.isDistanceDegraded
    }
    if first.isDistanceHealthy != second.isDistanceHealthy {
      return !first.isDistanceHealthy
    }
    let firstLeaseAge = now - (first.leaseStartedAt ?? now)
    let secondLeaseAge = now - (second.leaseStartedAt ?? now)
    if firstLeaseAge != secondLeaseAge {
      return firstLeaseAge > secondLeaseAge
    }
    return first.peerId < second.peerId
  }

  /// Selects at most one EDM owner. The candidate must remain better than the
  /// current owner for the configured dwell time before migration is allowed.
  /// Keeping this pure makes the one-owner invariant and migration hysteresis
  /// deterministic to exercise without NearbyInteraction hardware.
  func selectEDMOwner(
    candidates: [SpatialRangingCandidate],
    currentPeerId: String?,
    candidatePeerId: String?,
    candidateSince: CFTimeInterval?,
    now: CFTimeInterval,
    minimumScoreDelta: Double,
    minimumDwell: CFTimeInterval
  ) -> SpatialEDMSelectionPlan {
    guard let best = candidates.max(by: { first, second in
      let firstPriority = priority(for: first, now: now)
      let secondPriority = priority(for: second, now: now)
      if firstPriority == secondPriority {
        return first.peerId > second.peerId
      }

      return firstPriority < secondPriority
    }) else {
      return SpatialEDMSelectionPlan(
        bestPeerId: nil,
        candidatePeerId: nil,
        candidateSince: nil,
        shouldMigrate: false
      )
    }

    guard let currentPeerId else {
      return SpatialEDMSelectionPlan(
        bestPeerId: best.peerId,
        candidatePeerId: nil,
        candidateSince: nil,
        shouldMigrate: true
      )
    }

    guard currentPeerId != best.peerId else {
      return SpatialEDMSelectionPlan(
        bestPeerId: best.peerId,
        candidatePeerId: nil,
        candidateSince: nil,
        shouldMigrate: false
      )
    }

    let currentPriority = candidates.first {
      $0.peerId == currentPeerId
    }.map { priority(for: $0, now: now) } ?? 0
    let bestPriority = priority(for: best, now: now)
    guard bestPriority >= currentPriority + minimumScoreDelta else {
      return SpatialEDMSelectionPlan(
        bestPeerId: best.peerId,
        candidatePeerId: nil,
        candidateSince: nil,
        shouldMigrate: false
      )
    }

    guard candidatePeerId == best.peerId else {
      return SpatialEDMSelectionPlan(
        bestPeerId: best.peerId,
        candidatePeerId: best.peerId,
        candidateSince: now,
        shouldMigrate: false
      )
    }

    guard let candidateSince,
      now - candidateSince >= minimumDwell
    else {
      return SpatialEDMSelectionPlan(
        bestPeerId: best.peerId,
        candidatePeerId: best.peerId,
        candidateSince: candidateSince ?? now,
        shouldMigrate: false
      )
    }

    return SpatialEDMSelectionPlan(
      bestPeerId: best.peerId,
      candidatePeerId: nil,
      candidateSince: nil,
      shouldMigrate: true
    )
  }

  func priority(
    for candidate: SpatialRangingCandidate,
    now: CFTimeInterval
  ) -> Double {
    let phaseBonus: Double
    switch candidate.phase {
    case .verified:
      phaseBonus = 1.55
    case .candidate:
      phaseBonus = 1.0
    case .probing:
      phaseBonus = 0.35
    case .unprobed:
      phaseBonus = 0
    }

    let bodyBonus = candidate.isNearVisibleBody ? 0.35 : 0
    let carryBonus = candidate.isNearCarryRegion ? 0.55 : 0
    let neverRangedBonus = candidate.lastRangedAt == nil ? 0.65 : 0
    let fairnessAge = min(
      1.1,
      max(0, now - (candidate.lastRangedAt ?? 0)) / 12
    )
    let signalBonus = min(
      0.25,
      max(0, ((candidate.signalStrength ?? -100) + 100) / 100) * 0.25
    )

    let informationGain = max(0, min(2.0, candidate.expectedInformationGain))
    let distanceAmbiguityBonus = candidate.hasDistanceOnlyMeasurement
      && !candidate.hasProjectableMeasurement
      ? 0.48
      : 0
    let healthBonus: Double
    switch candidate.healthState {
    case .healthy:
      healthBonus = 0.15
    case .acquiring:
      healthBonus = 0.55
    case .degraded:
      healthBonus = 1.45
    case .softRecovering:
      healthBonus = 2.0
    case .renegotiating:
      healthBonus = 2.25
    }

    let distanceHealthBonus: Double
    switch candidate.distanceHealthState {
    case .healthy:
      distanceHealthBonus = 0
    case .acquiring:
      distanceHealthBonus = 0.2
    case .degraded:
      distanceHealthBonus = 1.45
    case .softRecovering:
      distanceHealthBonus = 2.0
    case .renegotiating:
      distanceHealthBonus = 2.25
    }

    return phaseBonus
      + bodyBonus
      + carryBonus
      + candidate.cameraInterest * 2.2
      + candidate.measurementFreshness * 0.6
      + neverRangedBonus
      + fairnessAge
      + signalBonus
      + informationGain
      + distanceAmbiguityBonus
      + max(healthBonus, distanceHealthBonus)
  }

  private func probeDeadlineHasElapsed(
    _ candidate: SpatialRangingCandidate,
    now: CFTimeInterval,
    hardDeadline: CFTimeInterval = SpatialRangingTuning.probeHardDeadline
  ) -> Bool {
    let probeStartedAt = candidate.probeStartedAt
      ?? candidate.leaseStartedAt
    guard let deadline = candidate.probeDeadlineAt
      ?? probeStartedAt.map({ $0 + hardDeadline })
    else {
      // Missing lifecycle metadata is a fail-safe release condition. A probe
      // must never become immortal because its timestamps were lost.
      return true
    }
    return now >= deadline
  }

  private func stickyPriority(
    for candidate: SpatialRangingCandidate,
    now: CFTimeInterval
  ) -> Double {
    priority(for: candidate, now: now)
      + (candidate.phase == .verified ? 0.4 : 0)
  }

  private func releasePriority(
    for candidate: SpatialRangingCandidate,
    now: CFTimeInterval
  ) -> Double {
    priority(for: candidate, now: now)
      - (candidate.phase == .probing ? 0.25 : 0)
  }

  private func isCameraRelevant(
    _ candidate: SpatialRangingCandidate,
    now: CFTimeInterval,
    keepScore: Double,
    hysteresisDuration: CFTimeInterval
  ) -> Bool {
    if candidate.isNearVisibleBody
      || candidate.isNearCarryRegion
      || candidate.cameraInterest >= keepScore
    {
      return true
    }

    guard let lastCameraRelevantAt = candidate.lastCameraRelevantAt else {
      return false
    }

    return now - lastCameraRelevantAt <= hysteresisDuration
  }

  private func shouldReleaseVerified(
    _ candidate: SpatialRangingCandidate,
    now: CFTimeInterval,
    keepScore: Double,
    releaseDuration: CFTimeInterval,
    role: SpatialRangingScheduleRole
  ) -> Bool {
    guard role == .cameraViewer else {
      return false
    }

    guard candidate.phase == .verified else {
      return false
    }

    guard !candidate.cameraAssistanceRecovering else {
      return false
    }

    guard !candidate.isNearVisibleBody,
      !candidate.isNearCarryRegion,
      candidate.cameraInterest < keepScore
    else {
      return false
    }

    let relevanceAge = candidate.lastCameraRelevantAt.map {
      max(0, now - $0)
    } ?? candidate.cameraInterestAge
    return relevanceAge >= releaseDuration
  }
}
