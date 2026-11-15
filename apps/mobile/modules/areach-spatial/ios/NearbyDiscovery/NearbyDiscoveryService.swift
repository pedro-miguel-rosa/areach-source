import ARKit
import CoreBluetooth
import CryptoKit
import Foundation
import NearbyInteraction
import Network
import QuartzCore
import simd

final class NearbyDiscoveryService: NSObject {
  static let serviceType = "_areach-uwb._tcp"
  static let initialRangingCapacity = 3
  static let peerEvictionGraceDuration: CFTimeInterval = 30

  let capabilityProfile = SpatialCapabilityProfile.current

  let stateQueue = DispatchQueue(label: "io.areach.spatial.nearby-state")
  private let stateQueueKey = DispatchSpecificKey<Void>()
  private let peerSnapshotCacheLock = NSLock()
  private var peerSnapshotCache: [NearbyPeerSpatialSnapshot] = []

  let localPeerId: String
  let signingPrivateKey: P256.Signing.PrivateKey
  let sendEvent: (String, [String: Any]) -> Void

  var listener: NWListener?
  var browser: NWBrowser?
  var connections: [String: NWConnection] = [:]
  var connectionPeerIds: [ObjectIdentifier: String] = [:]
  var discoveredEndpoints: [String: NWEndpoint] = [:]
  var receivingConnections = Set<ObjectIdentifier>()
  var authenticatedConnections = Set<ObjectIdentifier>()
  var connectionChallenges: [ObjectIdentifier: NearbyConnectionChallenge] = [:]
  var pendingConnectionProofs: [ObjectIdentifier: Data] = [:]
  var sentProofConnections = Set<ObjectIdentifier>()
  var browserReady = false
  var listenerReady = false
  var networkRestartAttempts = 0
  var networkRestartWorkItem: DispatchWorkItem?
  var lastSignpostedDiscoveredCount: Int?
  var discoveryStartedAt: CFTimeInterval?
  var didSignpostFirstBluetoothAdvertisement = false
  var didSignpostFirstBonjourDiscovery = false
  var didSignpostFirstAuthenticatedTransport = false
  var didSignpostFirstRangingTransaction = false
  var didSignpostFirstNIUpdate = false
  var didSignpostFirstCameraAssistance = false
  var didSignpostFirstCameraAssistanceConvergence = false
  var didSignpostFirstTransportDiscovery = false
  var didSignpostFirstIdentityResolution = false
  var didSignpostFirstWorldTransform = false
  var didSignpostFirstDistance = false
  var didSignpostCapabilityProfile = false
  var lastSignpostedExtendedDistancePeerId: String?
  var lastBluetoothNetworkRefreshAt: CFTimeInterval = 0
  var bluetoothWakeService: NearbyBluetoothWakeService?
  var bluetoothPeerIds = Set<String>()
  var peerBluetoothLastSeenAt: [String: CFTimeInterval] = [:]
  var peerEvictionTokens: [String: UUID] = [:]
  var discoveryExpiresAt: Date?
  var discoveryExpirationTimer: DispatchSourceTimer?
  var lastRangingTransportRefreshAt: CFTimeInterval = -.greatestFiniteMagnitude
  var lastRangingBonjourRefreshAt: CFTimeInterval = -.greatestFiniteMagnitude

  var localIdentity: NearbyPeerIdentity?
  var transportKey = ""
  var peerIdentities: [String: NearbyPeerIdentity] = [:]

