import Foundation
import NearbyInteraction
import QuartzCore
import simd

enum SpatialCameraAssistanceState: String {
  case unknown
  case notConverged
  case converged
}

/// Ordered quality semantics used by policy and instrumentation. A lower
/// tier is useful for presence/ranking, but must not be presented as precise
/// visual association evidence.
enum SpatialMeasurementTier: String {
  case presenceOnly
  case distanceOnly
  case directionAvailable
  case projectable
  case cameraAssisted
}

struct SpatialMeasurementQuality {
  let distanceAge: CFTimeInterval
  let directionAge: CFTimeInterval
  let isActive: Bool
  let sampleAge: CFTimeInterval
  let transformAge: CFTimeInterval
  let callbackAge: CFTimeInterval
  let usefulMeasurementAge: CFTimeInterval
  let healthState: SpatialRangingHealthState
  let convergence: SpatialCameraAssistanceState

  var convergencePenalty: Double {
    switch convergence {
    case .converged:
      return 0
    case .unknown:
      return 0.12
    case .notConverged:
      return 0.35
    }
  }

  var tier: SpatialMeasurementTier {
    let hasFreshTransform = transformAge.isFinite
      && transformAge <= SpatialPeerState.freshDuration
    let hasFreshDirection = directionAge.isFinite
      && directionAge <= SpatialMeasurementTuning.newMatchMaximumDirectionAge
    let hasFreshDistance = distanceAge.isFinite
      && distanceAge <= SpatialPeerState.freshDuration + 0.5

    if isActive, hasFreshTransform {
      return convergence == .converged ? .cameraAssisted : .projectable
    }

    if isActive, hasFreshDirection {
      return .directionAvailable
    }

    if isActive, hasFreshDistance {
      return .distanceOnly
    }

    return .presenceOnly
  }

  var freshness: Double {
    let hasTransform = transformAge < .greatestFiniteMagnitude
    let hasDirection = directionAge < .greatestFiniteMagnitude
    let hasDistance = distanceAge < .greatestFiniteMagnitude
    let transformFreshness = hasTransform
      ? exp(-Double(transformAge) / 1.25)
      : 0
    let distanceFreshness = hasDistance
      ? exp(-Double(distanceAge) / 1.6)
      : 0
    let directionFreshness = hasDirection
      ? exp(-Double(directionAge) / 1.25)
      : 0

    // Each measurement is an independent usable observation. Missing
    // distance must not erase a fresh direction sample, and a stale transform
    // must not erase a fresh pocket-distance sample.
    let freshness: Double
    if hasTransform || hasDirection || hasDistance {
      freshness = max(
        transformFreshness,
        max(directionFreshness, distanceFreshness)
      )
    } else {
      freshness = 0
    }
    return max(0, min(1, freshness))
  }
}

struct SpatialPeerState {
  static let freshDuration: CFTimeInterval = 1.8
  static let recoveryDuration: CFTimeInterval = SpatialRangingTuning.transportPresenceRetentionDuration

  let distance: Float?
  let distanceUpdatedAt: CFTimeInterval?
  let directionalMeasurement: SpatialDirectionalMeasurement?
  let distanceUncertainty: Float?
  let distanceSampleCount: Int
  let identity: NearbyPeerIdentity?
  let isRanging: Bool
  let presenceState: SpatialPeerPresenceState
  let rangingState: SpatialPeerRangingState
  let transportState: SpatialPeerTransportState
  let lastRangedAt: CFTimeInterval?
  let lastUpdatedAt: CFTimeInterval
  let peerId: String
  let signalStrength: Double?
  let cameraAssistanceEnabled: Bool
  let worldTransform: simd_float4x4?
  let worldTransformUpdatedAt: CFTimeInterval?
  let convergence: SpatialCameraAssistanceState
  /// Raw values are optional for replay compatibility. Live snapshots always
  /// populate them when the corresponding NI measurement is valid.
  let rawDistance: Float?
  let rawDistanceUpdatedAt: CFTimeInterval?
  let rawWorldTransform: simd_float4x4?
  let rawWorldTransformUpdatedAt: CFTimeInterval?
  let displayWorldTransform: simd_float4x4?
  let displayWorldTransformUpdatedAt: CFTimeInterval?
  let lastDelegateCallbackAt: CFTimeInterval?
  let lastUsefulMeasurementAt: CFTimeInterval?
  let lastDistanceMeasurementAt: CFTimeInterval?
  let lastDirectionMeasurementAt: CFTimeInterval?
  let lastWorldTransformMeasurementAt: CFTimeInterval?
  let lastTransportPresenceAt: CFTimeInterval?
  let lastAuthenticatedTransportAt: CFTimeInterval?
  let rangingHealth: SpatialRangingHealth
  let displayDistance: Float?

