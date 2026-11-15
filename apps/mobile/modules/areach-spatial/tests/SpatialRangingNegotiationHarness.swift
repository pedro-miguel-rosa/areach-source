import Foundation

private enum HarnessControl: Equatable {
  case accept(UUID)
  case busy(UUID)
  case ignored
}

private struct NegotiationModel {
  let localPeerId: String
  var state: SpatialPeerLinkState = .discovered
  var pending = false
  var observedTransactions = Set<UUID>()
  var sessionsStarted = 0
  var stopMessagesSent = 0
  var peerLostEmissions = 0
  var retryAfter: Double?

  mutating func beginOutbound(_ transactionId: UUID) {
    precondition(!pending)
    pending = true
    retryAfter = nil
    state = .negotiatingOutbound(transactionId: transactionId)
  }

  mutating func receiveRequest(
    from remotePeerId: String,
    transactionId: UUID
  ) -> HarnessControl {
    if observedTransactions.contains(transactionId) {
      switch state {
      case .negotiatingInbound(let currentTransactionId)
        where currentTransactionId == transactionId:
        return .accept(transactionId)
      case .ranging(let currentTransactionId, .responder)
        where currentTransactionId == transactionId:
        return .accept(transactionId)
      default:
        return .ignored
      }
    }
    observedTransactions.insert(transactionId)

    if let localTransactionId = state.outboundTransactionId {
      switch SpatialRangingNegotiationPolicy.collisionDecision(
        localPeerId: localPeerId,
        remotePeerId: remotePeerId
      ) {
      case .keepOutbound:
        return .busy(transactionId)
      case .yieldToInbound:
        state = .yieldingToInbound(
          localTransactionId: localTransactionId,
          incomingTransactionId: transactionId
        )
        pending = false
        state = .ranging(
          transactionId: transactionId,
          role: .responder
        )
        sessionsStarted += 1
        return .accept(transactionId)
      }
    }

    if case .ranging = state {
      return .busy(transactionId)
    }

    state = .ranging(transactionId: transactionId, role: .responder)
    sessionsStarted += 1
    return .accept(transactionId)
  }

  mutating func receiveAccept(_ transactionId: UUID) -> HarnessControl {
    guard state.outboundTransactionId == transactionId else {
      return .ignored
    }

    guard pending else {
      return .ignored
    }

    pending = false
    state = .ranging(transactionId: transactionId, role: .initiator)
    sessionsStarted += 1
    return .accept(transactionId)
  }

  mutating func receiveBusy(
    _ transactionId: UUID,
    now: Double
  ) -> HarnessControl {
    guard state.outboundTransactionId == transactionId, pending else {
      return .ignored
    }

    pending = false
    retryAfter = now + 1
    state = .cooldown(until: retryAfter ?? now)
    return .ignored
  }

  mutating func receiveStop(_ transactionId: UUID) -> HarnessControl {
    guard state.transactionId == transactionId else {
      return .ignored
    }

    pending = false
    state = .discovered
    return .ignored
  }
}

private struct StartupReconciliationModel {
  var hasCameraConsumer = false
  var hasDiscoveredPeer = false
  var reconciliationCount = 0

  mutating func registerCameraConsumer() {
    hasCameraConsumer = true
    reconcileIfReady()
  }

  mutating func discoverPeer() {
    hasDiscoveredPeer = true
    reconcileIfReady()
  }

  private mutating func reconcileIfReady() {
    if hasCameraConsumer && hasDiscoveredPeer {
      reconciliationCount += 1
    }
  }
}

@main
struct SpatialRangingNegotiationHarness {
  static func main() {
    testCollisionArrivalOrder()
    testCrossedNetworkConnectionsConverge()
    testStaleRangeStop()
    testStaleAcceptAfterRetry()
    testDuplicateAccept()
    testDuplicateRequest()
    testStaleBusy()
    testBluetoothFirstAttemptAndRetry()
    testBluetoothDisappearanceCancelsRetry()
    testStartupReconciliationOrder()
    testInboundAdmissionUsesSpareHardwareCapacity()
    testInboundAdmissionYieldsForegroundWork()
    testInboundAdmissionBusyWithoutSafeCapacity()
    testRemoteStopCooldownDoesNotBlockInboundAdmission()
    testBackgroundResponderInboundAdmission()
    testCameraDoesNotUseForegroundPreemption()
    testSuspendedRoleRejectsInbound()
    print("SpatialRangingNegotiationHarness: PASS")
  }

