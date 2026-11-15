import Foundation
import NearbyInteraction
import QuartzCore

private enum SpatialRangingRecoveryDimension: Equatable {
  case spatial
  case distance
}

extension NearbyDiscoveryService {
  func startRangingScheduler() {
    guard
      rangingTimer == nil,
      localIdentity != nil,
      runtimeRole != .suspended
    else {
      return
    }

    let timer = DispatchSource.makeTimerSource(queue: stateQueue)
    timer.schedule(
      deadline: .now(),
      repeating: SpatialRangingTuning.schedulerInterval
    )
    timer.setEventHandler { [weak self] in
      self?.maintainRangingPool()
    }
    rangingTimer = timer
    timer.resume()
  }

  func stopRangingScheduler() {
    rangingTimer?.cancel()
    rangingTimer = nil
    acquisitionQueueSize = 0
    verificationPeerCount = 0
  }

  func resetRanging() {
    let sessions = Array(nearbySessions.values)

    nearbySessions.removeAll()
    peerTokens.removeAll()
    activeRangingPeerIds.removeAll()
    pendingRangingPeerIds.removeAll()
    outboundRangingPeerIds.removeAll()
    rangingStartedAt.removeAll()
    rangingRetryAfter.removeAll()
    peerLastRangedAt.removeAll()
    peerLinkStates.removeAll()
    lastSignpostedMeasurementTiers.removeAll()
    observedRangingTransactions.removeAll()
    peerCameraInterests.removeAll()
    peerLastCameraRelevantAt.removeAll()
    peerRangingPhases.removeAll()
    peerProbeStartedAt.removeAll()
    peerProbeDeadlineAt.removeAll()
    peerFirstMeasurementAt.removeAll()
    peerFirstDistanceAt.removeAll()
    peerFirstProjectableMeasurementAt.removeAll()
    peerFirstUsefulMeasurementAt.removeAll()
    peerProbeCounts.removeAll()
    peerRangingHealth.removeAll()
    peerCameraAssistanceSuppressed.removeAll()
    peersWithSuccessfulRanging.removeAll()
    peersWithSignpostedFirstNIUpdate.removeAll()
    peersWithSignpostedFirstDistance.removeAll()
    peersWithSignpostedFirstWorldTransform.removeAll()
    acquisitionQueueSize = 0
    verificationPeerCount = 0
    rangingRotationCount = 0
    rangingRetryCount = 0
    probePromotionCount = 0
    probeEvictionCount = 0
    probeTimeoutCount = 0
    distanceOnlyMeasurementCount = 0
    directionMeasurementCount = 0
    cameraAssistedMeasurementCount = 0
    hardwareSessionCapacity = Self.initialRangingCapacity
    didDiscoverRangingLimit = false
    didDiscoverExtendedDistanceLimit = false
    extendedDistancePeerId = nil
    extendedDistanceCandidatePeerId = nil
    extendedDistanceCandidateSince = nil
    extendedDistanceStartedAt = nil
    extendedDistanceLastUsefulAt = nil
    extendedDistanceCooldownUntil.removeAll()
    lastSignpostedExtendedDistancePeerId = nil
    lastSignpostedRangingSummary = nil
    lastSignpostedPresenceCount = nil
    peersWithSignpostedStaleWorldTransform.removeAll()
    peersWithSignpostedStaleDistance.removeAll()
    maximumDiscoveredPeerCount = 0

    for session in sessions {
      session.invalidate()
    }
  }

  /// Refresh camera-interest scores before matching finishes. The scheduler
  /// can therefore acquire a phone that is merely geometrically interesting,
  /// not only a phone that already has an identity assignment. When a complete
  /// peer set is supplied, a probing peer missing from the set was evaluated by
  /// the camera pass and can be evicted immediately if its projection is not
  /// useful.
  func updateCameraInterest(
    _ interests: [SpatialCameraInterest],
    evaluatedPeerIds: Set<String>? = nil
  ) {
    withStateQueue {
      guard runtimeRole == .cameraViewer else {
        return
      }

      let now = CACurrentMediaTime()
      let updatedPeerIds = Set(interests.map(\.peerId))
      for interest in interests {
        peerCameraInterests[interest.peerId] = interest
        if interest.isNearBody
          || interest.isNearCarryRegion
          || interest.score >= SpatialRangingTuning.verifiedInterestKeepScore
        {
          peerLastCameraRelevantAt[interest.peerId] = now
        }
      }

      if let evaluatedPeerIds {
        for peerId in evaluatedPeerIds where !updatedPeerIds.contains(peerId) {
          peerCameraInterests.removeValue(forKey: peerId)
        }
      }

      peerCameraInterests = peerCameraInterests.filter { _, interest in
        now - interest.measuredAt
          <= SpatialRangingTuning.cameraInterestRetentionDuration
      }

      if let evaluatedPeerIds {
        let probingPeerIds = activeRangingPeerIds.filter { peerId in
          peerRangingPhases[peerId] == .probing
            && evaluatedPeerIds.contains(peerId)
        }
        for peerId in probingPeerIds {
          evaluateProbeOnStateQueue(peerId, now: now)
        }
      }

      maybeMigrateExtendedDistanceMeasurement(at: now)
      maintainRangingPool()
    }
  }

  /// Matcher state is fed back into the native scheduler without exposing its
  /// internal association graph to React Native. Verified peers remain sticky;
  /// a newly tentative association is only a candidate until the matcher has
  /// completed its existing confirmation rules.
  func updateAssociationState(
    verifiedPeerIds: Set<String>,
    tentativePeerIds: Set<String>
  ) {
    withStateQueue {
      for peerId in verifiedPeerIds {
        peerRangingPhases[peerId] = .verified
      }
      for peerId in tentativePeerIds where !verifiedPeerIds.contains(peerId) {
        if peerRangingPhases[peerId] != .candidate,
          peerRangingPhases[peerId] != .verified
        {
          peerRangingPhases[peerId] = .candidate
          SpatialPerformance.signposter.emitEvent(
            "Association started",
            "Peer: \(peerId.prefix(8), privacy: .public)"
          )
        }
      }

      maintainRangingPool()
    }
  }

