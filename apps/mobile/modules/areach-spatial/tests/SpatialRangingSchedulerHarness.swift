import Foundation

/// A deterministic harness for the scheduler policy. It intentionally runs
/// without an iPhone, ARKit, NearbyInteraction, or an Xcode test target; it
/// proves allocation and phase transitions, not physical UWB performance.
@main
struct SpatialRangingSchedulerHarness {
  private static let scheduler = SpatialRangingScheduler()
  private static let probeTimeout = 1.5
  private static let candidateLeaseDuration = 4.5
  private static let verifiedLeaseDuration = 8.0

  static func main() {
    testOnePeerPresencePool()
    testThreePeerPresencePool()
    testTwentyPeerPresencePool()
    testTwentyFourPeerPresencePool()
    testThirtyPeerPresencePool()
    testFiftyPeerPresencePool()
    testProbeEvictsClearlyIrrelevantPeer()
    testProbePromotesCameraCandidate()
    testProbeWaitsForDirection()
    testDistanceOnlyProbePromotesOnCameraDepthInterest()
    testProbeWithoutMeasurementReachesDeadline()
    testUsefulProbeReachesAbsoluteDeadline()
    testBackgroundResponderHasNoProactiveBudget()
    testViewerReservesAcquisitionCapacity()
    testVerifiedPeerIsSticky()
    testForegroundProximityKeepsVerifiedPeerWithoutBacklog()
    testForegroundProximityRotatesWhenPeerWaiting()
    testDistanceStalledVerifiedPeerDoesNotStarveWaitingPeer()
    testDistanceStalledPeerGetsRecoveryPriority()
    testNormalForegroundRotationDoesNotCountAsHealthFailure()
    testForegroundProximityCandidateDoesNotStarveWaitingPeer()
    testForegroundProximityPrefersLeastRecentlyRangedWaiter()
    testForegroundProximityDoesNotRotateResponderSession()
    testForegroundThreePhoneStarRotatesToWaitingPeer()
    testForegroundResponderLeavesProactiveBudgetAvailable()
    testRemoteStopDefersForegroundReacquisition()
    testForegroundProximitySingleSlotFairness()
    testForegroundProximityThreePeerFairness()
    testForegroundProximityFivePeerFairness()
    testForegroundProximityTenPeerFairness()
    testForegroundProximityTwentyPeerFairness()
    testForegroundSessionReleaseClearsInitiatorOwnership()
    testVerifiedInterestHysteresis()
    testSingleVerifiedPeerRemainsRangedWithoutReplacement()
    testVerifiedInterestReleasesQuickly()
    testCameraInterestOverridesWeakRSSI()
    testCandidateEventuallyYields()
    testWaitingPeerFairness()
    testRetryBackoffAndLearnedCapacity()
    testCapacityOneTwoAndThree()
    testSingleEDMOwnerAndMigrationHysteresis()
    testTwentyFourPeerProbeSimulation()
    print("SpatialRangingSchedulerHarness: PASS")
  }

  private static func testOnePeerPresencePool() {
    let plan = scheduler.plan(
      candidates: [makeCandidate(0)],
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.acquirePeerIds == ["peer-0"], "single peer was not acquired")
  }

  private static func testThreePeerPresencePool() {
    let plan = scheduler.plan(
      candidates: (0..<3).map { makeCandidate($0) },
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.acquirePeerIds.count == 3, "three-peer pool was underfilled")
  }

  private static func testTwentyPeerPresencePool() {
    let candidates = (0..<20).map { makeCandidate($0) }
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(candidates.count == 20, "20-peer presence scenario was not created")
    require(plan.acquirePeerIds.count == 3, "20-peer pool exceeded acquisition capacity")
  }

  private static func testTwentyFourPeerPresencePool() {
    let candidates = (0..<24).map { makeCandidate($0) }
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(candidates.count >= 20, "presence pool lost synthetic peers")
    require(plan.acquirePeerIds.count == 3, "viewer did not fill learned capacity")
    require(plan.releasePeerIds.isEmpty, "fresh acquisition pool rotated early")
    require(
      plan.acquirePeerIds.allSatisfy { id in
        candidates.first { $0.peerId == id }?.phase == .unprobed
      },
      "initial allocation did not select probes"
    )
  }

  private static func testProbeEvictsClearlyIrrelevantPeer() {
    let evaluation = scheduler.evaluateProbe(
      candidate: makeCandidate(
        0,
        phase: .probing,
        isActive: true,
        hasUsefulMeasurement: true,
        hasProjectableMeasurement: true,
        cameraInterest: 0.03,
        leaseStartedAt: 100
      ),
      promotionInterest: 0.18,
      evictionInterest: 0.14
    )

    require(
      evaluation.decision == .evict,
      "an outside probe did not release its slot from the first useful sample"
    )
  }