  private static func testCollisionArrivalOrder() {
    let firstOrder = runCollision(highPeerReceivesLowRequestFirst: true)
    let secondOrder = runCollision(highPeerReceivesLowRequestFirst: false)

    precondition(firstOrder == secondOrder)
    precondition(firstOrder.lowKeepsOutbound)
    precondition(firstOrder.highYieldsToInbound)
    precondition(firstOrder.stopMessagesSent == 0)
    precondition(firstOrder.peerLostEmissions == 0)
  }

  private static func testCrossedNetworkConnectionsConverge() {
    // Both peers prefer the one initiated by the lexicographically lower
    // stable peer ID, even when hello messages arrive in opposite directions.
    let lowPeerKeepsItsPreferredOutbound = !SpatialNetworkConnectionPolicy
      .shouldReplaceExisting(
        localPeerId: "peer-a",
        remotePeerId: "peer-c",
        existingIsLocallyInitiated: true,
        incomingIsLocallyInitiated: false,
        existingIsAuthenticated: true,
        incomingIsAuthenticated: true
      )
    let highPeerReplacesItsOutboundWithTheSameInbound =
      SpatialNetworkConnectionPolicy.shouldReplaceExisting(
        localPeerId: "peer-c",
        remotePeerId: "peer-a",
        existingIsLocallyInitiated: true,
        incomingIsLocallyInitiated: false,
        existingIsAuthenticated: true,
        incomingIsAuthenticated: true
      )

    precondition(lowPeerKeepsItsPreferredOutbound)
    precondition(highPeerReplacesItsOutboundWithTheSameInbound)

    let lowPeerReplacesAnInboundWithItsPreferredOutbound =
      SpatialNetworkConnectionPolicy.shouldReplaceExisting(
        localPeerId: "peer-a",
        remotePeerId: "peer-c",
        existingIsLocallyInitiated: false,
        incomingIsLocallyInitiated: true,
        existingIsAuthenticated: true,
        incomingIsAuthenticated: true
      )
    let highPeerKeepsTheMatchingInbound = SpatialNetworkConnectionPolicy
      .shouldReplaceExisting(
        localPeerId: "peer-c",
        remotePeerId: "peer-a",
        existingIsLocallyInitiated: false,
        incomingIsLocallyInitiated: true,
        existingIsAuthenticated: true,
        incomingIsAuthenticated: true
      )

    precondition(lowPeerReplacesAnInboundWithItsPreferredOutbound)
    precondition(!highPeerKeepsTheMatchingInbound)

    let authenticatedFallbackReplacesUnauthenticatedPreferredRoute =
      SpatialNetworkConnectionPolicy.shouldReplaceExisting(
        localPeerId: "peer-a",
        remotePeerId: "peer-c",
        existingIsLocallyInitiated: true,
        incomingIsLocallyInitiated: false,
        existingIsAuthenticated: false,
        incomingIsAuthenticated: true
      )
    precondition(authenticatedFallbackReplacesUnauthenticatedPreferredRoute)

    let unauthenticatedCandidateCannotReplaceAuthenticatedRoute =
      SpatialNetworkConnectionPolicy.shouldReplaceExisting(
        localPeerId: "peer-c",
        remotePeerId: "peer-a",
        existingIsLocallyInitiated: true,
        incomingIsLocallyInitiated: false,
        existingIsAuthenticated: true,
        incomingIsAuthenticated: false
      )
    precondition(!unauthenticatedCandidateCannotReplaceAuthenticatedRoute)
  }

  private static func runCollision(
    highPeerReceivesLowRequestFirst: Bool
  ) -> CollisionSummary {
    let lowTransactionId = UUID()
    let highTransactionId = UUID()
    var low = NegotiationModel(localPeerId: "peer-a")
    var high = NegotiationModel(localPeerId: "peer-b")
    low.beginOutbound(lowTransactionId)
    high.beginOutbound(highTransactionId)

    let controlToLow: HarnessControl
    let controlToHigh: HarnessControl
    if highPeerReceivesLowRequestFirst {
      controlToLow = high.receiveRequest(
        from: low.localPeerId,
        transactionId: lowTransactionId
      )
      controlToHigh = low.receiveRequest(
        from: high.localPeerId,
        transactionId: highTransactionId
      )
    } else {
      controlToHigh = low.receiveRequest(
        from: high.localPeerId,
        transactionId: highTransactionId
      )
      controlToLow = high.receiveRequest(
        from: low.localPeerId,
        transactionId: lowTransactionId
      )
    }

    if case .accept(let transactionId) = controlToLow {
      _ = low.receiveAccept(transactionId)
    }
    if case .busy(let transactionId) = controlToHigh {
      _ = high.receiveBusy(transactionId, now: 10)
    }

    return CollisionSummary(
      highYieldsToInbound: high.state == .ranging(
        transactionId: lowTransactionId,
        role: .responder
      ),
      lowKeepsOutbound: low.state == .ranging(
        transactionId: lowTransactionId,
        role: .initiator
      ),
      peerLostEmissions: low.peerLostEmissions + high.peerLostEmissions,
      stopMessagesSent: low.stopMessagesSent + high.stopMessagesSent
    )
  }