  private func evaluateProbeOnStateQueue(
    _ peerId: String,
    now: CFTimeInterval
  ) {
    guard
      activeRangingPeerIds.contains(peerId),
      peerRangingPhases[peerId] == .probing,
      peerFirstUsefulMeasurementAt[peerId] != nil
    else {
      return
    }

    guard let candidate = rangingCandidate(for: peerId, now: now) else {
      return
    }

    let evaluation = rangingScheduler.evaluateProbe(
      candidate: candidate,
      promotionInterest: SpatialRangingTuning.probePromotionInterest,
      evictionInterest: SpatialRangingTuning.probeEvictionInterest,
      now: now
    )
    switch evaluation.decision {
    case .wait:
      return
    case .promoteToCandidate:
      peerRangingPhases[peerId] = .candidate
      probePromotionCount += 1
      let probeDuration = candidate.firstUsefulMeasurementAt.map {
        max(0, $0 - (candidate.leaseStartedAt ?? $0))
      } ?? 0
      SpatialPerformance.signposter.emitEvent(
        "Probe promoted to candidate",
        "Peer: \(peerId.prefix(8), privacy: .public), reason: \(evaluation.reason, privacy: .public), duration milliseconds: \(Int(probeDuration * 1_000))"
      )
    case .evict:
      peerRangingPhases[peerId] = .unprobed
      peerProbeDeadlineAt.removeValue(forKey: peerId)
      peerProbeStartedAt.removeValue(forKey: peerId)
      peerFirstMeasurementAt.removeValue(forKey: peerId)
      peerFirstDistanceAt.removeValue(forKey: peerId)
      peerFirstProjectableMeasurementAt.removeValue(forKey: peerId)
      peerFirstUsefulMeasurementAt.removeValue(forKey: peerId)
      probeEvictionCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Probe evicted",
        "Peer: \(peerId.prefix(8), privacy: .public), reason: \(evaluation.reason, privacy: .public)"
      )
      endRanging(
        with: peerId,
        notifyPeer: true,
        reason: "probe-evicted",
        preserveSpatialState: false
      )
    }
  }

  /// Runs independently of allocation. A session can be active and still be
  /// unhealthy when NI is delivering callbacks without a usable distance or
  /// transform, so this watchdog is evaluated before the scheduler's pool
  /// policy on every state-queue tick.
  private func maintainRangingHealth(at now: CFTimeInterval) {
    for peerId in Array(activeRangingPeerIds) {
      var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
      if health.transactionStartedAt == nil {
        health.beginTransaction(
          at: rangingStartedAt[peerId] ?? now,
          state: .acquiring
        )
        peerRangingHealth[peerId] = health
      }

      let evaluation = SpatialRangingHealthPolicy.evaluate(
        health: health,
        role: rangingHealthRole,
        now: now,
        transportNearby: isPeerTransportNearby(peerId)
      )
      switch evaluation.action {
      case .wait:
        break
      case .markDegraded:
        if health.state == .healthy || health.state == .acquiring {
          health.state = .degraded
          health.consecutiveUsefulUpdates = 0
          health.lastUsefulMeasurementLostAt =
            health.lastUsefulMeasurementLostAt ?? now
          peerRangingHealth[peerId] = health
          SpatialPerformance.signposter.emitEvent(
            "Ranging health degraded",
            "Peer: \(peerId.prefix(8), privacy: .public), reason: \(evaluation.reason, privacy: .public), callback age: \(String(format: "%.2f", health.delegateCallbackAge(at: now))), useful age: \(String(format: "%.2f", health.usefulMeasurementAge(at: now)))"
          )
        }
      case .startSoftRecovery:
        startSoftRecovery(
          for: peerId,
          at: now,
          reason: evaluation.reason,
          dimension: .spatial
        )
      case .startHardRecovery:
        startHardRecovery(
          for: peerId,
          at: now,
          reason: evaluation.reason,
          dimension: .spatial
        )
      }

      guard activeRangingPeerIds.contains(peerId) else {
        continue
      }
      health = peerRangingHealth[peerId] ?? health
      let distanceEvaluation = SpatialRangingHealthPolicy.evaluateDistance(
        health: health,
        role: rangingHealthRole,
        now: now,
        transportNearby: isPeerTransportNearby(peerId)
      )
      switch distanceEvaluation.action {
      case .wait:
        break
      case .markDegraded:
        markDistanceHealthDegraded(
          for: peerId,
          at: now,
          reason: distanceEvaluation.reason
        )
      case .startSoftRecovery:
        startSoftRecovery(
          for: peerId,
          at: now,
          reason: distanceEvaluation.reason,
          dimension: .distance
        )
      case .startHardRecovery:
        startHardRecovery(
          for: peerId,
          at: now,
          reason: distanceEvaluation.reason,
          dimension: .distance
        )
      }
    }

    // Pending peers have no NI delegate stream yet, so their liveness clock is
    // the ranging request transaction itself. Keep this in the same watchdog
    // pass so a transport/acceptance stall cannot wait for a separate pool
    // policy to notice it.
    for peerId in Array(pendingRangingPeerIds) {
      guard
        let transactionId = currentOutboundRangingTransaction(for: peerId),
        now - (rangingStartedAt[peerId] ?? now)
          >= SpatialRangingTuning.rangingRequestTimeout
      else {
        continue
      }

      refreshTransportForRangingIfNeeded(
        for: peerId,
        at: now,
        reason: "ranging-request-timeout"
      )
      abortOutboundNegotiation(
        for: peerId,
        transactionId: transactionId,
        reason: "ranging-request-timeout"
      )
      resetNetworkConnectionForRangingRetry(
        to: peerId,
        reason: "ranging-request-timeout"
      )
    }
  }

  private func markDistanceHealthDegraded(
    for peerId: String,
    at now: CFTimeInterval,
    reason: String
  ) {
    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    guard health.distanceState == .healthy || health.distanceState == .acquiring else {
      peerRangingHealth[peerId] = health
      return
    }
    let previousDistanceState = health.distanceState
    health.distanceState = .degraded
    health.lastDistanceLostAt = health.lastDistanceLostAt ?? now
    peerRangingHealth[peerId] = health
    SpatialPerformance.signposter.emitEvent(
      "Distance health transition",
      "Peer: \(peerId.prefix(8), privacy: .public), from: \(previousDistanceState.rawValue, privacy: .public), to: degraded, role: \(self.runtimeRole.rawValue, privacy: .public)"
    )
    let distanceAge = health.distanceMeasurementAge(at: now)
    let timing = SpatialRangingHealthPolicy.timing(for: rangingHealthRole)
    SpatialPerformance.signposter.emitEvent(
      "Distance health degraded",
      "Peer: \(peerId.prefix(8), privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), reason: \(reason, privacy: .public), distance age: \(String(format: "%.2f", distanceAge)), direction age: \(String(format: "%.2f", self.peerAge(self.peerLastDirectionMeasurementAt[peerId] ?? self.peerRawDirectionalMeasurements[peerId]?.measuredAt, now: now))), transform age: \(String(format: "%.2f", self.peerAge(self.peerRawWorldTransformUpdatedAt[peerId], now: now)))"
    )
    if health.state == .healthy,
      health.usefulMeasurementAge(at: now) <= timing.healthyUsefulMeasurementAge
    {
      SpatialPerformance.signposter.emitEvent(
        "Distance stalled with spatial measurements still flowing",
        "Peer: \(peerId.prefix(8), privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), distance age: \(String(format: "%.2f", distanceAge)), active: \(self.activeRangingPeerIds.count), pending: \(self.pendingRangingPeerIds.count), local initiated: \(self.outboundRangingPeerIds.count)"
      )
    }
  }

  private func peerAge(
    _ timestamp: CFTimeInterval?,
    now: CFTimeInterval
  ) -> CFTimeInterval {
    guard let timestamp else {
      return .greatestFiniteMagnitude
    }
    return max(0, now - timestamp)
  }

  private func markRangingHealthDegraded(
    for peerId: String,
    at now: CFTimeInterval,
    reason: String
  ) {
    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    if health.transactionStartedAt == nil {
      health.beginTransaction(
        at: rangingStartedAt[peerId] ?? now,
        state: .acquiring
      )
    }
    guard health.state != .softRecovering, health.state != .renegotiating else {
      peerRangingHealth[peerId] = health
      return
    }

    let wasHealthy = health.state == .healthy
    health.state = .degraded
    health.consecutiveUsefulUpdates = 0
    health.lastUsefulMeasurementLostAt =
      health.lastUsefulMeasurementLostAt ?? now
    peerRangingHealth[peerId] = health
    if wasHealthy {
      SpatialPerformance.signposter.emitEvent(
        "Ranging health degraded",
        "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public)"
      )
    }
  }

  private func startSoftRecovery(
    for peerId: String,
    at now: CFTimeInterval,
    reason: String,
    dimension: SpatialRangingRecoveryDimension = .spatial
  ) {
    guard
      activeRangingPeerIds.contains(peerId),
      nearbySessions[peerId] != nil,
      let token = peerTokens[peerId]
    else {
      startHardRecovery(
        for: peerId,
        at: now,
        reason: "soft-recovery-prerequisites-missing",
        dimension: dimension
      )
      return
    }

    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    let timing = SpatialRangingHealthPolicy.timing(for: rangingHealthRole)
    let distanceTiming = timing
    let previousDistanceState = health.distanceState
    if dimension == .spatial {
      guard
        health.softRecoveryAttempts < timing.maximumSoftRecoveryAttempts,
        health.state != .softRecovering,
        now - (health.lastSoftRecoveryAt ?? -Double.greatestFiniteMagnitude)
          >= min(0.75, timing.softRecoveryTimeout * 0.4)
      else {
        return
      }

      health.state = .softRecovering
      health.softRecoveryAttempts += 1
      health.recoveryStartedAt = now
      health.lastSoftRecoveryAt = now
      health.consecutiveUsefulUpdates = 0
      health.consecutiveUselessUpdates = 0

      let distanceNeedsRecovery = health.distanceState != .healthy
        || !health.isDistanceMeasurementHealthy(at: now, role: rangingHealthRole)
      if distanceNeedsRecovery,
        health.distanceState != .softRecovering,
        health.distanceSoftRecoveryAttempts
          < distanceTiming.distanceMaximumSoftRecoveryAttempts
      {
        health.distanceState = .softRecovering
        health.distanceSoftRecoveryAttempts += 1
        health.distanceRecoveryStartedAt = now
        health.distanceLastSoftRecoveryAt = now
        health.consecutiveDistanceUpdates = 0
      }
    } else {
      guard
        health.distanceSoftRecoveryAttempts
          < distanceTiming.distanceMaximumSoftRecoveryAttempts,
        health.distanceState != .softRecovering,
        now - (health.distanceLastSoftRecoveryAt ?? -Double.greatestFiniteMagnitude)
          >= min(0.75, distanceTiming.distanceSoftRecoveryTimeout * 0.4)
      else {
        return
      }
      health.distanceState = .softRecovering
      health.distanceSoftRecoveryAttempts += 1
      health.distanceRecoveryStartedAt = now
      health.distanceLastSoftRecoveryAt = now
      health.consecutiveDistanceUpdates = 0
    }
    peerRangingHealth[peerId] = health
    if previousDistanceState != health.distanceState {
      SpatialPerformance.signposter.emitEvent(
        "Distance health transition",
        "Peer: \(peerId.prefix(8), privacy: .public), from: \(previousDistanceState.rawValue, privacy: .public), to: \(health.distanceState.rawValue, privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public)"
      )
    }
    SpatialPerformance.signposter.emitEvent(
      dimension == .distance ? "Distance recovery started" : "Ranging soft recovery started",
      "Peer: \(peerId.prefix(8), privacy: .public), dimension: \(dimension == .distance ? "distance" : "spatial", privacy: .public), reason: \(reason, privacy: .public), spatial attempt: \(health.softRecoveryAttempts), distance attempt: \(health.distanceSoftRecoveryAttempts)"
    )

    // Re-run the same non-invalidated session and token. The transaction and
    // identity remain intact; only hard recovery is allowed to replace them.
    runNearbySession(for: peerId, token: token)
  }

  /// A failed recovery attempt is handled as a fresh negotiation boundary.
  /// The transport/identity graph stays intact, while the invalidated NI
  /// object, transaction bookkeeping, and display estimates are discarded.
  /// The retry is delayed using the same bounded backoff as the pure health
  /// policy so an invalid state cannot turn into a tight restart loop.
  private func scheduleFreshRangingRetry(
    for peerId: String,
    at now: CFTimeInterval,
    reason: String,
    dimension: SpatialRangingRecoveryDimension = .spatial
  ) {
    let previousTransactionId = currentRangingTransaction(for: peerId)
    activeRangingPeerIds.remove(peerId)
    pendingRangingPeerIds.remove(peerId)
    outboundRangingPeerIds.remove(peerId)
    rangingStartedAt.removeValue(forKey: peerId)
    discardRangingSession(for: peerId)
    resetPeerDisplayState(for: peerId)
    setPeerLinkState(
      .discovered,
      for: peerId,
      reason: "fresh-retry-\(reason)"
    )

    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    let previousDistanceState = health.distanceState
    health.state = .renegotiating
    health.hardRecoveryAttempts = max(1, health.hardRecoveryAttempts + 1)
    health.distanceState = .renegotiating
    health.distanceHardRecoveryAttempts = max(1, health.distanceHardRecoveryAttempts + 1)
    health.recoveryStartedAt = now
    health.distanceRecoveryStartedAt = now
    health.lastHardRecoveryAt = now
    health.distanceLastHardRecoveryAt = now
    health.transactionStartedAt = now
    health.consecutiveUsefulUpdates = 0
    health.consecutiveUselessUpdates = 0
    peerRangingHealth[peerId] = health
    if previousDistanceState != health.distanceState {
      SpatialPerformance.signposter.emitEvent(
        "Distance health transition",
        "Peer: \(peerId.prefix(8), privacy: .public), from: \(previousDistanceState.rawValue, privacy: .public), to: \(health.distanceState.rawValue, privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public)"
      )
    }

    let timing = SpatialRangingHealthPolicy.timing(for: rangingHealthRole)
    let backoff: CFTimeInterval
    if dimension == .distance {
      backoff = min(
        timing.distanceMaximumHardRecoveryBackoff,
        timing.distanceMinimumHardRecoveryInterval
          * pow(2, Double(max(0, health.distanceHardRecoveryAttempts - 1)))
      )
    } else {
      backoff = min(
        timing.maximumHardRecoveryBackoff,
        timing.minimumHardRecoveryInterval
          * pow(2, Double(max(0, health.hardRecoveryAttempts - 1)))
      )
    }
    let retryAt = now + backoff
    rangingRetryAfter[peerId] = max(rangingRetryAfter[peerId] ?? 0, retryAt)
    rangingRetryCount += 1

    SpatialPerformance.signposter.emitEvent(
      "Ranging recovery failed",
      "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public), old transaction: \(previousTransactionId?.uuidString.prefix(8) ?? "none", privacy: .public), retry milliseconds: \(Int(backoff * 1_000)), hard attempt: \(health.hardRecoveryAttempts)"
    )
  }

  private func startHardRecovery(
    for peerId: String,
    at now: CFTimeInterval,
    reason: String,
    dimension: SpatialRangingRecoveryDimension = .spatial
  ) {
    guard activeRangingPeerIds.contains(peerId) else {
      return
    }

    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    let previousDistanceState = health.distanceState
    let isAlreadyRenegotiating = dimension == .distance
      ? health.distanceState == .renegotiating
      : health.state == .renegotiating
    guard !isAlreadyRenegotiating else {
      scheduleFreshRangingRetry(
        for: peerId,
        at: now,
        reason: reason,
        dimension: dimension
      )
      return
    }

    let previousTransactionId = currentRangingTransaction(for: peerId)
    if let previousTransactionId {
      sendRangingMessage(
        .rangeStop,
        to: peerId,
        transactionId: previousTransactionId
      )
    }

    activeRangingPeerIds.remove(peerId)
    pendingRangingPeerIds.remove(peerId)
    outboundRangingPeerIds.remove(peerId)
    rangingStartedAt.removeValue(forKey: peerId)
    rangingRetryAfter.removeValue(forKey: peerId)
    discardRangingSession(for: peerId)
    resetPeerDisplayState(for: peerId)
    setPeerLinkState(
      .discovered,
      for: peerId,
      reason: "hard-recovery-\(reason)"
    )

    health.state = .renegotiating
    health.hardRecoveryAttempts += 1
    health.distanceState = .renegotiating
    health.distanceHardRecoveryAttempts += 1
    health.recoveryStartedAt = now
    health.distanceRecoveryStartedAt = now
    health.lastHardRecoveryAt = now
    health.distanceLastHardRecoveryAt = now
    health.transactionStartedAt = now
    health.consecutiveUsefulUpdates = 0
    health.consecutiveUselessUpdates = 0
    peerRangingHealth[peerId] = health

    if previousDistanceState != health.distanceState {
      SpatialPerformance.signposter.emitEvent(
        "Distance health transition",
        "Peer: \(peerId.prefix(8), privacy: .public), from: \(previousDistanceState.rawValue, privacy: .public), to: \(health.distanceState.rawValue, privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public)"
      )
    }

    rangingRetryCount += 1
    SpatialPerformance.signposter.emitEvent(
      dimension == .distance ? "Distance hard recovery started" : "Ranging hard recovery started",
      "Peer: \(peerId.prefix(8), privacy: .public), dimension: \(dimension == .distance ? "distance" : "spatial", privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), reason: \(reason, privacy: .public), old transaction: \(previousTransactionId?.uuidString.prefix(8) ?? "none", privacy: .public), spatial attempt: \(health.hardRecoveryAttempts), distance attempt: \(health.distanceHardRecoveryAttempts), learned hardware capacity: \(self.hardwareSessionCapacity)"
    )

    guard
      shouldRunProactiveRanging,
      runtimeRole.allowsProactiveRanging,
      peerIdentities[peerId] != nil
    else {
      rangingRetryAfter[peerId] = now
        + (dimension == .distance
          ? SpatialRangingHealthPolicy.timing(for: rangingHealthRole)
            .distanceMinimumHardRecoveryInterval
          : SpatialRangingHealthPolicy.timing(for: rangingHealthRole)
            .minimumHardRecoveryInterval)
      return
    }

    guard isPeerTransportNearby(peerId) else {
      let retryAt = now + SpatialRangingTuning.transportRetryBaseDelay
      rangingRetryAfter[peerId] = max(rangingRetryAfter[peerId] ?? 0, retryAt)
      refreshTransportForRangingIfNeeded(
        for: peerId,
        at: now,
        reason: "\(reason)-transport-unavailable"
      )
      SpatialPerformance.signposter.emitEvent(
        "Ranging recovery waiting for transport",
        "Peer: \(peerId.prefix(8), privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), dimension: \(dimension == .distance ? "distance" : "spatial", privacy: .public), retry milliseconds: \(Int(SpatialRangingTuning.transportRetryBaseDelay * 1_000))"
      )
      return
    }

    requestRanging(
      with: peerId,
      healthState: .renegotiating
    )
  }

  func maintainRangingPool() {
    let now = CACurrentMediaTime()
    maintainRangingHealth(at: now)

    let orphanedOutboundPeerIds = SpatialRangingSessionOwnership
      .removeOrphanedOutboundPeerIds(
        activePeerIds: activeRangingPeerIds,
        pendingPeerIds: pendingRangingPeerIds,
        outboundPeerIds: &outboundRangingPeerIds
      )
    if !orphanedOutboundPeerIds.isEmpty {
      SpatialPerformance.signposter.emitEvent(
        "Orphaned outbound ranging ownership cleared",
        "Peers: \(orphanedOutboundPeerIds.map { String($0.prefix(8)) }.joined(separator: ", "), privacy: .public), count: \(orphanedOutboundPeerIds.count)"
      )
    }

    guard
      shouldRunProactiveRanging,
      runtimeRole.allowsProactiveRanging
    else {
      return
    }

    maintainExtendedDistanceHealth(at: now)

    let sessionCapacity = effectiveRangingCapacity
    let outboundCapacity = outboundInitiationCapacity

    for (peerId, identity) in peerIdentities where identity.userId == nil {
      emitCredentialDiscovered(for: peerId)
    }

    let discoveredPeerIds = Set(discoveredEndpoints.keys)
      .union(bluetoothPeerIds)
      .union(peerIdentities.keys)
      .union(activeRangingPeerIds)
      .union(pendingRangingPeerIds)
    let presenceCount = peerIdentities.count
    if lastSignpostedPresenceCount != presenceCount {
      lastSignpostedPresenceCount = presenceCount
      SpatialPerformance.signposter.emitEvent(
        "Nearby presence pool count",
        "Count: \(presenceCount)"
      )
    }
    if presenceCount > maximumDiscoveredPeerCount {
      maximumDiscoveredPeerCount = presenceCount
      SpatialPerformance.signposter.emitEvent(
        "Maximum discovered peer count",
        "Count: \(self.maximumDiscoveredPeerCount)"
      )
    }
    let scheduleCandidates = discoveredPeerIds.compactMap {
      rangingCandidate(for: $0, now: now)
    }
    let waitingPeerCount = scheduleCandidates.filter(\.isEligible).count
    acquisitionQueueSize = waitingPeerCount

    let activeCandidates = scheduleCandidates.filter(\.isActive)
    verificationPeerCount = activeCandidates.filter {
      $0.phase == .candidate || $0.phase == .verified
    }.count

    let role: SpatialRangingScheduleRole = runtimeRole == .cameraViewer
      ? .cameraViewer
      : .foregroundProximity
    let plan = rangingScheduler.plan(
      candidates: scheduleCandidates,
      role: role,
      now: now,
      sessionCapacity: sessionCapacity,
      outboundCapacity: outboundCapacity,
      outboundCount: outboundRangingPeerIds.count,
      probeTimeout: SpatialRangingTuning.probeTimeout,
      candidateLeaseDuration: SpatialRangingTuning.candidateLeaseDuration,
      verifiedLeaseDuration: SpatialRangingTuning.verifiedLeaseDuration,
      probeHardDeadline: SpatialRangingTuning.probeHardDeadline
    )

    for peerId in plan.releasePeerIds {
      let phase = peerRangingPhases[peerId] ?? .candidate
      let sessionOwner = outboundRangingPeerIds.contains(peerId)
        ? "initiator"
        : "responder"
      let reason: String
      switch phase {
      case .probing:
        probeTimeoutCount += 1
        let hardDeadline = scheduleCandidates.first(where: {
          $0.peerId == peerId
        })?.probeDeadlineAt
        reason = hardDeadline.map { now >= $0 } == true
          ? "probe-hard-deadline"
          : "probe-timeout"
      case .candidate:
        reason = runtimeRole == .foregroundProximity && waitingPeerCount > 0
          ? "foreground-fairness-rotation"
          : "candidate-lease-expired"
      case .verified:
        reason = runtimeRole == .foregroundProximity && waitingPeerCount > 0
          ? "foreground-fairness-rotation"
          : "verified-lease-expired"
      case .unprobed:
        reason = "acquisition-slot-released"
      }
      SpatialPerformance.signposter.emitEvent(
        "Ranging peer release selected",
        "Peer: \(peerId.prefix(8), privacy: .public), owner: \(sessionOwner, privacy: .public), phase: \(phase.rawValue, privacy: .public), reason: \(reason, privacy: .public), active: \(self.activeRangingPeerIds.count), pending: \(self.pendingRangingPeerIds.count), outbound: \(self.outboundRangingPeerIds.count), hardware: \(self.effectiveRangingCapacity), waiting: \(self.acquisitionQueueSize)"
      )
      endRanging(
        with: peerId,
        notifyPeer: true,
        reason: reason
      )
    }

    for peerId in plan.acquirePeerIds {
      SpatialPerformance.signposter.emitEvent(
        "Ranging peer acquisition selected",
        "Peer: \(peerId.prefix(8), privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), reason: \(self.runtimeRole == .foregroundProximity ? "foreground-fairness-queue" : "camera-interest-scheduler", privacy: .public)"
      )
      requestRanging(with: peerId)
    }

    signpostRangingStateIfNeeded()
  }

  private func rangingCandidate(
    for peerId: String,
    now: CFTimeInterval
  ) -> SpatialRangingCandidate? {
    guard let identity = peerIdentities[peerId] else {
      return nil
    }

    let interest = peerCameraInterests[peerId]
    let health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    let currentTransformUpdatedAt = health.currentAttemptTimestamp(
      peerRawWorldTransformUpdatedAt[peerId]
    )
    let currentDistanceUpdatedAt = health.currentAttemptTimestamp(
      peerRawDistanceUpdatedAt[peerId]
    )
    let currentDirectionUpdatedAt = health.currentAttemptTimestamp(
      peerLastDirectionMeasurementAt[peerId]
        ?? peerRawDirectionalMeasurements[peerId]?.measuredAt
    )
    let transformAge = currentTransformUpdatedAt.map {
      max(0, now - $0)
    } ?? .greatestFiniteMagnitude
    let distanceAge = currentDistanceUpdatedAt.map {
      max(0, now - $0)
    } ?? .greatestFiniteMagnitude
    let directionAge = currentDirectionUpdatedAt.map {
      max(0, now - $0)
    } ?? .greatestFiniteMagnitude
    let transformFreshness = transformAge.isFinite
      ? max(0, min(1, exp(-transformAge / 1.25)))
      : 0
    let distanceFreshness = distanceAge.isFinite
      ? max(0, min(1, exp(-distanceAge / 1.6)))
      : 0
    let directionFreshness = directionAge.isFinite
      ? max(0, min(1, exp(-directionAge / 1.25)))
      : 0
    let measurementFreshness = max(
      transformFreshness,
      max(directionFreshness, distanceFreshness)
    )
    let isActive = activeRangingPeerIds.contains(peerId)
    let isPending = pendingRangingPeerIds.contains(peerId)
    let phase = peerRangingPhases[peerId]
      ?? (interest?.isVerified == true
        ? .verified
        : interest != nil ? .candidate : .unprobed)
    let probeStartedAt = peerProbeStartedAt[peerId]
      ?? rangingStartedAt[peerId]
    let hasUsefulMeasurement = health.currentAttemptTimestamp(
      health.lastUsefulMeasurementAt
        ?? peerLastUsefulMeasurementAt[peerId]
    ) != nil
    let hasFreshDistance = peerRawDistances[peerId] != nil
      && currentDistanceUpdatedAt != nil
      && distanceAge <= SpatialMeasurementTuning.newMatchMaximumDistanceAge
      && (phase != .probing
        || (currentDistanceUpdatedAt ?? 0)
          >= (probeStartedAt ?? .greatestFiniteMagnitude))
    let hasProjectableMeasurement = peerRawWorldTransforms[peerId] != nil
      && currentTransformUpdatedAt != nil
      && transformAge <= SpatialRangingTuning.probeTimeout
      && (phase != .probing
        || (currentTransformUpdatedAt ?? 0)
          >= (probeStartedAt ?? .greatestFiniteMagnitude))
    let hasDirectionalMeasurement = peerRawDirectionalMeasurements[peerId] != nil
      && currentDirectionUpdatedAt != nil
      && directionAge <= SpatialMeasurementTuning.newMatchMaximumDirectionAge
      && (phase != .probing
        || (currentDirectionUpdatedAt ?? 0)
          >= (probeStartedAt ?? .greatestFiniteMagnitude))
    let hasDistanceOnlyMeasurement = hasFreshDistance
      && !hasProjectableMeasurement
      && !hasDirectionalMeasurement
    let hasCurrentUsefulMeasurement = hasUsefulMeasurement
    let measurementHealthy = health.isMeasurementHealthy(
      at: now,
      role: rangingHealthRole
    )
    let measurementDegraded = health.state == .degraded
      || (health.state == .healthy
        && health.usefulMeasurementAge(at: now)
          >= SpatialRangingHealthPolicy.timing(for: rangingHealthRole)
            .degradedUsefulMeasurementAge)
    let distanceTiming = SpatialRangingHealthPolicy.timing(for: rangingHealthRole)
    let distanceHealthy = health.isDistanceMeasurementHealthy(
      at: now,
      role: rangingHealthRole
    )
    let distanceDegraded = health.distanceState == .degraded
      || health.distanceState == .softRecovering
      || health.distanceState == .renegotiating
      || (!distanceHealthy
        && health.distanceMeasurementAge(at: now)
          >= distanceTiming.degradedDistanceMeasurementAge)

    let interestAge = interest.map {
      max(0, now - $0.measuredAt)
    } ?? .greatestFiniteMagnitude

    return SpatialRangingCandidate(
      peerId: peerId,
      phase: phase,
      isActive: isActive,
      isPending: isPending,
      isLocallyInitiated: outboundRangingPeerIds.contains(peerId),
      isEligible: !isActive
        && !isPending
        && now >= (rangingRetryAfter[peerId] ?? 0)
        // Camera acquisition may range an unresolved event peer while
        // credential resolution is still in flight.
        && (runtimeRole == .cameraViewer || identity.userId != nil),
      isVerified: phase == .verified || interest?.isVerified == true,
      isTentative: phase == .candidate || interest?.isTentative == true,
      isNearVisibleBody: interest?.isNearBody == true,
      isNearCarryRegion: interest?.isNearCarryRegion == true,
      hasUsefulMeasurement: hasCurrentUsefulMeasurement,
      hasDistanceOnlyMeasurement: hasDistanceOnlyMeasurement,
      hasDirectionalMeasurement: hasDirectionalMeasurement,
      hasProjectableMeasurement: hasProjectableMeasurement,
      measurementFreshness: measurementFreshness,
      cameraInterest: interest?.score ?? 0,
      cameraInterestAge: interestAge,
      lastCameraRelevantAt: peerLastCameraRelevantAt[peerId],
      signalStrength: peerSignalStrengths[peerId],
      lastRangedAt: peerLastRangedAt[peerId],
      leaseStartedAt: rangingStartedAt[peerId],
      probeStartedAt: probeStartedAt,
      firstMeasurementAt: peerFirstMeasurementAt[peerId]
        ?? peerFirstUsefulMeasurementAt[peerId],
      firstDistanceAt: peerFirstDistanceAt[peerId],
      firstProjectableMeasurementAt: peerFirstProjectableMeasurementAt[peerId],
      probeDeadlineAt: peerProbeDeadlineAt[peerId],
      firstUsefulMeasurementAt: peerFirstUsefulMeasurementAt[peerId],
      expectedInformationGain: expectedInformationGain(
        phase: phase,
        interest: interest,
        hasDistanceOnlyMeasurement: hasDistanceOnlyMeasurement,
        hasProjectableMeasurement: hasProjectableMeasurement,
        lastRangedAt: peerLastRangedAt[peerId],
        now: now
      ),
      retryAfter: rangingRetryAfter[peerId] ?? 0,
      healthState: health.state,
      lastUsefulMeasurementAt: health.currentAttemptTimestamp(
        health.lastUsefulMeasurementAt
      ),
      usefulMeasurementAge: health.usefulMeasurementAge(at: now),
      isMeasurementHealthy: measurementHealthy,
      isMeasurementDegraded: measurementDegraded,
      distanceHealthState: health.distanceState,
      isDistanceHealthy: distanceHealthy,
      isDistanceDegraded: distanceDegraded,
      isRecovering: health.isRecovering,
      cameraAssistanceRecovering: runtimeRole == .cameraViewer
        && arTrackingState != .normal
    )
  }

  private func expectedInformationGain(
    phase: SpatialPeerRangingPhase,
    interest: SpatialCameraInterest?,
    hasDistanceOnlyMeasurement: Bool,
    hasProjectableMeasurement: Bool,
    lastRangedAt: CFTimeInterval?,
    now: CFTimeInterval
  ) -> Double {
    let phaseNeed: Double
    switch phase {
    case .unprobed:
      phaseNeed = 1.15
    case .probing:
      phaseNeed = 0.4
    case .candidate:
      phaseNeed = 0.95
    case .verified:
      phaseNeed = 0.25
    }
    let interestNeed = (interest?.score ?? 0) * 1.25
    let bodyNeed = interest?.isNearBody == true ? 0.5 : 0
    let carryNeed = interest?.isNearCarryRegion == true ? 0.75 : 0
    let ambiguityNeed = hasDistanceOnlyMeasurement
      && !hasProjectableMeasurement
      ? 0.8
      : 0
    let fairnessNeed = min(0.75, max(0, now - (lastRangedAt ?? 0)) / 18)
    return min(
      2,
      phaseNeed + interestNeed + bodyNeed + carryNeed + ambiguityNeed
        + fairnessNeed
    )
  }

  func handleRangingRequest(
    from peerId: String,
    tokenData: Data?,
    transactionId: UUID?,
    transportAuthenticated: Bool
  ) {
    guard transportAuthenticated, peerIdentities[peerId] != nil else {
      return
    }

    guard let transactionId else {
      signpostIgnoredRangingMessage(
        kind: .rangeRequest,
        peerId: peerId,
        transactionId: nil,
        disposition: .missingTransaction
      )
      return
    }

    if observedRangingTransactions[peerId]?.contains(transactionId) == true {
      switch peerLinkState(for: peerId) {
      case .negotiatingInbound(let currentTransactionId)
        where currentTransactionId == transactionId:
        sendInboundRangingAcceptance(
          to: peerId,
          transactionId: transactionId
        )
      case .ranging(let currentTransactionId, .responder)
        where currentTransactionId == transactionId:
        sendInboundRangingAcceptance(
          to: peerId,
          transactionId: transactionId
        )
      default:
        signpostIgnoredRangingMessage(
          kind: .rangeRequest,
          peerId: peerId,
          transactionId: transactionId,
          disposition: .duplicate
        )
      }
      return
    }
    _ = rememberRangingTransaction(transactionId, for: peerId)

    guard
      let tokenData,
      let peerToken = try? NearbyDiscoveryTokenCodec.decode(tokenData)
    else {
      sendRangingBusy(
        to: peerId,
        transactionId: transactionId,
        reason: "invalid-peer-discovery-token"
      )
      return
    }

    let currentState = peerLinkState(for: peerId)
    if let localTransactionId = currentState.outboundTransactionId,
      pendingRangingPeerIds.contains(peerId)
        || outboundRangingPeerIds.contains(peerId)
        || activeRangingPeerIds.contains(peerId)
    {
      switch SpatialRangingNegotiationPolicy.collisionDecision(
        localPeerId: localPeerId,
        remotePeerId: peerId
      ) {
      case .keepOutbound:
        // The lower stable peer ID keeps its attempt. A collision response is
        // scoped to the incoming transaction and must not close the link.
        sendRangingMessage(
          .rangeBusy,
          to: peerId,
          transactionId: transactionId
        )
        SpatialPerformance.signposter.emitEvent(
          "Ranging collision won",
          "Peer: \(peerId.prefix(8), privacy: .public), transaction: \(localTransactionId.uuidString.prefix(8), privacy: .public)"
        )
        return
      case .yieldToInbound:
        yieldOutboundAttempt(
          to: peerId,
          localTransactionId: localTransactionId,
          incomingTransactionId: transactionId
        )
      }
    }

    if activeRangingPeerIds.contains(peerId) {
      sendRangingBusy(
        to: peerId,
        transactionId: transactionId,
        reason: "peer-already-active"
      )
      return
    }

    let session = nearbySession(for: peerId)
    guard
      let localToken = session.discoveryToken,
      let encodedToken = try? NearbyDiscoveryTokenCodec.encode(localToken)
    else {
      discardRangingSession(for: peerId)
      sendRangingBusy(
        to: peerId,
        transactionId: transactionId,
        reason: "local-discovery-token-unavailable"
      )
      return
    }

    let scheduleRole: SpatialRangingScheduleRole
    switch runtimeRole {
    case .cameraViewer:
      scheduleRole = .cameraViewer
    case .foregroundProximity:
      scheduleRole = .foregroundProximity
    case .backgroundResponder:
      scheduleRole = .backgroundResponder
    case .suspended:
      scheduleRole = .suspended
    }
    let admissionPolicy = SpatialRangingAdmissionPolicy()
    let admissionDecision = admissionPolicy.decision(
      role: scheduleRole,
      activeSessionCount: activeRangingPeerIds.count,
      pendingSessionCount: pendingRangingPeerIds.count,
      hardwareCapacity: effectiveRangingCapacity,
      requestingPeerId: peerId,
      yieldablePeerIds: foregroundYieldablePeerIds(excluding: peerId)
    )
    switch admissionDecision {
    case .acceptWithSpareCapacity:
      break
    case .acceptAfterYield(let yieldingPeerId):
      let didYield = endRanging(
        with: yieldingPeerId,
        notifyPeer: true,
        reason: "inbound-capacity-preemption",
        preserveSpatialState: true
      )
      guard didYield else {
        sendRangingBusy(
          to: peerId,
          transactionId: transactionId,
          reason: "yieldable-session-ended-before-preemption"
        )
        return
      }
      SpatialPerformance.signposter.emitEvent(
        "Inbound ranging capacity preemption",
        "Requester: \(peerId.prefix(8), privacy: .public), yielded: \(yieldingPeerId.prefix(8), privacy: .public), hardware capacity: \(self.effectiveRangingCapacity)"
      )
      guard
        activeRangingPeerIds.count + pendingRangingPeerIds.count
          < effectiveRangingCapacity
      else {
        sendRangingBusy(
          to: peerId,
          transactionId: transactionId,
          reason: "yield-did-not-free-hardware-capacity"
        )
        return
      }
    case .busy(let reason):
      sendRangingBusy(
        to: peerId,
        transactionId: transactionId,
        reason: reason
      )
      return
    }

    peerTokens[peerId] = peerToken
    activeRangingPeerIds.insert(peerId)
    pendingRangingPeerIds.remove(peerId)
    outboundRangingPeerIds.remove(peerId)
    setPeerLinkState(
      .negotiatingInbound(transactionId: transactionId),
      for: peerId,
      reason: "inbound-request"
    )
    if peerRangingPhases[peerId] == nil
      || peerRangingPhases[peerId] == .unprobed
    {
      peerRangingPhases[peerId] = .candidate
    }
    rangingRetryAfter.removeValue(forKey: peerId)
    let now = CACurrentMediaTime()
    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    health.beginTransaction(
      at: now,
      state: health.state == .renegotiating ? .renegotiating : .acquiring
    )
    peerRangingHealth[peerId] = health
    rangingStartedAt[peerId] = now
    if peerRangingPhases[peerId] == .probing {
      peerProbeStartedAt[peerId] = now
      peerProbeDeadlineAt[peerId] = now
        + SpatialRangingTuning.probeHardDeadline
    }
    sendRangingMessage(
      .rangeAccept,
      to: peerId,
      discoveryToken: encodedToken,
      transactionId: transactionId
    )
    setPeerLinkState(
      .ranging(transactionId: transactionId, role: .responder),
      for: peerId,
      reason: "inbound-accepted"
    )
    SpatialPerformance.signposter.emitEvent(
      "Ranging request accepted",
      "Peer: \(peerId.prefix(8), privacy: .public), role: responder"
    )
    runNearbySession(for: peerId, token: peerToken)
    SpatialPerformance.signposter.emitEvent("UWB inbound ranging started")
  }

  private func foregroundYieldablePeerIds(excluding requestingPeerId: String) -> [String] {
    guard runtimeRole == .foregroundProximity else {
      return []
    }

    return outboundRangingPeerIds
      .filter { peerId in
        guard peerId != requestingPeerId,
          activeRangingPeerIds.contains(peerId)
            || pendingRangingPeerIds.contains(peerId),
          !(peerRangingHealth[peerId] ?? SpatialRangingHealth()).isRecovering
        else {
          return false
        }

        switch peerLinkState(for: peerId) {
        case .connecting, .authenticating, .negotiatingOutbound:
          return true
        case .ranging(_, .initiator):
          return true
        case .discovered, .yieldingToInbound, .negotiatingInbound,
          .ranging(_, .responder), .cooldown:
          return false
        }
      }
      .sorted { firstPeerId, secondPeerId in
        let firstPhase = peerRangingPhases[firstPeerId] ?? .unprobed
        let secondPhase = peerRangingPhases[secondPeerId] ?? .unprobed
        if firstPhase != secondPhase {
          return foregroundYieldPriority(firstPhase)
            < foregroundYieldPriority(secondPhase)
        }
        let firstStartedAt = rangingStartedAt[firstPeerId] ?? 0
        let secondStartedAt = rangingStartedAt[secondPeerId] ?? 0
        if firstStartedAt != secondStartedAt {
          return firstStartedAt < secondStartedAt
        }
        return firstPeerId < secondPeerId
      }
  }

  private func foregroundYieldPriority(
    _ phase: SpatialPeerRangingPhase
  ) -> Int {
    switch phase {
    case .unprobed, .probing:
      return 0
    case .candidate:
      return 1
    case .verified:
      return 2
    }
  }

  private func sendRangingBusy(
    to peerId: String,
    transactionId: UUID,
    reason: String
  ) {
    let activeResponderCount = activeRangingPeerIds
      .subtracting(outboundRangingPeerIds)
      .count
    SpatialPerformance.signposter.emitEvent(
      "Ranging request busy",
      "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), active: \(self.activeRangingPeerIds.count), responders: \(activeResponderCount), pending: \(self.pendingRangingPeerIds.count), outbound/local: \(self.outboundRangingPeerIds.count), hardware capacity: \(self.effectiveRangingCapacity), foreground proactive capacity: \(self.foregroundProactiveCapacity), waiting: \(self.acquisitionQueueSize)"
    )
    sendRangingMessage(
      .rangeBusy,
      to: peerId,
      transactionId: transactionId
    )
  }

  func handleRangingAccepted(
    by peerId: String,
    tokenData: Data?,
    transactionId: UUID?
  ) {
    guard let transactionId else {
      signpostIgnoredRangingMessage(
        kind: .rangeAccept,
        peerId: peerId,
        transactionId: nil,
        disposition: .missingTransaction
      )
      return
    }

    guard currentOutboundRangingTransaction(for: peerId) == transactionId else {
      signpostIgnoredRangingMessage(
        kind: .rangeAccept,
        peerId: peerId,
        transactionId: transactionId,
        disposition: .stale
      )
      return
    }

    guard pendingRangingPeerIds.remove(peerId) != nil else {
      if case .ranging(let currentTransactionId, let role) = peerLinkState(for: peerId),
        currentTransactionId == transactionId,
        role == .initiator
      {
        signpostIgnoredRangingMessage(
          kind: .rangeAccept,
          peerId: peerId,
          transactionId: transactionId,
          disposition: .duplicate
        )
      } else {
        signpostIgnoredRangingMessage(
          kind: .rangeAccept,
          peerId: peerId,
          transactionId: transactionId,
          disposition: .stale
        )
      }
      return
    }

    guard
      let tokenData,
      let token = try? NearbyDiscoveryTokenCodec.decode(tokenData),
      nearbySessions[peerId] != nil
    else {
      abortOutboundNegotiation(
        for: peerId,
        transactionId: transactionId,
        reason: "invalid-accept"
      )
      return
    }

    peerTokens[peerId] = token
    activeRangingPeerIds.insert(peerId)
    outboundRangingPeerIds.insert(peerId)
    setPeerLinkState(
      .ranging(transactionId: transactionId, role: .initiator),
      for: peerId,
      reason: "outbound-accepted"
    )
    if peerRangingPhases[peerId] == nil {
      peerRangingPhases[peerId] = .probing
    }
    rangingRetryAfter.removeValue(forKey: peerId)
    let now = CACurrentMediaTime()
    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    health.beginTransaction(
      at: now,
      state: health.state == .renegotiating ? .renegotiating : .acquiring
    )
    peerRangingHealth[peerId] = health
    rangingStartedAt[peerId] = now
    if peerRangingPhases[peerId] == .probing {
      peerProbeStartedAt[peerId] = now
      peerProbeDeadlineAt[peerId] = now
        + SpatialRangingTuning.probeHardDeadline
    }
    SpatialPerformance.signposter.emitEvent(
      "Ranging request accepted",
      "Peer: \(peerId.prefix(8), privacy: .public), role: viewer"
    )
    runNearbySession(for: peerId, token: token)
    SpatialPerformance.signposter.emitEvent("UWB outbound ranging started")
  }

  func handleRangingBusy(peerId: String, transactionId: UUID?) {
    guard let transactionId else {
      signpostIgnoredRangingMessage(
        kind: .rangeBusy,
        peerId: peerId,
        transactionId: nil,
        disposition: .missingTransaction
      )
      return
    }

    guard currentOutboundRangingTransaction(for: peerId) == transactionId else {
      signpostIgnoredRangingMessage(
        kind: .rangeBusy,
        peerId: peerId,
        transactionId: transactionId,
        disposition: .stale
      )
      return
    }

    guard pendingRangingPeerIds.contains(peerId) else {
      signpostIgnoredRangingMessage(
        kind: .rangeBusy,
        peerId: peerId,
        transactionId: transactionId,
        disposition: .duplicate
      )
      return
    }

    abortOutboundNegotiation(
      for: peerId,
      transactionId: transactionId,
      reason: "busy"
    )
  }

  private func yieldOutboundAttempt(
    to peerId: String,
    localTransactionId: UUID,
    incomingTransactionId: UUID
  ) {
    guard currentOutboundRangingTransaction(for: peerId) == localTransactionId else {
      return
    }

    setPeerLinkState(
      .yieldingToInbound(
        localTransactionId: localTransactionId,
        incomingTransactionId: incomingTransactionId
      ),
      for: peerId,
      reason: "deterministic-collision-loss"
    )

    pendingRangingPeerIds.remove(peerId)
    outboundRangingPeerIds.remove(peerId)
    activeRangingPeerIds.remove(peerId)
    discardRangingSession(for: peerId)
    rangingStartedAt.removeValue(forKey: peerId)
    rangingRetryAfter.removeValue(forKey: peerId)

    SpatialPerformance.signposter.emitEvent(
      "Outbound ranging yielded",
      "Peer: \(peerId.prefix(8), privacy: .public), local transaction: \(localTransactionId.uuidString.prefix(8), privacy: .public), incoming transaction: \(incomingTransactionId.uuidString.prefix(8), privacy: .public)"
    )
  }

  private func sendInboundRangingAcceptance(
    to peerId: String,
    transactionId: UUID
  ) {
    guard
      let session = nearbySessions[peerId],
      let localToken = session.discoveryToken,
      let encodedToken = try? NearbyDiscoveryTokenCodec.encode(localToken)
    else {
      return
    }

    sendRangingMessage(
      .rangeAccept,
      to: peerId,
      discoveryToken: encodedToken,
      transactionId: transactionId
    )
  }

  private func abortOutboundNegotiation(
    for peerId: String,
    transactionId: UUID,
    reason: String
  ) {
    guard currentOutboundRangingTransaction(for: peerId) == transactionId else {
      return
    }

    pendingRangingPeerIds.remove(peerId)
    outboundRangingPeerIds.remove(peerId)
    discardRangingSession(for: peerId)
    rangingStartedAt.removeValue(forKey: peerId)

    if peerRangingPhases[peerId] == .probing {
      peerRangingPhases[peerId] = .unprobed
      peerProbeStartedAt.removeValue(forKey: peerId)
      peerProbeDeadlineAt.removeValue(forKey: peerId)
      peerFirstMeasurementAt.removeValue(forKey: peerId)
      peerFirstDistanceAt.removeValue(forKey: peerId)
      peerFirstProjectableMeasurementAt.removeValue(forKey: peerId)
      peerFirstUsefulMeasurementAt.removeValue(forKey: peerId)
    }

    let now = CACurrentMediaTime()
    let retryKind = SpatialRangingRetryPolicy.kind(for: reason)
    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    if retryKind == .negotiationFailure {
      health.rangingFailureAttempts += 1
      health.state = .renegotiating
      health.distanceState = .renegotiating
      health.recoveryStartedAt = now
      health.distanceRecoveryStartedAt = now
      health.lastHardRecoveryAt = health.lastHardRecoveryAt ?? now
      health.distanceLastHardRecoveryAt = health.distanceLastHardRecoveryAt ?? now
      health.transactionStartedAt = now
      health.consecutiveUsefulUpdates = 0
      health.consecutiveDistanceUpdates = 0
      peerRangingHealth[peerId] = health
    }
    let retryDecision = SpatialRangingRetryPolicy.decision(
      for: retryKind,
      consecutiveFailureCount: health.rangingFailureAttempts,
      deterministicJitter: retryJitter(for: peerId)
    )
    rangingRetryCount += 1
    let retryDelay = retryDecision.delay
    let retryAt = now + retryDelay
    rangingRetryAfter[peerId] = retryAt
    setPeerLinkState(
      .cooldown(until: retryAt),
      for: peerId,
      reason: reason
    )
    SpatialPerformance.signposter.emitEvent(
      retryKind == .contention
        ? "Ranging contention retry scheduled"
        : "Ranging retry scheduled",
      "Peer: \(peerId.prefix(8), privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), reason: \(reason, privacy: .public), retry kind: \(retryKind.rawValue, privacy: .public), delay milliseconds: \(Int(retryDelay * 1_000)), failure attempt: \(health.rangingFailureAttempts), active: \(self.activeRangingPeerIds.count), pending: \(self.pendingRangingPeerIds.count), local initiated: \(self.outboundRangingPeerIds.count), count: \(self.rangingRetryCount)"
    )
  }

  /// A remembered presence record is enough to keep identity alive, but it is
  /// not itself a writable control path. When a recovery transaction has no
  /// current connection, kick the already-running Bonjour/BLE discovery paths
  /// once per bounded interval so the next retry can recreate transport.
  private func refreshTransportForRangingIfNeeded(
    for peerId: String,
    at now: CFTimeInterval,
    reason: String
  ) {
    guard
      now.isFinite,
      now - lastRangingTransportRefreshAt
        >= SpatialRangingTuning.rangingTransportRefreshInterval
    else {
      return
    }

    lastRangingTransportRefreshAt = now
    let shouldRefreshBonjourBrowser = browser != nil
    ensureDiscoveryTransport()
    bluetoothWakeService?.refreshDiscovery()
    if shouldRefreshBonjourBrowser {
      refreshBonjourDiscoveryForRanging(at: now, reason: reason)
    }
    SpatialPerformance.signposter.emitEvent(
      "Ranging transport refresh requested",
      "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public)"
    )
  }

  @discardableResult
  func endRanging(
    with peerId: String,
    notifyPeer: Bool,
    reason: String,
    preserveSpatialState: Bool = true,
    transactionId: UUID? = nil
  ) -> Bool {
    let currentState = peerLinkState(for: peerId)
    let currentTransactionId = currentState.transactionId
    if let transactionId,
      currentTransactionId != transactionId
    {
      signpostIgnoredRangingMessage(
        kind: .rangeStop,
        peerId: peerId,
        transactionId: transactionId,
        disposition: .stale
      )
      return false
    }

    let removal = SpatialRangingSessionOwnership.removePeer(
      peerId,
      activePeerIds: &activeRangingPeerIds,
      pendingPeerIds: &pendingRangingPeerIds,
      outboundPeerIds: &outboundRangingPeerIds
    )
    let wasRanging = removal.hadRangingOwnership
      || peerWorldTransforms[peerId] != nil
      || peerDistances[peerId] != nil
    let identity = peerIdentities[peerId]

    if notifyPeer,
      let controlTransactionId = transactionId ?? currentTransactionId
    {
      sendRangingMessage(
        .rangeStop,
        to: peerId,
        transactionId: controlTransactionId
      )
    }

    discardRangingSession(for: peerId)
    let now = CACurrentMediaTime()
    if reason == "remote-stop" {
      let scheduleRole: SpatialRangingScheduleRole
      switch runtimeRole {
      case .cameraViewer:
        scheduleRole = .cameraViewer
      case .foregroundProximity:
        scheduleRole = .foregroundProximity
      case .backgroundResponder:
        scheduleRole = .backgroundResponder
      case .suspended:
        scheduleRole = .suspended
      }
      if let retryDeadline = SpatialForegroundRangingPolicy
        .remoteStopRetryDeadline(role: scheduleRole, now: now)
      {
        rangingRetryAfter[peerId] = max(
          rangingRetryAfter[peerId] ?? 0,
          retryDeadline
        )
        SpatialPerformance.signposter.emitEvent(
          "Foreground peer deferred after remote stop",
          "Peer: \(peerId.prefix(8), privacy: .public), retry milliseconds: \(Int((retryDeadline - now) * 1_000))"
        )
      }
    }
    peerLastRangedAt[peerId] = now
    rangingStartedAt.removeValue(forKey: peerId)

    if reason == "probe-timeout"
      || reason == "probe-hard-deadline"
      || reason == "probe-evicted"
      || reason == "candidate-lease-expired"
      || reason == "verified-lease-expired"
      || reason == "foreground-fairness-rotation"
      || reason == "inbound-capacity-preemption"
    {
      rangingRotationCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Ranging slot rotated",
        "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public), count: \(self.rangingRotationCount)"
      )
    }

    if reason == "probe-timeout"
      || reason == "probe-hard-deadline"
      || reason == "probe-evicted"
      || reason == "nearby-session-failed"
      || reason == "camera-consumer-ended"
    {
      peerRangingPhases[peerId] = .unprobed
      peerProbeStartedAt.removeValue(forKey: peerId)
      peerProbeDeadlineAt.removeValue(forKey: peerId)
      peerFirstMeasurementAt.removeValue(forKey: peerId)
      peerFirstDistanceAt.removeValue(forKey: peerId)
      peerFirstProjectableMeasurementAt.removeValue(forKey: peerId)
      peerFirstUsefulMeasurementAt.removeValue(forKey: peerId)
    }

    if !preserveSpatialState {
      clearPeerWorldTransform(for: peerId)
    }

    if let retryAt = rangingRetryAfter[peerId], retryAt > now {
      setPeerLinkState(
        .cooldown(until: retryAt),
        for: peerId,
        reason: reason
      )
    } else {
      setPeerLinkState(
        .discovered,
        for: peerId,
        reason: reason
      )
    }

    if wasRanging {
      emitPeerLost(
        peerId,
        identity: identity,
        reason: reason,
        stillNearby: isPeerTransportNearby(peerId)
          || peerEvictionTokens[peerId] != nil
      )
    }

    closeConnectionWhenIdle(to: peerId)
    signpostRangingStateIfNeeded()
    return wasRanging
  }

  func peerId(for session: NISession) -> String? {
    withStateQueue {
      nearbySessions.first { $0.value === session }?.key
    }
  }

  func identity(for peerId: String) -> NearbyPeerIdentity? {
    withStateQueue { peerIdentities[peerId] }
  }

  func token(for peerId: String) -> NIDiscoveryToken? {
    withStateQueue { peerTokens[peerId] }
  }

  func runNearbySession(for peerId: String, token: NIDiscoveryToken) {
    withStateQueue {
      let configuration = NINearbyPeerConfiguration(peerToken: token)
      let session = nearbySession(for: peerId)
      var cameraAssistanceEnabled = false

      if #available(iOS 16.0, *),
        runtimeRole == .cameraViewer,
        capabilityProfile.cameraAssistance,
        !peerCameraAssistanceSuppressed.contains(peerId),
        let arSession
      {
        cameraAssistanceEnabled = true
        configuration.isCameraAssistanceEnabled = true
        session.setARSession(arSession)
      }
      peerCameraAssistanceEnabled[peerId] = cameraAssistanceEnabled
      if cameraAssistanceEnabled, !didSignpostFirstCameraAssistance {
        didSignpostFirstCameraAssistance = true
        let latencyMilliseconds = discoveryStartedAt.map {
          Int((CACurrentMediaTime() - $0) * 1_000)
        } ?? -1
        SpatialPerformance.signposter.emitEvent(
          "First camera assistance enabled",
          "Latency milliseconds: \(latencyMilliseconds), peer: \(peerId.prefix(8), privacy: .public)"
        )
      }

      let wasExtendedDistanceOwner = extendedDistancePeerId == peerId
      var usesExtendedDistanceMeasurement = false
      if #available(iOS 17.0, *),
        shouldUseExtendedDistanceMeasurement(for: peerId, token: token)
      {
        configuration.isExtendedDistanceMeasurementEnabled = true
        extendedDistancePeerId = peerId
        usesExtendedDistanceMeasurement = true
      }

      if !usesExtendedDistanceMeasurement, wasExtendedDistanceOwner {
        extendedDistancePeerId = nil
        extendedDistanceStartedAt = nil
        extendedDistanceLastUsefulAt = nil
        extendedDistanceCandidatePeerId = nil
        extendedDistanceCandidateSince = nil
        if lastSignpostedExtendedDistancePeerId == peerId {
          lastSignpostedExtendedDistancePeerId = nil
          SpatialPerformance.signposter.emitEvent(
            "Extended Distance Measurement disabled"
          )
        }
      }

      if usesExtendedDistanceMeasurement,
        lastSignpostedExtendedDistancePeerId != peerId
      {
        lastSignpostedExtendedDistancePeerId = peerId
        SpatialPerformance.signposter.emitEvent(
          "Extended Distance Measurement enabled",
          "Peer: \(peerId.prefix(8), privacy: .public)"
        )
      }

      if usesExtendedDistanceMeasurement {
        extendedDistanceStartedAt = CACurrentMediaTime()
        extendedDistanceLastUsefulAt = nil
      }

      session.run(configuration)
      SpatialPerformance.signposter.emitEvent(
        "NISession started",
        "Peer: \(peerId.prefix(8), privacy: .public), camera assistance: \(cameraAssistanceEnabled), EDM: \(usesExtendedDistanceMeasurement)"
      )
    }
  }

  private func shouldUseExtendedDistanceMeasurement(
    for peerId: String,
    token: NIDiscoveryToken
  ) -> Bool {
    guard
      runtimeRole == .cameraViewer,
      !didDiscoverExtendedDistanceLimit,
      #available(iOS 17.0, *),
      capabilityProfile.extendedDistanceMeasurement,
      token.deviceCapabilities.supportsExtendedDistanceMeasurement
    else {
      return false
    }

    guard CACurrentMediaTime() >= (extendedDistanceCooldownUntil[peerId] ?? 0) else {
      return false
    }

    guard let phase = peerRangingPhases[peerId],
      phase == .candidate || phase == .verified,
      let interest = peerCameraInterests[peerId],
      interest.isNearBody
        || interest.isNearCarryRegion
        || interest.score >= SpatialRangingTuning.probePromotionInterest
    else {
      return false
    }

    guard let extendedDistancePeerId else {
      return true
    }

    return extendedDistancePeerId == peerId
  }

  private func maybeMigrateExtendedDistanceMeasurement(at now: CFTimeInterval) {
    guard
      runtimeRole == .cameraViewer,
      !didDiscoverExtendedDistanceLimit
    else {
      return
    }

    let eligibleCandidates = activeRangingPeerIds.compactMap { peerId -> SpatialRangingCandidate? in
      guard
        peerRangingPhases[peerId] == .candidate
          || peerRangingPhases[peerId] == .verified
      else {
        return nil
      }

      guard let interest = peerCameraInterests[peerId],
        interest.isNearBody
          || interest.isNearCarryRegion
          || interest.score >= SpatialRangingTuning.probePromotionInterest
      else {
        return nil
      }

      guard let token = peerTokens[peerId] else {
        return nil
      }

      if #available(iOS 17.0, *) {
        guard now >= (extendedDistanceCooldownUntil[peerId] ?? 0),
          capabilityProfile.extendedDistanceMeasurement,
          token.deviceCapabilities.supportsExtendedDistanceMeasurement
        else {
          return nil
        }

        return rangingCandidate(for: peerId, now: now)
      }

      return nil
    }
    guard !eligibleCandidates.isEmpty else {
      extendedDistanceCandidatePeerId = nil
      extendedDistanceCandidateSince = nil
      return
    }

    let selection = rangingScheduler.selectEDMOwner(
      candidates: eligibleCandidates,
      currentPeerId: extendedDistancePeerId,
      candidatePeerId: extendedDistanceCandidatePeerId,
      candidateSince: extendedDistanceCandidateSince,
      now: now,
      minimumScoreDelta: SpatialRangingTuning.extendedDistanceMigrationHysteresis,
      minimumDwell: SpatialRangingTuning.cameraInterestHysteresisDuration
    )
    extendedDistanceCandidatePeerId = selection.candidatePeerId
    extendedDistanceCandidateSince = selection.candidateSince

    guard let bestPeerId = selection.bestPeerId else {
      return
    }

    guard selection.shouldMigrate else {
      return
    }

    guard let currentPeerId = extendedDistancePeerId else {
      extendedDistancePeerId = bestPeerId
      didDiscoverExtendedDistanceLimit = false
      if let token = peerTokens[bestPeerId] {
        runNearbySession(for: bestPeerId, token: token)
      }
      return
    }

    extendedDistancePeerId = bestPeerId
    didDiscoverExtendedDistanceLimit = false
    extendedDistanceCandidatePeerId = nil
    extendedDistanceCandidateSince = nil
    if let previousToken = peerTokens[currentPeerId] {
      // Re-run the previous session with EDM disabled before enabling it for
      // the new winner. This keeps the one-active-EDM invariant explicit.
      runNearbySession(for: currentPeerId, token: previousToken)
    }
    if let token = peerTokens[bestPeerId] {
      runNearbySession(for: bestPeerId, token: token)
    }
  }

  /// EDM is an optimization, not a prerequisite. A session that goes quiet
  /// is restarted with normal NI so identity acquisition can continue.
  func maintainExtendedDistanceHealth(at now: CFTimeInterval) {
    guard
      let peerId = extendedDistancePeerId,
      activeRangingPeerIds.contains(peerId),
      !didDiscoverExtendedDistanceLimit
    else {
      return
    }

    let lastUsefulAt = extendedDistanceLastUsefulAt
      ?? extendedDistanceStartedAt
      ?? now
    guard now - lastUsefulAt >= SpatialRangingTuning.extendedDistanceHealthTimeout else {
      return
    }

    extendedDistancePeerId = nil
    extendedDistanceStartedAt = nil
    extendedDistanceLastUsefulAt = nil
    extendedDistanceCooldownUntil[peerId] = now
      + SpatialRangingTuning.extendedDistanceRetryCooldown
    extendedDistanceCandidatePeerId = nil
    extendedDistanceCandidateSince = nil

    SpatialPerformance.signposter.emitEvent(
      "Extended Distance Measurement health fallback",
      "Peer: \(peerId.prefix(8), privacy: .public)"
    )

    if let token = peerTokens[peerId] {
      runNearbySession(for: peerId, token: token)
    }
  }

  private func requestRanging(
    with peerId: String,
    healthState requestedHealthState: SpatialRangingHealthState? = nil
  ) {
    let transactionId = UUID()
    guard SpatialRangingSessionOwnership.insertOutboundAttempt(
      peerId,
      pendingPeerIds: &pendingRangingPeerIds,
      outboundPeerIds: &outboundRangingPeerIds
    ) else {
      return
    }

    let now = CACurrentMediaTime()
    var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
    let healthState = requestedHealthState
      ?? (health.state == .renegotiating ? .renegotiating : .acquiring)
    health.beginTransaction(at: now, state: healthState)
    peerRangingHealth[peerId] = health
    _ = rememberRangingTransaction(transactionId, for: peerId)
    if healthState == .renegotiating {
      SpatialPerformance.signposter.emitEvent(
        "Fresh ranging transaction after health failure",
        "Peer: \(peerId.prefix(8), privacy: .public), transaction: \(transactionId.uuidString.prefix(8), privacy: .public), hard attempt: \(health.hardRecoveryAttempts)"
      )
    }
    let isNewProbe = peerRangingPhases[peerId] == nil
      || peerRangingPhases[peerId] == .unprobed
    let isRestartedProbe = requestedHealthState == .renegotiating
      && peerRangingPhases[peerId] == .probing
    if isNewProbe || isRestartedProbe {
      peerRangingPhases[peerId] = .probing
      peerProbeStartedAt[peerId] = now
      peerProbeDeadlineAt[peerId] = now
        + SpatialRangingTuning.probeHardDeadline
      peerFirstMeasurementAt.removeValue(forKey: peerId)
      peerFirstDistanceAt.removeValue(forKey: peerId)
      peerFirstProjectableMeasurementAt.removeValue(forKey: peerId)
      peerFirstUsefulMeasurementAt.removeValue(forKey: peerId)
      peerProbeCounts[peerId, default: 0] += 1
      SpatialPerformance.signposter.emitEvent(
        "Probe selected",
        "Peer: \(peerId.prefix(8), privacy: .public), number: \(self.peerProbeCounts[peerId] ?? 0)"
      )
    }
    rangingStartedAt[peerId] = now
    setPeerLinkState(
      .connecting(transactionId: transactionId),
      for: peerId,
      reason: "scheduler-acquired"
    )
    if !didSignpostFirstRangingTransaction {
      didSignpostFirstRangingTransaction = true
      let latencyMilliseconds = discoveryStartedAt.map {
        Int((now - $0) * 1_000)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "First ranging transaction started",
        "Latency milliseconds: \(latencyMilliseconds), peer: \(peerId.prefix(8), privacy: .public), transaction: \(transactionId.uuidString.prefix(8), privacy: .public)"
      )
    }

    if connections[peerId] != nil {
      sendRangingRequest(to: peerId)
      return
    }

    if let endpoint = discoveredEndpoints[peerId] {
      connect(to: endpoint, peerId: peerId)
      return
    }

    if bluetoothWakeService?.canSendMessage(to: peerId) == true {
      sendRangingRequest(to: peerId)
      return
    }

    refreshTransportForRangingIfNeeded(
      for: peerId,
      at: now,
      reason: "request-transport-unavailable"
    )
    abortOutboundNegotiation(
      for: peerId,
      transactionId: transactionId,
      reason: "transport-unavailable"
    )
  }

  func sendRangingRequest(to peerId: String) {
    guard
      pendingRangingPeerIds.contains(peerId),
      let transactionId = currentOutboundRangingTransaction(for: peerId)
    else {
      return
    }

    setPeerLinkState(
      .negotiatingOutbound(transactionId: transactionId),
      for: peerId,
      reason: "transport-ready"
    )

    let session = nearbySession(for: peerId)
    guard
      let token = session.discoveryToken,
      let encodedToken = try? NearbyDiscoveryTokenCodec.encode(token)
    else {
      abortOutboundNegotiation(
        for: peerId,
        transactionId: transactionId,
        reason: "local-token-unavailable"
      )
      return
    }

    if let connection = connections[peerId] {
      let connectionId = ObjectIdentifier(connection)
      guard authenticatedConnections.contains(connectionId) else {
        authenticateConnections(with: peerId)
        return
      }

      sendRangingMessage(
        .rangeRequest,
        to: peerId,
        discoveryToken: encodedToken,
        transactionId: transactionId
      )
      SpatialPerformance.signposter.emitEvent(
        "Ranging request sent",
        "Peer: \(peerId.prefix(8), privacy: .public), transaction: \(transactionId.uuidString.prefix(8), privacy: .public), transport: network"
      )
      return
    }

    if bluetoothWakeService?.send(
      .rangeRequest,
      to: peerId,
      discoveryToken: encodedToken,
      transactionId: transactionId
    ) == true {
      SpatialPerformance.signposter.emitEvent(
        "Ranging request sent",
        "Peer: \(peerId.prefix(8), privacy: .public), transaction: \(transactionId.uuidString.prefix(8), privacy: .public), transport: bluetooth"
      )
      return
    }

    refreshTransportForRangingIfNeeded(
      for: peerId,
      at: CACurrentMediaTime(),
      reason: "send-transport-unavailable"
    )
    abortOutboundNegotiation(
      for: peerId,
      transactionId: transactionId,
      reason: "transport-unavailable"
    )
  }

  private func nearbySession(for peerId: String) -> NISession {
    if let session = nearbySessions[peerId] {
      return session
    }

    let session = NISession()
    session.delegateQueue = stateQueue
    session.delegate = self
    nearbySessions[peerId] = session
    return session
  }

  private func discardRangingSession(for peerId: String) {
    let session = nearbySessions.removeValue(forKey: peerId)
    peerTokens.removeValue(forKey: peerId)
    if extendedDistancePeerId == peerId {
      extendedDistancePeerId = nil
      extendedDistanceStartedAt = nil
      extendedDistanceLastUsefulAt = nil
      if lastSignpostedExtendedDistancePeerId == peerId {
        lastSignpostedExtendedDistancePeerId = nil
        SpatialPerformance.signposter.emitEvent(
          "Extended Distance Measurement disabled"
        )
      }
    }
    session?.invalidate()
  }

  private func retryJitter(for peerId: String) -> CFTimeInterval {
    CFTimeInterval(peerId.utf8.reduce(0) { ($0 + Int($1)) % 10 }) / 10
  }

  private func recordSuccessfulRanging(
    with peerId: String,
    hasUsefulMeasurement: Bool,
    hasDistance: Bool
  ) {
    guard hasUsefulMeasurement else {
      return
    }

    if hasDistance,
      peersWithSignpostedFirstDistance.insert(peerId).inserted
    {
      SpatialPerformance.signposter.emitEvent(
        "First UWB distance received",
        "Peer: \(peerId.prefix(8), privacy: .public)"
      )
    }

    guard
      !didDiscoverRangingLimit,
      peersWithSuccessfulRanging.insert(peerId).inserted,
      pendingRangingPeerIds.isEmpty,
      activeRangingPeerIds.count == hardwareSessionCapacity,
      activeRangingPeerIds.isSubset(of: peersWithSuccessfulRanging)
    else {
      return
    }

    hardwareSessionCapacity += 1
    signpostRangingStateIfNeeded()
    maintainRangingPool()
  }

  private func recordFirstUsefulProbeMeasurement(
    for peerId: String,
    measuredAt: CFTimeInterval,
    hasWorldTransform: Bool,
    hasDistance: Bool,
    hasDirectionalMeasurement: Bool
  ) {
    guard
      peerRangingPhases[peerId] == .probing,
      (hasWorldTransform || hasDistance || hasDirectionalMeasurement)
    else {
      return
    }

    if peerFirstMeasurementAt[peerId] == nil {
      peerFirstMeasurementAt[peerId] = measuredAt
      // Keep the old key as a source-compatible alias for diagnostics and
      // existing callers while the lifecycle uses the explicit timestamps.
      peerFirstUsefulMeasurementAt[peerId] = measuredAt
      let probeDuration = measuredAt - (rangingStartedAt[peerId] ?? measuredAt)
      SpatialPerformance.signposter.emitEvent(
        "First useful probe measurement",
        "Peer: \(peerId.prefix(8), privacy: .public), duration milliseconds: \(Int(max(0, probeDuration) * 1_000)), world transform: \(hasWorldTransform), direction: \(hasDirectionalMeasurement), distance: \(hasDistance)"
      )
    }

    if hasDistance {
      peerFirstDistanceAt[peerId] = peerFirstDistanceAt[peerId] ?? measuredAt
      distanceOnlyMeasurementCount += hasWorldTransform || hasDirectionalMeasurement
        ? 0
        : 1
    }
    if hasWorldTransform {
      peerFirstProjectableMeasurementAt[peerId] =
        peerFirstProjectableMeasurementAt[peerId] ?? measuredAt
      if peerCameraAssistanceStates[peerId] == .converged {
        cameraAssistedMeasurementCount += 1
      } else {
        directionMeasurementCount += 1
      }
    }
    if hasDirectionalMeasurement, !hasWorldTransform {
      directionMeasurementCount += 1
    }

    // A first distance sample can precede camera assistance's projectable
    // transform. Keep feeding fresh NI updates while the peer is probing so a
    // later direction sample can promote it without another acquisition.
    onUsefulRangingSample?(
      SpatialRangingSample(
        peerId: peerId,
        measuredAt: measuredAt,
        hasWorldTransform: hasWorldTransform,
        hasDistance: hasDistance,
        hasDirectionalMeasurement: hasDirectionalMeasurement
      )
    )
  }

  private func handleRangingFailure(
    for peerId: String,
    error: Error
  ) {
    let nearbyError = error as NSError
    let isNearbyInteractionError = nearbyError.domain == NIErrorDomain

    if isNearbyInteractionError,
      #available(iOS 17.0, *),
      nearbyError.code == NIError.Code.activeExtendedDistanceSessionsLimitExceeded.rawValue
    {
      didDiscoverExtendedDistanceLimit = true
      extendedDistanceCooldownUntil[peerId] = CACurrentMediaTime()
        + SpatialRangingTuning.extendedDistanceRetryCooldown
      SpatialPerformance.signposter.emitEvent(
        "Nearby Interaction extended-distance fallback",
        "Peer: \(peerId.prefix(8), privacy: .public), code: \(nearbyError.code)"
      )
    }

    if isNearbyInteractionError,
      nearbyError.code == NIError.Code.activeSessionsLimitExceeded.rawValue
    {
      didDiscoverRangingLimit = true
      hardwareSessionCapacity = max(1, activeRangingPeerIds.count - 1)
      signpostRangingStateIfNeeded()
    }

    if isNearbyInteractionError,
      nearbyError.code == NIError.Code.invalidARConfiguration.rawValue
    {
      peerCameraAssistanceSuppressed.insert(peerId)
      SpatialPerformance.signposter.emitEvent(
        "Nearby Interaction camera-assistance fallback",
        "Peer: \(peerId.prefix(8), privacy: .public), code: \(nearbyError.code)"
      )
    }

    let reason = "nearby-session-invalidated-\(nearbyError.code)"
    SpatialPerformance.signposter.emitEvent(
      "Nearby Interaction session invalidated",
      "Peer: \(peerId.prefix(8), privacy: .public), domain: \(nearbyError.domain, privacy: .public), code: \(nearbyError.code), description: \(nearbyError.localizedDescription, privacy: .public)"
    )

    let now = CACurrentMediaTime()
    let disposition = SpatialRangingFailurePolicy.invalidationDisposition(
      isActive: activeRangingPeerIds.contains(peerId),
      isPending: pendingRangingPeerIds.contains(peerId),
      isAlreadyRenegotiating: peerRangingHealth[peerId]?.state == .renegotiating
    )
    switch disposition {
    case .activeFreshRetry:
      scheduleFreshRangingRetry(
        for: peerId,
        at: now,
        reason: reason
      )
    case .activeHardRecovery:
      startHardRecovery(
        for: peerId,
        at: now,
        reason: reason
      )
    case .pendingFreshRetry:
      guard let transactionId = currentOutboundRangingTransaction(for: peerId)
      else {
        discardRangingSession(for: peerId)
        break
      }

      var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
      health.state = .renegotiating
      health.hardRecoveryAttempts = max(1, health.hardRecoveryAttempts + 1)
      health.recoveryStartedAt = now
      health.lastHardRecoveryAt = now
      health.transactionStartedAt = now
      health.consecutiveUsefulUpdates = 0
      health.consecutiveUselessUpdates = 0
      peerRangingHealth[peerId] = health
      abortOutboundNegotiation(
        for: peerId,
        transactionId: transactionId,
        reason: reason
      )
    case .discard:
      // An invalidated session is never reused. Removing this mapping before
      // the next acquisition also makes any delayed delegate callback unable
      // to mutate the fresh transaction.
      discardRangingSession(for: peerId)
    }
    maintainRangingPool()
  }

  var effectiveRangingCapacity: Int {
    switch runtimeRole {
    case .backgroundResponder:
      // The responder accepts inbound sessions using hardware capacity even
      // though its outbound initiation budget is zero.
      return max(1, hardwareSessionCapacity)
    case .cameraViewer:
      return max(1, hardwareSessionCapacity)
    case .foregroundProximity:
      // Inbound sessions and locally initiated work share this real hardware
      // limit. The separate proactive budget below keeps attendee ranging
      // energy-conscious without rejecting safe inbound responders.
      return max(1, hardwareSessionCapacity)
    case .suspended:
      return 0
    }
  }

  var foregroundProactiveCapacity: Int {
    max(
      0,
      min(
        hardwareSessionCapacity,
        SpatialRangingTuning.foregroundProximityConcurrentLimit
      )
    )
  }

  var outboundInitiationCapacity: Int {
    switch runtimeRole {
    case .cameraViewer:
      return max(1, hardwareSessionCapacity)
    case .foregroundProximity:
      return foregroundProactiveCapacity
    case .backgroundResponder:
      return 0
    case .suspended:
      return 0
    }
  }

  func signpostRangingStateIfNeeded() {
    let mode = rangingMode.rawValue
    let role = runtimeRole.rawValue
    let activeCount = activeRangingPeerIds.count
    let pendingCount = pendingRangingPeerIds.count
    let hardwareCapacity = effectiveRangingCapacity
    let outboundCapacity = outboundInitiationCapacity
    let outboundCount = outboundRangingPeerIds.count
    let activeResponderPeerIds = activeRangingPeerIds
      .subtracting(outboundRangingPeerIds)
    let activeResponderLabels = activeResponderPeerIds
      .sorted()
      .map { String($0.prefix(8)) }
      .joined(separator: ",")
    let orphanedOutboundCount = outboundRangingPeerIds.subtracting(
      activeRangingPeerIds.union(pendingRangingPeerIds)
    ).count
    let presenceCount = peerIdentities.count
    let distanceDegradedCount = activeRangingPeerIds.filter { peerId in
      guard let health = peerRangingHealth[peerId] else {
        return false
      }
      return health.distanceState == .degraded
        || health.distanceState == .softRecovering
        || health.distanceState == .renegotiating
    }.count
    let summary = "\(role):\(mode):\(presenceCount):\(activeCount):\(pendingCount):\(outboundCount):\(activeResponderLabels):\(orphanedOutboundCount):\(hardwareCapacity):\(foregroundProactiveCapacity):\(outboundCapacity):\(acquisitionQueueSize):\(verificationPeerCount):\(rangingRotationCount):\(rangingRetryCount):\(probePromotionCount):\(probeEvictionCount):\(probeTimeoutCount):\(distanceDegradedCount):\(distanceOnlyMeasurementCount):\(directionMeasurementCount):\(cameraAssistedMeasurementCount)"

    guard summary != lastSignpostedRangingSummary else {
      return
    }

    lastSignpostedRangingSummary = summary
    SpatialPerformance.signposter.emitEvent(
      "Nearby ranging state",
      "Role: \(role, privacy: .public), mode: \(mode, privacy: .public), presence peers: \(presenceCount), active NI sessions: \(activeCount), active responders: \(activeResponderPeerIds.count) [\(activeResponderLabels, privacy: .public)], pending NI sessions: \(pendingCount), outbound/local initiated: \(outboundCount), orphaned outbound ownership: \(orphanedOutboundCount), learned hardware capacity: \(self.hardwareSessionCapacity), foreground proactive capacity: \(self.foregroundProactiveCapacity), role proactive capacity: \(outboundCapacity), waiting peers: \(self.acquisitionQueueSize), distance-degraded active peers: \(distanceDegradedCount), candidate/verified peers: \(self.verificationPeerCount), rotations: \(self.rangingRotationCount), retries: \(self.rangingRetryCount), promotions: \(self.probePromotionCount), evictions: \(self.probeEvictionCount), probe timeouts: \(self.probeTimeoutCount), distance-only updates: \(self.distanceOnlyMeasurementCount), direction updates: \(self.directionMeasurementCount), camera-assisted updates: \(self.cameraAssistedMeasurementCount)"
    )
  }
}

