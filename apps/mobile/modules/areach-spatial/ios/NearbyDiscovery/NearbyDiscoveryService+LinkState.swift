import Foundation
import QuartzCore

extension NearbyDiscoveryService {
  func markPeerDiscoveredIfNeeded(
    _ peerId: String,
    reason: String
  ) {
    guard peerLinkStates[peerId] == nil else {
      return
    }

    setPeerLinkState(.discovered, for: peerId, reason: reason)
  }

  func signpostFirstBluetoothAdvertisement() {
    withStateQueue {
      guard !didSignpostFirstBluetoothAdvertisement else {
        return
      }

      didSignpostFirstBluetoothAdvertisement = true
      let latencyMilliseconds = discoveryStartedAt.map {
        Int((CACurrentMediaTime() - $0) * 1_000)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "First BLE advertisement",
        "Latency milliseconds: \(latencyMilliseconds)"
      )
    }
  }

  func signpostFirstAuthenticatedTransport(_ transport: String) {
    withStateQueue {
      guard !didSignpostFirstAuthenticatedTransport else {
        return
      }

      didSignpostFirstAuthenticatedTransport = true
      let latencyMilliseconds = discoveryStartedAt.map {
        Int((CACurrentMediaTime() - $0) * 1_000)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "First authenticated transport",
        "Latency milliseconds: \(latencyMilliseconds), transport: \(transport, privacy: .public)"
      )
    }
  }

  func peerLinkState(for peerId: String) -> SpatialPeerLinkState {
    peerLinkStates[peerId] ?? .discovered
  }

  func currentRangingTransaction(for peerId: String) -> UUID? {
    peerLinkState(for: peerId).transactionId
  }

  func currentOutboundRangingTransaction(for peerId: String) -> UUID? {
    peerLinkState(for: peerId).outboundTransactionId
  }

  func setPeerLinkState(
    _ state: SpatialPeerLinkState,
    for peerId: String,
    reason: String
  ) {
    guard peerLinkStates[peerId] != state else {
      return
    }

    peerLinkStates[peerId] = state
    SpatialPerformance.signposter.emitEvent(
      "Nearby peer link state",
      "Peer: \(peerId.prefix(8), privacy: .public), state: \(state.debugDescription, privacy: .public), reason: \(reason, privacy: .public)"
    )
  }

  @discardableResult
  func rememberRangingTransaction(
    _ transactionId: UUID,
    for peerId: String
  ) -> Bool {
    var transactions = observedRangingTransactions[peerId] ?? []
    guard transactions.insert(transactionId).inserted else {
      return false
    }

    if transactions.count > 32 {
      transactions.removeFirst()
    }
    observedRangingTransactions[peerId] = transactions
    return true
  }

  func forgetPeerLinkState(for peerId: String) {
    peerLinkStates.removeValue(forKey: peerId)
    observedRangingTransactions.removeValue(forKey: peerId)
    lastSignpostedMeasurementTiers.removeValue(forKey: peerId)
  }

  func signpostIgnoredRangingMessage(
    kind: NearbyNetworkMessage.Kind,
    peerId: String,
    transactionId: UUID?,
    disposition: SpatialRangingMessageDisposition
  ) {
    let transactionLabel = transactionId.map {
      String($0.uuidString.prefix(8))
    } ?? "none"
    SpatialPerformance.signposter.emitEvent(
      "Nearby ranging message ignored",
      "Kind: \(kind.rawValue, privacy: .public), peer: \(peerId.prefix(8), privacy: .public), transaction: \(transactionLabel, privacy: .public), disposition: \(disposition.rawValue, privacy: .public)"
    )
  }
}