  var nearbySessions: [String: NISession] = [:]
  var peerTokens: [String: NIDiscoveryToken] = [:]
  var activeRangingPeerIds = Set<String>()
  var pendingRangingPeerIds = Set<String>()
  var rangingStartedAt: [String: CFTimeInterval] = [:]
  var rangingRetryAfter: [String: CFTimeInterval] = [:]
  var peerLastRangedAt: [String: CFTimeInterval] = [:]
  /// Negotiation state is kept per peer rather than inferred from the
  /// scheduler's active/pending sets. Delayed transport messages can then be
  /// matched to the exact attempt that created them.
  var peerLinkStates: [String: SpatialPeerLinkState] = [:]
  var lastSignpostedMeasurementTiers: [String: String] = [:]
  /// Recent transaction IDs make duplicate control messages idempotent while
  /// remaining bounded for long-lived events.
  var observedRangingTransactions: [String: Set<UUID>] = [:]
  var peerCameraInterests: [String: SpatialCameraInterest] = [:]
  var peerLastCameraRelevantAt: [String: CFTimeInterval] = [:]
  var peerRangingPhases: [String: SpatialPeerRangingPhase] = [:]
  var peerProbeStartedAt: [String: CFTimeInterval] = [:]
  var peerProbeDeadlineAt: [String: CFTimeInterval] = [:]
  var peerFirstMeasurementAt: [String: CFTimeInterval] = [:]
  var peerFirstDistanceAt: [String: CFTimeInterval] = [:]
  var peerFirstProjectableMeasurementAt: [String: CFTimeInterval] = [:]
  var peerFirstUsefulMeasurementAt: [String: CFTimeInterval] = [:]
  var peerProbeCounts: [String: Int] = [:]
  var outboundRangingPeerIds = Set<String>()
  var peerSignalStrengths: [String: Double] = [:]
  var peersWithSuccessfulRanging = Set<String>()
  var peersWithSignpostedFirstNIUpdate = Set<String>()
  var peersWithSignpostedFirstDistance = Set<String>()
  var peersWithSignpostedFirstWorldTransform = Set<String>()
  /// Learned hardware/session capacity. This is separate from the number of
  /// sessions this role may proactively initiate.
  var hardwareSessionCapacity = initialRangingCapacity
  var didDiscoverRangingLimit = false
  var didDiscoverExtendedDistanceLimit = false
  var extendedDistancePeerId: String?
  var extendedDistanceCandidatePeerId: String?
  var extendedDistanceCandidateSince: CFTimeInterval?
  var extendedDistanceStartedAt: CFTimeInterval?
  var extendedDistanceLastUsefulAt: CFTimeInterval?
  var extendedDistanceCooldownUntil: [String: CFTimeInterval] = [:]
  var isAppActive = true
  var rangingMode = NearbyRangingMode.presence
  /// Owned by the native camera view lifecycle. JavaScript mode requests are
  /// retained only for backwards-compatible low-cost proximity behavior.
  private(set) var cameraConsumerCount = 0
  private(set) var presencePhase: SpatialPresencePhase = .idle
  private(set) var backgroundResponderState: SpatialBackgroundResponderState
  private(set) var runtimeRole: SpatialRuntimeRole = .suspended
  var rangingTimer: DispatchSourceTimer?
  var lastSignpostedRangingSummary: String?
  var lastSignpostedPresenceCount: Int?
  var peersWithSignpostedStaleWorldTransform = Set<String>()
  var peersWithSignpostedStaleDistance = Set<String>()
  var maximumDiscoveredPeerCount = 0
  var acquisitionQueueSize = 0
  var verificationPeerCount = 0
  var rangingRotationCount = 0
  var rangingRetryCount = 0
  var probePromotionCount = 0
  var probeEvictionCount = 0
  var probeTimeoutCount = 0
  var distanceOnlyMeasurementCount = 0
  var directionMeasurementCount = 0
  var cameraAssistedMeasurementCount = 0
  let rangingScheduler = SpatialRangingScheduler()

  /// The callback is installed by the native runtime. It is invoked on the
  /// state queue after the spatial state has been updated, and must return
  /// quickly so NI delegate callbacks are never blocked by camera fusion.
  var onUsefulRangingSample: ((SpatialRangingSample) -> Void)?
  var onDiscoveryExpired: (() -> Void)?