  init(
    distance: Float?,
    distanceUpdatedAt: CFTimeInterval?,
    directionalMeasurement: SpatialDirectionalMeasurement? = nil,
    distanceUncertainty: Float?,
    distanceSampleCount: Int,
    identity: NearbyPeerIdentity?,
    isRanging: Bool,
    presenceState: SpatialPeerPresenceState,
    rangingState: SpatialPeerRangingState,
    transportState: SpatialPeerTransportState,
    lastRangedAt: CFTimeInterval?,
    lastUpdatedAt: CFTimeInterval,
    peerId: String,
    signalStrength: Double?,
    cameraAssistanceEnabled: Bool,
    worldTransform: simd_float4x4?,
    worldTransformUpdatedAt: CFTimeInterval?,
    convergence: SpatialCameraAssistanceState,
    rawDistance: Float? = nil,
    rawDistanceUpdatedAt: CFTimeInterval? = nil,
    rawWorldTransform: simd_float4x4? = nil,
    rawWorldTransformUpdatedAt: CFTimeInterval? = nil,
    displayWorldTransform: simd_float4x4? = nil,
    displayWorldTransformUpdatedAt: CFTimeInterval? = nil,
    lastDelegateCallbackAt: CFTimeInterval? = nil,
    lastUsefulMeasurementAt: CFTimeInterval? = nil,
    lastDistanceMeasurementAt: CFTimeInterval? = nil,
    lastDirectionMeasurementAt: CFTimeInterval? = nil,
    lastWorldTransformMeasurementAt: CFTimeInterval? = nil,
    lastTransportPresenceAt: CFTimeInterval? = nil,
    lastAuthenticatedTransportAt: CFTimeInterval? = nil,
    rangingHealth: SpatialRangingHealth = SpatialRangingHealth(),
    displayDistance: Float? = nil
  ) {
    self.distance = distance
    self.distanceUpdatedAt = distanceUpdatedAt
    self.directionalMeasurement = directionalMeasurement
    self.distanceUncertainty = distanceUncertainty
    self.distanceSampleCount = distanceSampleCount
    self.identity = identity
    self.isRanging = isRanging
    self.presenceState = presenceState
    self.rangingState = rangingState
    self.transportState = transportState
    self.lastRangedAt = lastRangedAt
    self.lastUpdatedAt = lastUpdatedAt
    self.peerId = peerId
    self.signalStrength = signalStrength
    self.cameraAssistanceEnabled = cameraAssistanceEnabled
    self.worldTransform = worldTransform
    self.worldTransformUpdatedAt = worldTransformUpdatedAt
    self.convergence = convergence
    self.rawDistance = rawDistance
    self.rawDistanceUpdatedAt = rawDistanceUpdatedAt
    self.rawWorldTransform = rawWorldTransform
    self.rawWorldTransformUpdatedAt = rawWorldTransformUpdatedAt
    self.displayWorldTransform = displayWorldTransform
    self.displayWorldTransformUpdatedAt = displayWorldTransformUpdatedAt
    self.lastDelegateCallbackAt = lastDelegateCallbackAt
    self.lastUsefulMeasurementAt = lastUsefulMeasurementAt
    self.lastDistanceMeasurementAt = lastDistanceMeasurementAt
    self.lastDirectionMeasurementAt = lastDirectionMeasurementAt
    self.lastWorldTransformMeasurementAt = lastWorldTransformMeasurementAt
    self.lastTransportPresenceAt = lastTransportPresenceAt
    self.lastAuthenticatedTransportAt = lastAuthenticatedTransportAt
    self.rangingHealth = rangingHealth
    self.displayDistance = displayDistance
  }

  func isFresh(at time: CFTimeInterval) -> Bool {
    let hasFreshTransform = transformAge(at: time) <= Self.freshDuration
    let hasFreshDirection = directionAge(at: time)
      <= SpatialMeasurementTuning.newMatchMaximumDirectionAge
    let hasFreshDistance = effectiveRawDistance != nil
      && distanceAge(at: time) <= Self.freshDuration + 0.5
    return hasFreshTransform || hasFreshDirection || hasFreshDistance
  }

  func isRecoverable(at time: CFTimeInterval) -> Bool {
    presenceAge(at: time) <= Self.recoveryDuration
      || (lastTransportPresenceAt == nil && time - lastUpdatedAt <= Self.recoveryDuration)
  }

  func presenceAge(at time: CFTimeInterval) -> CFTimeInterval {
    guard let lastTransportPresenceAt else {
      return .greatestFiniteMagnitude
    }

    return max(0, time - lastTransportPresenceAt)
  }

  func transformAge(at time: CFTimeInterval) -> CFTimeInterval {
    guard let updatedAt = currentRawWorldTransformUpdatedAt else {
      return .greatestFiniteMagnitude
    }

    return max(0, time - updatedAt)
  }

  func distanceAge(at time: CFTimeInterval) -> CFTimeInterval {
    guard let updatedAt = currentRawDistanceUpdatedAt else {
      return .greatestFiniteMagnitude
    }

    return max(0, time - updatedAt)
  }

  func directionAge(at time: CFTimeInterval) -> CFTimeInterval {
    guard let measuredAt = currentDirectionalMeasurement?.measuredAt else {
      return .greatestFiniteMagnitude
    }

    return max(0, time - measuredAt)
  }

  var currentDirectionalMeasurement: SpatialDirectionalMeasurement? {
    guard let directionalMeasurement,
      let transactionStartedAt = rangingHealth.transactionStartedAt
    else {
      return directionalMeasurement
    }

    return directionalMeasurement.measuredAt >= transactionStartedAt
      ? directionalMeasurement
      : nil
  }

  func directionalMeasurement(
    at time: CFTimeInterval,
    maximumAge: CFTimeInterval = SpatialMeasurementTuning.newMatchMaximumDirectionAge
  ) -> SpatialDirectionalMeasurement? {
    guard let measurement = currentDirectionalMeasurement,
      measurement.isFresh(at: time, maximumAge: maximumAge)
    else {
      return nil
    }

    return measurement
  }

  var effectiveRawDistance: Float? {
    rawDistance ?? distance
  }

  var effectiveRawDistanceUpdatedAt: CFTimeInterval? {
    rawDistanceUpdatedAt ?? distanceUpdatedAt
  }

  var currentRawDistanceUpdatedAt: CFTimeInterval? {
    guard rangingHealth.transactionStartedAt != nil else {
      return effectiveRawDistanceUpdatedAt
    }

    return rangingHealth.currentAttemptTimestamp(effectiveRawDistanceUpdatedAt)
  }

  var effectiveRawWorldTransform: simd_float4x4? {
    rawWorldTransform ?? worldTransform
  }