  private static func testThirtyPeerPresencePool() {
    let candidates = (0..<30).map { makeCandidate($0) }
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(candidates.count == 30, "30-peer presence scenario was not created")
    require(plan.acquirePeerIds.count == 3, "30-peer pool consumed more than the working set")
  }

  private static func testFiftyPeerPresencePool() {
    let candidates = (0..<50).map { makeCandidate($0) }
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(candidates.count == 50, "50-peer presence scenario was not created")
    require(plan.acquirePeerIds.count == 3, "50-peer pool exceeded acquisition capacity")
    require(
      plan.acquirePeerIds == ["peer-0", "peer-1", "peer-10"],
      "50-peer initial allocation was not deterministic"
    )
  }

  private static func testProbePromotesCameraCandidate() {
    let evaluation = scheduler.evaluateProbe(
      candidate: makeCandidate(
        0,
        phase: .probing,
        isActive: true,
        hasUsefulMeasurement: true,
        hasProjectableMeasurement: true,
        cameraInterest: 0.2,
        leaseStartedAt: 100
      ),
      promotionInterest: 0.18,
      evictionInterest: 0.14,
      now: 100
    )

    require(
      evaluation.decision == .promoteToCandidate,
      "a camera-interesting probe was not promoted"
    )
  }

  private static func testProbeWaitsForDirection() {
    let evaluation = scheduler.evaluateProbe(
      candidate: makeCandidate(
        0,
        phase: .probing,
        isActive: true,
        hasUsefulMeasurement: true,
        hasProjectableMeasurement: false,
        cameraInterest: 0,
        leaseStartedAt: 100
      ),
      promotionInterest: 0.18,
      evictionInterest: 0.14,
      now: 100.3
    )

    require(
      evaluation.decision == .wait,
      "distance-only sample was treated as a safe identity rejection"
    )
  }

  private static func testDistanceOnlyProbePromotesOnCameraDepthInterest() {
    let evaluation = scheduler.evaluateProbe(
      candidate: makeCandidate(
        0,
        phase: .probing,
        isActive: true,
        isNearVisibleBody: true,
        hasUsefulMeasurement: true,
        hasProjectableMeasurement: false,
        cameraInterest: 0.08,
        leaseStartedAt: 100,
        firstUsefulMeasurementAt: 100.1
      ),
      promotionInterest: 0.18,
      evictionInterest: 0.14,
      now: 100.3
    )

    require(
      evaluation.decision == .promoteToCandidate,
      "fresh distance-only body-depth evidence did not promote the probe"
    )
  }

  private static func testProbeWithoutMeasurementReachesDeadline() {
    let beforeDeadline = scheduler.evaluateProbe(
      candidate: makeCandidate(
        0,
        phase: .probing,
        isActive: true,
        leaseStartedAt: 100,
        probeDeadlineAt: 102.4
      ),
      promotionInterest: 0.18,
      evictionInterest: 0.14,
      now: 102.3
    )
    require(
      beforeDeadline.decision == .wait,
      "probe without a measurement expired before its deadline"
    )

    let atDeadline = scheduler.evaluateProbe(
      candidate: makeCandidate(
        0,
        phase: .probing,
        isActive: true,
        leaseStartedAt: 100,
        probeDeadlineAt: 102.4
      ),
      promotionInterest: 0.18,
      evictionInterest: 0.14,
      now: 102.4
    )
    require(
      atDeadline.decision == .evict,
      "probe without a measurement held its slot beyond the deadline"
    )
  }