  /// Raw NI measurements are authoritative for health, scheduling, matching,
  /// and diagnostics. The legacy `peerWorldTransforms`/`peerDistances` names
  /// below intentionally remain the display values used by the render path.
  var peerRawWorldTransforms: [String: simd_float4x4] = [:]
  var peerRawWorldTransformUpdatedAt: [String: CFTimeInterval] = [:]
  var peerRawDirectionalMeasurements: [String: SpatialDirectionalMeasurement] = [:]
  var peerWorldTransforms: [String: simd_float4x4] = [:]
  var peerWorldTransformUpdatedAt: [String: CFTimeInterval] = [:]
  var peerWorldPositionFilters: [String: SpatialWorldPositionFilter] = [:]
  var peerRawDistances: [String: Float] = [:]
  var peerRawDistanceUpdatedAt: [String: CFTimeInterval] = [:]
  var peerDistances: [String: Float] = [:]
  var peerDistanceUpdatedAt: [String: CFTimeInterval] = [:]
  var peerDistanceUncertainty: [String: Float] = [:]
  var peerDistanceSamples: [String: [Float]] = [:]
  var peerDistanceDisplayFilters: [String: SpatialDistanceDisplayFilter] = [:]
  /// These clocks have deliberately different meanings. In particular, a
  /// callback with no usable measurement updates only the callback clock.
  var peerLastDelegateCallbackAt: [String: CFTimeInterval] = [:]
  var peerLastUsefulMeasurementAt: [String: CFTimeInterval] = [:]
  var peerLastDistanceMeasurementAt: [String: CFTimeInterval] = [:]
  var peerLastWorldTransformMeasurementAt: [String: CFTimeInterval] = [:]
  var peerLastDirectionMeasurementAt: [String: CFTimeInterval] = [:]
  var peerLastTransportPresenceAt: [String: CFTimeInterval] = [:]
  var peerLastAuthenticatedTransportAt: [String: CFTimeInterval] = [:]
  var peerRangingHealth: [String: SpatialRangingHealth] = [:]
  var peerCameraAssistanceSuppressed = Set<String>()
  var peerCameraAssistanceStates: [String: SpatialCameraAssistanceState] = [:]
  var peerCameraAssistanceEnabled: [String: Bool] = [:]
  var peerCredentialLastEmittedAt: [String: CFTimeInterval] = [:]
  var peerLastEmittedAt: [String: CFTimeInterval] = [:]
  /// Compatibility timestamp for older replay/diagnostic consumers. It is
  /// never used as the NI health clock or presence eviction clock.
  var peerLastUpdatedAt: [String: CFTimeInterval] = [:]
  var currentSessionState: (state: String, message: String?) = ("stopped", nil)

  weak var arSession: ARSession?
  private var arSessionIdentifier: ObjectIdentifier?
  private(set) var arTrackingState: SpatialARTrackingState = .unknown

  var localPublicKey: String {
    signingPrivateKey.publicKey.x963Representation.base64EncodedString()
  }

  static var isSupported: Bool {
    SpatialCapabilityProfile.current.nearbyInteractionSupported
  }

  init(
    sendEvent: @escaping (String, [String: Any]) -> Void,
    localPeerId: String,
    signingPrivateKey: P256.Signing.PrivateKey
  ) {
    self.localPeerId = localPeerId
    self.sendEvent = sendEvent
    self.signingPrivateKey = signingPrivateKey

    backgroundResponderState = capabilityProfile.backgroundResponderHardwareSupported
      ? .capabilityOnly
      : .unavailable

    super.init()

    stateQueue.setSpecific(key: stateQueueKey, value: ())
  }

  @discardableResult
  func start(
    eventScope: String,
    credential: String,
    transportKey: String,
    expiresAt: Double
  ) -> Bool {
    withStateQueue {
      if !didSignpostCapabilityProfile {
        didSignpostCapabilityProfile = true
        SpatialPerformance.signposter.emitEvent(
          "Spatial capability profile",
          "Profile: \(self.capabilityProfile.description, privacy: .public)"
        )
      }

      guard Self.isSupported else {
        emitState(
          "unsupported",
          message: "Nearby Interaction requires an iPhone with UWB direction support."
        )
        return false
      }

      guard
        !eventScope.isEmpty,
        !credential.isEmpty,
        !transportKey.isEmpty,
        let expirationDate = expirationDate(from: expiresAt)
      else {
        emitState("failed", message: "Nearby discovery credentials are unavailable.")
        return false
      }

      if localIdentity?.eventScope == eventScope,
        self.transportKey == transportKey
      {
        updateCredential(
          eventScope: eventScope,
          credential: credential,
          expiresAt: expiresAt
        )
        emitState("ready")
        return true
      }

      resetDiscovery()
      discoveryStartedAt = CACurrentMediaTime()
      SpatialPerformance.signposter.emitEvent("Nearby discovery started")
      transitionPresence(to: .credentialReady)

      localIdentity = NearbyPeerIdentity(
        credential: credential,
        eventScope: eventScope,
        publicKey: localPublicKey,
        userId: nil
      )
      self.transportKey = transportKey

      do {
        try startNetworkDiscovery()

        let bluetoothWakeService = NearbyBluetoothWakeService(
          queue: stateQueue,
          onMessageReceived: { [weak self] message in
            self?.handleBluetoothMessage(message)
          },
          onFirstAdvertisement: { [weak self] in
            self?.signpostFirstBluetoothAdvertisement()
          },
          onPeerSignalStrengthUpdated: { [weak self] peerId, signalStrength in
            self?.updatePeerSignalStrength(
              signalStrength,
              for: peerId
            )
          },
          onRemoteWakeReceived: { [weak self] in
            self?.refreshNetworkDiscoveryAfterBluetoothWake()
          }
        )
        self.bluetoothWakeService = bluetoothWakeService
        bluetoothWakeService.start(
          eventScope: eventScope,
          localPeerId: localPeerId,
          credential: credential,
          transportKey: transportKey,
          signingPrivateKey: signingPrivateKey
        )
        transitionPresence(to: .presenceReady)
        updateRuntimeRole()
        scheduleDiscoveryExpiration(at: expirationDate)

        if shouldRunProactiveRanging, runtimeRole.allowsProactiveRanging {
          startRangingScheduler()
        }

        // When the platform can support a background responder, remain in
        // presenceReady until the Activity coordinator confirms the
        // system-owned Live Activity. Devices without that path can enter
        // foreground presence immediately.
        if !capabilityProfile.backgroundResponderHardwareSupported
          || !capabilityProfile.liveActivityAuthorized
        {
          transitionPresence(to: .active)
        }
        emitState("searching")
        return true
      } catch {
        resetDiscovery()
        emitState("failed", message: error.localizedDescription)
        return false
      }
    }
  }