  var effectiveRawWorldTransformUpdatedAt: CFTimeInterval? {
    rawWorldTransformUpdatedAt ?? worldTransformUpdatedAt
  }

  var currentRawWorldTransformUpdatedAt: CFTimeInterval? {
    guard rangingHealth.transactionStartedAt != nil else {
      return effectiveRawWorldTransformUpdatedAt
    }

    return rangingHealth.currentAttemptTimestamp(effectiveRawWorldTransformUpdatedAt)
  }

  var effectiveDisplayWorldTransform: simd_float4x4? {
    displayWorldTransform
  }

  func isWorldTransformUsable(at time: CFTimeInterval) -> Bool {
    SpatialRenderFreshnessPolicy.canRenderSolidPhoneMarker(
      worldTransformAvailable: effectiveRawWorldTransform != nil,
      transformAge: transformAge(at: time)
    )
  }

  func quality(at time: CFTimeInterval) -> SpatialMeasurementQuality {
    SpatialMeasurementQuality(
      distanceAge: distanceAge(at: time),
      directionAge: directionAge(at: time),
      isActive: isRanging,
      sampleAge: usefulMeasurementAge(at: time),
      transformAge: transformAge(at: time),
      callbackAge: callbackAge(at: time),
      usefulMeasurementAge: usefulMeasurementAge(at: time),
      healthState: rangingHealth.state,
      convergence: convergence
    )
  }

  func callbackAge(at time: CFTimeInterval) -> CFTimeInterval {
    let currentCallbackAt = rangingHealth.currentAttemptTimestamp(
      lastDelegateCallbackAt ?? rangingHealth.lastDelegateCallbackAt
    )
    guard let currentCallbackAt else {
      return .greatestFiniteMagnitude
    }

    return max(0, time - currentCallbackAt)
  }

  func usefulMeasurementAge(at time: CFTimeInterval) -> CFTimeInterval {
    let latestUsefulAt = lastUsefulMeasurementAt
      ?? rangingHealth.lastUsefulMeasurementAt
    if let currentUsefulAt = rangingHealth.currentAttemptTimestamp(latestUsefulAt) {
      return max(0, time - currentUsefulAt)
    }

    return rangingHealth.transactionStartedAt == nil
      ? max(0, time - lastUpdatedAt)
      : .greatestFiniteMagnitude
  }

  func measurementTier(at time: CFTimeInterval) -> SpatialMeasurementTier {
    quality(at: time).tier
  }

  func distanceMeasurement(at time: CFTimeInterval) -> SpatialDepthMeasurement? {
    guard
      let distance = effectiveRawDistance,
      let distanceUpdatedAt = currentRawDistanceUpdatedAt,
      let distanceUncertainty,
      distance.isFinite,
      distance > 0,
      distanceUpdatedAt.isFinite,
      distanceUncertainty.isFinite,
      distanceUncertainty > 0
    else {
      return nil
    }

    let quality: Float
    if isRanging {
      quality = min(
        0.94,
        0.68 + Float(min(max(distanceSampleCount, 1), 5)) * 0.05
      )
    } else {
      // A released scalar may help a verified overlay recover, but it must
      // not regain new-identity authority.
      quality = 0.35
    }
    return SpatialDepthMeasurement(
      distance: distance,
      quality: quality,
      uncertainty: distanceUncertainty,
      source: .uwbDistance,
      measuredAt: distanceUpdatedAt
    )
  }

  func isEligibleForNewIdentity(at time: CFTimeInterval) -> Bool {
    guard isRanging else {
      return false
    }

    if effectiveRawWorldTransform != nil,
      transformAge(at: time) <= SpatialMeasurementTuning.newMatchMaximumTransformAge
    {
      return true
    }

    return directionalMeasurement(at: time) != nil
  }
}

/// Kept as an internal compatibility name while the world model uses the
/// clearer peer-state terminology.
typealias NearbyPeerSpatialSnapshot = SpatialPeerState

extension NearbyDiscoveryService {
  private static var credentialEventInterval: CFTimeInterval { 2 }
  private static var peerEventInterval: CFTimeInterval { 0.2 }

  var rangingHealthRole: SpatialRangingHealthRole {
    switch runtimeRole {
    case .cameraViewer:
      return .cameraViewer
    case .foregroundProximity:
      return .foregroundProximity
    case .backgroundResponder, .suspended:
      return .backgroundResponder
    }
  }

  static func isValidWorldTransform(_ transform: simd_float4x4) -> Bool {
    let columns = transform.columns
    return columns.0.x.isFinite && columns.0.y.isFinite
      && columns.0.z.isFinite && columns.0.w.isFinite
      && columns.1.x.isFinite && columns.1.y.isFinite
      && columns.1.z.isFinite && columns.1.w.isFinite
      && columns.2.x.isFinite && columns.2.y.isFinite
      && columns.2.z.isFinite && columns.2.w.isFinite
      && columns.3.x.isFinite && columns.3.y.isFinite
      && columns.3.z.isFinite && columns.3.w.isFinite
  }

  static func directionalMeasurement(
    from nearbyObject: NINearbyObject,
    at now: CFTimeInterval
  ) -> SpatialDirectionalMeasurement? {
    let supportsDirectionMeasurement: Bool
    if #available(iOS 16.0, *) {
      supportsDirectionMeasurement =
        NISession.deviceCapabilities.supportsDirectionMeasurement
    } else {
      // NINearbyObject.direction is available on the deployment target, but
      // the device capability snapshot is only exposed here on newer iOS.
      supportsDirectionMeasurement = true
    }
    guard supportsDirectionMeasurement else {
      return nil
    }