extension NearbyDiscoveryService: NISessionDelegate {
  func session(
    _ session: NISession,
    didUpdate nearbyObjects: [NINearbyObject]
  ) {
    guard let peerId = peerId(for: session) else {
      return
    }

    let now = CACurrentMediaTime()
    let hasDistance = nearbyObjects.contains { nearbyObject in
      guard let distance = nearbyObject.distance else {
        return false
      }
      return distance.isFinite && distance > 0
    }
    let hasDirection = nearbyObjects.contains { nearbyObject in
      Self.directionalMeasurement(from: nearbyObject, at: now) != nil
    }
    let hasWorldTransform: Bool
    if #available(iOS 16.0, *) {
      hasWorldTransform = nearbyObjects.contains { nearbyObject in
        guard let transform = session.worldTransform(for: nearbyObject) else {
          return false
        }
        return Self.isValidWorldTransform(transform)
      }
    } else {
      hasWorldTransform = false
    }
    let hasUsefulMeasurement = SpatialRangingHealthPolicy.hasUsefulMeasurement(
      hasFinitePositiveDistance: hasDistance,
      hasValidWorldTransform: hasWorldTransform,
      hasValidDirection: hasDirection
    )
    recordPeerDelegateCallback(
      peerId,
      at: now,
      hasDistance: hasDistance,
      hasWorldTransform: hasWorldTransform,
      hasDirection: hasDirection
    )
    recordSuccessfulRanging(
      with: peerId,
      hasUsefulMeasurement: hasUsefulMeasurement,
      hasDistance: hasDistance
    )