  func updateCredential(
    eventScope: String,
    credential: String,
    expiresAt: Double
  ) {
    withStateQueue {
      guard
        localIdentity?.eventScope == eventScope,
        !credential.isEmpty,
        let expirationDate = expirationDate(from: expiresAt)
      else {
        return
      }

      let credentialChanged = localIdentity?.credential != credential
      localIdentity = NearbyPeerIdentity(
        credential: credential,
        eventScope: eventScope,
        publicKey: localPublicKey,
        userId: nil
      )
      scheduleDiscoveryExpiration(at: expirationDate)

      updateAdvertisedIdentity()
      bluetoothWakeService?.updateCredential(credential)

      for connection in connections.values {
        sendHello(on: connection)
      }

      if credentialChanged {
        ensureDiscoveryTransport()
      }
    }
  }

  func resolvePeer(
    peerId: String,
    credential: String,
    publicKey: String,
    userId: String
  ) {
    withStateQueue {
      guard
        !userId.isEmpty,
        let identity = peerIdentities[peerId],
        identity.credential == credential,
        identity.publicKey == nil || identity.publicKey == publicKey
      else {
        return
      }

      let resolvedIdentity = identity.resolving(
        userId: userId,
        publicKey: publicKey
      )
      peerIdentities[peerId] = resolvedIdentity
      if !didSignpostFirstIdentityResolution {
        didSignpostFirstIdentityResolution = true
        let latencyMilliseconds = discoveryStartedAt.map {
          Int((CACurrentMediaTime() - $0) * 1_000)
        } ?? -1
        SpatialPerformance.signposter.emitEvent(
          "First identity resolution",
          "Latency milliseconds: \(latencyMilliseconds)"
        )
      }
      peerCredentialLastEmittedAt.removeValue(forKey: peerId)
      emitResolvedPeerPresence(peerId, identity: resolvedIdentity)
      authenticateConnections(with: peerId)
    }
  }

  func setRangingMode(_ rawMode: String) {
    withStateQueue {
      guard !expireDiscoveryIfNeeded() else {
        return
      }

      guard let mode = NearbyRangingMode(rawValue: rawMode) else {
        return
      }

      let didChangeMode = rangingMode != mode
      rangingMode = mode

      let previousRole = runtimeRole
      updateRuntimeRole()

      if didChangeMode, mode == .proximity {
        bluetoothWakeService?.refreshDiscovery()
      }

      // The same NI session can survive a tab change, but its configuration
      // must follow the role. In particular, returning to Camera must attach
      // the current AR session so direction/world-transform updates resume.
      if previousRole != runtimeRole {
        reconfigureActiveRangingSessions()
      }

      // A live event owns foreground proximity regardless of which tab is
      // visible. The mode remains source-compatible, but it must not be able
      // to tear down the event's only distance channel during navigation.
      if shouldRunProactiveRanging, runtimeRole.allowsProactiveRanging {
        startRangingScheduler()
        maintainRangingPool()
      }

      signpostRangingStateIfNeeded()
    }
  }

