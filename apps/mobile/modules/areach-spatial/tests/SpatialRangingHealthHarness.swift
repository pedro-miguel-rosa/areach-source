import Foundation
import simd

/// Deterministic coverage for NI liveness, render freshness, adaptive sensor
/// filters, and scheduler health separation. This harness deliberately uses
/// only pure policy/filter types; it proves state transitions and safety gates,
/// not Nearby Interaction or camera behavior on physical devices.
@main
struct SpatialRangingHealthHarness {
  private static let scheduler = SpatialRangingScheduler()

  static func main() {
    testContinuousUsefulMeasurementsStayHealthy()
    testUselessCallbacksRefreshOnlyCallbackClock()
    testDirectionOnlyDoesNotKeepForegroundDistanceHealthy()
    testTransformOnlyDoesNotKeepForegroundDistanceHealthy()
    testDistanceOnlyKeepsForegroundDistanceHealthy()
    testOneRecentScalarSampleCountsAsLiveDistance()
    testDirectionAndTransformCanStaySpatiallyHealthyWhileDistanceDegrades()
    testCameraSpatialHealthCanRemainUsefulWhileDistanceDegrades()
    testCameraDistanceStallTriggersBoundedRecovery()
    testMissingForegroundDistanceTriggersRecovery()
    testPersistentMissingDistanceTriggersHardRecovery()
    testDistanceStallRecoveryContinuesWithoutTransport()
    testDistanceRecoveryReturnsDistanceHealthToHealthy()
    testDistanceRecoveryResetsFailureBackoff()
    testDistanceStallCannotRemainForeverWhileDirectionContinues()
    testDistanceStallCannotRemainForeverAfterTransportDisappears()
    testRangeBusyUsesContentionRetry()
    testContentionRetryDoesNotAccumulateHardRecoveryBackoff()
    testTransportUnavailableUsesBoundedRetry()
    testNegotiationFailureUsesBoundedExponentialBackoff()
    testDistanceOnlyMeasurementIsUseful()
    testTransformOnlyMeasurementIsUseful()
    testAllUsefulMeasurementsStoppingTriggersBoundedRecovery()
    testSoftRecoveryRequiresUsefulConfirmations()
    testBackgroundResponderRemainsPassive()
    testHardRecoveryUsesBoundedBackoff()
    testOldTransactionsAreRejectedAfterReplacement()
    testRemovalReasonsChooseBoundedRecovery()
    testInvalidationAlwaysUsesFreshSessionPath()
    testStalledVerifiedPeerIsReleasableAndPrioritized()
    testHealthyVerifiedPeerRemainsSticky()
    testARTrackingRecoveryKeepsHealthyVerifiedPeerSticky()
    testRenderMarkerRequiresFreshTransform()
    testStationaryWorldJitterIsSmoothed()
    testFastWorldMovementTracksResponsively()
    testWorldDiscontinuityAndGapReset()
    testDistanceOutlierIsRejected()
    testMovingDistanceRespondsQuickly()
    testDistanceGapResetsDisplayState()
    print("SpatialRangingHealthHarness: PASS")
  }

  private static func testContinuousUsefulMeasurementsStayHealthy() {
    let health = healthyHealth()
    let evaluation = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 0.8,
      transportNearby: true
    )