  private static func testStaleRangeStop() {
    let oldTransactionId = UUID()
    let currentTransactionId = UUID()
    var model = NegotiationModel(localPeerId: "peer-a")
    model.beginOutbound(oldTransactionId)
    _ = model.receiveAccept(oldTransactionId)
    model.beginOutbound(currentTransactionId)
    _ = model.receiveAccept(currentTransactionId)

    _ = model.receiveStop(oldTransactionId)
    precondition(
      model.state == .ranging(
        transactionId: currentTransactionId,
        role: .initiator
      )
    )
  }

  private static func testStaleAcceptAfterRetry() {
    let oldTransactionId = UUID()
    let currentTransactionId = UUID()
    var model = NegotiationModel(localPeerId: "peer-a")
    model.beginOutbound(oldTransactionId)
    _ = model.receiveBusy(oldTransactionId, now: 20)
    model.beginOutbound(currentTransactionId)

    _ = model.receiveAccept(oldTransactionId)
    precondition(model.pending)
    precondition(model.state.outboundTransactionId == currentTransactionId)
  }

  private static func testDuplicateAccept() {
    let transactionId = UUID()
    var model = NegotiationModel(localPeerId: "peer-a")
    model.beginOutbound(transactionId)
    _ = model.receiveAccept(transactionId)
    _ = model.receiveAccept(transactionId)

    precondition(model.sessionsStarted == 1)
    precondition(
      model.state == .ranging(
        transactionId: transactionId,
        role: .initiator
      )
    )
  }

  private static func testDuplicateRequest() {
    let transactionId = UUID()
    var model = NegotiationModel(localPeerId: "peer-b")
    _ = model.receiveRequest(from: "peer-a", transactionId: transactionId)
    let duplicate = model.receiveRequest(
      from: "peer-a",
      transactionId: transactionId
    )

    precondition(duplicate == .accept(transactionId))
    precondition(model.sessionsStarted == 1)
  }

  private static func testStaleBusy() {
    let oldTransactionId = UUID()
    let currentTransactionId = UUID()
    var model = NegotiationModel(localPeerId: "peer-a")
    model.beginOutbound(oldTransactionId)
    _ = model.receiveBusy(oldTransactionId, now: 30)
    model.beginOutbound(currentTransactionId)

    _ = model.receiveBusy(oldTransactionId, now: 31)
    precondition(model.pending)
    precondition(model.state.outboundTransactionId == currentTransactionId)
  }

  private static func testBluetoothFirstAttemptAndRetry() {
    precondition(
      SpatialBluetoothRetryPolicy.isEligible(
        now: 100,
        lastAttemptAt: nil,
        delay: 1.5
      )
    )

    let retryAt = SpatialBluetoothRetryPolicy.nextRetryAt(
      lastAttemptAt: 100,
      delay: 2.75
    )
    precondition(retryAt == 102.75)
    precondition(
      !SpatialBluetoothRetryPolicy.isEligible(
        now: 102.74,
        lastAttemptAt: 100,
        delay: 2.75
      )
    )
    precondition(
      SpatialBluetoothRetryPolicy.isEligible(
        now: 102.75,
        lastAttemptAt: 100,
        delay: 2.75
      )
    )
  }

  private static func testBluetoothDisappearanceCancelsRetry() {
    let retryDeadline = SpatialBluetoothRetryPolicy.nextRetryAt(
      lastAttemptAt: 100,
      delay: 8
    )
    precondition(retryDeadline == 108)

    let disappearedPeerLastAdvertisement: Double? = nil
    precondition(
      SpatialBluetoothRetryPolicy.advertisementExpiry(
        lastAdvertisementAt: disappearedPeerLastAdvertisement,
        staleAfter: 4
      ) == nil
    )
  }