  func registerCameraConsumer() {
    withStateQueue {
      let previousRole = runtimeRole
      cameraConsumerCount += 1
      updateRuntimeRole()
      ensureDiscoveryTransport()
      if previousRole != runtimeRole {
        reconfigureActiveRangingSessions()
      }
      startRangingSchedulerIfNeeded()
      maintainRangingPoolIfNeeded()
    }
  }

  func unregisterCameraConsumer() {
    withStateQueue {
      let previousRole = runtimeRole
      cameraConsumerCount = max(0, cameraConsumerCount - 1)
      updateRuntimeRole()
      ensureDiscoveryTransport()

      guard cameraConsumerCount == 0 else {
        return
      }

      if previousRole != runtimeRole {
        // A camera view can be detached while a live event is still visible
        // on another screen. Re-run existing sessions without the old AR
        // session instead of invalidating the only UWB link.
        reconfigureActiveRangingSessions()
      }

      if runtimeRole == .foregroundProximity {
        startRangingSchedulerIfNeeded()
        maintainRangingPoolIfNeeded()
      } else if runtimeRole == .suspended {
        stopRangingScheduler()
        for peerId in Array(activeRangingPeerIds.union(pendingRangingPeerIds)) {
          endRanging(
            with: peerId,
            notifyPeer: true,
            reason: "camera-consumer-ended",
            preserveSpatialState: true
          )
        }
      }
    }
  }

  private func startRangingSchedulerIfNeeded() {
    guard
      shouldRunProactiveRanging,
      runtimeRole.allowsProactiveRanging
    else {
      return
    }
    startRangingScheduler()
  }

  private func maintainRangingPoolIfNeeded() {
    guard
      shouldRunProactiveRanging,
      runtimeRole.allowsProactiveRanging
    else {
      return
    }
    maintainRangingPool()
  }

  func setAppActive(_ isActive: Bool) {
    withStateQueue {
      guard !expireDiscoveryIfNeeded() else {
        return
      }

      guard isAppActive != isActive else {
        return
      }

      isAppActive = isActive
      updateRuntimeRole()

      if isActive {
        ensureDiscoveryTransport()
      }

      if runtimeRole == .backgroundResponder || runtimeRole == .suspended {
        let peersToEnd = runtimeRole == .backgroundResponder
          ? outboundRangingPeerIds.union(pendingRangingPeerIds)
          : activeRangingPeerIds.union(pendingRangingPeerIds)
        for peerId in peersToEnd {
          endRanging(
            with: peerId,
            notifyPeer: true,
            reason: runtimeRole == .backgroundResponder
              ? "background-responder"
              : "background-responder-unavailable",
            preserveSpatialState: true
          )
        }
        if runtimeRole == .backgroundResponder {
          startRangingScheduler()
        } else {
          stopRangingScheduler()
        }
      }

      for peerId in activeRangingPeerIds where runtimeRole != .suspended {
        if let token = peerTokens[peerId] {
          runNearbySession(for: peerId, token: token)
        }
      }

      SpatialPerformance.signposter.emitEvent(
        isActive ? "Nearby discovery foregrounded" : "Nearby discovery backgrounded"
      )

      if isActive, shouldRunProactiveRanging,
        runtimeRole.allowsProactiveRanging
      {
        startRangingScheduler()
        maintainRangingPool()
      }
    }
  }

  func stop() {
    withStateQueue {
      resetDiscovery()
      rangingMode = .presence
      runtimeRole = SpatialRuntimeRole(
        isAppActive: isAppActive,
        cameraConsumerActive: cameraConsumerCount > 0,
        activeLiveEventPresence: localIdentity != nil,
        backgroundResponderActive: backgroundResponderState == .active
      )
      emitState("stopped")
    }
  }

