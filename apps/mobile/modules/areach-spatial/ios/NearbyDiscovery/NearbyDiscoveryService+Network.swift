import CryptoKit
import Foundation
import NearbyInteraction
import Network
import Security

struct NearbyNetworkMessage: Codable {
  enum Kind: String, Codable {
    case hello
    case proof
    case rangeAccept
    case rangeBusy
    case rangeRequest
    case rangeStop

    var isRangingControl: Bool {
      switch self {
      case .rangeAccept, .rangeBusy, .rangeRequest, .rangeStop:
        return true
      case .hello, .proof:
        return false
      }
    }
  }

  let credential: String?
  let challenge: String?
  let discoveryToken: Data?
  let eventScope: String?
  let kind: Kind
  let peerId: String
  let signature: Data?
  let transactionId: UUID?

  init(
    kind: Kind,
    peerId: String,
    challenge: String? = nil,
    credential: String? = nil,
    discoveryToken: Data? = nil,
    eventScope: String? = nil,
    signature: Data? = nil,
    transactionId: UUID? = nil
  ) {
    self.challenge = challenge
    self.credential = credential
    self.discoveryToken = discoveryToken
    self.eventScope = eventScope
    self.kind = kind
    self.peerId = peerId
    self.signature = signature
    self.transactionId = transactionId
  }
}

struct NearbyConnectionChallenge {
  let local: String
  let isLocallyInitiated: Bool
  var remote: String?
}

private enum NearbyNetworkTuning {
  /// A three-phone mesh can briefly have both directions of a connection in
  /// flight before deterministic duplicate resolution converges. This limit
  /// is for control transports only; NI session capacity remains separate.
  static let maximumConcurrentConnections = 6
}

extension NearbyDiscoveryService {
  private static var maximumMessageLength: Int { 64 * 1024 }
  private static var credentialChunkLength: Int { 180 }

  func startNetworkDiscovery() throws {
    guard let localIdentity else {
      return
    }

    let listener = try NWListener(using: makeConnectionParameters())
    listener.newConnectionLimit = NearbyNetworkTuning.maximumConcurrentConnections
    listener.service = advertisedService(for: localIdentity)
    listener.newConnectionHandler = { [weak self] connection in
      self?.withStateQueue {
        self?.startConnection(connection, expectedPeerId: nil)
      }
    }
    listener.stateUpdateHandler = { [weak self] state in
      self?.withStateQueue {
        self?.handleListenerState(state)
      }
    }
    listener.serviceRegistrationUpdateHandler = { [weak self] change in
      self?.withStateQueue {
        self?.signpostServiceRegistration(change)
      }
    }
    self.listener = listener
    listener.start(queue: stateQueue)

    startBonjourBrowser()
  }