  private static func testUsefulProbeReachesAbsoluteDeadline() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .probing,
          isActive: true,
          hasUsefulMeasurement: true,
          hasProjectableMeasurement: false,
          leaseStartedAt: 0
        ),
        makeCandidate(1),
      ],
      role: .cameraViewer,
      now: 10,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(
      plan.releasePeerIds == ["peer-0"],
      "useful distance-only probe was allowed to exceed its hard deadline"
    )
    require(
      plan.acquirePeerIds == ["peer-1"],
      "hard-deadline release did not return the slot to acquisition"
    )
  }

  private static func testBackgroundResponderHasNoProactiveBudget() {
    let candidates = [
      makeCandidate(0, phase: .verified, isActive: true, leaseStartedAt: 90),
      makeCandidate(1),
      makeCandidate(2),
    ]
    let plan = scheduler.plan(
      candidates: candidates,
      role: .backgroundResponder,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 0,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.acquirePeerIds.isEmpty, "background responder initiated ranging")
    require(plan.releasePeerIds.isEmpty, "background responder rotated sessions")
  }

  private static func testViewerReservesAcquisitionCapacity() {
    let candidates = [
      makeCandidate(
        0,
        phase: .verified,
        isActive: true,
        isVerified: true,
        measurementFreshness: 0.9,
        cameraInterest: 0.9,
        leaseStartedAt: 100
      ),
      makeCandidate(
        1,
        phase: .candidate,
        isActive: true,
        measurementFreshness: 0.8,
        cameraInterest: 0.8,
        leaseStartedAt: 100
      ),
      makeCandidate(
        2,
        phase: .probing,
        isActive: true,
        leaseStartedAt: 98
      ),
      makeCandidate(3),
    ]
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-2"], "probe slot was not reclaimed")
    require(plan.acquirePeerIds == ["peer-3"], "viewer did not reserve an acquisition slot")
  }

  private static func testVerifiedPeerIsSticky() {
    let candidates = [
      makeCandidate(
        0,
        phase: .verified,
        isActive: true,
        isVerified: true,
        measurementFreshness: 0.9,
        cameraInterest: 0.9,
        leaseStartedAt: 0
      ),
      makeCandidate(
        1,
        phase: .candidate,
        isActive: true,
        measurementFreshness: 0.8,
        cameraInterest: 0.8,
        leaseStartedAt: 0
      ),
      makeCandidate(2, phase: .probing, isActive: true, leaseStartedAt: 0),
      makeCandidate(3),
    ]
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(!plan.releasePeerIds.contains("peer-0"), "verified peer lost sticky priority")
    require(plan.acquirePeerIds == ["peer-3"], "new probe did not progress beside verified work")
  }

  private static func testVerifiedInterestHysteresis() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          cameraInterest: 0.03,
          lastCameraRelevantAt: 0
        ),
        makeCandidate(1, cameraInterest: 0.8),
      ],
      role: .cameraViewer,
      now: 0.5,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds.isEmpty, "verified target lost its short interest hysteresis")
    require(plan.acquirePeerIds.isEmpty, "verified target rotated before hysteresis elapsed")
  }

  private static func testForegroundProximityKeepsVerifiedPeerWithoutBacklog() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          measurementFreshness: 0.9,
          leaseStartedAt: 90
        )
      ],
      role: .foregroundProximity,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 1,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(
      plan.releasePeerIds.isEmpty,
      "foreground attendee presence released its verified ranging link"
    )
    require(
      plan.acquirePeerIds.isEmpty,
      "foreground attendee presence scheduled an unnecessary replacement"
    )
  }

  private static func testForegroundProximityRotatesWhenPeerWaiting() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          leaseStartedAt: 90
        ),
        makeCandidate(1),
      ],
      role: .foregroundProximity,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 1,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-0"], "foreground incumbent did not yield after its lease")
    require(plan.acquirePeerIds == ["peer-1"], "foreground waiting peer did not acquire the released slot")
  }

  private static func testDistanceStalledVerifiedPeerDoesNotStarveWaitingPeer() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          lastRangedAt: 90,
          leaseStartedAt: 90,
          distanceHealthState: .degraded,
          isDistanceHealthy: false
        ),
        makeCandidate(
          1,
          phase: .verified,
          isActive: true,
          isVerified: true,
          lastRangedAt: 90,
          leaseStartedAt: 90,
          distanceHealthState: .healthy,
          isDistanceHealthy: true
        ),
        makeCandidate(2),
      ],
      role: .foregroundProximity,
      now: 100,
      sessionCapacity: 2,
      outboundCapacity: 2,
      outboundCount: 2,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-0"], "distance-stalled verified peer was not the releasable incumbent")
    require(plan.acquirePeerIds == ["peer-2"], "waiting attendee did not acquire the released foreground slot")
  }

  private static func testDistanceStalledPeerGetsRecoveryPriority() {
    let healthy = makeCandidate(
      0,
      phase: .candidate,
      distanceHealthState: .healthy,
      isDistanceHealthy: true
    )
    let stalled = makeCandidate(
      1,
      phase: .candidate,
      distanceHealthState: .degraded,
      isDistanceHealthy: false
    )

    require(
      scheduler.priority(for: stalled, now: 100)
        > scheduler.priority(for: healthy, now: 100),
      "distance-stalled peer did not receive scheduler recovery priority"
    )
  }

  private static func testNormalForegroundRotationDoesNotCountAsHealthFailure() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    health.softRecoveryAttempts = 1
    health.hardRecoveryAttempts = 2
    health.distanceSoftRecoveryAttempts = 1
    health.distanceHardRecoveryAttempts = 2
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          leaseStartedAt: 0
        ),
        makeCandidate(1),
      ],
      role: .foregroundProximity,
      now: 10,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 1,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-0"], "healthy foreground lease did not rotate normally")
    require(health.softRecoveryAttempts == 1, "scheduler rotation changed spatial soft-failure history")
    require(health.hardRecoveryAttempts == 2, "scheduler rotation accumulated spatial hard-failure history")
    require(health.distanceSoftRecoveryAttempts == 1, "scheduler rotation changed distance soft-failure history")
    require(health.distanceHardRecoveryAttempts == 2, "scheduler rotation accumulated distance hard-failure history")
  }

  private static func testForegroundProximityCandidateDoesNotStarveWaitingPeer() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .candidate,
          isActive: true,
          isTentative: true,
          leaseStartedAt: 90
        ),
        makeCandidate(1),
      ],
      role: .foregroundProximity,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 1,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-0"], "foreground candidate monopolized its slot")
    require(plan.acquirePeerIds == ["peer-1"], "waiting peer did not replace the foreground candidate")
  }

  private static func testForegroundProximityPrefersLeastRecentlyRangedWaiter() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          leaseStartedAt: 90
        ),
        makeCandidate(1, lastRangedAt: 99),
        makeCandidate(2, lastRangedAt: 90),
      ],
      role: .foregroundProximity,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 1,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-0"], "foreground incumbent did not make room")
    require(plan.acquirePeerIds == ["peer-2"], "foreground scheduler ignored last-ranged fairness")
  }

  private static func testForegroundProximityDoesNotRotateResponderSession() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isLocallyInitiated: false,
          isVerified: true,
          leaseStartedAt: 0
        ),
      ],
      role: .foregroundProximity,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds.isEmpty, "foreground scheduler rotated an inbound responder without backlog")
    require(plan.acquirePeerIds.isEmpty, "foreground scheduler exceeded hardware capacity for a responder")
  }

  private static func testForegroundThreePhoneStarRotatesToWaitingPeer() {
    // Models B in the reported triangle: A's inbound responder session fills
    // B's learned one-session pool while C waits for a local opportunity.
    let responder = makeCandidate(
      0,
      phase: .verified,
      isActive: true,
      isLocallyInitiated: false,
      isVerified: true,
      hasUsefulMeasurement: true,
      leaseStartedAt: 0
    )
    let waitingPeer = makeCandidate(1, lastRangedAt: nil)

    let beforeLeaseExpiry = scheduler.plan(
      candidates: [responder, waitingPeer],
      role: .foregroundProximity,
      now: SpatialRangingTuning.foregroundProximityLeaseDuration - 0.01,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )
    require(
      beforeLeaseExpiry.releasePeerIds.isEmpty,
      "foreground responder rotated before its bounded lease elapsed"
    )

    let afterLeaseExpiry = scheduler.plan(
      candidates: [responder, waitingPeer],
      role: .foregroundProximity,
      now: SpatialRangingTuning.foregroundProximityLeaseDuration,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )
    require(
      afterLeaseExpiry.releasePeerIds == ["peer-0"],
      "full foreground responder slot did not rotate for a waiting attendee"
    )
    require(
      afterLeaseExpiry.acquirePeerIds == ["peer-1"],
      "waiting attendee did not acquire the yielded responder slot"
    )
  }

  private static func testForegroundResponderLeavesProactiveBudgetAvailable() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isLocallyInitiated: false,
          isVerified: true,
          leaseStartedAt: 0
        ),
        makeCandidate(1),
        makeCandidate(2),
      ],
      role: .foregroundProximity,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds.isEmpty, "foreground responder yielded to the proactive budget")
    require(
      plan.acquirePeerIds == ["peer-1", "peer-2"],
      "responder session incorrectly consumed local proactive slots"
    )
  }

  private static func testRemoteStopDefersForegroundReacquisition() {
    let retryDeadline = SpatialForegroundRangingPolicy.remoteStopRetryDeadline(
      role: .foregroundProximity,
      now: 50
    )
    guard let retryDeadline else {
      preconditionFailure("foreground remote stop did not produce a retry deadline")
    }
    require(
      retryDeadline == 50 + SpatialRangingTuning.foregroundRemoteStopCooldownDuration,
      "foreground phone did not defer reclaiming a remotely yielded edge"
    )
    let beforeRetry = scheduler.plan(
      candidates: [makeCandidate(0, retryAfter: retryDeadline)],
      role: .foregroundProximity,
      now: retryDeadline - 0.01,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )
    require(beforeRetry.acquirePeerIds.isEmpty, "foreground scheduler reclaimed a remotely yielded edge too early")
    let afterRetry = scheduler.plan(
      candidates: [makeCandidate(0, retryAfter: retryDeadline)],
      role: .foregroundProximity,
      now: retryDeadline,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )
    require(afterRetry.acquirePeerIds == ["peer-0"], "foreground scheduler did not re-enable a peer after the bounded defer")
    require(
      SpatialForegroundRangingPolicy.remoteStopRetryDeadline(
        role: .cameraViewer,
        now: 50
      ) == nil,
      "Camera viewer received the foreground peer retry cooldown"
    )
    require(
      SpatialForegroundRangingPolicy.remoteStopRetryDeadline(
        role: .backgroundResponder,
        now: 50
      ) == nil,
      "background responder received a proactive retry cooldown"
    )
  }

  private static func testForegroundProximitySingleSlotFairness() {
    requireForegroundPeersReceiveOpportunity(peerCount: 10, capacity: 1)
  }

  private static func testForegroundProximityThreePeerFairness() {
    requireForegroundPeersReceiveOpportunity(peerCount: 3, capacity: 2)
  }

  private static func testForegroundProximityFivePeerFairness() {
    requireForegroundPeersReceiveOpportunity(peerCount: 5, capacity: 3)
  }

  private static func testForegroundProximityTenPeerFairness() {
    requireForegroundPeersReceiveOpportunity(peerCount: 10, capacity: 3)
  }

  private static func testForegroundProximityTwentyPeerFairness() {
    requireForegroundPeersReceiveOpportunity(peerCount: 20, capacity: 3)
  }

  private static func testForegroundSessionReleaseClearsInitiatorOwnership() {
    var duplicatePendingPeerIds = Set<String>()
    var staleOutboundPeerIds: Set<String> = ["stale-peer"]
    require(
      !SpatialRangingSessionOwnership.insertOutboundAttempt(
        "stale-peer",
        pendingPeerIds: &duplicatePendingPeerIds,
        outboundPeerIds: &staleOutboundPeerIds
      ),
      "a stale outbound entry was accepted as a new attempt"
    )
    require(
      duplicatePendingPeerIds.isEmpty,
      "failed outbound acquisition left a phantom pending peer"
    )

    var activePeerIds: Set<String> = ["active-peer"]
    var pendingPeerIds = Set<String>()
    var outboundPeerIds: Set<String> = ["active-peer"]
    let activeRemoval = SpatialRangingSessionOwnership.removePeer(
      "active-peer",
      activePeerIds: &activePeerIds,
      pendingPeerIds: &pendingPeerIds,
      outboundPeerIds: &outboundPeerIds
    )

    require(activeRemoval.wasActive, "active foreground session was not removed")
    require(activeRemoval.wasOutbound, "active initiator ownership was not removed")
    require(outboundPeerIds.isEmpty, "released foreground peer remained in outbound budget")

    pendingPeerIds.insert("pending-peer")
    outboundPeerIds.insert("pending-peer")
    let pendingRemoval = SpatialRangingSessionOwnership.removePeer(
      "pending-peer",
      activePeerIds: &activePeerIds,
      pendingPeerIds: &pendingPeerIds,
      outboundPeerIds: &outboundPeerIds
    )
    require(pendingRemoval.wasPending, "pending foreground session was not removed")
    require(pendingRemoval.wasOutbound, "pending initiator ownership was not removed")
    require(outboundPeerIds.isEmpty, "aborted foreground peer remained in outbound budget")

    activePeerIds.insert("live-peer")
    outboundPeerIds.formUnion(["live-peer", "orphan-peer"])
    let orphanedPeerIds = SpatialRangingSessionOwnership
      .removeOrphanedOutboundPeerIds(
        activePeerIds: activePeerIds,
        pendingPeerIds: pendingPeerIds,
        outboundPeerIds: &outboundPeerIds
      )
    require(orphanedPeerIds == ["orphan-peer"], "orphan reconciliation removed the wrong owner")
    require(
      outboundPeerIds == ["live-peer"],
      "orphan reconciliation changed a live outbound owner"
    )
  }

  private static func requireForegroundPeersReceiveOpportunity(
    peerCount: Int,
    capacity: Int
  ) {
    struct ActivePeer {
      var startedAt: CFTimeInterval
    }

    var now: CFTimeInterval = 100
    var active: [Int: ActivePeer] = [:]
    var activePeerIds = Set<String>()
    var pendingPeerIds = Set<String>()
    var outboundPeerIds = Set<String>()
    var lastRangedAt: [Int: CFTimeInterval] = [:]
    var opportunities = Set<Int>()
    let maximumCycles = Int(ceil(Double(peerCount) / Double(capacity))) + 1

    for _ in 0..<maximumCycles {
      let candidates = (0..<peerCount).map { index in
        if let activePeer = active[index] {
          let peerId = "peer-\(index)"
          return makeCandidate(
            index,
            phase: .verified,
            isActive: true,
            isLocallyInitiated: outboundPeerIds.contains(peerId),
            isVerified: true,
            lastRangedAt: lastRangedAt[index],
            leaseStartedAt: activePeer.startedAt
          )
        }

        return makeCandidate(
          index,
          lastRangedAt: lastRangedAt[index]
        )
      }
      let plan = scheduler.plan(
        candidates: candidates,
        role: .foregroundProximity,
        now: now,
        sessionCapacity: capacity,
        outboundCapacity: capacity,
        outboundCount: outboundPeerIds.count,
        probeTimeout: probeTimeout,
        candidateLeaseDuration: candidateLeaseDuration,
        verifiedLeaseDuration: verifiedLeaseDuration
      )

      require(
        active.count - plan.releasePeerIds.count + plan.acquirePeerIds.count <= capacity,
        "foreground simulation exceeded its bounded working set"
      )
      for peerId in plan.releasePeerIds {
        guard let index = Int(peerId.dropFirst("peer-".count)) else {
          continue
        }
        _ = SpatialRangingSessionOwnership.removePeer(
          peerId,
          activePeerIds: &activePeerIds,
          pendingPeerIds: &pendingPeerIds,
          outboundPeerIds: &outboundPeerIds
        )
        active.removeValue(forKey: index)
        lastRangedAt[index] = now
      }
      for peerId in plan.acquirePeerIds {
        guard let index = Int(peerId.dropFirst("peer-".count)) else {
          continue
        }
        active[index] = ActivePeer(startedAt: now)
        activePeerIds.insert(peerId)
        outboundPeerIds.insert(peerId)
        opportunities.insert(index)
      }

      if opportunities.count == peerCount {
        break
      }
      now += SpatialRangingTuning.foregroundProximityLeaseDuration
    }

    require(
      opportunities.count == peerCount,
      "foreground ranging starved a peer in a larger attendee simulation"
    )
  }

  private static func testVerifiedInterestReleasesQuickly() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          cameraInterest: 0.02,
          lastCameraRelevantAt: 0
        ),
        makeCandidate(1, cameraInterest: 0.9),
      ],
      role: .cameraViewer,
      now: 0.8,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-0"], "irrelevant verified target held its UWB slot")
    require(plan.acquirePeerIds == ["peer-1"], "released verified slot was not reused")
  }

  private static func testSingleVerifiedPeerRemainsRangedWithoutReplacement() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(
          0,
          phase: .verified,
          isActive: true,
          isVerified: true,
          measurementFreshness: 0,
          cameraInterest: 0,
          leaseStartedAt: 0,
          lastCameraRelevantAt: 0
        )
      ],
      role: .cameraViewer,
      now: 12,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 1,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(
      plan.releasePeerIds.isEmpty,
      "the only verified peer was released without a replacement"
    )
    require(
      plan.acquirePeerIds.isEmpty,
      "the only verified peer was scheduled for a redundant reacquisition"
    )
  }

  private static func testCameraInterestOverridesWeakRSSI() {
    let plan = scheduler.plan(
      candidates: [
        makeCandidate(0, cameraInterest: 0.12, signalStrength: -48),
        makeCandidate(1, cameraInterest: 0.92, signalStrength: -96),
      ],
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.acquirePeerIds == ["peer-1"], "strong RSSI displaced the visually relevant peer")
  }

  private static func testCandidateEventuallyYields() {
    let candidates = [
      makeCandidate(
        0,
        phase: .candidate,
        isActive: true,
        cameraInterest: 0.2,
        leaseStartedAt: 0
      ),
      makeCandidate(1),
    ]
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 5,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.releasePeerIds == ["peer-0"], "stale candidate did not yield")
    require(plan.acquirePeerIds == ["peer-1"], "yielded candidate slot was not reused")
  }

  private static func testWaitingPeerFairness() {
    let candidates = [
      makeCandidate(0, lastRangedAt: 0),
      makeCandidate(1, lastRangedAt: 99),
    ]
    let plan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )

    require(plan.acquirePeerIds == ["peer-0"], "older waiting peer was starved")
  }

  private static func testRetryBackoffAndLearnedCapacity() {
    let candidates = [
      makeCandidate(0, retryAfter: 101),
      makeCandidate(1),
      makeCandidate(2),
    ]
    let blockedPlan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 3,
      outboundCapacity: 3,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )
    require(!blockedPlan.acquirePeerIds.contains("peer-0"), "retry backoff was ignored")

    let capacityLimitedPlan = scheduler.plan(
      candidates: candidates,
      role: .cameraViewer,
      now: 102,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: probeTimeout,
      candidateLeaseDuration: candidateLeaseDuration,
      verifiedLeaseDuration: verifiedLeaseDuration
    )
    require(capacityLimitedPlan.acquirePeerIds.count <= 1, "learned capacity was exceeded")
  }

  private static func testCapacityOneTwoAndThree() {
    for capacity in 1...3 {
      let plan = scheduler.plan(
        candidates: (0..<8).map { makeCandidate($0) },
        role: .cameraViewer,
        now: 100,
        sessionCapacity: capacity,
        outboundCapacity: capacity,
        outboundCount: 0,
        probeTimeout: probeTimeout,
        candidateLeaseDuration: candidateLeaseDuration,
        verifiedLeaseDuration: verifiedLeaseDuration
      )
      require(
        plan.acquirePeerIds.count == capacity,
        "capacity \(capacity) was not allocated exactly"
      )
    }
  }

  private static func testSingleEDMOwnerAndMigrationHysteresis() {
    let candidates = [
      makeCandidate(0, phase: .candidate, isActive: true, cameraInterest: 0.2),
      makeCandidate(1, phase: .candidate, isActive: true, cameraInterest: 0.8),
      makeCandidate(2, phase: .candidate, isActive: true, cameraInterest: 0.1),
    ]
    let initial = scheduler.selectEDMOwner(
      candidates: candidates,
      currentPeerId: nil,
      candidatePeerId: nil,
      candidateSince: nil,
      now: 100,
      minimumScoreDelta: 0.2,
      minimumDwell: 0.75
    )
    require(initial.shouldMigrate, "EDM did not select an initial owner")
    require(initial.bestPeerId == "peer-1", "EDM selected the wrong owner")
    require(Set([initial.bestPeerId].compactMap { $0 }).count == 1, "more than one EDM owner was selected")

    let waiting = scheduler.selectEDMOwner(
      candidates: candidates,
      currentPeerId: "peer-0",
      candidatePeerId: "peer-1",
      candidateSince: 100,
      now: 100.5,
      minimumScoreDelta: 0.2,
      minimumDwell: 0.75
    )
    require(!waiting.shouldMigrate, "EDM migrated before hysteresis dwell")

    let migrated = scheduler.selectEDMOwner(
      candidates: candidates,
      currentPeerId: "peer-0",
      candidatePeerId: "peer-1",
      candidateSince: 100,
      now: 100.8,
      minimumScoreDelta: 0.2,
      minimumDwell: 0.75
    )
    require(migrated.shouldMigrate, "EDM did not migrate after sustained advantage")
    require(migrated.bestPeerId == "peer-1", "EDM migrated to the wrong owner")
  }

  private static func testTwentyFourPeerProbeSimulation() {
    struct ActiveProbe {
      var phase: SpatialPeerRangingPhase
      var startedAt: CFTimeInterval
    }

    let targetIndex = 17
    var now: CFTimeInterval = 0
    var active: [Int: ActiveProbe] = [:]
    var lastRangedAt: [Int: CFTimeInterval] = [:]
    var probeOrder: [Int] = []
    var targetFirstProbeAt: CFTimeInterval?

    for _ in 0..<120 {
      let candidates = (0..<24).map { index in
        if let activeProbe = active[index] {
          return makeCandidate(
            index,
            phase: activeProbe.phase,
            isActive: true,
            isVerified: activeProbe.phase == .verified,
            hasUsefulMeasurement: activeProbe.phase != .probing,
            hasProjectableMeasurement: activeProbe.phase != .probing,
          cameraInterest: activeProbe.phase == .candidate ? 0.2 : 0,
            lastRangedAt: lastRangedAt[index],
            leaseStartedAt: activeProbe.startedAt
          )
        }

        return makeCandidate(
          index,
          phase: .unprobed,
          lastRangedAt: lastRangedAt[index]
        )
      }
      let plan = scheduler.plan(
        candidates: candidates,
        role: .cameraViewer,
        now: now,
        sessionCapacity: 3,
        outboundCapacity: 3,
        outboundCount: 0,
        probeTimeout: probeTimeout,
        candidateLeaseDuration: candidateLeaseDuration,
        verifiedLeaseDuration: verifiedLeaseDuration
      )

      for peerId in plan.releasePeerIds {
        guard let index = Int(peerId.dropFirst("peer-".count)) else {
          continue
        }
        active.removeValue(forKey: index)
        lastRangedAt[index] = now
      }
      for peerId in plan.acquirePeerIds {
        guard let index = Int(peerId.dropFirst("peer-".count)) else {
          continue
        }
        active[index] = ActiveProbe(phase: .probing, startedAt: now)
        probeOrder.append(index)
        if index == targetIndex, targetFirstProbeAt == nil {
          targetFirstProbeAt = now
        }
      }

      for (index, activeProbe) in Array(active) {
        guard activeProbe.phase == .probing else {
          continue
        }

        let isTarget = index == targetIndex
        let evaluation = scheduler.evaluateProbe(
          candidate: makeCandidate(
            index,
            phase: .probing,
            isActive: true,
            hasUsefulMeasurement: true,
            hasProjectableMeasurement: true,
            cameraInterest: isTarget ? 0.2 : 0.03,
            lastRangedAt: lastRangedAt[index],
            leaseStartedAt: activeProbe.startedAt
          ),
          promotionInterest: 0.18,
          evictionInterest: 0.14
        )
        switch evaluation.decision {
        case .promoteToCandidate:
          active[index]?.phase = .candidate
        case .evict:
          active.removeValue(forKey: index)
          lastRangedAt[index] = now
        case .wait:
          break
        }
      }

      if probeOrder.count >= 24 {
        break
      }
      now += 0.1
    }

    require(targetFirstProbeAt != nil, "late target was never probed")
    require(Set(probeOrder).count == 24, "fair simulation starved a presence peer")
    require(
      (targetFirstProbeAt ?? .greatestFiniteMagnitude) < 5,
      "target wait exceeded the deterministic probe budget"
    )
  }

  private static func makeCandidate(
    _ index: Int,
    phase: SpatialPeerRangingPhase = .unprobed,
    isActive: Bool = false,
    isPending: Bool = false,
    isLocallyInitiated: Bool? = nil,
    isVerified: Bool = false,
    isTentative: Bool = false,
    isNearVisibleBody: Bool = false,
    isNearCarryRegion: Bool = false,
    hasUsefulMeasurement: Bool = false,
    hasProjectableMeasurement: Bool = false,
    measurementFreshness: Double = 0,
    cameraInterest: Double = 0,
    signalStrength: Double? = nil,
    lastRangedAt: CFTimeInterval? = nil,
    leaseStartedAt: CFTimeInterval? = nil,
    firstUsefulMeasurementAt: CFTimeInterval? = nil,
    probeDeadlineAt: CFTimeInterval? = nil,
    retryAfter: CFTimeInterval = 0,
    distanceHealthState: SpatialRangingDistanceHealthState = .healthy,
    isDistanceHealthy: Bool = true,
    cameraInterestAge: CFTimeInterval = .greatestFiniteMagnitude,
    lastCameraRelevantAt: CFTimeInterval? = nil,
    expectedInformationGain: Double = 0
  ) -> SpatialRangingCandidate {
    SpatialRangingCandidate(
      peerId: "peer-\(index)",
      phase: phase,
      isActive: isActive,
      isPending: isPending,
      isLocallyInitiated: isLocallyInitiated ?? (isActive || isPending),
      isEligible: !isActive && !isPending,
      isVerified: isVerified,
      isTentative: isTentative,
      isNearVisibleBody: isNearVisibleBody,
      isNearCarryRegion: isNearCarryRegion,
      hasUsefulMeasurement: hasUsefulMeasurement,
      hasDistanceOnlyMeasurement: hasUsefulMeasurement && !hasProjectableMeasurement,
      hasProjectableMeasurement: hasProjectableMeasurement,
      measurementFreshness: measurementFreshness,
      cameraInterest: cameraInterest,
      cameraInterestAge: cameraInterestAge,
      lastCameraRelevantAt: lastCameraRelevantAt,
      signalStrength: signalStrength,
      lastRangedAt: lastRangedAt,
      leaseStartedAt: leaseStartedAt,
      probeStartedAt: leaseStartedAt,
      firstMeasurementAt: firstUsefulMeasurementAt,
      firstDistanceAt: hasUsefulMeasurement ? firstUsefulMeasurementAt : nil,
      firstProjectableMeasurementAt: hasProjectableMeasurement
        ? firstUsefulMeasurementAt
        : nil,
      probeDeadlineAt: probeDeadlineAt ?? leaseStartedAt.map {
        $0 + SpatialRangingTuning.probeHardDeadline
      },
      firstUsefulMeasurementAt: firstUsefulMeasurementAt,
      expectedInformationGain: expectedInformationGain,
      retryAfter: retryAfter,
      distanceHealthState: distanceHealthState,
      isDistanceHealthy: isDistanceHealthy,
      isDistanceDegraded: distanceHealthState == .degraded
    )
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fputs("SpatialRangingSchedulerHarness: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