  /// The Live Activity layer reports whether its lifecycle request actually
  /// produced an active instance. Capability alone never promotes a locked
  /// device to a background responder.
  @discardableResult
  func setBackgroundResponderActive(_ active: Bool) -> Bool {
    withStateQueue {
      let canActivate = active
        && capabilityProfile.backgroundResponderHardwareSupported
        && capabilityProfile.liveActivityAuthorized
        && localIdentity != nil
        && bluetoothWakeService != nil
        && discoveryExpiresAt.map { $0 > Date() } == true
      if canActivate {
        backgroundResponderState = .active
        transitionPresence(to: .backgroundCapable)
      } else if capabilityProfile.backgroundResponderHardwareSupported {
        backgroundResponderState = .capabilityOnly
        if localIdentity != nil,
          presencePhase != .idle,
          presencePhase != .stopping
        {
          transitionPresence(to: .active)
        }
      } else {
        backgroundResponderState = .unavailable
        if localIdentity != nil,
          presencePhase != .idle,
          presencePhase != .stopping
        {
          transitionPresence(to: .active)
        }
      }

      SpatialPerformance.signposter.emitEvent(
        "Background responder state",
        "State: \(self.backgroundResponderState.rawValue, privacy: .public), hardware: \(self.capabilityProfile.backgroundResponderHardwareSupported), live activity authorization: \(self.capabilityProfile.liveActivityAuthorized)"
      )

      let previousRole = runtimeRole
      updateRuntimeRole()
      guard previousRole != runtimeRole else {
        return backgroundResponderState == .active
      }

      if runtimeRole == .suspended {
        for peerId in activeRangingPeerIds.union(pendingRangingPeerIds) {
          endRanging(
            with: peerId,
            notifyPeer: true,
            reason: "background-responder-unavailable",
            preserveSpatialState: true
          )
        }
        stopRangingScheduler()
      } else if runtimeRole == .backgroundResponder {
        // The passive responder keeps a health monitor for inbound NI
        // sessions, but never acquires outbound ranging slots.
        startRangingScheduler()
      } else if shouldRunProactiveRanging,
        runtimeRole.allowsProactiveRanging
      {
        startRangingScheduler()
        maintainRangingPool()
      }

      return backgroundResponderState == .active
    }
  }

  func isBackgroundResponderActive() -> Bool {
    withStateQueue {
      backgroundResponderState == .active
    }
  }

  private func updateRuntimeRole() {
    runtimeRole = SpatialRuntimeRole(
      isAppActive: isAppActive,
      cameraConsumerActive: cameraConsumerCount > 0,
      activeLiveEventPresence: localIdentity != nil,
      backgroundResponderActive: backgroundResponderState == .active
    )
    bluetoothWakeService?.setDiscoveryIntensity(
      intensity: runtimeRole == .cameraViewer
        ? .cameraAcquisition
        : runtimeRole == .backgroundResponder
          ? .backgroundPassive
          : .foregroundNormal
    )

    SpatialPerformance.signposter.emitEvent(
      "Nearby runtime role",
      "Role: \(self.runtimeRole.rawValue, privacy: .public)"
    )
  }

  /// Camera visibility and active event presence are native facts. The old
  /// JavaScript ranging mode is retained for source compatibility and
  /// diagnostics, but it is not allowed to disable foreground proximity.
  var shouldRunProactiveRanging: Bool {
    localIdentity != nil
      && (cameraConsumerCount > 0 || runtimeRole == .foregroundProximity)
  }

  /// Reconciles transport and scheduler prerequisites after an actual native
  /// lifecycle transition. Credential refreshes intentionally do not call
  /// this: the live-event heartbeat is for attendance, not a discovery
  /// polling workaround.
  func ensureDiscoveryTransport() {
    withStateQueue {
      guard localIdentity != nil else {
        return
      }

      if (listener == nil || browser == nil), networkRestartWorkItem == nil {
        stopNetworkDiscovery(cancelRestart: false)
        do {
          try startNetworkDiscovery()
        } catch {
          emitState(
            "waiting",
            message: "Nearby discovery is reconnecting. \(error.localizedDescription)"
          )
          return
        }
      }

      updateRuntimeRole()
      if localIdentity != nil, runtimeRole != .suspended {
        startRangingScheduler()
      }
      if shouldRunProactiveRanging, runtimeRole.allowsProactiveRanging {
        startRangingScheduler()
        maintainRangingPool()
      }
    }
  }

  private func reconfigureActiveRangingSessions() {
    for peerId in activeRangingPeerIds {
      guard let token = peerTokens[peerId] else {
        continue
      }

      runNearbySession(for: peerId, token: token)
    }

    SpatialPerformance.signposter.emitEvent(
      "Active ranging sessions reconfigured",
      "Role: \(self.runtimeRole.rawValue, privacy: .public), count: \(self.activeRangingPeerIds.count)"
    )
  }