    require(health.state == .healthy, "useful samples did not reach healthy")
    require(health.isMeasurementHealthy(at: 0.8, role: .cameraViewer), "healthy sample stream was not healthy")
    require(evaluation.action == .wait, "healthy sample stream triggered recovery")
  }

  private static func testUselessCallbacksRefreshOnlyCallbackClock() {
    var health = healthyHealth()
    health.softRecoveryAttempts = 1
    health.hardRecoveryAttempts = 2
    let previousUsefulAt = health.lastUsefulMeasurementAt
    let previousDistanceAt = health.lastDistanceAt
    let previousTransformAt = health.lastTransformAt

    let didRecordUseful = health.recordDelegateCallback(
      at: 0.4,
      hasDistance: false,
      hasTransform: false,
      healthyConfirmationCount: 3
    )

    require(!didRecordUseful, "an empty callback was counted as useful")
    require(health.lastDelegateCallbackAt == 0.4, "callback clock did not advance")
    require(health.lastUsefulMeasurementAt == previousUsefulAt, "empty callback refreshed useful clock")
    require(health.lastDistanceAt == previousDistanceAt, "empty callback refreshed distance clock")
    require(health.lastTransformAt == previousTransformAt, "empty callback refreshed transform clock")
    require(health.softRecoveryAttempts == 1, "empty callback reset soft recovery attempts")
    require(health.hardRecoveryAttempts == 2, "empty callback reset hard recovery attempts")

    let evaluation = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 1.6,
      transportNearby: true
    )
    require(evaluation.action == .markDegraded, "empty callback stream did not degrade")
  }

  private static func testDirectionOnlyDoesNotKeepForegroundDistanceHealthy() {
    let health = spatiallyHealthyWithoutDistance()
    let evaluation = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
        .degradedDistanceMeasurementAge,
      transportNearby: true
    )

    require(health.state == .healthy, "direction-only stream was not spatially healthy")
    require(!health.isDistanceMeasurementHealthy(at: 4, role: .foregroundProximity), "direction-only samples counted as healthy distance")
    require(evaluation.action == .markDegraded, "direction-only samples masked foreground distance loss")
  }

  private static func testTransformOnlyDoesNotKeepForegroundDistanceHealthy() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    for time in [0.1, 0.2, 0.3] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: false,
        hasTransform: true,
        healthyConfirmationCount: 3,
        hasDirection: false,
        distanceHealthyConfirmationCount: 2
      )
    }

    let evaluation = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
        .degradedDistanceMeasurementAge,
      transportNearby: true
    )
    require(health.state == .healthy, "transform-only stream was not spatially healthy")
    require(evaluation.action == .markDegraded, "transform-only samples masked foreground distance loss")
  }

  private static func testDistanceOnlyKeepsForegroundDistanceHealthy() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    for time in [0.1, 0.2, 0.3] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: true,
        hasTransform: false,
        healthyConfirmationCount: 3,
        distanceHealthyConfirmationCount: 2
      )
    }

    require(health.state == .healthy, "distance-only samples were not spatially healthy")
    require(health.distanceState == .healthy, "distance-only samples did not restore distance health")
    require(health.isDistanceMeasurementHealthy(at: 0.4, role: .foregroundProximity), "fresh finite distance was not healthy")
  }

  private static func testOneRecentScalarSampleCountsAsLiveDistance() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    _ = health.recordDelegateCallback(
      at: 0.1,
      hasDistance: true,
      hasTransform: false,
      healthyConfirmationCount: 3,
      distanceHealthyConfirmationCount: 2
    )

    require(health.isDistanceMeasurementHealthy(at: 0.2, role: .foregroundProximity), "one recent positive distance was not considered live")
    let evaluation = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: 0.2,
      transportNearby: true
    )
    require(evaluation.action == .wait, "a fresh distance sample triggered recovery")
  }

  private static func testDirectionAndTransformCanStaySpatiallyHealthyWhileDistanceDegrades() {
    let health = spatiallyHealthyWithoutDistance()
    let spatialEvaluation = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .foregroundProximity,
      now: 4,
      transportNearby: true
    )
    let distanceEvaluation = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
        .degradedDistanceMeasurementAge,
      transportNearby: true
    )

    require(spatialEvaluation.action == .wait, "fresh spatial measurements were incorrectly declared NI-dead")
    require(distanceEvaluation.action == .markDegraded, "distance health did not degrade independently")
  }

  private static func testCameraSpatialHealthCanRemainUsefulWhileDistanceDegrades() {
    let health = spatiallyHealthyWithoutDistance()
    let spatial = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 4,
      transportNearby: true
    )
    let distance = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .cameraViewer,
      now: 4,
      transportNearby: true
    )

    require(spatial.action == .wait, "Camera lost useful spatial health when distance alone was missing")
    require(distance.action == .markDegraded, "Camera distance did not degrade independently")
  }

  private static func testCameraDistanceStallTriggersBoundedRecovery() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    var firstHardRecoveryAt: CFTimeInterval?
    var hardRecoveryCount = 0

    for step in 1...150 {
      let now = Double(step) * 0.1
      _ = health.recordDelegateCallback(
        at: now,
        hasDistance: false,
        hasTransform: true,
        healthyConfirmationCount: 3,
        hasDirection: true,
        distanceHealthyConfirmationCount: 2
      )

      let spatialEvaluation = SpatialRangingHealthPolicy.evaluate(
        health: health,
        role: .cameraViewer,
        now: now,
        transportNearby: true
      )
      require(spatialEvaluation.action == .wait, "Camera lost spatial health while direction/transform remained fresh")

      let distanceEvaluation = SpatialRangingHealthPolicy.evaluateDistance(
        health: health,
        role: .cameraViewer,
        now: now,
        transportNearby: true
      )
      switch distanceEvaluation.action {
      case .wait:
        break
      case .markDegraded:
        health.distanceState = .degraded
        health.lastDistanceLostAt = now
      case .startSoftRecovery:
        health.distanceState = .softRecovering
        health.distanceSoftRecoveryAttempts += 1
        health.distanceRecoveryStartedAt = now
        health.distanceLastSoftRecoveryAt = now
      case .startHardRecovery:
        firstHardRecoveryAt = firstHardRecoveryAt ?? now
        hardRecoveryCount += 1
        health.distanceState = .renegotiating
        health.distanceHardRecoveryAttempts += 1
        health.distanceRecoveryStartedAt = now
        health.distanceLastHardRecoveryAt = now
      }
    }

    let timing = SpatialRangingHealthPolicy.timing(for: .cameraViewer)
    require(firstHardRecoveryAt != nil, "Camera direction/transform masked distance loss indefinitely")
    require(
      (firstHardRecoveryAt ?? 0) <= timing.degradedDistanceMeasurementAge
        + timing.distanceSoftRecoveryTimeout + 0.2,
      "Camera distance recovery exceeded its bounded first-attempt deadline"
    )
    require(hardRecoveryCount >= 2, "Camera stayed in a distance-stalled fresh transaction without a bounded retry")
    require(health.state == .healthy, "Camera distance loss incorrectly erased fresh spatial health")
  }

  private static func testMissingForegroundDistanceTriggersRecovery() {
    var health = spatiallyHealthyWithoutDistance()
    let now = SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
      .degradedDistanceMeasurementAge
    let degraded = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: now,
      transportNearby: true
    )
    require(degraded.action == .markDegraded, "missing distance did not enter degraded state")

    health.distanceState = .degraded
    health.lastDistanceLostAt = now
    let recovery = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: now + 0.1,
      transportNearby: true
    )
    require(recovery.action == .startSoftRecovery, "degraded distance skipped soft recovery")
  }

  private static func testPersistentMissingDistanceTriggersHardRecovery() {
    var health = spatiallyHealthyWithoutDistance()
    let timing = SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
    health.distanceState = .softRecovering
    health.distanceSoftRecoveryAttempts = 1
    health.distanceRecoveryStartedAt = 10
    health.distanceLastSoftRecoveryAt = 10

    let evaluation = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: 10 + timing.distanceSoftRecoveryTimeout,
      transportNearby: true
    )
    require(evaluation.action == .startHardRecovery, "persistent missing distance avoided fresh negotiation")
  }

  private static func testDistanceStallRecoveryContinuesWithoutTransport() {
    var health = spatiallyHealthyWithoutDistance()
    let timing = SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
    let degradedAt: CFTimeInterval = 4
    health.distanceState = .degraded
    health.lastDistanceLostAt = degradedAt

    let softRecovery = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: degradedAt + 0.1,
      transportNearby: false
    )
    require(
      softRecovery.action == .startSoftRecovery,
      "missing transport blocked local distance recovery"
    )

    health.distanceState = .softRecovering
    health.distanceSoftRecoveryAttempts = 1
    health.distanceRecoveryStartedAt = degradedAt + 0.1
    health.distanceLastSoftRecoveryAt = degradedAt + 0.1
    let hardRecoveryAt = degradedAt + 0.1 + timing.distanceSoftRecoveryTimeout
    let hardRecovery = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: hardRecoveryAt,
      transportNearby: false
    )
    require(
      hardRecovery.action == .startHardRecovery,
      "distance hard recovery waited forever for transport to return"
    )

    health.distanceState = .renegotiating
    health.distanceHardRecoveryAttempts = 1
    health.distanceRecoveryStartedAt = hardRecoveryAt
    health.distanceLastHardRecoveryAt = hardRecoveryAt
    let retryAt = hardRecoveryAt + max(
      timing.distanceHardRecoveryTimeout,
      timing.distanceMinimumHardRecoveryInterval
    ) + 0.1
    let retry = SpatialRangingHealthPolicy.evaluateDistance(
      health: health,
      role: .foregroundProximity,
      now: retryAt,
      transportNearby: false
    )
    require(
      retry.action == .startHardRecovery,
      "fresh ranging retry remained blocked while transport was unavailable"
    )
  }

  private static func testDistanceRecoveryReturnsDistanceHealthToHealthy() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    health.distanceState = .softRecovering
    health.distanceSoftRecoveryAttempts = 1
    health.distanceHardRecoveryAttempts = 2
    health.distanceRecoveryStartedAt = 1
    for time in [1.1, 1.2] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: true,
        hasTransform: false,
        healthyConfirmationCount: 3,
        distanceHealthyConfirmationCount: 2
      )
    }

    require(health.distanceState == .healthy, "fresh distance did not restore distance health")
    require(health.distanceSoftRecoveryAttempts == 0, "distance recovery retained soft attempts")
    require(health.distanceHardRecoveryAttempts == 0, "distance recovery retained hard attempts")
  }

  private static func testDistanceRecoveryResetsFailureBackoff() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0, state: .renegotiating)
    health.distanceState = .renegotiating
    health.distanceSoftRecoveryAttempts = 1
    health.distanceHardRecoveryAttempts = 3
    health.rangingFailureAttempts = 4
    for time in [0.1, 0.2] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: true,
        hasTransform: true,
        healthyConfirmationCount: 2,
        distanceHealthyConfirmationCount: 2
      )
    }

    require(health.distanceHardRecoveryAttempts == 0, "successful distance did not reset hard-recovery backoff")
    require(health.distanceSoftRecoveryAttempts == 0, "successful distance did not reset soft-recovery attempts")
    require(health.rangingFailureAttempts == 0, "successful spatial measurements retained negotiation-failure backoff")
  }

  private static func testDistanceStallCannotRemainForeverWhileDirectionContinues() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    var firstHardRecoveryAt: CFTimeInterval?
    var hardRecoveryCount = 0

    for step in 1...250 {
      let now = Double(step) * 0.1
      _ = health.recordDelegateCallback(
        at: now,
        hasDistance: false,
        hasTransform: true,
        healthyConfirmationCount: 3,
        hasDirection: true,
        distanceHealthyConfirmationCount: 2
      )
      let spatial = SpatialRangingHealthPolicy.evaluate(
        health: health,
        role: .foregroundProximity,
        now: now,
        transportNearby: true
      )
      require(spatial.action == .wait, "fresh direction/transform stopped being spatially healthy")

      let evaluation = SpatialRangingHealthPolicy.evaluateDistance(
        health: health,
        role: .foregroundProximity,
        now: now,
        transportNearby: true
      )
      switch evaluation.action {
      case .wait:
        break
      case .markDegraded:
        health.distanceState = .degraded
        health.lastDistanceLostAt = now
      case .startSoftRecovery:
        health.distanceState = .softRecovering
        health.distanceSoftRecoveryAttempts += 1
        health.distanceRecoveryStartedAt = now
        health.distanceLastSoftRecoveryAt = now
      case .startHardRecovery:
        firstHardRecoveryAt = firstHardRecoveryAt ?? now
        hardRecoveryCount += 1
        health.distanceState = .renegotiating
        health.distanceHardRecoveryAttempts += 1
        health.distanceRecoveryStartedAt = now
        health.distanceLastHardRecoveryAt = now
      }
    }

    let timing = SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
    require(firstHardRecoveryAt != nil, "continuous direction masked distance loss indefinitely")
    require(
      (firstHardRecoveryAt ?? 0) <= timing.degradedDistanceMeasurementAge
        + timing.distanceSoftRecoveryTimeout + 0.2,
      "distance hard recovery exceeded its bounded first-attempt deadline"
    )
    require(hardRecoveryCount >= 2, "distance remained in a fresh transaction without a bounded retry")
    require(health.state == .healthy, "distance-only failure incorrectly erased spatial health")
  }

  private static func testDistanceStallCannotRemainForeverAfterTransportDisappears() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    var firstHardRecoveryAt: CFTimeInterval?
    var hardRecoveryCount = 0

    for step in 1...300 {
      let now = Double(step) * 0.1
      _ = health.recordDelegateCallback(
        at: now,
        hasDistance: false,
        hasTransform: true,
        healthyConfirmationCount: 3,
        hasDirection: true,
        distanceHealthyConfirmationCount: 2
      )

      let spatial = SpatialRangingHealthPolicy.evaluate(
        health: health,
        role: .foregroundProximity,
        now: now,
        transportNearby: false
      )
      require(spatial.action == .wait, "transport loss erased useful spatial health")

      let evaluation = SpatialRangingHealthPolicy.evaluateDistance(
        health: health,
        role: .foregroundProximity,
        now: now,
        transportNearby: false
      )
      switch evaluation.action {
      case .wait:
        break
      case .markDegraded:
        health.distanceState = .degraded
        health.lastDistanceLostAt = now
      case .startSoftRecovery:
        health.distanceState = .softRecovering
        health.distanceSoftRecoveryAttempts += 1
        health.distanceRecoveryStartedAt = now
        health.distanceLastSoftRecoveryAt = now
      case .startHardRecovery:
        firstHardRecoveryAt = firstHardRecoveryAt ?? now
        hardRecoveryCount += 1
        health.distanceState = .renegotiating
        health.distanceHardRecoveryAttempts += 1
        health.distanceRecoveryStartedAt = now
        health.distanceLastHardRecoveryAt = now
      }
    }

    let timing = SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
    require(firstHardRecoveryAt != nil, "missing transport blocked distance hard recovery")
    require(
      (firstHardRecoveryAt ?? 0) <= timing.degradedDistanceMeasurementAge
        + timing.distanceSoftRecoveryTimeout + 0.2,
      "missing transport delayed first hard recovery beyond the distance deadline"
    )
    require(
      hardRecoveryCount >= 2,
      "missing transport prevented bounded fresh-transaction retries"
    )
    require(health.state == .healthy, "transport loss incorrectly erased spatial health")
  }

  private static func testRangeBusyUsesContentionRetry() {
    require(SpatialRangingRetryPolicy.kind(for: "busy") == .contention, "rangeBusy was not classified as contention")
    require(SpatialRangingRetryPolicy.kind(for: "simultaneous-initiation-collision") == .contention, "collision was not classified as contention")
    let decision = SpatialRangingRetryPolicy.decision(
      for: .contention,
      consecutiveFailureCount: 8,
      deterministicJitter: 0.8
    )

    require(!decision.incrementsFailureCount, "rangeBusy counted as a ranging failure")
    require(decision.delay >= SpatialRangingTuning.contentionRetryBaseDelay, "contention retry was too aggressive")
    require(
      decision.delay <= SpatialRangingTuning.contentionRetryBaseDelay
        + SpatialRangingTuning.contentionRetryMaximumJitter,
      "rangeBusy inherited long hard-recovery backoff"
    )
  }

  private static func testContentionRetryDoesNotAccumulateHardRecoveryBackoff() {
    var health = SpatialRangingHealth()
    health.hardRecoveryAttempts = 4
    health.distanceHardRecoveryAttempts = 3
    health.rangingFailureAttempts = 2
    let decision = SpatialRangingRetryPolicy.decision(
      for: .contention,
      consecutiveFailureCount: health.rangingFailureAttempts,
      deterministicJitter: 0.4
    )

    require(!decision.incrementsFailureCount, "normal contention accumulated failure count")
    require(health.hardRecoveryAttempts == 4, "contention changed hard NI failure history")
    require(health.distanceHardRecoveryAttempts == 3, "contention changed distance failure history")
    require(health.rangingFailureAttempts == 2, "contention incremented negotiation-failure history")
    require(decision.delay < SpatialRangingHealthPolicy.timing(for: .foregroundProximity)
      .minimumHardRecoveryInterval, "contention used hard-recovery backoff")
  }

  private static func testTransportUnavailableUsesBoundedRetry() {
    require(SpatialRangingRetryPolicy.kind(for: "transport-unavailable") == .transportUnavailable, "transport loss used negotiation-failure policy")
    require(SpatialRangingRetryPolicy.kind(for: "ranging-request-timeout") == .transportUnavailable, "ranging request timeout used genuine-failure backoff")
    let decision = SpatialRangingRetryPolicy.decision(
      for: .transportUnavailable,
      consecutiveFailureCount: 6,
      deterministicJitter: 0.9
    )

    require(!decision.incrementsFailureCount, "temporary transport loss accumulated hard failure count")
    require(decision.delay >= SpatialRangingTuning.transportRetryBaseDelay, "transport retry skipped bounded refresh window")
    require(decision.delay <= SpatialRangingTuning.transportRetryBaseDelay
      + SpatialRangingTuning.transportRetryMaximumJitter, "transport retry delay was not bounded")
  }

  private static func testNegotiationFailureUsesBoundedExponentialBackoff() {
    require(SpatialRangingRetryPolicy.kind(for: "invalid-accept") == .negotiationFailure, "invalid negotiation was not classified as a failure")
    let first = SpatialRangingRetryPolicy.decision(
      for: .negotiationFailure,
      consecutiveFailureCount: 1,
      deterministicJitter: 0
    )
    let repeated = SpatialRangingRetryPolicy.decision(
      for: .negotiationFailure,
      consecutiveFailureCount: 4,
      deterministicJitter: 0
    )

    require(first.incrementsFailureCount, "genuine negotiation failure was treated as contention")
    require(repeated.delay > first.delay, "repeated negotiation failure did not back off")
    require(repeated.delay <= SpatialRangingTuning.maximumRetryDelay, "failure backoff exceeded its configured cap")
  }

  private static func testDistanceOnlyMeasurementIsUseful() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    for time in [0.1, 0.2, 0.3] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: true,
        hasTransform: false,
        healthyConfirmationCount: 3
      )
    }

    require(health.state == .healthy, "distance-only samples were not useful")
    require(health.lastDistanceAt == 0.3, "distance clock was not recorded")
    require(health.lastTransformAt == nil, "distance-only sample invented a transform clock")
  }

  private static func testTransformOnlyMeasurementIsUseful() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    for time in [0.1, 0.2, 0.3] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: false,
        hasTransform: true,
        healthyConfirmationCount: 3
      )
    }

    require(health.state == .healthy, "transform-only samples were not useful")
    require(health.lastTransformAt == 0.3, "transform clock was not recorded")
    require(health.lastDistanceAt == nil, "transform-only sample invented a distance clock")
  }

  private static func testAllUsefulMeasurementsStoppingTriggersBoundedRecovery() {
    var health = healthyHealth()
    let degraded = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 1.6,
      transportNearby: true
    )
    require(degraded.action == .markDegraded, "stalled healthy session did not degrade")

    health.state = .degraded
    health.lastUsefulMeasurementLostAt = 1.6
    let soft = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 1.6,
      transportNearby: true
    )
    require(soft.action == .startSoftRecovery, "degraded session skipped soft recovery")

    health.state = .softRecovering
    health.softRecoveryAttempts = 1
    health.recoveryStartedAt = 1.6
    let waiting = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 3.0,
      transportNearby: true
    )
    require(waiting.action == .wait, "soft recovery was not bounded by its window")

    let hard = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 3.5,
      transportNearby: true
    )
    require(hard.action == .startHardRecovery, "failed soft recovery did not require renegotiation")
  }

  private static func testSoftRecoveryRequiresUsefulConfirmations() {
    var health = healthyHealth()
    health.state = .softRecovering
    health.lastUsefulMeasurementAt = nil
    health.consecutiveUsefulUpdates = 0
    health.softRecoveryAttempts = 1
    health.hardRecoveryAttempts = 2
    health.recoveryStartedAt = 1
    health.lastSoftRecoveryAt = 1

    _ = health.recordDelegateCallback(
      at: 1.1,
      hasDistance: false,
      hasTransform: true,
      healthyConfirmationCount: 3
    )
    _ = health.recordDelegateCallback(
      at: 1.2,
      hasDistance: false,
      hasTransform: true,
      healthyConfirmationCount: 3
    )
    require(health.state == .softRecovering, "one or two recovery samples confirmed too early")

    _ = health.recordDelegateCallback(
      at: 1.3,
      hasDistance: false,
      hasTransform: true,
      healthyConfirmationCount: 3
    )
    require(health.state == .healthy, "useful recovery samples did not restore health")
    require(health.softRecoveryAttempts == 0, "soft attempts were not reset after recovery")
    require(health.hardRecoveryAttempts == 0, "hard attempts were not reset after recovery")
  }

  private static func testBackgroundResponderRemainsPassive() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0, state: .degraded)
    health.recoveryStartedAt = 0
    let evaluation = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .backgroundResponder,
      now: 10,
      transportNearby: true
    )

    require(evaluation.action == .wait, "background responder attempted proactive recovery")
    require(evaluation.reason == "background-responder-passive-recovery", "background responder used the wrong policy")
  }

  private static func testHardRecoveryUsesBoundedBackoff() {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0, state: .renegotiating)
    health.hardRecoveryAttempts = 2
    health.recoveryStartedAt = 0
    health.lastHardRecoveryAt = 6

    let inBackoff = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 8,
      transportNearby: true
    )
    require(inBackoff.action == .wait, "hard recovery backoff was ignored")
    require(inBackoff.reason == "hard-recovery-backoff", "hard recovery returned the wrong backoff reason")

    let ready = SpatialRangingHealthPolicy.evaluate(
      health: health,
      role: .cameraViewer,
      now: 12,
      transportNearby: true
    )
    require(ready.action == .startHardRecovery, "bounded hard recovery never became eligible")
  }

  private static func testOldTransactionsAreRejectedAfterReplacement() {
    let oldTransaction = UUID()
    let freshTransaction = UUID()

    let freshDisposition = SpatialRangingNegotiationPolicy.disposition(
      incomingTransactionId: freshTransaction,
      expectedTransactionId: freshTransaction,
      observedTransactionIds: []
    )
    require(freshDisposition == .accept, "fresh transaction was not accepted")

    for controlName in ["stop", "accept", "busy"] {
      let oldDisposition = SpatialRangingNegotiationPolicy.disposition(
        incomingTransactionId: oldTransaction,
        expectedTransactionId: freshTransaction,
        observedTransactionIds: []
      )
      require(oldDisposition != .accept, "old \(controlName) was accepted after replacement")
    }

    let duplicateDisposition = SpatialRangingNegotiationPolicy.disposition(
      incomingTransactionId: freshTransaction,
      expectedTransactionId: freshTransaction,
      observedTransactionIds: [freshTransaction]
    )
    require(duplicateDisposition == .duplicate, "fresh transaction duplicate was not idempotent")
  }

  private static func testRemovalReasonsChooseBoundedRecovery() {
    require(
      SpatialRangingFailurePolicy.removalAction(for: .timeout)
        == .softRecovery,
      "timeout did not choose bounded soft recovery"
    )
    require(
      SpatialRangingFailurePolicy.removalAction(for: .unknown)
        == .softRecovery,
      "unknown removal did not choose conservative soft recovery"
    )
    require(
      SpatialRangingFailurePolicy.removalAction(for: .peerEnded)
        == .freshNegotiation,
      "peer-ended removal reused the stale NI session path"
    )
  }

  private static func testInvalidationAlwaysUsesFreshSessionPath() {
    require(
      SpatialRangingFailurePolicy.invalidationDisposition(
        isActive: true,
        isPending: false,
        isAlreadyRenegotiating: false
      ) == .activeHardRecovery,
      "active invalidation skipped hard recovery"
    )
    require(
      SpatialRangingFailurePolicy.invalidationDisposition(
        isActive: true,
        isPending: false,
        isAlreadyRenegotiating: true
      ) == .activeFreshRetry,
      "renegotiating invalidation did not request a fresh retry"
    )
    require(
      SpatialRangingFailurePolicy.invalidationDisposition(
        isActive: false,
        isPending: true,
        isAlreadyRenegotiating: false
      ) == .pendingFreshRetry,
      "pending invalidation did not request a fresh retry"
    )
    require(
      SpatialRangingFailurePolicy.invalidationDisposition(
        isActive: false,
        isPending: false,
        isAlreadyRenegotiating: false
      ) == .discard,
      "orphan invalidation kept a dead session authoritative"
    )
  }

  private static func testStalledVerifiedPeerIsReleasableAndPrioritized() {
    let healthy = makeCandidate(
      "healthy",
      phase: .verified,
      isActive: true,
      isVerified: true,
      hasUsefulMeasurement: true,
      hasProjectableMeasurement: true,
      measurementFreshness: 1,
      cameraInterest: 0.4,
      healthState: .healthy,
      isMeasurementHealthy: true,
      leaseStartedAt: 99,
      lastCameraRelevantAt: 99
    )
    let stalled = makeCandidate(
      "stalled",
      phase: .verified,
      isActive: true,
      isVerified: true,
      hasUsefulMeasurement: false,
      hasProjectableMeasurement: false,
      measurementFreshness: 0,
      cameraInterest: 0.4,
      healthState: .degraded,
      isMeasurementHealthy: false,
      isMeasurementDegraded: true,
      leaseStartedAt: 99,
      lastCameraRelevantAt: 99
    )
    let waiting = makeCandidate(
      "waiting",
      phase: .unprobed,
      isEligible: true,
      isVerified: false,
      hasUsefulMeasurement: false,
      expectedInformationGain: 1
    )

    let plan = scheduler.plan(
      candidates: [healthy, stalled, waiting],
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 2,
      outboundCapacity: 2,
      outboundCount: 0,
      probeTimeout: 1.5,
      candidateLeaseDuration: 4.5,
      verifiedLeaseDuration: 8
    )

    require(plan.releasePeerIds == ["stalled"], "stalled verified peer consumed a sticky slot")
    require(plan.acquirePeerIds == ["waiting"], "scheduler did not refill the recovered slot")
    require(
      scheduler.priority(for: stalled, now: 100) > scheduler.priority(for: healthy, now: 100),
      "degraded verified peer was not prioritized for recovery"
    )
  }

  private static func testHealthyVerifiedPeerRemainsSticky() {
    let healthy = makeCandidate(
      "healthy",
      phase: .verified,
      isActive: true,
      isVerified: true,
      hasUsefulMeasurement: true,
      hasProjectableMeasurement: true,
      measurementFreshness: 1,
      cameraInterest: 0.4,
      healthState: .healthy,
      isMeasurementHealthy: true,
      leaseStartedAt: 99,
      lastCameraRelevantAt: 99
    )
    let waiting = makeCandidate(
      "candidate",
      phase: .candidate,
      isEligible: true,
      isVerified: false,
      hasUsefulMeasurement: false,
      expectedInformationGain: 1
    )

    let plan = scheduler.plan(
      candidates: [healthy, waiting],
      role: .cameraViewer,
      now: 100,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: 1.5,
      candidateLeaseDuration: 4.5,
      verifiedLeaseDuration: 8
    )

    require(plan.releasePeerIds.isEmpty, "healthy verified peer was rotated unnecessarily")
    require(plan.acquirePeerIds.isEmpty, "healthy verified peer did not keep its slot")
  }

  private static func testARTrackingRecoveryKeepsHealthyVerifiedPeerSticky() {
    let recoveringCamera = makeCandidate(
      "camera-recovering",
      phase: .verified,
      isActive: true,
      isVerified: true,
      hasUsefulMeasurement: true,
      hasDistanceOnlyMeasurement: true,
      measurementFreshness: 0.8,
      cameraInterest: 0,
      healthState: .healthy,
      isMeasurementHealthy: true,
      cameraAssistanceRecovering: true,
      leaseStartedAt: 0,
      lastCameraRelevantAt: 0
    )

    let plan = scheduler.plan(
      candidates: [recoveringCamera],
      role: .cameraViewer,
      now: 30,
      sessionCapacity: 1,
      outboundCapacity: 1,
      outboundCount: 0,
      probeTimeout: 1.5,
      candidateLeaseDuration: 4.5,
      verifiedLeaseDuration: 8
    )

    require(
      plan.releasePeerIds.isEmpty,
      "AR recovery released a healthy distance session"
    )
  }

  private static func testRenderMarkerRequiresFreshTransform() {
    require(
      SpatialRenderFreshnessPolicy.canRenderSolidPhoneMarker(
        worldTransformAvailable: true,
        transformAge: 0.4
      ),
      "fresh transform was rejected for rendering"
    )
    require(
      !SpatialRenderFreshnessPolicy.canRenderSolidPhoneMarker(
        worldTransformAvailable: false,
        transformAge: 0.1
      ),
      "missing transform rendered as a solid marker"
    )
    require(
      !SpatialRenderFreshnessPolicy.canRenderSolidPhoneMarker(
        worldTransformAvailable: true,
        transformAge: 0.56
      ),
      "stale transform rendered as a solid marker"
    )
    require(
      !SpatialRenderFreshnessPolicy.canRenderSolidPhoneMarker(
        worldTransformAvailable: true,
        transformAge: .greatestFiniteMagnitude
      ),
      "unbounded transform age rendered as a solid marker"
    )
  }

  private static func testStationaryWorldJitterIsSmoothed() {
    let rawPositions: [Float] = [0, 0.08, -0.06, 0.04, -0.03, 0.02]
    var filter = SpatialWorldPositionFilter()
    let displayPositions = rawPositions.enumerated().map { index, position in
      filter.filter(
        transform(at: position),
        at: Double(index) * 0.1
      ).columns.3.x
    }
    let rawRange = (rawPositions.max() ?? 0) - (rawPositions.min() ?? 0)
    let displayRange = (displayPositions.max() ?? 0) - (displayPositions.min() ?? 0)
    require(displayRange < rawRange * 0.85, "stationary world jitter was not smoothed")
  }

  private static func testFastWorldMovementTracksResponsively() {
    let rawPositions: [Float] = [0, 0.08, 0.2, 0.38, 0.6, 0.85, 1.1]
    var filter = SpatialWorldPositionFilter()
    let displayPositions = rawPositions.enumerated().map { index, position in
      filter.filter(
        transform(at: position),
        at: Double(index) * 0.1
      ).columns.3.x
    }
    let finalPosition = displayPositions.last ?? 0
    require(finalPosition > 0.85, "fast world movement lagged excessively")
    require(
      zip(displayPositions, displayPositions.dropFirst()).allSatisfy {
        first, second in first < second
      },
      "responsive world movement was not monotonic"
    )
  }

  private static func testWorldDiscontinuityAndGapReset() {
    var discontinuityFilter = SpatialWorldPositionFilter()
    _ = discontinuityFilter.filter(transform(at: 0), at: 0)
    _ = discontinuityFilter.filter(transform(at: 0.1), at: 0.1)
    let discontinuity = discontinuityFilter.filter(transform(at: 2), at: 0.2)
    require(abs(discontinuity.columns.3.x - 2) < 0.0001, "large world discontinuity chased the old position")

    var gapFilter = SpatialWorldPositionFilter()
    _ = gapFilter.filter(transform(at: 0), at: 0)
    _ = gapFilter.filter(transform(at: 0.1), at: 0.1)
    let gap = gapFilter.filter(transform(at: 1.5), at: 1.0)
    require(abs(gap.columns.3.x - 1.5) < 0.0001, "world measurement gap retained stale filter state")
  }

  private static func testDistanceOutlierIsRejected() {
    var filter = SpatialDistanceDisplayFilter()
    _ = filter.update(2.0, at: 0)
    _ = filter.update(2.02, at: 0.1)
    _ = filter.update(1.98, at: 0.2)
    let result = filter.update(8, at: 0.3)

    require(result.distance < 2.5, "single distance outlier jumped the display")
    require(result.sampleCount == 4, "distance sample history was not retained")
    require(result.uncertainty.isFinite && result.uncertainty > 0, "distance uncertainty was invalid")
  }

  private static func testMovingDistanceRespondsQuickly() {
    var filter = SpatialDistanceDisplayFilter()
    _ = filter.update(1, at: 0)
    _ = filter.update(1.5, at: 0.1)
    let result = filter.update(2, at: 0.2)
    require(result.distance > 1.7, "moving distance display lagged excessively")
  }

  private static func testDistanceGapResetsDisplayState() {
    var filter = SpatialDistanceDisplayFilter()
    _ = filter.update(1, at: 0)
    _ = filter.update(1.1, at: 0.1)
    let result = filter.update(4, at: 2)
    require(abs(result.distance - 4) < 0.0001, "distance gap retained the old display estimate")
    require(result.sampleCount == 1, "distance gap did not reset the sample window")
  }

  private static func healthyHealth() -> SpatialRangingHealth {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    for time in [0.1, 0.2, 0.3] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: true,
        hasTransform: true,
        healthyConfirmationCount: 3
      )
    }
    return health
  }

  private static func spatiallyHealthyWithoutDistance() -> SpatialRangingHealth {
    var health = SpatialRangingHealth()
    health.beginTransaction(at: 0)
    for time in [0.1, 0.2, 0.3, 1.0, 2.0, 3.0, 3.7, 3.8, 3.9] {
      _ = health.recordDelegateCallback(
        at: time,
        hasDistance: false,
        hasTransform: true,
        healthyConfirmationCount: 3,
        hasDirection: true,
        distanceHealthyConfirmationCount: 2
      )
    }
    return health
  }

  private static func makeCandidate(
    _ peerId: String,
    phase: SpatialPeerRangingPhase,
    isActive: Bool = false,
    isPending: Bool = false,
    isEligible: Bool = false,
    isVerified: Bool = false,
    isNearVisibleBody: Bool = false,
    isNearCarryRegion: Bool = false,
    hasUsefulMeasurement: Bool = false,
    hasDistanceOnlyMeasurement: Bool = false,
    hasProjectableMeasurement: Bool = false,
    measurementFreshness: Double = 0,
    cameraInterest: Double = 0,
    healthState: SpatialRangingHealthState = .healthy,
    isMeasurementHealthy: Bool = true,
    isMeasurementDegraded: Bool = false,
    isRecovering: Bool = false,
    cameraAssistanceRecovering: Bool = false,
    leaseStartedAt: CFTimeInterval? = nil,
    lastCameraRelevantAt: CFTimeInterval? = nil,
    expectedInformationGain: Double = 0
  ) -> SpatialRangingCandidate {
    SpatialRangingCandidate(
      peerId: peerId,
      phase: phase,
      isActive: isActive,
      isPending: isPending,
      isEligible: isEligible,
      isVerified: isVerified,
      isTentative: phase == .candidate,
      isNearVisibleBody: isNearVisibleBody,
      isNearCarryRegion: isNearCarryRegion,
      hasUsefulMeasurement: hasUsefulMeasurement,
      hasDistanceOnlyMeasurement: hasDistanceOnlyMeasurement,
      hasProjectableMeasurement: hasProjectableMeasurement,
      measurementFreshness: measurementFreshness,
      cameraInterest: cameraInterest,
      cameraInterestAge: lastCameraRelevantAt.map { max(0, 100 - $0) }
        ?? .greatestFiniteMagnitude,
      lastCameraRelevantAt: lastCameraRelevantAt,
      signalStrength: nil,
      lastRangedAt: isActive ? 90 : nil,
      leaseStartedAt: leaseStartedAt,
      probeStartedAt: nil,
      firstMeasurementAt: nil,
      firstDistanceAt: nil,
      firstProjectableMeasurementAt: nil,
      probeDeadlineAt: nil,
      firstUsefulMeasurementAt: nil,
      expectedInformationGain: expectedInformationGain,
      retryAfter: 0,
      healthState: healthState,
      lastUsefulMeasurementAt: nil,
      usefulMeasurementAge: hasUsefulMeasurement ? 0 : .greatestFiniteMagnitude,
      isMeasurementHealthy: isMeasurementHealthy,
      isMeasurementDegraded: isMeasurementDegraded,
      isRecovering: isRecovering,
      cameraAssistanceRecovering: cameraAssistanceRecovering
    )
  }

  private static func transform(at x: Float) -> simd_float4x4 {
    var result = matrix_identity_float4x4
    result.columns.3 = SIMD4<Float>(x, 0, 0, 1)
    return result
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fail(message)
    }
  }

  private static func fail(_ message: String) -> Never {
    fputs("SpatialRangingHealthHarness: FAIL: \(message)\n", stderr)
    exit(1)
  }
}