    let direction = nearbyObject.direction.flatMap { direction in
      direction.x.isFinite && direction.y.isFinite && direction.z.isFinite
        && simd_length(direction) > 0.001
        ? direction
        : nil
    }
    let horizontalAngle: Float?
    if #available(iOS 16.0, *) {
      horizontalAngle = nearbyObject.horizontalAngle.flatMap {
        $0.isFinite ? $0 : nil
      }
    } else {
      horizontalAngle = nil
    }

    guard direction != nil || horizontalAngle != nil else {
      return nil
    }

    return SpatialDirectionalMeasurement(
      direction: direction,
      horizontalAngle: horizontalAngle,
      measuredAt: now
    )
  }

  private func currentRangingTimestamp(
    _ timestamp: CFTimeInterval?,
    health: SpatialRangingHealth?
  ) -> CFTimeInterval? {
    guard let health else {
      return timestamp
    }

    return health.currentAttemptTimestamp(timestamp)
  }

  func peerSpatialSnapshots() -> [NearbyPeerSpatialSnapshot] {
    return withStateQueue {
      let now = CACurrentMediaTime()

      // Presence and measurement have independent lifetimes. A quiet NI
      // delegate must not erase a still-authenticated peer or its diagnostic
      // history; actual peer eviction is owned by the transport layer.
      let peerIds = Set(peerIdentities.keys)
        .union(peerLastTransportPresenceAt.keys)
        .union(peerRawWorldTransforms.keys)
        .union(peerWorldTransforms.keys)
        .union(peerRawDirectionalMeasurements.keys)
        .union(peerRawDistances.keys)
        .union(peerDistances.keys)

      let snapshots: [NearbyPeerSpatialSnapshot] = peerIds.compactMap { peerId in
      let health = peerRangingHealth[peerId]
      let currentDelegateCallbackAt = currentRangingTimestamp(
        peerLastDelegateCallbackAt[peerId] ?? health?.lastDelegateCallbackAt,
        health: health
      )
      let currentUsefulMeasurementAt = currentRangingTimestamp(
        peerLastUsefulMeasurementAt[peerId] ?? health?.lastUsefulMeasurementAt,
        health: health
      )
      let currentDistanceMeasurementAt = currentRangingTimestamp(
        peerLastDistanceMeasurementAt[peerId] ?? health?.lastDistanceAt,
        health: health
      )
      let currentWorldTransformMeasurementAt = currentRangingTimestamp(
        peerLastWorldTransformMeasurementAt[peerId] ?? health?.lastTransformAt,
        health: health
      )
      let currentDirectionMeasurementAt = currentRangingTimestamp(
        peerLastDirectionMeasurementAt[peerId] ?? health?.lastDirectionAt,
        health: health
      )
      let currentUsefulAt = currentUsefulMeasurementAt
        let updatedAt = currentUsefulAt
          ?? peerLastTransportPresenceAt[peerId]
          ?? peerLastUpdatedAt[peerId]
          ?? 0
        let safeUpdatedAt = updatedAt.isFinite ? updatedAt : 0

        let identity = peerIdentities[peerId]
        let rangingState: SpatialPeerRangingState
        if pendingRangingPeerIds.contains(peerId) {
          rangingState = .requesting
        } else if activeRangingPeerIds.contains(peerId) {
          rangingState = extendedDistancePeerId == peerId
            ? .activeEDM
            : .activeLegacy
        } else if now < (rangingRetryAfter[peerId] ?? 0) {
          rangingState = .cooldown
        } else {
          rangingState = .idle
        }

        let presenceState: SpatialPeerPresenceState
        if peerLastTransportPresenceAt[peerId].map({
          now - $0 > SpatialPeerState.recoveryDuration
        }) == true {
          presenceState = .stale
        } else if identity?.userId?.isEmpty == false {
          presenceState = .identityResolved
        } else {
          presenceState = .discovered
        }

        let transportState: SpatialPeerTransportState
        if let connection = connections[peerId],
          authenticatedConnections.contains(ObjectIdentifier(connection))
        {
          transportState = .authenticatedLocalNetwork
        } else if connections[peerId] != nil || discoveredEndpoints[peerId] != nil {
          transportState = .localNetwork
        } else if bluetoothPeerIds.contains(peerId) {
          transportState = .bluetooth
        } else {
          transportState = .unavailable
        }

        let snapshot = SpatialPeerState(
          distance: peerRawDistances[peerId],
          distanceUpdatedAt: peerRawDistanceUpdatedAt[peerId],
          directionalMeasurement: peerRawDirectionalMeasurements[peerId],
          distanceUncertainty: peerDistanceUncertainty[peerId],
          distanceSampleCount: peerDistanceSamples[peerId]?.count ?? 0,
          identity: identity,
          isRanging: activeRangingPeerIds.contains(peerId),
          presenceState: presenceState,
          rangingState: rangingState,
          transportState: transportState,
          lastRangedAt: peerLastRangedAt[peerId],
          lastUpdatedAt: safeUpdatedAt,
          peerId: peerId,
          signalStrength: peerSignalStrengths[peerId],
          cameraAssistanceEnabled: peerCameraAssistanceEnabled[peerId] ?? false,
          worldTransform: peerRawWorldTransforms[peerId],
          worldTransformUpdatedAt: peerRawWorldTransformUpdatedAt[peerId],
          convergence: peerCameraAssistanceStates[peerId] ?? .unknown,
          rawDistance: peerRawDistances[peerId],
          rawDistanceUpdatedAt: peerRawDistanceUpdatedAt[peerId],
          rawWorldTransform: peerRawWorldTransforms[peerId],
          rawWorldTransformUpdatedAt: peerRawWorldTransformUpdatedAt[peerId],
          displayWorldTransform: peerWorldTransforms[peerId],
          displayWorldTransformUpdatedAt: peerWorldTransformUpdatedAt[peerId],
          lastDelegateCallbackAt: currentDelegateCallbackAt,
          lastUsefulMeasurementAt: currentUsefulMeasurementAt,
          lastDistanceMeasurementAt: currentDistanceMeasurementAt,
          lastDirectionMeasurementAt: currentDirectionMeasurementAt,
          lastWorldTransformMeasurementAt: currentWorldTransformMeasurementAt,
          lastTransportPresenceAt: peerLastTransportPresenceAt[peerId],
          lastAuthenticatedTransportAt: peerLastAuthenticatedTransportAt[peerId],
          rangingHealth: peerRangingHealth[peerId] ?? SpatialRangingHealth(),
          displayDistance: peerDistances[peerId]
        )

        let transformAge = snapshot.transformAge(at: now)
        if snapshot.effectiveRawWorldTransform != nil,
          transformAge > SpatialMeasurementTuning.renderMaximumTransformAge
        {
          if peersWithSignpostedStaleWorldTransform.insert(peerId).inserted {
            let ageMilliseconds = transformAge.isFinite
              ? Int(min(transformAge, 99_999) * 1_000)
              : -1
            SpatialPerformance.signposter.emitEvent(
              "World transform became stale",
              "Peer: \(peerId.prefix(8), privacy: .public), age milliseconds: \(ageMilliseconds), health: \(snapshot.rangingHealth.state.rawValue, privacy: .public)"
            )
          }
        } else {
          peersWithSignpostedStaleWorldTransform.remove(peerId)
        }

        let distanceAge = snapshot.distanceAge(at: now)
        if snapshot.effectiveRawDistance != nil,
          distanceAge > SpatialPeerState.freshDuration + 0.5
        {
          if peersWithSignpostedStaleDistance.insert(peerId).inserted {
            let ageMilliseconds = distanceAge.isFinite
              ? Int(min(distanceAge, 99_999) * 1_000)
              : -1
            SpatialPerformance.signposter.emitEvent(
              "Distance became stale",
              "Peer: \(peerId.prefix(8), privacy: .public), age milliseconds: \(ageMilliseconds), health: \(snapshot.rangingHealth.state.rawValue, privacy: .public)"
            )
          }
        } else {
          peersWithSignpostedStaleDistance.remove(peerId)
        }

        let measurementTier = snapshot.measurementTier(at: now).rawValue
        if lastSignpostedMeasurementTiers[peerId] != measurementTier {
          lastSignpostedMeasurementTiers[peerId] = measurementTier
          SpatialPerformance.signposter.emitEvent(
            "Nearby peer measurement tier",
            "Peer: \(peerId.prefix(8), privacy: .public), tier: \(measurementTier, privacy: .public), link: \(self.peerLinkState(for: peerId).debugDescription, privacy: .public)"
          )
        }

        return snapshot
      }

      updatePeerSnapshotCache(snapshots)
      return snapshots
    }
  }

  /// Rehydrates the small JavaScript presence cache after a route/provider
  /// remount. The live native service remains authoritative; this is only a
  /// current-state snapshot so the attendee list does not wait for the next
  /// NI callback before showing a still-nearby resolved peer.
  func nearbyPeerPresenceSnapshot() -> [[String: Any]] {
    withStateQueue {
      let now = CACurrentMediaTime()
      return peerSpatialSnapshots().compactMap { snapshot in
        guard
          snapshot.isRecoverable(at: now),
          let userId = snapshot.identity?.userId,
          !userId.isEmpty
        else {
          return nil
        }

        var payload: [String: Any] = [
          "peerId": snapshot.peerId,
          "userId": userId,
        ]
        if let distance = snapshot.displayDistance ?? snapshot.distance,
          snapshot.distanceAge(at: now)
            <= SpatialPeerState.freshDuration + 0.5
        {
          payload["distance"] = distance
        }
        return payload
      }
    }
  }

  /// Replays unresolved identities for a route/provider that mounted after
  /// discovery already found a nearby phone. Credential events are deliberately
  /// not retained indefinitely, so this current-state view closes that startup
  /// race without exposing the native identity graph.
  func nearbyCredentialSnapshot() -> [[String: Any]] {
    withStateQueue {
      peerIdentities.compactMap { peerId, identity in
        guard identity.userId == nil, !identity.credential.isEmpty else {
          return nil
        }

        return [
          "credential": identity.credential,
          "peerId": peerId,
        ]
      }
    }
  }

  /// The last native session state is authoritative when the React listener
  /// attaches after the corresponding event was emitted.
  func nearbySessionStateSnapshot() -> [String: Any] {
    withStateQueue {
      var payload: [String: Any] = ["state": currentSessionState.state]
      if let message = currentSessionState.message {
        payload["message"] = message
      }
      return payload
    }
  }

  func emitState(_ state: String, message: String? = nil) {
    withStateQueue {
      currentSessionState = (state, message)

      var payload: [String: Any] = ["state": state]

      if let message {
        payload["message"] = message
      }

      emit("onNearbySessionState", payload)
    }
  }

  func emitCredentialDiscovered(for peerId: String) {
    withStateQueue {
      guard
        let identity = peerIdentities[peerId],
        identity.userId == nil
      else {
        return
      }

      let now = CACurrentMediaTime()

      if let lastEmittedAt = peerCredentialLastEmittedAt[peerId] {
        guard now - lastEmittedAt >= Self.credentialEventInterval else {
          return
        }
      }

      peerCredentialLastEmittedAt[peerId] = now
      emit(
        "onNearbyCredentialDiscovered",
        [
          "credential": identity.credential,
          "peerId": peerId,
        ]
      )
    }
  }

  func emitPeerUpdate(
    _ peerId: String,
    identity: NearbyPeerIdentity?,
    session: NISession,
    nearbyObject: NINearbyObject
  ) {
    withStateQueue {
      let now = CACurrentMediaTime()

      if #available(iOS 16.0, *) {
        setPeerSpatialState(
          session.worldTransform(for: nearbyObject),
          directionalMeasurement: Self.directionalMeasurement(
            from: nearbyObject,
            at: now
          ),
          distance: nearbyObject.distance,
          for: peerId,
          now: now
        )
      } else {
        setPeerSpatialState(
          nil,
          directionalMeasurement: Self.directionalMeasurement(
            from: nearbyObject,
            at: now
          ),
          distance: nearbyObject.distance,
          for: peerId,
          now: now
        )
      }

      if identity?.userId == nil {
        emitCredentialDiscovered(for: peerId)
        return
      }

      if let lastEmittedAt = peerLastEmittedAt[peerId] {
        guard now - lastEmittedAt >= Self.peerEventInterval else {
          return
        }
      }

      peerLastEmittedAt[peerId] = now
      emit(
        "onNearbyPeerUpdate",
        NearbyPeerEventPayload.update(
          peerId: peerId,
          identity: identity,
          nearbyObject: nearbyObject
        )
      )
    }
  }

  func emitResolvedPeerPresence(
    _ peerId: String,
    identity: NearbyPeerIdentity
  ) {
    withStateQueue {
      guard identity.userId != nil else {
        return
      }

      let now = CACurrentMediaTime()

      if let lastEmittedAt = peerLastEmittedAt[peerId] {
        guard now - lastEmittedAt >= Self.peerEventInterval else {
          return
        }
      }

      peerLastEmittedAt[peerId] = now
      emit(
        "onNearbyPeerUpdate",
        NearbyPeerEventPayload.base(
          peerId: peerId,
          identity: identity
        )
      )
    }
  }

  func emitPeerLost(
    _ peerId: String,
    identity: NearbyPeerIdentity?,
    reason: String,
    stillNearby: Bool = false
  ) {
    emit(
      "onNearbyPeerLost",
      NearbyPeerEventPayload.lost(
        peerId: peerId,
        identity: identity,
        reason: reason,
        stillNearby: stillNearby
      )
    )
  }

  private func emit(_ eventName: String, _ payload: [String: Any]) {
    DispatchQueue.main.async { [sendEvent] in
      sendEvent(eventName, payload)
    }
  }

  private func setPeerSpatialState(
    _ transform: simd_float4x4?,
    directionalMeasurement: SpatialDirectionalMeasurement?,
    distance: Float?,
    for peerId: String,
    now: CFTimeInterval
  ) {
    if let directionalMeasurement,
      directionalMeasurement.bearingRadians != nil
    {
      peerRawDirectionalMeasurements[peerId] = directionalMeasurement
      peerLastDirectionMeasurementAt[peerId] = now
    } else {
      // A callback without direction means direction is currently
      // unavailable. Do not let an older angle act as current identity
      // evidence while scalar distance continues to arrive.
      peerRawDirectionalMeasurements.removeValue(forKey: peerId)
      peerLastDirectionMeasurementAt.removeValue(forKey: peerId)
    }

    if let transform,
      Self.isValidWorldTransform(transform)
    {
      let hadWorldTransform = peerRawWorldTransforms[peerId] != nil
      var filter = peerWorldPositionFilters[peerId]
        ?? SpatialWorldPositionFilter()
      peerRawWorldTransforms[peerId] = transform
      peerRawWorldTransformUpdatedAt[peerId] = now
      peerWorldTransforms[peerId] = filter.filter(transform, at: now)
      peerWorldPositionFilters[peerId] = filter
      peerWorldTransformUpdatedAt[peerId] = now
      peerLastWorldTransformMeasurementAt[peerId] = now

      if peersWithSignpostedFirstWorldTransform.insert(peerId).inserted {
        SpatialPerformance.signposter.emitEvent(
          "First world transform received",
          "Peer: \(peerId.prefix(8), privacy: .public)"
        )
      }

      if !hadWorldTransform, !didSignpostFirstWorldTransform {
        didSignpostFirstWorldTransform = true
        let latencyMilliseconds = discoveryStartedAt.map {
          Int((now - $0) * 1_000)
        } ?? -1
        SpatialPerformance.signposter.emitEvent(
          "First world transform received",
          "Latency milliseconds: \(latencyMilliseconds)"
        )
      }
    }
    if let distance, distance.isFinite, distance > 0 {
      peerRawDistances[peerId] = distance
      peerRawDistanceUpdatedAt[peerId] = now
      peerLastDistanceMeasurementAt[peerId] = now
      if !didSignpostFirstDistance {
        didSignpostFirstDistance = true
        let latencyMilliseconds = discoveryStartedAt.map {
          Int((now - $0) * 1_000)
        } ?? -1
        SpatialPerformance.signposter.emitEvent(
          "First UWB distance latency",
          "Latency milliseconds: \(latencyMilliseconds)"
        )
      }

      var filter = peerDistanceDisplayFilters[peerId]
        ?? SpatialDistanceDisplayFilter()
      let display = filter.update(distance, at: now)
      peerDistanceDisplayFilters[peerId] = filter
      peerDistances[peerId] = display.distance
      peerDistanceUpdatedAt[peerId] = now
      peerDistanceUncertainty[peerId] = display.uncertainty
      var samples = peerDistanceSamples[peerId, default: []]
      samples.append(distance)
      if samples.count > SpatialMeasurementTuning.distanceMedianWindow {
        samples.removeFirst(
          samples.count - SpatialMeasurementTuning.distanceMedianWindow
        )
      }
      peerDistanceSamples[peerId] = samples
    }
  }

  /// Records the callback clock separately from measurement clocks. This is
  /// intentionally called once per NI callback, not once per nearby object.
  func recordPeerDelegateCallback(
    _ peerId: String,
    at now: CFTimeInterval,
    hasDistance: Bool,
    hasWorldTransform: Bool,
    hasDirection: Bool = false
  ) {
    withStateQueue {
      let role = rangingHealthRole
      let timing = SpatialRangingHealthPolicy.timing(for: role)
      var health = peerRangingHealth[peerId] ?? SpatialRangingHealth()
      let previousState = health.state
      let previousDistanceState = health.distanceState
      let wasRecovering = health.isRecovering || health.state == .degraded
      let wasDistanceRecovering = health.isDistanceRecovering
        || health.distanceState == .degraded
      let recoveryStartedAt = health.recoveryStartedAt
      let distanceRecoveryStartedAt = health.distanceRecoveryStartedAt
      let distanceLostAt = health.lastDistanceLostAt
      let usefulMeasurementLostAt = health.lastUsefulMeasurementLostAt
      let softRecoveryAttempts = health.softRecoveryAttempts
      let hardRecoveryAttempts = health.hardRecoveryAttempts
      let distanceSoftRecoveryAttempts = health.distanceSoftRecoveryAttempts
      let distanceHardRecoveryAttempts = health.distanceHardRecoveryAttempts
      let hasUsefulMeasurement = health.recordDelegateCallback(
        at: now,
        hasDistance: hasDistance,
        hasTransform: hasWorldTransform,
        healthyConfirmationCount: timing.recoveryHealthyConfirmationCount,
        hasDirection: hasDirection,
        distanceHealthyConfirmationCount: timing.distanceRecoveryHealthyConfirmationCount
      )
      peerRangingHealth[peerId] = health
      peerLastDelegateCallbackAt[peerId] = now
      if hasUsefulMeasurement {
        peerLastUsefulMeasurementAt[peerId] = now
        // Compatibility only; health and eviction never read this key.
        peerLastUpdatedAt[peerId] = now
      }

      if previousState != health.state {
        SpatialPerformance.signposter.emitEvent(
          "Ranging health transition",
          "Peer: \(peerId.prefix(8), privacy: .public), from: \(previousState.rawValue, privacy: .public), to: \(health.state.rawValue, privacy: .public), useful: \(hasUsefulMeasurement), distance: \(hasDistance), direction: \(hasDirection), transform: \(hasWorldTransform)"
        )
        if health.state == .healthy {
          SpatialPerformance.signposter.emitEvent(
            "Ranging health healthy",
            "Peer: \(peerId.prefix(8), privacy: .public), recovery latency milliseconds: \((usefulMeasurementLostAt ?? recoveryStartedAt).map { Int(max(0, now - $0) * 1_000) } ?? -1), useful confirmations: \(health.consecutiveUsefulUpdates)"
          )
          if wasRecovering {
            SpatialPerformance.signposter.emitEvent(
              "Ranging recovery succeeded",
              "Peer: \(peerId.prefix(8), privacy: .public), recovery latency milliseconds: \((usefulMeasurementLostAt ?? recoveryStartedAt).map { Int(max(0, now - $0) * 1_000) } ?? -1), soft attempts: \(softRecoveryAttempts), hard attempts: \(hardRecoveryAttempts)"
            )

            if previousState == .softRecovering {
              SpatialPerformance.signposter.emitEvent(
                "Soft recovery succeeded",
                "Peer: \(peerId.prefix(8), privacy: .public), recovery latency milliseconds: \((usefulMeasurementLostAt ?? recoveryStartedAt).map { Int(max(0, now - $0) * 1_000) } ?? -1), attempt: \(softRecoveryAttempts)"
              )
            } else if previousState == .renegotiating {
              SpatialPerformance.signposter.emitEvent(
                "Hard recovery succeeded",
                "Peer: \(peerId.prefix(8), privacy: .public), recovery latency milliseconds: \((usefulMeasurementLostAt ?? recoveryStartedAt).map { Int(max(0, now - $0) * 1_000) } ?? -1), attempt: \(hardRecoveryAttempts)"
              )
            }
          }
        }
      }

      if previousDistanceState != health.distanceState
      {
        SpatialPerformance.signposter.emitEvent(
          "Distance health transition",
          "Peer: \(peerId.prefix(8), privacy: .public), from: \(previousDistanceState.rawValue, privacy: .public), to: \(health.distanceState.rawValue, privacy: .public), distance age: \(String(format: "%.2f", health.distanceMeasurementAge(at: now)))"
        )
      }

      if previousDistanceState != health.distanceState,
        health.distanceState == .healthy,
        previousDistanceState != .acquiring
      {
        SpatialPerformance.signposter.emitEvent(
          "Distance recovery succeeded",
          "Peer: \(peerId.prefix(8), privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), distance age: \(String(format: "%.2f", health.distanceMeasurementAge(at: now))), recovery latency milliseconds: \((distanceRecoveryStartedAt ?? distanceLostAt).map { Int(max(0, now - $0) * 1_000) } ?? -1), soft attempts: \(distanceSoftRecoveryAttempts), hard attempts: \(distanceHardRecoveryAttempts), spatial state: \(health.state.rawValue, privacy: .public)"
        )
      } else if wasDistanceRecovering,
        health.isDistanceMeasurementHealthy(at: now, role: role)
      {
        // The state can already be `.healthy` when a brief distance dropout
        // recovers before the watchdog's degraded threshold is reached.
        SpatialPerformance.signposter.emitEvent(
          "Distance recovery succeeded",
          "Peer: \(peerId.prefix(8), privacy: .public), role: \(self.runtimeRole.rawValue, privacy: .public), distance age: \(String(format: "%.2f", health.distanceMeasurementAge(at: now))), recovery latency milliseconds: \((distanceRecoveryStartedAt ?? distanceLostAt).map { Int(max(0, now - $0) * 1_000) } ?? -1), soft attempts: \(distanceSoftRecoveryAttempts), hard attempts: \(distanceHardRecoveryAttempts), spatial state: \(health.state.rawValue, privacy: .public)"
        )
      }
    }
  }

  func updateCameraAssistanceState(
    _ state: SpatialCameraAssistanceState,
    for peerId: String
  ) {
    withStateQueue {
      peerCameraAssistanceStates[peerId] = state
    }
  }

  func clearPeerWorldTransform(for peerId: String) {
    withStateQueue {
      peerRawWorldTransforms.removeValue(forKey: peerId)
      peerRawWorldTransformUpdatedAt.removeValue(forKey: peerId)
      peerRawDirectionalMeasurements.removeValue(forKey: peerId)
      peerWorldTransforms.removeValue(forKey: peerId)
      peerWorldTransformUpdatedAt.removeValue(forKey: peerId)
      peerWorldPositionFilters.removeValue(forKey: peerId)
      peerRawDistances.removeValue(forKey: peerId)
      peerRawDistanceUpdatedAt.removeValue(forKey: peerId)
      peerDistances.removeValue(forKey: peerId)
      peerDistanceUpdatedAt.removeValue(forKey: peerId)
      peerDistanceUncertainty.removeValue(forKey: peerId)
      peerDistanceSamples.removeValue(forKey: peerId)
      peerDistanceDisplayFilters.removeValue(forKey: peerId)
      peerLastDelegateCallbackAt.removeValue(forKey: peerId)
      peerLastUsefulMeasurementAt.removeValue(forKey: peerId)
      peerLastDistanceMeasurementAt.removeValue(forKey: peerId)
      peerLastWorldTransformMeasurementAt.removeValue(forKey: peerId)
      peerLastDirectionMeasurementAt.removeValue(forKey: peerId)
      peerRangingHealth.removeValue(forKey: peerId)
      peersWithSignpostedStaleWorldTransform.remove(peerId)
      peersWithSignpostedStaleDistance.remove(peerId)
      peerCameraAssistanceSuppressed.remove(peerId)
      peerCameraAssistanceEnabled.removeValue(forKey: peerId)
      peerCameraAssistanceStates.removeValue(forKey: peerId)
      peerLastEmittedAt.removeValue(forKey: peerId)
      peerLastUpdatedAt.removeValue(forKey: peerId)
    }
  }

  /// Drops only render-side estimates during a hard NI replacement. Raw
  /// history remains available for diagnostics, but its timestamp/transaction
  /// gates prevent it from becoming fresh association evidence.
  func resetPeerDisplayState(for peerId: String) {
    withStateQueue {
      peerWorldTransforms.removeValue(forKey: peerId)
      peerWorldTransformUpdatedAt.removeValue(forKey: peerId)
      peerWorldPositionFilters.removeValue(forKey: peerId)
      peerDistances.removeValue(forKey: peerId)
      peerDistanceUpdatedAt.removeValue(forKey: peerId)
      peerDistanceUncertainty.removeValue(forKey: peerId)
      peerDistanceSamples.removeValue(forKey: peerId)
      peerDistanceDisplayFilters.removeValue(forKey: peerId)
    }
  }

  func clearPeerWorldTransforms() {
    withStateQueue {
      peerRawWorldTransforms.removeAll()
      peerRawWorldTransformUpdatedAt.removeAll()
      peerRawDirectionalMeasurements.removeAll()
      peerWorldTransforms.removeAll()
      peerWorldTransformUpdatedAt.removeAll()
      peerWorldPositionFilters.removeAll()
      peerRawDistances.removeAll()
      peerRawDistanceUpdatedAt.removeAll()
      peerDistances.removeAll()
      peerDistanceUpdatedAt.removeAll()
      peerDistanceUncertainty.removeAll()
      peerDistanceSamples.removeAll()
      peerDistanceDisplayFilters.removeAll()
      peerLastDelegateCallbackAt.removeAll()
      peerLastUsefulMeasurementAt.removeAll()
      peerLastDistanceMeasurementAt.removeAll()
      peerLastWorldTransformMeasurementAt.removeAll()
      peerLastDirectionMeasurementAt.removeAll()
      peersWithSignpostedStaleWorldTransform.removeAll()
      peersWithSignpostedStaleDistance.removeAll()
      peerCameraAssistanceEnabled.removeAll()
      peerCameraAssistanceStates.removeAll()
      peerCredentialLastEmittedAt.removeAll()
      peerLastEmittedAt.removeAll()
      peerLastUpdatedAt.removeAll()
    }
  }

  /// Removes AR/camera-assistance state without discarding a still-nearby
  /// peer's scalar UWB distance. This is used when the camera view leaves the
  /// window but the live-event presence channel remains active.
  func clearCameraSpatialState() {
    withStateQueue {
      peerRawWorldTransforms.removeAll()
      peerRawWorldTransformUpdatedAt.removeAll()
      peerRawDirectionalMeasurements.removeAll()
      peerWorldTransforms.removeAll()
      peerWorldTransformUpdatedAt.removeAll()
      peerWorldPositionFilters.removeAll()
      peerLastWorldTransformMeasurementAt.removeAll()
      peerLastDirectionMeasurementAt.removeAll()
      peersWithSignpostedStaleWorldTransform.removeAll()
      peerCameraAssistanceEnabled.removeAll()
      peerCameraAssistanceStates.removeAll()
      peerCameraInterests.removeAll()
    }
  }
}