  func setARSession(_ session: ARSession?) {
    withStateQueue {
      let didChangeSession: Bool
      if let session {
        didChangeSession = arSessionIdentifier != ObjectIdentifier(session)
        arSessionIdentifier = ObjectIdentifier(session)
      } else {
        didChangeSession = arSessionIdentifier != nil
        arSessionIdentifier = nil
      }
      arSession = session

      guard session != nil else {
        arTrackingState = .unknown
        // The camera coordinate system is gone, but proximity ranging may
        // continue while another live-event screen is visible. Preserve the
        // scalar distance/presence state and only clear camera-specific data.
        clearCameraSpatialState()
        return
      }

      if didChangeSession {
        // World transforms belong to the AR world map that produced them.
        // Preserve scalar UWB presence, but force a fresh projectable sample
        // after a camera/session replacement.
        peerCameraAssistanceSuppressed.removeAll()
        clearCameraSpatialState()
      }

      ensureDiscoveryTransport()

      for peerId in activeRangingPeerIds {
        if let token = peerTokens[peerId] {
          runNearbySession(for: peerId, token: token)
        }
      }
    }
  }

  func updateARTrackingState(_ trackingState: ARCamera.TrackingState) {
    let state: SpatialARTrackingState
    switch trackingState {
    case .normal:
      state = .normal
    case .limited:
      state = .limited
    case .notAvailable:
      state = .notAvailable
    @unknown default:
      state = .unknown
    }

    withStateQueue {
      let previousState = arTrackingState
      arTrackingState = state
      if state != .normal {
        // AR pose loss must hide stale camera positions, but it must not tear
        // down NI distance or the authenticated transport.
        clearCameraSpatialState()
      } else if previousState != .normal {
        reconfigureActiveRangingSessions()
      }
      SpatialPerformance.signposter.emitEvent(
        "AR tracking state",
        "State: \(state.rawValue, privacy: .public), previous: \(previousState.rawValue, privacy: .public)"
      )
    }
  }

  func notifyARSessionInterruptionEnded() {
    withStateQueue {
      guard arSession != nil else {
        return
      }

      reconfigureActiveRangingSessions()
      SpatialPerformance.signposter.emitEvent(
        "AR session interruption ended",
        "Ranging sessions reattached: \(self.activeRangingPeerIds.count)"
      )
    }
  }

  func notifyARSessionInterrupted() {
    withStateQueue {
      arTrackingState = .interrupted
      clearCameraSpatialState()
      SpatialPerformance.signposter.emitEvent("AR session interrupted")
    }
  }

  func updatePeerSignalStrength(
    _ signalStrength: Int,
    for peerId: String
  ) {
    withStateQueue {
      guard signalStrength != Int.min else {
        return
      }

      let measuredSignalStrength = Double(signalStrength)
      let previousSignalStrength = peerSignalStrengths[peerId]
      let now = CACurrentMediaTime()
      cancelPeerEviction(for: peerId)
      bluetoothPeerIds.insert(peerId)
      peerBluetoothLastSeenAt[peerId] = now
      markPeerTransportPresence(for: peerId, at: now)
      peerSignalStrengths[peerId] =
        previousSignalStrength.map {
          $0 * 0.7 + measuredSignalStrength * 0.3
        } ?? measuredSignalStrength

      schedulePeerEviction(
        for: peerId,
        reason: "bluetooth-recovery-timed-out"
      )

      if previousSignalStrength == nil {
        SpatialPerformance.signposter.emitEvent(
          "Bluetooth peer signal mapped",
          "RSSI: \(signalStrength)"
        )
      }

      if shouldRunProactiveRanging, runtimeRole.allowsProactiveRanging {
        maintainRangingPool()
      }
    }
  }

  func withStateQueue<T>(_ operation: () -> T) -> T {
    if DispatchQueue.getSpecific(key: stateQueueKey) != nil {
      return operation()
    }

    return stateQueue.sync(execute: operation)
  }

  func updatePeerSnapshotCache(_ snapshots: [NearbyPeerSpatialSnapshot]) {
    peerSnapshotCacheLock.lock()
    peerSnapshotCache = snapshots
    peerSnapshotCacheLock.unlock()
  }

  func cachedPeerSpatialSnapshots() -> [NearbyPeerSpatialSnapshot] {
    peerSnapshotCacheLock.lock()
    defer { peerSnapshotCacheLock.unlock() }
    return peerSnapshotCache
  }

  func isPeerTransportNearby(_ peerId: String) -> Bool {
    discoveredEndpoints[peerId] != nil
      || connections[peerId] != nil
      || peerLastTransportPresenceAt[peerId].map {
        CACurrentMediaTime() - $0 <= Self.peerEvictionGraceDuration
      } == true
      || peerBluetoothLastSeenAt[peerId].map {
        CACurrentMediaTime() - $0 <= Self.peerEvictionGraceDuration
      } == true
  }