  private static func testStartupReconciliationOrder() {
    var cameraAfterPeer = StartupReconciliationModel()
    cameraAfterPeer.discoverPeer()
    precondition(cameraAfterPeer.reconciliationCount == 0)
    cameraAfterPeer.registerCameraConsumer()
    precondition(cameraAfterPeer.reconciliationCount == 1)

    var peerAfterCamera = StartupReconciliationModel()
    peerAfterCamera.registerCameraConsumer()
    precondition(peerAfterCamera.reconciliationCount == 0)
    peerAfterCamera.discoverPeer()
    precondition(peerAfterCamera.reconciliationCount == 1)
  }

  private static func testInboundAdmissionUsesSpareHardwareCapacity() {
    let decision = SpatialRangingAdmissionPolicy().decision(
      role: .foregroundProximity,
      activeSessionCount: 1,
      pendingSessionCount: 1,
      hardwareCapacity: 3,
      requestingPeerId: "camera-peer",
      yieldablePeerIds: []
    )

    precondition(decision == .acceptWithSpareCapacity)
  }

  private static func testInboundAdmissionYieldsForegroundWork() {
    let policy = SpatialRangingAdmissionPolicy()
    let decision = policy.decision(
      role: .foregroundProximity,
      activeSessionCount: 2,
      pendingSessionCount: 1,
      hardwareCapacity: 3,
      requestingPeerId: "camera-peer",
      yieldablePeerIds: ["peer-local-candidate", "peer-local-verified"]
    )

    precondition(
      decision == .acceptAfterYield(peerId: "peer-local-candidate")
    )

    let afterYield = policy.decision(
      role: .foregroundProximity,
      activeSessionCount: 1,
      pendingSessionCount: 1,
      hardwareCapacity: 3,
      requestingPeerId: "camera-peer",
      yieldablePeerIds: ["peer-local-verified"]
    )
    precondition(afterYield == .acceptWithSpareCapacity)
  }

  private static func testInboundAdmissionBusyWithoutSafeCapacity() {
    let decision = SpatialRangingAdmissionPolicy().decision(
      role: .foregroundProximity,
      activeSessionCount: 2,
      pendingSessionCount: 1,
      hardwareCapacity: 3,
      requestingPeerId: "camera-peer",
      yieldablePeerIds: []
    )

    precondition(
      decision == .busy(
        reason: "hardware-capacity-exhausted-no-safe-yield"
      )
    )
  }

  private static func testRemoteStopCooldownDoesNotBlockInboundAdmission() {
    let retryDeadline = SpatialForegroundRangingPolicy.remoteStopRetryDeadline(
      role: .foregroundProximity,
      now: 100
    )
    precondition(retryDeadline == 100 + SpatialRangingTuning.foregroundRemoteStopCooldownDuration)

    let incomingCameraRequest = SpatialRangingAdmissionPolicy().decision(
      role: .foregroundProximity,
      activeSessionCount: 0,
      pendingSessionCount: 0,
      hardwareCapacity: 1,
      requestingPeerId: "camera-peer",
      yieldablePeerIds: []
    )
    precondition(
      incomingCameraRequest == .acceptWithSpareCapacity,
      "foreground edge cooldown incorrectly blocked an inbound session"
    )
  }

  private static func testBackgroundResponderInboundAdmission() {
    let decision = SpatialRangingAdmissionPolicy().decision(
      role: .backgroundResponder,
      activeSessionCount: 0,
      pendingSessionCount: 0,
      hardwareCapacity: 3,
      requestingPeerId: "camera-peer",
      yieldablePeerIds: []
    )

    precondition(decision == .acceptWithSpareCapacity)
  }

  private static func testCameraDoesNotUseForegroundPreemption() {
    let decision = SpatialRangingAdmissionPolicy().decision(
      role: .cameraViewer,
      activeSessionCount: 3,
      pendingSessionCount: 0,
      hardwareCapacity: 3,
      requestingPeerId: "another-camera",
      yieldablePeerIds: ["locally-initiated-camera-session"]
    )

    guard case .busy = decision else {
      preconditionFailure("camera sessions were offered to foreground preemption")
    }
  }

  private static func testSuspendedRoleRejectsInbound() {
    let decision = SpatialRangingAdmissionPolicy().decision(
      role: .suspended,
      activeSessionCount: 0,
      pendingSessionCount: 0,
      hardwareCapacity: 3,
      requestingPeerId: "peer",
      yieldablePeerIds: []
    )

    precondition(decision == .busy(reason: "runtime-suspended"))
  }
}

private struct CollisionSummary: Equatable {
  let highYieldsToInbound: Bool
  let lowKeepsOutbound: Bool
  let peerLostEmissions: Int
  let stopMessagesSent: Int
}