    if peersWithSignpostedFirstNIUpdate.insert(peerId).inserted {
      SpatialPerformance.signposter.emitEvent(
        "First NI update",
        "Peer: \(peerId.prefix(8), privacy: .public)"
      )
    }
    if !didSignpostFirstNIUpdate {
      didSignpostFirstNIUpdate = true
      let latencyMilliseconds = discoveryStartedAt.map {
        Int((CACurrentMediaTime() - $0) * 1_000)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "First NI update latency",
        "Latency milliseconds: \(latencyMilliseconds), peer: \(peerId.prefix(8), privacy: .public)"
      )
    }

    if peerId == extendedDistancePeerId, hasUsefulMeasurement {
      extendedDistanceLastUsefulAt = now
    }

    for nearbyObject in nearbyObjects {
      emitPeerUpdate(
        peerId,
        identity: identity(for: peerId),
        session: session,
        nearbyObject: nearbyObject
      )
    }

    recordFirstUsefulProbeMeasurement(
      for: peerId,
      measuredAt: now,
      hasWorldTransform: hasWorldTransform,
      hasDistance: hasDistance,
      hasDirectionalMeasurement: hasDirection
    )
  }

  @available(iOS 16.0, *)
  func session(
    _ session: NISession,
    didUpdateAlgorithmConvergence convergence: NIAlgorithmConvergence,
    for object: NINearbyObject?
  ) {
    guard let peerId = peerId(for: session) else {
      return
    }

    let description = String(describing: convergence.status).lowercased()
    let state: SpatialCameraAssistanceState
    if description.contains("notconverged")
      || description.contains("not converged")
    {
      state = .notConverged
    } else if description.contains("converged") {
      state = .converged
    } else {
      state = .unknown
    }

    updateCameraAssistanceState(state, for: peerId)
    if state == .converged, !didSignpostFirstCameraAssistanceConvergence {
      didSignpostFirstCameraAssistanceConvergence = true
      let latencyMilliseconds = discoveryStartedAt.map {
        Int((CACurrentMediaTime() - $0) * 1_000)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "First camera assistance converged",
        "Latency milliseconds: \(latencyMilliseconds), peer: \(peerId.prefix(8), privacy: .public)"
      )
    }
    SpatialPerformance.signposter.emitEvent(
      "Camera Assistance convergence",
      "Peer: \(peerId.prefix(8), privacy: .public), state: \(state.rawValue, privacy: .public)"
    )
  }

  func session(
    _ session: NISession,
    didRemove nearbyObjects: [NINearbyObject],
    reason: NINearbyObject.RemovalReason
  ) {
    guard let peerId = peerId(for: session) else {
      return
    }

    // NI object removal is a precise-link signal, not an event-presence
    // signal. Timeout and unknown removals must not make React remove an
    // attendee while Bonjour/BLE still owns the peer identity. The transport
    // eviction path emits the actual presence loss event.
    if case .peerEnded = reason {
      emitPeerLost(
        peerId,
        identity: identity(for: peerId),
        reason: "\(reason)",
        stillNearby: true
      )
    }

    guard activeRangingPeerIds.contains(peerId) else {
      return
    }

    let removalReason: SpatialRangingRemovalReason
    switch reason {
    case .timeout:
      removalReason = .timeout
    case .peerEnded:
      removalReason = .peerEnded
    @unknown default:
      removalReason = .unknown
    }

    switch SpatialRangingFailurePolicy.removalAction(for: removalReason) {
    case .softRecovery:
      markRangingHealthDegraded(
        for: peerId,
        at: CACurrentMediaTime(),
        reason: removalReason == .timeout
          ? "nearby-object-timeout"
          : "nearby-object-removed"
      )
      startSoftRecovery(
        for: peerId,
        at: CACurrentMediaTime(),
        reason: removalReason == .timeout
          ? "nearby-object-timeout"
          : "nearby-object-removed"
      )
    case .freshNegotiation:
      startHardRecovery(
        for: peerId,
        at: CACurrentMediaTime(),
        reason: "nearby-object-peer-ended"
      )
    }
  }

  func sessionSuspensionEnded(_ session: NISession) {
    guard
      let peerId = peerId(for: session),
      let token = token(for: peerId)
    else {
      return
    }

    if peerRangingHealth[peerId]?.state == .degraded {
      startSoftRecovery(
        for: peerId,
        at: CACurrentMediaTime(),
        reason: "nearby-session-resumed"
      )
    } else {
      runNearbySession(for: peerId, token: token)
    }
  }

  func sessionWasSuspended(_ session: NISession) {
    guard let peerId = peerId(for: session) else {
      return
    }

    markRangingHealthDegraded(
      for: peerId,
      at: CACurrentMediaTime(),
      reason: "nearby-session-suspended"
    )
    SpatialPerformance.signposter.emitEvent("Nearby ranging suspended")
  }

  func session(_ session: NISession, didInvalidateWith error: Error) {
    guard let peerId = peerId(for: session) else {
      return
    }

    handleRangingFailure(for: peerId, error: error)
  }
}
