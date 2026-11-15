import Foundation
import QuartzCore

/// The negotiation transaction is deliberately separate from the Nearby
/// Interaction session. A transport message can be delayed after its NI
/// session has already been replaced, so every ranging control message must
/// identify the attempt it belongs to.
enum SpatialRangingLinkRole: String {
  case initiator
  case responder
}

enum SpatialPeerLinkState: Equatable {
  case discovered
  case connecting(transactionId: UUID)
  case authenticating(transactionId: UUID?)
  case negotiatingOutbound(transactionId: UUID)
  case yieldingToInbound(
    localTransactionId: UUID,
    incomingTransactionId: UUID
  )
  case negotiatingInbound(transactionId: UUID)
  case ranging(transactionId: UUID, role: SpatialRangingLinkRole)
  case cooldown(until: CFTimeInterval)

  var transactionId: UUID? {
    switch self {
    case .discovered, .cooldown:
      return nil
    case .authenticating(let transactionId):
      return transactionId
    case .connecting(let transactionId),
      .negotiatingOutbound(let transactionId),
      .negotiatingInbound(let transactionId),
      .ranging(let transactionId, _):
      return transactionId
    case .yieldingToInbound(_, let incomingTransactionId):
      return incomingTransactionId
    }
  }

  var outboundTransactionId: UUID? {
    switch self {
    case .connecting(let transactionId),
      .negotiatingOutbound(let transactionId):
      return transactionId
    case .authenticating(let transactionId):
      return transactionId
    case .yieldingToInbound(let localTransactionId, _):
      return localTransactionId
    case .ranging(let transactionId, let role) where role == .initiator:
      return transactionId
    case .discovered, .negotiatingInbound, .ranging, .cooldown:
      return nil
    }
  }

  var debugDescription: String {
    switch self {
    case .discovered:
      return "discovered"
    case .connecting(let transactionId):
      return "connecting:\(transactionId.shortDescription)"
    case .authenticating(let transactionId):
      return "authenticating:\(transactionId?.shortDescription ?? "none")"
    case .negotiatingOutbound(let transactionId):
      return "negotiating-outbound:\(transactionId.shortDescription)"
    case .yieldingToInbound(_, let transactionId):
      return "yielding-to-inbound:\(transactionId.shortDescription)"
    case .negotiatingInbound(let transactionId):
      return "negotiating-inbound:\(transactionId.shortDescription)"
    case .ranging(let transactionId, let role):
      return "ranging-\(role.rawValue):\(transactionId.shortDescription)"
    case .cooldown(let until):
      return "cooldown-until:\(String(format: "%.2f", until))"
    }
  }
}

enum SpatialRangingCollisionDecision: String {
  case keepOutbound
  case yieldToInbound
}

enum SpatialRangingMessageDisposition: String {
  case accept
  case duplicate
  case stale
  case missingTransaction
}

/// Pure, deterministic rules shared by the service and its command-line
/// harness. It intentionally contains no transport or NI behavior.
enum SpatialRangingNegotiationPolicy {
  static func collisionDecision(
    localPeerId: String,
    remotePeerId: String
  ) -> SpatialRangingCollisionDecision {
    localPeerId < remotePeerId ? .keepOutbound : .yieldToInbound
  }

  static func disposition(
    incomingTransactionId: UUID?,
    expectedTransactionId: UUID?,
    observedTransactionIds: Set<UUID>
  ) -> SpatialRangingMessageDisposition {
    guard let incomingTransactionId else {
      return .missingTransaction
    }

    if observedTransactionIds.contains(incomingTransactionId) {
      return .duplicate
    }

    guard expectedTransactionId == incomingTransactionId else {
      return .stale
    }

    return .accept
  }
}

/// Resolves crossed Bonjour connections the same way at both ends. When two
/// peers connect simultaneously, the lower stable peer ID owns the outbound
/// connection and the higher ID keeps that same connection as inbound.
enum SpatialNetworkConnectionPolicy {
  static func shouldReplaceExisting(
    localPeerId: String,
    remotePeerId: String,
    existingIsLocallyInitiated: Bool,
    incomingIsLocallyInitiated: Bool,
    existingIsAuthenticated: Bool,
    incomingIsAuthenticated: Bool
  ) -> Bool {
    // Never let an unauthenticated candidate take over a route. An
    // authenticated candidate should, however, replace an unusable
    // unauthenticated incumbent even if it is not the deterministic route.
    guard incomingIsAuthenticated else {
      return false
    }
    guard existingIsAuthenticated else {
      return true
    }

    let preferredInitiatorIsLocal = localPeerId < remotePeerId
    let existingIsPreferred =
      existingIsLocallyInitiated == preferredInitiatorIsLocal
    let incomingIsPreferred =
      incomingIsLocallyInitiated == preferredInitiatorIsLocal

    guard existingIsPreferred != incomingIsPreferred else {
      return false
    }

    return incomingIsPreferred
  }
}

private extension UUID {
  var shortDescription: String {
    String(uuidString.prefix(8)).lowercased()
  }
}