  func markPeerTransportPresence(
    for peerId: String,
    authenticated: Bool = false,
    at now: CFTimeInterval = CACurrentMediaTime()
  ) {
    withStateQueue {
      guard !peerId.isEmpty, now.isFinite else {
        return
      }

      cancelPeerEviction(for: peerId)
      peerLastTransportPresenceAt[peerId] = now
      if authenticated {
        peerLastAuthenticatedTransportAt[peerId] = now
      }
    }
  }

  private func resetDiscovery() {
    transitionPresence(to: .stopping)
    discoveryExpirationTimer?.cancel()
    discoveryExpirationTimer = nil
    bluetoothWakeService?.stop()
    bluetoothWakeService = nil
    stopRangingScheduler()
    stopNetworkDiscovery()
    resetRanging()

    localIdentity = nil
    transportKey = ""
    discoveryExpiresAt = nil
    lastBluetoothNetworkRefreshAt = 0
    lastRangingTransportRefreshAt = -.greatestFiniteMagnitude
    lastRangingBonjourRefreshAt = -.greatestFiniteMagnitude
    peerIdentities.removeAll()
    bluetoothPeerIds.removeAll()
    peerBluetoothLastSeenAt.removeAll()
    peerLastTransportPresenceAt.removeAll()
    peerLastAuthenticatedTransportAt.removeAll()
    peerSignalStrengths.removeAll()
    peerCameraInterests.removeAll()
    peerLastCameraRelevantAt.removeAll()
    peerCredentialLastEmittedAt.removeAll()
    backgroundResponderState = capabilityProfile.backgroundResponderHardwareSupported
      ? .capabilityOnly
      : .unavailable
    discoveryStartedAt = nil
    didSignpostFirstBluetoothAdvertisement = false
    didSignpostFirstBonjourDiscovery = false
    didSignpostFirstAuthenticatedTransport = false
    didSignpostFirstRangingTransaction = false
    didSignpostFirstNIUpdate = false
    didSignpostFirstCameraAssistance = false
    didSignpostFirstCameraAssistanceConvergence = false
    didSignpostFirstTransportDiscovery = false
    didSignpostFirstIdentityResolution = false
    didSignpostFirstWorldTransform = false
    didSignpostFirstDistance = false
    lastSignpostedExtendedDistancePeerId = nil
    cancelAllPeerEvictions()
    clearPeerWorldTransforms()
    updatePeerSnapshotCache([])
    currentSessionState = ("stopped", nil)
    transitionPresence(to: .idle)
  }

  private func transitionPresence(to nextPhase: SpatialPresencePhase) {
    guard presencePhase != nextPhase else {
      return
    }

    let previousPhase = presencePhase
    presencePhase = nextPhase
    SpatialPerformance.signposter.emitEvent(
      "Nearby presence phase",
      "From: \(previousPhase.rawValue, privacy: .public), to: \(nextPhase.rawValue, privacy: .public)"
    )
  }

  private func expirationDate(from millisecondsSince1970: Double) -> Date? {
    guard millisecondsSince1970.isFinite else {
      return nil
    }

    let expirationDate = Date(
      timeIntervalSince1970: millisecondsSince1970 / 1000
    )
    return expirationDate > Date() ? expirationDate : nil
  }

  private func scheduleDiscoveryExpiration(at expirationDate: Date) {
    discoveryExpirationTimer?.cancel()
    discoveryExpiresAt = expirationDate

    let timer = DispatchSource.makeTimerSource(queue: stateQueue)
    timer.schedule(
      deadline: .now() + max(0, expirationDate.timeIntervalSinceNow),
      leeway: .seconds(1)
    )
    timer.setEventHandler { [weak self] in
      self?.expireDiscoveryIfNeeded()
    }
    discoveryExpirationTimer = timer
    timer.resume()
  }

  @discardableResult
  func expireDiscoveryIfNeeded() -> Bool {
    guard
      let discoveryExpiresAt,
      discoveryExpiresAt <= Date()
    else {
      return false
    }

    SpatialPerformance.signposter.emitEvent(
      "Nearby discovery expired"
    )
    resetDiscovery()
    onDiscoveryExpired?()
    rangingMode = .presence
    emitState("stopped", message: "Live event ended.")
    return true
  }
}

enum NearbyRangingMode: String {
  case camera
  case presence
  case proximity
}