  private func startBonjourBrowser() {
    guard localIdentity != nil else {
      return
    }

    let browserParameters = NWParameters.tcp
    browserParameters.includePeerToPeer = true

    let browser = NWBrowser(
      for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
      using: browserParameters
    )
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      self?.withStateQueue {
        self?.updateDiscoveredPeers(results)
      }
    }
    browser.stateUpdateHandler = { [weak self] state in
      self?.withStateQueue {
        self?.handleBrowserState(state)
      }
    }
    self.browser = browser
    browser.start(queue: stateQueue)
  }

  /// Restarts browsing without closing the listener or authenticated peer
  /// connections. Ranging recovery can encounter a silent/stale browser even
  /// while the listener remains ready, so rebuilding both transports would
  /// unnecessarily drop every attendee link.
  func refreshBonjourDiscoveryForRanging(
    at now: CFTimeInterval,
    reason: String
  ) {
    withStateQueue {
      guard
        isAppActive,
        localIdentity != nil,
        now.isFinite,
        now - lastRangingBonjourRefreshAt
          >= SpatialRangingTuning.rangingBonjourRefreshInterval
      else {
        return
      }

      lastRangingBonjourRefreshAt = now
      browser?.browseResultsChangedHandler = nil
      browser?.stateUpdateHandler = nil
      browser?.cancel()
      browser = nil
      browserReady = false
      startBonjourBrowser()
      SpatialPerformance.signposter.emitEvent(
        "Ranging Bonjour discovery refreshed",
        "Reason: \(reason, privacy: .public)"
      )
    }
  }

  func refreshNetworkDiscoveryAfterBluetoothWake() {
    withStateQueue {
      guard !expireDiscoveryIfNeeded() else {
        return
      }

      guard localIdentity != nil else {
        return
      }

      // Foreground browsing is already active. The BLE write exists to
      // wake a suspended attendee and refresh its Bonjour endpoint.
      guard !isAppActive || listener == nil || browser == nil else {
        return
      }

      let now = CACurrentMediaTime()

      guard now - lastBluetoothNetworkRefreshAt >= 8 else {
        return
      }

      lastBluetoothNetworkRefreshAt = now

      stopNetworkDiscovery()

      do {
        try startNetworkDiscovery()
        startRangingScheduler()
        maintainRangingPool()
        SpatialPerformance.signposter.emitEvent(
          "Nearby discovery woken by Bluetooth"
        )
      } catch {
        emitState(
          "waiting",
          message: "Nearby discovery is reconnecting. \(error.localizedDescription)"
        )
      }
    }
  }

  func stopNetworkDiscovery(cancelRestart: Bool = true) {
    if cancelRestart {
      networkRestartWorkItem?.cancel()
      networkRestartWorkItem = nil
      networkRestartAttempts = 0
    }

    browser?.stateUpdateHandler = nil
    browser?.cancel()
    browser = nil

    listener?.stateUpdateHandler = nil
    listener?.serviceRegistrationUpdateHandler = nil
    listener?.cancel()
    listener = nil

    let activeConnections = Array(connections.values)
    connections.removeAll()
    connectionPeerIds.removeAll()
    discoveredEndpoints.removeAll()
    receivingConnections.removeAll()
    authenticatedConnections.removeAll()
    connectionChallenges.removeAll()
    pendingConnectionProofs.removeAll()
    sentProofConnections.removeAll()
    browserReady = false
    listenerReady = false
    lastSignpostedDiscoveredCount = nil

    for connection in activeConnections {
      connection.stateUpdateHandler = nil
      connection.cancel()
    }
  }

  func updateAdvertisedIdentity() {
    guard let localIdentity, listener != nil else {
      return
    }

    listener?.service = advertisedService(for: localIdentity)
  }

  private func updateDiscoveredPeers(_ results: Set<NWBrowser.Result>) {
    guard let eventScope = localIdentity?.eventScope else {
      return
    }

    var visiblePeerIds = Set<String>()

    for result in results {
      guard
        case .bonjour(let txtRecord) = result.metadata,
        txtRecord["eventScope"] == eventScope,
        let peerId = txtRecord["peerId"],
        let credential = credential(from: txtRecord),
        !peerId.isEmpty,
        !credential.isEmpty,
        peerId != localPeerId
      else {
        continue
      }

      visiblePeerIds.insert(peerId)
      cancelPeerEviction(for: peerId)
      discoveredEndpoints[peerId] = result.endpoint
      markPeerTransportPresence(for: peerId)

      let previousIdentity = peerIdentities[peerId]
      peerIdentities[peerId] = NearbyPeerIdentity(
        credential: credential,
        eventScope: eventScope,
        publicKey: previousIdentity?.publicKey,
        userId: previousIdentity?.credential == credential
          ? previousIdentity?.userId
        : nil
      )
      markPeerDiscoveredIfNeeded(peerId, reason: "bonjour-discovered")

      if previousIdentity?.credential != credential {
        peerCredentialLastEmittedAt.removeValue(forKey: peerId)
        emitCredentialDiscovered(for: peerId)
      }
    }

    if !visiblePeerIds.isEmpty, !didSignpostFirstTransportDiscovery {
      didSignpostFirstTransportDiscovery = true
      let latencyMilliseconds = discoveryStartedAt.map {
        Int((CACurrentMediaTime() - $0) * 1_000)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "First transport discovery",
        "Latency milliseconds: \(latencyMilliseconds), peers: \(visiblePeerIds.count)"
      )
    }

    if !visiblePeerIds.isEmpty, !didSignpostFirstBonjourDiscovery {
      didSignpostFirstBonjourDiscovery = true
      let latencyMilliseconds = discoveryStartedAt.map {
        Int((CACurrentMediaTime() - $0) * 1_000)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "First Bonjour discovery",
        "Latency milliseconds: \(latencyMilliseconds), peers: \(visiblePeerIds.count)"
      )
    }

    for peerId in Array(discoveredEndpoints.keys) where !visiblePeerIds.contains(peerId) {
      discoveredEndpoints.removeValue(forKey: peerId)

      if connections[peerId] == nil {
        schedulePeerEviction(
          for: peerId,
          reason: "not-discovered"
        )
      }
    }

    if lastSignpostedDiscoveredCount != visiblePeerIds.count {
      lastSignpostedDiscoveredCount = visiblePeerIds.count
      SpatialPerformance.signposter.emitEvent(
        "Nearby peers discovered",
        "Count: \(visiblePeerIds.count)"
      )
    }

    // Discovery results are a prerequisite transition, not a reason to wait
    // for a periodic credential refresh before the scheduler reconciles.
    ensureDiscoveryTransport()
  }

  func connect(to endpoint: NWEndpoint, peerId: String) {
    let connection = NWConnection(
      to: endpoint,
      using: makeConnectionParameters()
    )
    startConnection(connection, expectedPeerId: peerId)
  }

  private func startConnection(
    _ connection: NWConnection,
    expectedPeerId: String?
  ) {
    guard connectionChallenges.count < NearbyNetworkTuning.maximumConcurrentConnections else {
      SpatialPerformance.signposter.emitEvent(
        "Nearby network connection bounded",
        "Limit: \(NearbyNetworkTuning.maximumConcurrentConnections)"
      )
      connection.cancel()
      return
    }

    let connectionId = ObjectIdentifier(connection)
    connectionChallenges[connectionId] = NearbyConnectionChallenge(
      local: randomChallenge(),
      isLocallyInitiated: expectedPeerId != nil,
      remote: nil
    )
    if let expectedPeerId {
      connectionPeerIds[connectionId] = expectedPeerId
      if connections[expectedPeerId] == nil {
        connections[expectedPeerId] = connection
      } else {
        // Keep the existing route until this candidate proves the remote
        // identity. Duplicate election must never let an unauthenticated
        // hello displace an authenticated peer connection.
        SpatialPerformance.signposter.emitEvent(
          "Nearby network duplicate connection pending authentication",
          "Peer: \(expectedPeerId.prefix(8), privacy: .public), candidate: local-outbound"
        )
      }
    }

    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else {
        return
      }

      self.withStateQueue {
        switch state {
        case .ready:
          SpatialPerformance.signposter.emitEvent(
            "Nearby network connection established"
          )
          self.sendHello(on: connection)
          self.receiveNextMessage(on: connection)
        case .failed(let error):
          self.connectionEnded(
            connection,
            reason: error.debugDescription
          )
        case .waiting:
          self.stateQueue.asyncAfter(deadline: .now() + 3) {
            [weak self, weak connection] in
            guard
              let self,
              let connection,
              case .waiting = connection.state
            else {
              return
            }

            self.connectionEnded(connection, reason: "network-unavailable")
          }
        case .cancelled:
          self.connectionEnded(connection, reason: "cancelled")
        default:
          break
        }
      }
    }
    connection.start(queue: stateQueue)
  }

  func sendHello(on connection: NWConnection) {
    let connectionId = ObjectIdentifier(connection)

    guard
      let localIdentity,
      let challenge = connectionChallenges[connectionId]?.local
    else {
      return
    }

    send(
      NearbyNetworkMessage(
        kind: .hello,
        peerId: localPeerId,
        challenge: challenge,
        credential: localIdentity.credential,
        eventScope: localIdentity.eventScope
      ),
      on: connection
    )
  }

  func sendRangingMessage(
    _ kind: NearbyNetworkMessage.Kind,
    to peerId: String,
    discoveryToken: Data? = nil,
    transactionId: UUID? = nil
  ) {
    if let connection = connections[peerId],
      case .ready = connection.state
    {
      send(
        NearbyNetworkMessage(
          kind: kind,
          peerId: localPeerId,
          discoveryToken: discoveryToken,
          signature: nil,
          transactionId: transactionId
        ),
        on: connection
      )
      return
    }

    if bluetoothWakeService?.send(
      kind,
      to: peerId,
      discoveryToken: discoveryToken,
      transactionId: transactionId
    ) == true {
      return
    }
  }

  private func send(
    _ message: NearbyNetworkMessage,
    on connection: NWConnection
  ) {
    do {
      let payload = try JSONEncoder().encode(message)

      guard payload.count <= Self.maximumMessageLength else {
        throw NearbyNetworkError.messageTooLarge
      }

      let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
      let context = NWConnection.ContentContext(
        identifier: "nearby-message",
        metadata: [metadata]
      )

      connection.send(
        content: payload,
        contentContext: context,
        isComplete: true,
        completion: .contentProcessed { [weak self, weak connection] error in
          guard let self, let connection, let error else {
            return
          }

          self.withStateQueue {
            self.connectionEnded(
              connection,
              reason: error.debugDescription
            )
          }
        }
      )
    } catch {
      connectionEnded(connection, reason: error.localizedDescription)
    }
  }

  private func receiveNextMessage(on connection: NWConnection) {
    let connectionId = ObjectIdentifier(connection)

    guard receivingConnections.insert(connectionId).inserted else {
      return
    }

    connection.receiveMessage { [weak self, weak connection] data, _, _, error in
      guard let self, let connection else {
        return
      }

      self.withStateQueue {
        self.receivingConnections.remove(connectionId)

        if let data, !data.isEmpty {
          do {
            guard data.count <= Self.maximumMessageLength else {
              throw NearbyNetworkError.messageTooLarge
            }

            let message = try JSONDecoder().decode(
              NearbyNetworkMessage.self,
              from: data
            )
            self.handle(message, from: connection)
          } catch {
            self.connectionEnded(
              connection,
              reason: error.localizedDescription
            )
            return
          }
        }

        if let error {
          self.connectionEnded(
            connection,
            reason: error.debugDescription
          )
          return
        }

        self.receiveNextMessage(on: connection)
      }
    }
  }

  private func handle(
    _ message: NearbyNetworkMessage,
    from connection: NWConnection
  ) {
    guard !expireDiscoveryIfNeeded() else {
      connection.cancel()
      return
    }

    guard message.peerId != localPeerId else {
      connectionEnded(connection, reason: "invalid-peer")
      return
    }

    if message.kind == .hello {
      handleHello(message, from: connection)
      return
    }

    let connectionId = ObjectIdentifier(connection)

    guard connectionPeerIds[connectionId] == message.peerId else {
      connectionEnded(connection, reason: "unidentified-peer")
      return
    }

    if message.kind == .proof {
      handleProof(message, from: connection)
      return
    }

    guard authenticatedConnections.contains(connectionId) else {
      connectionEnded(connection, reason: "unauthenticated-peer")
      return
    }

    switch message.kind {
    case .rangeRequest:
      handleRangingRequest(
        from: message.peerId,
        tokenData: message.discoveryToken,
        transactionId: message.transactionId,
        transportAuthenticated: true
      )
    case .rangeAccept:
      handleRangingAccepted(
        by: message.peerId,
        tokenData: message.discoveryToken,
        transactionId: message.transactionId
      )
    case .rangeBusy:
      handleRangingBusy(
        peerId: message.peerId,
        transactionId: message.transactionId
      )
    case .rangeStop:
      guard let transactionId = message.transactionId else {
        signpostIgnoredRangingMessage(
          kind: .rangeStop,
          peerId: message.peerId,
          transactionId: nil,
          disposition: .missingTransaction
        )
        return
      }
      endRanging(
        with: message.peerId,
        notifyPeer: false,
        reason: "remote-stop",
        transactionId: transactionId
      )
    case .hello:
      break
    case .proof:
      break
    }
  }

  private func handleHello(
    _ message: NearbyNetworkMessage,
    from connection: NWConnection
  ) {
    guard
      let localIdentity,
      message.eventScope == localIdentity.eventScope,
      let remoteChallenge = message.challenge,
      !remoteChallenge.isEmpty,
      let credential = message.credential,
      !credential.isEmpty
    else {
      connectionEnded(connection, reason: "invalid-identity")
      return
    }

    let connectionId = ObjectIdentifier(connection)

    if let expectedPeerId = connectionPeerIds[connectionId],
      expectedPeerId != message.peerId
    {
      connectionEnded(connection, reason: "unexpected-peer")
      return
    }

    if connections[message.peerId] == nil {
      connections[message.peerId] = connection
    } else if connections[message.peerId] !== connection {
      let candidateDirection = connectionChallenges[connectionId]?.isLocallyInitiated == true
        ? "local-outbound"
        : "inbound"
      SpatialPerformance.signposter.emitEvent(
        "Nearby network duplicate connection pending authentication",
        "Peer: \(message.peerId.prefix(8), privacy: .public), candidate: \(candidateDirection, privacy: .public)"
      )
    }

    cancelPeerEviction(for: message.peerId)
    markPeerTransportPresence(for: message.peerId)
    connectionPeerIds[connectionId] = message.peerId
    connectionChallenges[connectionId]?.remote = remoteChallenge

    let previousCredential = peerIdentities[message.peerId]?.credential
    peerIdentities[message.peerId] = NearbyPeerIdentity(
      credential: credential,
      eventScope: localIdentity.eventScope,
      publicKey: peerIdentities[message.peerId]?.publicKey,
      userId: previousCredential == credential
        ? peerIdentities[message.peerId]?.userId
        : nil
    )
    switch peerLinkState(for: message.peerId) {
    case .discovered:
      setPeerLinkState(
        .authenticating(transactionId: nil),
        for: message.peerId,
        reason: "network-hello"
      )
    case .connecting(let transactionId):
      setPeerLinkState(
        .authenticating(transactionId: transactionId),
        for: message.peerId,
        reason: "network-hello"
      )
    default:
      break
    }

    if previousCredential != credential {
      peerCredentialLastEmittedAt.removeValue(forKey: message.peerId)
    }
    emitCredentialDiscovered(for: message.peerId)
    authenticate(connection, peerId: message.peerId)
    maintainRangingPool()
  }

  /// A ranging transaction timeout can otherwise leave a ready but unusable
  /// connection in `connections`; every later retry then reuses that same
  /// path. Drop only this peer's control connection so the next attempt can
  /// establish a fresh authenticated path without disturbing other attendees.
  func resetNetworkConnectionForRangingRetry(
    to peerId: String,
    reason: String
  ) {
    guard let connection = connections.removeValue(forKey: peerId) else {
      return
    }

    let connectionId = ObjectIdentifier(connection)
    connectionPeerIds.removeValue(forKey: connectionId)
    receivingConnections.remove(connectionId)
    authenticatedConnections.remove(connectionId)
    connectionChallenges.removeValue(forKey: connectionId)
    pendingConnectionProofs.removeValue(forKey: connectionId)
    sentProofConnections.remove(connectionId)
    connection.stateUpdateHandler = nil
    connection.cancel()
    SpatialPerformance.signposter.emitEvent(
      "Ranging transport connection reset",
      "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public)"
    )
  }

  private func connectionEnded(
    _ connection: NWConnection,
    reason: String
  ) {
    let connectionId = ObjectIdentifier(connection)
    let peerId = connectionPeerIds.removeValue(forKey: connectionId)

    receivingConnections.remove(connectionId)
    authenticatedConnections.remove(connectionId)
    connectionChallenges.removeValue(forKey: connectionId)
    pendingConnectionProofs.removeValue(forKey: connectionId)
    sentProofConnections.remove(connectionId)
    connection.stateUpdateHandler = nil
    connection.cancel()

    guard
      let peerId,
      connections[peerId] === connection
    else {
      return
    }

    let isStillDiscovered = discoveredEndpoints[peerId] != nil
    connections.removeValue(forKey: peerId)

    if pendingRangingPeerIds.contains(peerId) {
      handleRangingBusy(
        peerId: peerId,
        transactionId: currentOutboundRangingTransaction(for: peerId)
      )
    }

    if isStillDiscovered {
      maintainRangingPool()
    } else {
      schedulePeerEviction(for: peerId, reason: reason)
    }
  }

  func closeConnectionWhenIdle(to peerId: String) {
    stateQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
      self?.withStateQueue {
        guard
          let self,
          !self.activeRangingPeerIds.contains(peerId),
          !self.pendingRangingPeerIds.contains(peerId),
          let connection = self.connections.removeValue(forKey: peerId)
        else {
          return
        }

        let connectionId = ObjectIdentifier(connection)
        self.connectionPeerIds.removeValue(forKey: connectionId)
        self.receivingConnections.remove(connectionId)
        self.authenticatedConnections.remove(connectionId)
        self.connectionChallenges.removeValue(forKey: connectionId)
        self.pendingConnectionProofs.removeValue(forKey: connectionId)
        self.sentProofConnections.remove(connectionId)
        connection.stateUpdateHandler = nil
        connection.cancel()

        if self.discoveredEndpoints[peerId] == nil {
          self.schedulePeerEviction(
            for: peerId,
            reason: "not-discovered"
          )
        }
      }
    }
  }

  func cancelPeerEviction(for peerId: String) {
    peerEvictionTokens.removeValue(forKey: peerId)
  }

  func cancelAllPeerEvictions() {
    peerEvictionTokens.removeAll()
  }

  func schedulePeerEviction(
    for peerId: String,
    reason: String
  ) {
    let token = UUID()
    peerEvictionTokens[peerId] = token

    stateQueue.asyncAfter(
      deadline: .now() + Self.peerEvictionGraceDuration
    ) { [weak self] in
      guard let self else {
        return
      }

      self.withStateQueue {
        guard
          self.peerEvictionTokens[peerId] == token,
          self.discoveredEndpoints[peerId] == nil,
          self.connections[peerId] == nil
        else {
          return
        }

        if let lastBluetoothSeenAt = self.peerBluetoothLastSeenAt[peerId],
          CACurrentMediaTime() - lastBluetoothSeenAt
            <= Self.peerEvictionGraceDuration
        {
          self.schedulePeerEviction(for: peerId, reason: reason)
          return
        }

        if let lastPresenceAt = self.peerLastTransportPresenceAt[peerId],
          CACurrentMediaTime() - lastPresenceAt
            <= Self.peerEvictionGraceDuration
        {
          self.schedulePeerEviction(for: peerId, reason: reason)
          return
        }

        self.peerEvictionTokens.removeValue(forKey: peerId)
        let identity = self.peerIdentities.removeValue(forKey: peerId)
        self.bluetoothPeerIds.remove(peerId)
        self.peerBluetoothLastSeenAt.removeValue(forKey: peerId)
        self.peerLastTransportPresenceAt.removeValue(forKey: peerId)
        self.peerLastAuthenticatedTransportAt.removeValue(forKey: peerId)
        let didEmitLoss = self.endRanging(
          with: peerId,
          notifyPeer: false,
          reason: reason,
          preserveSpatialState: false
        )
        self.peerSignalStrengths.removeValue(forKey: peerId)
        self.forgetPeerLinkState(for: peerId)

        if !didEmitLoss {
          self.emitPeerLost(
            peerId,
            identity: identity,
            reason: reason
          )
        }
      }
    }
  }

  func authenticateConnections(with peerId: String) {
    for (connectionId, connectionPeerId) in connectionPeerIds
    where connectionPeerId == peerId {
      guard let connection = connections[peerId] else {
        continue
      }

      authenticate(connection, peerId: peerId)

      if authenticatedConnections.contains(connectionId) {
        break
      }
    }
  }

  private func handleProof(
    _ message: NearbyNetworkMessage,
    from connection: NWConnection
  ) {
    let connectionId = ObjectIdentifier(connection)

    guard let signature = message.signature else {
      connectionEnded(connection, reason: "invalid-proof")
      return
    }

    pendingConnectionProofs[connectionId] = signature
    authenticate(connection, peerId: message.peerId)
  }

  private func authenticate(
    _ connection: NWConnection,
    peerId: String
  ) {
    let connectionId = ObjectIdentifier(connection)

    guard
      !authenticatedConnections.contains(connectionId),
      let localIdentity,
      let peerIdentity = peerIdentities[peerId],
      let challenge = connectionChallenges[connectionId],
      let remoteChallenge = challenge.remote
    else {
      return
    }

    if sentProofConnections.insert(connectionId).inserted {
      do {
        let payload = proofPayload(
          signerPeerId: localPeerId,
          verifierPeerId: peerId,
          eventScope: localIdentity.eventScope,
          credential: localIdentity.credential,
          signerChallenge: challenge.local,
          verifierChallenge: remoteChallenge
        )
        let signature = try signingPrivateKey.signature(
          for: payload
        )
        send(
          NearbyNetworkMessage(
            kind: .proof,
            peerId: localPeerId,
            signature: signature.derRepresentation
          ),
          on: connection
        )
      } catch {
        connectionEnded(
          connection,
          reason: error.localizedDescription
        )
        return
      }
    }

    guard
      peerIdentity.userId != nil,
      let publicKey = peerIdentity.publicKey,
      let signatureData = pendingConnectionProofs[connectionId]
    else {
      return
    }

    do {
      let verifyingKey = try P256.Signing.PublicKey(
        x963Representation: Data(base64Encoded: publicKey) ?? Data()
      )
      let signature = try P256.Signing.ECDSASignature(
        derRepresentation: signatureData
      )
      let payload = proofPayload(
        signerPeerId: peerId,
        verifierPeerId: localPeerId,
        eventScope: peerIdentity.eventScope,
        credential: peerIdentity.credential,
        signerChallenge: remoteChallenge,
        verifierChallenge: challenge.local
      )

      guard verifyingKey.isValidSignature(signature, for: payload) else {
        connectionEnded(connection, reason: "invalid-proof")
        return
      }
    } catch {
      connectionEnded(connection, reason: "invalid-proof")
      return
    }

    pendingConnectionProofs.removeValue(forKey: connectionId)
    authenticatedConnections.insert(connectionId)
    selectAuthenticatedNetworkConnection(
      for: peerId,
      authenticatedCandidate: connection
    )
    markPeerTransportPresence(
      for: peerId,
      authenticated: true
    )
    signpostFirstAuthenticatedTransport("network")
    SpatialPerformance.signposter.emitEvent(
      "Nearby peer authenticated"
    )

    if pendingRangingPeerIds.contains(peerId),
      connections[peerId] === connection
    {
      sendRangingRequest(to: peerId)
    } else if case .authenticating = peerLinkState(for: peerId) {
      setPeerLinkState(
        .discovered,
        for: peerId,
        reason: "network-authenticated"
      )
    }
  }

  /// Select the same authenticated connection at both ends. The lower stable
  /// peer ID owns the outbound connection; the other end keeps that inbound
  /// connection. A candidate is considered only after its signature proof is
  /// valid, so an unauthenticated hello cannot replace a live route.
  private func selectAuthenticatedNetworkConnection(
    for peerId: String,
    authenticatedCandidate: NWConnection
  ) {
    guard let currentConnection = connections[peerId] else {
      connections[peerId] = authenticatedCandidate
      return
    }

    guard currentConnection !== authenticatedCandidate else {
      return
    }

    let currentId = ObjectIdentifier(currentConnection)
    let candidateId = ObjectIdentifier(authenticatedCandidate)
    guard let candidateIsOutbound = connectionChallenges[candidateId]?.isLocallyInitiated else {
      return
    }

    let currentIsOutbound = connectionChallenges[currentId]?.isLocallyInitiated
    let candidateIsPreferred = candidateIsOutbound == (localPeerId < peerId)
    let currentIsAuthenticated = authenticatedConnections.contains(currentId)
    let shouldReplace: Bool
    if let currentIsOutbound {
      shouldReplace = SpatialNetworkConnectionPolicy.shouldReplaceExisting(
        localPeerId: localPeerId,
        remotePeerId: peerId,
        existingIsLocallyInitiated: currentIsOutbound,
        incomingIsLocallyInitiated: candidateIsOutbound,
        existingIsAuthenticated: currentIsAuthenticated,
        incomingIsAuthenticated: authenticatedConnections.contains(candidateId)
      )
    } else {
      shouldReplace = !currentIsAuthenticated
        && authenticatedConnections.contains(candidateId)
    }

    if shouldReplace {
      connections[peerId] = authenticatedCandidate
      SpatialPerformance.signposter.emitEvent(
        "Nearby network duplicate connection replaced",
        "Peer: \(peerId.prefix(8), privacy: .public), selected: \(candidateIsPreferred ? "deterministic-owner" : "authenticated-fallback", privacy: .public), prior: \(currentIsAuthenticated ? "authenticated" : "unauthenticated", privacy: .public)"
      )
      connectionEnded(
        currentConnection,
        reason: "preferred-network-connection"
      )
    } else {
      let currentIsPreferred = currentIsOutbound.map {
        $0 == (localPeerId < peerId)
      } ?? false
      SpatialPerformance.signposter.emitEvent(
        "Nearby network duplicate connection kept",
        "Peer: \(peerId.prefix(8), privacy: .public), selected: \(currentIsPreferred ? "deterministic-owner" : "authenticated-current", privacy: .public), candidate: \(candidateIsOutbound ? "local-outbound" : "inbound", privacy: .public)"
      )
      connectionEnded(
        authenticatedCandidate,
        reason: "duplicate-network-connection"
      )
    }
  }

  private func handleListenerState(_ state: NWListener.State) {
    switch state {
    case .ready:
      listenerReady = true
      emitNetworkReadyIfPossible()
    case .waiting(let error):
      listenerReady = false
      emitState("waiting", message: error.localizedDescription)
      scheduleNetworkRestart(after: error)
    case .failed(let error):
      listenerReady = false
      scheduleNetworkRestart(after: error)
    case .cancelled:
      listenerReady = false
      if localIdentity != nil {
        scheduleNetworkRestart(after: .posix(.ECANCELED))
      }
    case .setup:
      break
    @unknown default:
      break
    }
  }

  private func handleBrowserState(_ state: NWBrowser.State) {
    switch state {
    case .ready:
      browserReady = true
      emitNetworkReadyIfPossible()
    case .waiting(let error):
      browserReady = false
      emitState("waiting", message: error.localizedDescription)
      scheduleNetworkRestart(after: error)
    case .failed(let error):
      browserReady = false
      scheduleNetworkRestart(after: error)
    case .cancelled:
      browserReady = false
      if localIdentity != nil {
        scheduleNetworkRestart(after: .posix(.ECANCELED))
      }
    case .setup:
      break
    @unknown default:
      break
    }
  }

  private func emitNetworkReadyIfPossible() {
    guard listenerReady, browserReady else {
      return
    }

    networkRestartAttempts = 0
    emitState("ready")
    ensureDiscoveryTransport()
  }

  private func scheduleNetworkRestart(after error: NWError) {
    guard localIdentity != nil, networkRestartWorkItem == nil else {
      return
    }

    let delay = min(30, pow(2, Double(networkRestartAttempts)))
    networkRestartAttempts += 1
    emitState(
      "waiting",
      message: "Nearby discovery is reconnecting. \(error.localizedDescription)"
    )

    let workItem = DispatchWorkItem { [weak self] in
      guard let self else {
        return
      }

      self.withStateQueue {
        self.networkRestartWorkItem = nil

        self.stopRangingScheduler()
        self.stopNetworkDiscovery(cancelRestart: false)
        self.resetRanging()
        self.cancelAllPeerEvictions()
        // Bonjour is only one discovery transport. Keep resolved identities,
        // BLE presence, and recoverable spatial state while the listener and
        // browser are rebuilt so a network hiccup does not look like an event
        // exit to the attendee UI.
        SpatialPerformance.signposter.emitEvent(
          "Nearby discovery transport restarting",
          "Retaining peers: \(self.peerIdentities.count)"
        )

        do {
          try self.startNetworkDiscovery()

          if self.shouldRunProactiveRanging,
            self.runtimeRole.allowsProactiveRanging
          {
            self.startRangingScheduler()
            self.maintainRangingPool()
          }
        } catch {
          self.scheduleNetworkRestart(
            after: NWError.posix(.ENETDOWN)
          )
        }
      }
    }
    networkRestartWorkItem = workItem
    stateQueue.asyncAfter(
      deadline: .now() + delay,
      execute: workItem
    )
  }

  private func signpostServiceRegistration(
    _ change: NWListener.ServiceRegistrationChange
  ) {
    switch change {
    case .add:
      SpatialPerformance.signposter.emitEvent(
        "Bonjour service registered"
      )
    case .remove:
      SpatialPerformance.signposter.emitEvent(
        "Bonjour service unregistered"
      )
    @unknown default:
      break
    }
  }

  private func credential(from txtRecord: NWTXTRecord) -> String? {
    guard
      let encodedCount = txtRecord["credentialCount"],
      let count = Int(encodedCount),
      count > 0,
      count <= 16
    else {
      return nil
    }

    let chunks = (0..<count).compactMap {
      txtRecord["credential\($0)"]
    }

    return chunks.count == count ? chunks.joined() : nil
  }

  private func randomChallenge() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)

    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      return UUID().uuidString.lowercased()
    }

    return Data(bytes).base64EncodedString()
  }

  private func proofPayload(
    signerPeerId: String,
    verifierPeerId: String,
    eventScope: String,
    credential: String,
    signerChallenge: String,
    verifierChallenge: String
  ) -> Data {
    Data(
      [
        "areach-nearby-proof-v1",
        signerPeerId,
        verifierPeerId,
        eventScope,
        credential,
        signerChallenge,
        verifierChallenge,
      ].joined(separator: "\n").utf8
    )
  }

  private func makeConnectionParameters() -> NWParameters {
    let tlsOptions = NWProtocolTLS.Options()
    let preSharedKey = Data(transportKey.utf8).withUnsafeBytes {
      DispatchData(bytes: $0)
    }
    let preSharedKeyIdentity = Data(
      (localIdentity?.eventScope ?? "areach").utf8
    ).withUnsafeBytes {
      DispatchData(bytes: $0)
    }

    sec_protocol_options_add_pre_shared_key(
      tlsOptions.securityProtocolOptions,
      preSharedKey as dispatch_data_t,
      preSharedKeyIdentity as dispatch_data_t
    )
    sec_protocol_options_append_tls_ciphersuite(
      tlsOptions.securityProtocolOptions,
      tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!
    )

    let parameters = NWParameters(tls: tlsOptions)
    let webSocketOptions = NWProtocolWebSocket.Options(.version13)
    webSocketOptions.autoReplyPing = true

    parameters.defaultProtocolStack.applicationProtocols.insert(
      webSocketOptions,
      at: 0
    )
    parameters.allowLocalEndpointReuse = true
    parameters.includePeerToPeer = true
    return parameters
  }

  private func advertisedService(
    for identity: NearbyPeerIdentity
  ) -> NWListener.Service {
    var txtRecord: [String: String] = [
      "eventScope": identity.eventScope,
      "peerId": localPeerId,
    ]
    let credentialChunks = identity.credential.chunked(
      maximumLength: Self.credentialChunkLength
    )
    txtRecord["credentialCount"] = String(credentialChunks.count)

    for (index, chunk) in credentialChunks.enumerated() {
      txtRecord["credential\(index)"] = chunk
    }

    return NWListener.Service(
      name: localPeerId,
      type: Self.serviceType,
      domain: nil,
      txtRecord: NWTXTRecord(txtRecord)
    )
  }
}

private enum NearbyNetworkError: LocalizedError {
  case messageTooLarge

  var errorDescription: String? {
    "Nearby discovery message is too large."
  }
}

extension String {
  fileprivate func chunked(maximumLength: Int) -> [String] {
    guard !isEmpty else {
      return []
    }

    var chunks: [String] = []
    var start = startIndex

    while start < endIndex {
      let end =
        index(
          start,
          offsetBy: maximumLength,
          limitedBy: endIndex
        ) ?? endIndex
      chunks.append(String(self[start..<end]))
      start = end
    }

    return chunks
  }
}
