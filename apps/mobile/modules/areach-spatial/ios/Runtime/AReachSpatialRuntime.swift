import ARKit
import CryptoKit
import Foundation
import QuartzCore
import Security
import UIKit
import os
import simd

enum SpatialPerformance {
  static let signposter = OSSignposter(
    subsystem: "io.areach.spatial",
    category: .pointsOfInterest
  )
}

final class AReachSpatialRuntime {
  static let shared = AReachSpatialRuntime()

  private struct SpatialProbeContext {
    let bodies: [SpatialBodyDetection]
    let verifiedPeerIds: Set<String>
    let tentativePeerIds: Set<String>
  }

  var sendEvent: ((String, [String: Any]) -> Void)?

  private let sessionStore = NearbyDiscoverySessionStore()
  private lazy var nearbyDiscoveryService: NearbyDiscoveryService = {
    let service = NearbyDiscoveryService(
      sendEvent: { [weak self] eventName, payload in
        self?.sendEvent?(eventName, payload)
      },
      localPeerId: sessionStore.peerId,
      signingPrivateKey: sessionStore.signingPrivateKey
    )
    service.onUsefulRangingSample = { [weak self] sample in
      self?.handleUsefulRangingSample(sample)
    }
    service.onDiscoveryExpired = { [weak self] in
      self?.sessionStore.clearActiveSession()
      self?.sessionStore.clearBackgroundResponderActive()
    }
    return service
  }()

  private let arContext = ARContext()
  private let targetMatcher = SpatialTargetMatcher()
  private let cameraInterestEstimator = SpatialCameraInterestEstimator()
  private let probeCameraInterestEstimator = SpatialCameraInterestEstimator()
  #if DEBUG
    private let replayRecorder = SpatialReplayRecorder()
  #endif
  private let fusionQueue = DispatchQueue(
    label: "io.areach.spatial.fusion",
    qos: .userInitiated
  )
  private let probeFeedbackQueue = DispatchQueue(
    label: "io.areach.spatial.probe-feedback",
    qos: .userInitiated
  )
  private let renderStateLock = NSLock()
  private let instrumentationLock = NSLock()
  private let probeContextLock = NSLock()
  private let associationUncertaintyLock = NSLock()
  private var renderStates: [SpatialRenderTargetState] = []
  private var renderGeneration: UInt64 = 0
  private var cameraSessionStartedAt: CFTimeInterval?
  private var firstOverlayAcquiredAt: CFTimeInterval?
  private var lastOverlayLostAt: CFTimeInterval?
  private var maximumDetectedBodyCount = 0
  private var maximumVisibleTargetCount = 0
  private var overlayLossCount = 0
  private var overlayReacquisitionCount = 0
  private var overlayReacquisitionDuration: CFTimeInterval = 0
  private var previousVisiblePeerIds = Set<String>()
  private var processedVisionFrameCount = 0
  private var lastSignpostedPeerCount: Int?
  private var lastSignpostedResolvedPeerCount: Int?
  private var lastSignpostedTargetCount: Int?
  private var lastSignpostedFusionSummary: String?
  private var lastSignpostedBodyDuplicateSummary: String?
  private var hasSpatialInputs = false
  #if DEBUG
    private var didSignpostFirstDebugPhoneMarker = false
  #endif
  /// Queue-confined immutable hand-off between peer, body, and association
  /// subsystems. JavaScript never receives this graph.
  private var latestWorldSnapshot: SpatialWorldSnapshot?
  private var probeContext: SpatialProbeContext?
  private var currentAssociationUncertainty: SpatialAssociationUncertainty = .uncertain

  private init() {}

  func prepareNearbyDiscoveryForLaunch(
    restoringInBackground: Bool
  ) {
    guard restoringInBackground else {
      sessionStore.clearActiveSession()
      sessionStore.clearBackgroundResponderActive()
      return
    }

    restoreNearbyDiscoveryIfNeeded()
  }

  private func restoreNearbyDiscoveryIfNeeded() {
    guard let session = sessionStore.activeSession else {
      sessionStore.clearBackgroundResponderActive()
      return
    }

    guard session.expiresAt > Date().timeIntervalSince1970 * 1_000 else {
      sessionStore.clearActiveSession()
      sessionStore.clearBackgroundResponderActive()
      return
    }

    guard
      nearbyDiscoveryService.start(
        eventScope: session.eventScope,
        credential: session.credential,
        transportKey: session.transportKey,
        expiresAt: session.expiresAt
      )
    else {
      sessionStore.clearActiveSession()
      sessionStore.clearBackgroundResponderActive()
      return
    }

    if sessionStore.backgroundResponderActive {
      let restored = nearbyDiscoveryService.setBackgroundResponderActive(true)
      if !restored {
        // ActivityKit authorization, the discovery credential, or the local
        // identity may have changed while the app was suspended. Do not leave
        // a persisted flag claiming that the passive responder is active.
        sessionStore.clearBackgroundResponderActive()
      }
    }
  }

  func nearbyIdentity() -> [String: String] {
    [
      "peerId": nearbyDiscoveryService.localPeerId,
      "publicKey": nearbyDiscoveryService.localPublicKey,
    ]
  }

  func nearbyPeerPresenceSnapshot() -> [[String: Any]] {
    nearbyDiscoveryService.nearbyPeerPresenceSnapshot()
  }

  func nearbyCredentialSnapshot() -> [[String: Any]] {
    nearbyDiscoveryService.nearbyCredentialSnapshot()
  }

  func nearbySessionStateSnapshot() -> [String: Any] {
    nearbyDiscoveryService.nearbySessionStateSnapshot()
  }

  func startNearbyDiscovery(
    eventScope: String,
    credential: String,
    transportKey: String,
    expiresAt: Double
  ) throws {
    // The preview starts discovery before navigating to the live camera. The
    // live layout then reconciles the same native session. Do not clear the
    // first spatial acquisition just because that reconciliation calls start
    // again; only a genuinely different event/transport needs a matcher reset.
    let startsDifferentSession = sessionStore.activeSession.map { session in
      session.eventScope != eventScope || session.transportKey != transportKey
    } ?? true
    if startsDifferentSession {
      resetTargetMatcher()
    }
    guard
      nearbyDiscoveryService.start(
        eventScope: eventScope,
        credential: credential,
        transportKey: transportKey,
        expiresAt: expiresAt
      )
    else {
      sessionStore.clearActiveSession()
      sessionStore.clearBackgroundResponderActive()
      throw NearbyDiscoveryStartError()
    }

    sessionStore.saveActiveSession(
      NearbyDiscoverySession(
        credential: credential,
        eventScope: eventScope,
        expiresAt: expiresAt,
        transportKey: transportKey
      )
    )
  }

  func updateNearbyDiscoveryCredential(
    eventScope: String,
    credential: String,
    expiresAt: Double
  ) {
    if let session = sessionStore.activeSession,
      session.eventScope == eventScope
    {
      sessionStore.saveActiveSession(
        NearbyDiscoverySession(
          credential: credential,
          eventScope: eventScope,
          expiresAt: expiresAt,
          transportKey: session.transportKey
        )
      )
    }
    nearbyDiscoveryService.updateCredential(
      eventScope: eventScope,
      credential: credential,
      expiresAt: expiresAt
    )
  }

  func resolveNearbyPeer(
    peerId: String,
    credential: String,
    publicKey: String,
    userId: String
  ) {
    nearbyDiscoveryService.resolvePeer(
      peerId: peerId,
      credential: credential,
      publicKey: publicKey,
      userId: userId
    )
  }

  func setNearbyRangingMode(_ mode: String) {
    nearbyDiscoveryService.setRangingMode(mode)
  }

  func registerCameraConsumer() {
    nearbyDiscoveryService.registerCameraConsumer()
  }

  func unregisterCameraConsumer() {
    nearbyDiscoveryService.unregisterCameraConsumer()
  }

  @discardableResult
  func setBackgroundResponderActive(_ active: Bool) -> Bool {
    let isActive = nearbyDiscoveryService.setBackgroundResponderActive(active)
    sessionStore.saveBackgroundResponderActive(isActive)
    return isActive
  }

  func isBackgroundResponderActive() -> Bool {
    nearbyDiscoveryService.isBackgroundResponderActive()
  }

  func setNearbyDiscoveryAppActive(_ isActive: Bool) {
    nearbyDiscoveryService.setAppActive(isActive)
  }

  func stopNearbyDiscovery() {
    sessionStore.clearActiveSession()
    sessionStore.clearBackgroundResponderActive()
    finishCameraMetricsAndResetMatcher()
    nearbyDiscoveryService.stop()
  }

  func setARSession(
    _ session: ARSession?,
    viewportSize: CGSize,
    orientation: UIInterfaceOrientation
  ) {
    dispatchPrecondition(condition: .onQueue(.main))

    arContext.setARSession(
      session,
      viewportSize: viewportSize,
      orientation: orientation
    )
    nearbyDiscoveryService.setARSession(session)

    fusionQueue.async { [weak self] in
      guard let self else {
        return
      }

      if session == nil {
        self.finishCameraMetrics()
        self.targetMatcher.reset()
        self.storeProbeContext(
          bodies: [],
          verifiedPeerIds: [],
          tentativePeerIds: []
        )
        self.setAssociationUncertainty(.uncertain)
        self.latestWorldSnapshot = nil
        self.hasSpatialInputs = false
        self.advanceRenderGeneration()
        self.publishRenderStates([])
      } else {
        self.storeProbeContext(
          bodies: [],
          verifiedPeerIds: [],
          tentativePeerIds: []
        )
        self.setAssociationUncertainty(.uncertain)
        self.advanceRenderGeneration()
        self.publishRenderStates([])
        self.hasSpatialInputs = false
        self.beginCameraMetrics()
      }
    }
  }

  func updateViewport(size: CGSize, orientation: UIInterfaceOrientation) {
    dispatchPrecondition(condition: .onQueue(.main))
    arContext.updateViewport(size: size, orientation: orientation)
  }

  func viewportSnapshot() -> SpatialViewportSnapshot {
    arContext.viewportSnapshot()
  }

  func updateARCamera(_ camera: ARCamera) {
    arContext.updateCamera(camera)
  }

  func updateARTrackingState(_ trackingState: ARCamera.TrackingState) {
    nearbyDiscoveryService.updateARTrackingState(trackingState)
  }

  func notifyARSessionInterruptionEnded() {
    nearbyDiscoveryService.notifyARSessionInterruptionEnded()
  }

  func notifyARSessionInterrupted() {
    nearbyDiscoveryService.notifyARSessionInterrupted()
  }

  func associationUncertainty() -> SpatialAssociationUncertainty {
    associationUncertaintyLock.lock()
    defer { associationUncertaintyLock.unlock() }
    return currentAssociationUncertainty
  }

  private func setAssociationUncertainty(
    _ uncertainty: SpatialAssociationUncertainty
  ) {
    associationUncertaintyLock.lock()
    currentAssociationUncertainty = uncertainty
    associationUncertaintyLock.unlock()
  }

  private func storeProbeContext(
    bodies: [SpatialBodyDetection],
    verifiedPeerIds: Set<String>,
    tentativePeerIds: Set<String>
  ) {
    probeContextLock.lock()
    probeContext = SpatialProbeContext(
      bodies: bodies,
      verifiedPeerIds: verifiedPeerIds,
      tentativePeerIds: tentativePeerIds
    )
    probeContextLock.unlock()
  }

  private func currentProbeContext() -> SpatialProbeContext? {
    probeContextLock.lock()
    defer { probeContextLock.unlock() }
    return probeContext
  }

  /// NI delegate callbacks arrive on the nearby state queue. Camera-interest
  /// estimation is intentionally handed to a separate native queue so a fast
  /// probe cannot wait behind a full body/matcher pass or block the NI state
  /// machine.
  private func handleUsefulRangingSample(_ sample: SpatialRangingSample) {
    probeFeedbackQueue.async { [weak self] in
      guard let self,
        sample.hasWorldTransform
          || sample.hasDirectionalMeasurement
          || sample.hasDistance
      else {
        return
      }

      let now = CACurrentMediaTime()
      let viewport = self.arContext.viewportSnapshot()
      guard viewport.isUsable, let projection = self.arContext.projectionSnapshot()
      else {
        return
      }

      let context = self.currentProbeContext()
      let peers = self.nearbyDiscoveryService.peerSpatialSnapshots()
      guard !peers.isEmpty else {
        return
      }

      let world = SpatialWorldSnapshot(
        viewer: SpatialViewerState(
          cameraTransform: projection.camera.transform,
          cameraProjectionMatrix: Self.cameraProjectionMatrix(
            for: projection.camera,
            orientation: viewport.orientation,
            viewportSize: viewport.size
          ),
          viewport: viewport,
          trackingQuality: Self.viewerTrackingQuality(
            projection.camera.trackingState
          ),
          timestamp: now,
          cameraHorizontalProjectionScale: Self.horizontalProjectionScale(
            for: projection.camera,
            orientation: viewport.orientation,
            viewportSize: viewport.size
          )
        ),
        peers: peers,
        bodies: context?.bodies ?? [],
        associations: [],
        timestamp: now
      )
      let interests = self.probeCameraInterestEstimator.estimate(
        world: world,
        verifiedPeerIds: context?.verifiedPeerIds ?? [],
        tentativePeerIds: context?.tentativePeerIds ?? [],
        now: now,
        viewport: viewport,
        projectAtCapture: { worldTransform in
          self.arContext.project(
            worldPosition: Self.worldPosition(from: worldTransform),
            using: projection
          )
        }
      )
      self.nearbyDiscoveryService.updateCameraInterest(
        interests,
        evaluatedPeerIds: Set(peers.map(\.peerId))
      )
    }
  }

  private func deriveAssociationUncertainty(
    detectionCount: Int,
    targetCount: Int,
    ambiguousRejectionsBefore: Int
  ) -> SpatialAssociationUncertainty {
    let rejectedAmbiguity = targetMatcher.ambiguousMatchRejectionCount
      > ambiguousRejectionsBefore
    let hasTentativeAssociation = !targetMatcher.tentativePeerIds.isEmpty
    let hasCompetingPairs = targetMatcher.lastGatedCandidatePairCount > 1
      && detectionCount > 1

    if rejectedAmbiguity || hasCompetingPairs {
      return .highlyAmbiguous
    }

    if hasTentativeAssociation
      || (detectionCount > 0 && targetCount == 0)
    {
      return .uncertain
    }

    return .stable
  }

  func processDetections(
    for detections: [SpatialBodyDetection],
    peers: [NearbyPeerSpatialSnapshot],
    sourceCamera: ARCamera,
    viewportSize: CGSize,
    orientation: UIInterfaceOrientation,
    bodyDiagnostics: SpatialBodyPipelineDiagnostics,
    completion: @escaping (
      [SpatialMatchedTarget],
      UInt64,
      SpatialBodyPipelineDiagnostics
    ) -> Void
  ) {
    fusionQueue.async { [weak self] in
      guard let self else {
        return
      }

      let interval = SpatialPerformance.signposter.beginInterval(
        "Target matching"
      )
      let now = CACurrentMediaTime()
      let processingGeneration = self.currentRenderGeneration()
      self.hasSpatialInputs = true
      let viewport = SpatialViewportSnapshot(
        size: viewportSize,
        orientation: orientation,
        version: 0,
        updatedAt: now
      )
      let world = SpatialWorldSnapshot(
        viewer: SpatialViewerState(
          cameraTransform: sourceCamera.transform,
          cameraProjectionMatrix: Self.cameraProjectionMatrix(
            for: sourceCamera,
            orientation: orientation,
            viewportSize: viewportSize
          ),
          viewport: viewport,
          trackingQuality: Self.viewerTrackingQuality(
            sourceCamera.trackingState
          ),
          timestamp: now,
          cameraHorizontalProjectionScale: Self.horizontalProjectionScale(
            for: sourceCamera,
            orientation: orientation,
            viewportSize: viewportSize
          )
        ),
        peers: peers,
        bodies: detections,
        associations: [],
        timestamp: now
      )
      self.latestWorldSnapshot = world
      self.storeProbeContext(
        bodies: detections,
        verifiedPeerIds: self.targetMatcher.verifiedPeerIds,
        tentativePeerIds: self.targetMatcher.tentativePeerIds
      )
      let captureProjection = self.arContext.projectionSnapshot(
        camera: sourceCamera,
        viewport: viewport,
        capturedAt: now
      )
      let currentProjection = self.arContext.projectionSnapshot()
      let interests = self.cameraInterestEstimator.estimate(
        world: world,
        verifiedPeerIds: self.targetMatcher.verifiedPeerIds,
        tentativePeerIds: self.targetMatcher.tentativePeerIds,
        now: now,
        viewport: viewport,
        projectAtCapture: { worldTransform in
          guard let captureProjection else {
            return nil
          }
          return self.arContext.project(
            worldPosition: Self.worldPosition(from: worldTransform),
            using: captureProjection
          )
        }
      )
      self.nearbyDiscoveryService.updateCameraInterest(
        interests,
        evaluatedPeerIds: Set(world.peers.map(\.peerId))
      )

      let ambiguousRejectionsBefore =
        self.targetMatcher.ambiguousMatchRejectionCount
      let targets = self.targetMatcher.update(
        world: world,
        now: now,
        projectAtCapture: { worldTransform in
          guard let captureProjection else {
            return nil
          }
          return self.arContext.project(
            worldPosition: Self.worldPosition(from: worldTransform),
            using: captureProjection
          )
        },
        projectCurrent: { worldTransform in
          guard let currentProjection else {
            return nil
          }
          return self.arContext.project(
            worldPosition: Self.worldPosition(from: worldTransform),
            using: currentProjection
          )
        }
      )
      let completedBodyDiagnostics = bodyDiagnostics.withMatcherOutput(
        trackedBodyCount: self.targetMatcher.lastActiveBodyTrackCount,
        duplicateTrackSuppressionCount:
          self.targetMatcher.lastDuplicateDetectionSuppressionCount
          + self.targetMatcher.lastDuplicateTrackSuppressionCount,
        duplicateTrackRetirementCount:
          self.targetMatcher.lastDuplicateTrackRetirementCount
      )
      self.nearbyDiscoveryService.updateAssociationState(
        verifiedPeerIds: self.targetMatcher.verifiedPeerIds,
        tentativePeerIds: self.targetMatcher.tentativePeerIds
      )
      self.setAssociationUncertainty(
        self.deriveAssociationUncertainty(
          detectionCount: detections.count,
          // Plausible/group cards are render output, not strict identity
          // evidence. Keep Vision cadence/3D policy keyed to verified state.
          targetCount: self.targetMatcher.verifiedPeerIds.count,
          ambiguousRejectionsBefore: ambiguousRejectionsBefore
        )
      )
      self.storeProbeContext(
        bodies: detections,
        verifiedPeerIds: self.targetMatcher.verifiedPeerIds,
        tentativePeerIds: self.targetMatcher.tentativePeerIds
      )
      let associatedWorld = world.withAssociations(
        self.targetMatcher.associationsSnapshot(now: now)
      )
      self.latestWorldSnapshot = associatedWorld
      let renderStates = self.targetMatcher.renderSnapshot(now: now)
      #if DEBUG
        self.replayRecorder.record(
          associatedWorld,
          renderStates: renderStates
        )
      #endif
      self.publishRenderStates(renderStates)
      self.signpostFusionMetrics()
      self.signpostBodyDuplicateDiagnostics(completedBodyDiagnostics)
      self.recordCameraMetrics(
        detectionCount: detections.count,
        targets: targets
      )

      guard self.isCurrentRenderGeneration(processingGeneration) else {
        SpatialPerformance.signposter.endInterval(
          "Target matching",
          interval
        )
        return
      }

      self.instrumentationLock.lock()
      let shouldSignpostTargetCount = self.lastSignpostedTargetCount != targets.count
      if shouldSignpostTargetCount {
        self.lastSignpostedTargetCount = targets.count
      }
      self.instrumentationLock.unlock()
      if shouldSignpostTargetCount {
        SpatialPerformance.signposter.emitEvent(
          "Visible overlay target count",
          "Count: \(targets.count)"
        )
      }
      SpatialPerformance.signposter.endInterval(
        "Target matching",
        interval
      )
      completion(targets, processingGeneration, completedBodyDiagnostics)
    }
  }

  func peerSpatialSnapshots() -> [NearbyPeerSpatialSnapshot] {
    return currentPeerSpatialSnapshots()
  }

  func clearSpatialTargets() {
    fusionQueue.async { [weak self] in
      guard let self, self.hasSpatialInputs else {
        return
      }

      self.hasSpatialInputs = false
      self.targetMatcher.reset()
      self.latestWorldSnapshot = nil
      self.advanceRenderGeneration()
      self.publishRenderStates([])
    }
  }

  func isCurrentRenderGeneration(_ generation: UInt64) -> Bool {
    renderStateLock.lock()
    defer { renderStateLock.unlock() }
    return renderGeneration == generation
  }

  func projectedTargets() -> [SpatialMatchedTarget] {
    dispatchPrecondition(condition: .onQueue(.main))

    renderStateLock.lock()
    let states = renderStates
    renderStateLock.unlock()
    let projection = arContext.projectionSnapshot()
    let now = CACurrentMediaTime()
    let recoverablePeerIds = Set(
      nearbyDiscoveryService.cachedPeerSpatialSnapshots()
        .filter { $0.isRecoverable(at: now) }
        .map(\.peerId)
    )

    return states.compactMap { state in
      guard recoverablePeerIds.contains(state.peerId),
        SpatialRenderDecisionPolicy.retainsDisplay(
          now: now,
          lastBodyEvidenceAt: state.lastBodyEvidenceAt,
          lastPeerEvidenceAt: state.lastPeerEvidenceAt,
          peerIsRecoverable: true,
          hasContradictorySpatialEvidence:
            state.hasContradictorySpatialEvidence,
          contradictoryEvidenceSince: state.contradictoryEvidenceSince
        )
      else {
        return nil
      }

      let peerPoint: CGPoint?
      if !state.usesBodyAnchor,
        now - state.lastSpatialEvidenceAt
          <= SpatialMeasurementTuning.renderMaximumTransformAge,
        let worldTransform = state.renderWorldTransform,
        let projection
      {
        peerPoint = arContext.project(
          worldPosition: Self.worldPosition(from: worldTransform),
          using: projection
        )
      } else {
        peerPoint = nil
      }
      let screenPoint: CGPoint
      if let peerPoint {
        if let offset = state.screenOffsetFromPeer {
          screenPoint = CGPoint(
            x: peerPoint.x + offset.dx,
            y: peerPoint.y + offset.dy
          )
        } else {
          screenPoint = peerPoint
        }
      } else {
        screenPoint = state.fallbackScreenPoint
      }

      return SpatialMatchedTarget(
        anchorSource: state.anchorSource,
        distance: state.distance,
        peerId: state.peerId,
        renderMode: state.renderMode,
        screenPoint: screenPoint,
        userId: state.userId
      )
    }
  }

  #if DEBUG
    func debugReplayFrames() -> [SpatialReplayFrame] {
      replayRecorder.frames()
    }

    func debugReplayData() -> Data? {
      replayRecorder.encodedFrames()
    }

    func clearDebugReplay() {
      replayRecorder.clear()
    }

    func debugPhoneMarkers() -> [SpatialDebugPhoneMarker] {
      dispatchPrecondition(condition: .onQueue(.main))
      let projection = arContext.projectionSnapshot()
      let now = CACurrentMediaTime()
      let peers = nearbyDiscoveryService.cachedPeerSpatialSnapshots().filter {
        $0.isRecoverable(at: now)
      }
      renderStateLock.lock()
      let renderStateByPeerId = Dictionary(
        uniqueKeysWithValues: renderStates.map { ($0.peerId, $0) }
      )
      renderStateLock.unlock()
      let markers: [SpatialDebugPhoneMarker] = peers.compactMap { peer in
        guard
          peer.isWorldTransformUsable(at: now),
          let worldTransform = peer.effectiveDisplayWorldTransform,
          let projection,
          let point = arContext.project(
            worldPosition: Self.worldPosition(from: worldTransform),
            using: projection
          )
        else {
          return nil
        }

        return SpatialDebugPhoneMarker(
          distance: peer.displayDistance ?? peer.distance,
          distanceNormalizedResidual: renderStateByPeerId[peer.peerId]?
            .distanceNormalizedResidual,
          associationConfidence: renderStateByPeerId[peer.peerId]?
            .associationConfidence,
          associationMode: renderStateByPeerId[peer.peerId]?
            .associationMode.rawValue,
          renderMode: renderStateByPeerId[peer.peerId]?
            .renderMode.rawValue,
          measurementTier: peer.measurementTier(at: now).rawValue,
          healthState: peer.rangingHealth.state.rawValue,
          usefulMeasurementAge: peer.usefulMeasurementAge(at: now),
          callbackAge: peer.callbackAge(at: now),
          transformAge: peer.transformAge(at: now),
          distanceAge: peer.distanceAge(at: now),
          directionAvailable: peer.directionalMeasurement(at: now) != nil,
          directionAge: peer.directionAge(at: now),
          peerId: peer.peerId,
          point: point,
          userId: peer.identity?.userId
        )
      }

      if !markers.isEmpty, !didSignpostFirstDebugPhoneMarker {
        didSignpostFirstDebugPhoneMarker = true
        let latencyMilliseconds = nearbyDiscoveryService.discoveryStartedAt.map {
          Int((CACurrentMediaTime() - $0) * 1_000)
        } ?? -1
        SpatialPerformance.signposter.emitEvent(
          "First blue phone marker rendered",
          "Latency milliseconds: \(latencyMilliseconds), markers: \(markers.count)"
        )
      }

      return markers
    }
  #endif

  private func publishRenderStates(_ states: [SpatialRenderTargetState]) {
    renderStateLock.lock()
    renderStates = states
    renderStateLock.unlock()
  }

  private func currentRenderGeneration() -> UInt64 {
    renderStateLock.lock()
    defer { renderStateLock.unlock() }
    return renderGeneration
  }

  private func advanceRenderGeneration() {
    renderStateLock.lock()
    renderGeneration &+= 1
    renderStateLock.unlock()
  }

  private func currentPeerSpatialSnapshots()
    -> [NearbyPeerSpatialSnapshot]
  {
    let now = CACurrentMediaTime()
    let peers = nearbyDiscoveryService.peerSpatialSnapshots().filter {
      $0.isRecoverable(at: now)
    }
    let resolvedPeerCount = peers.reduce(into: 0) { count, peer in
      if peer.identity?.userId?.isEmpty == false {
        count += 1
      }
    }

    instrumentationLock.lock()
    let shouldSignpostPeerCount = lastSignpostedPeerCount != peers.count
    let shouldSignpostResolvedPeerCount =
      lastSignpostedResolvedPeerCount != resolvedPeerCount
    if shouldSignpostPeerCount {
      lastSignpostedPeerCount = peers.count
    }
    if shouldSignpostResolvedPeerCount {
      lastSignpostedResolvedPeerCount = resolvedPeerCount
    }
    instrumentationLock.unlock()
    if shouldSignpostPeerCount {
      SpatialPerformance.signposter.emitEvent(
        "Active peer count",
        "Count: \(peers.count)"
      )
    }
    if shouldSignpostResolvedPeerCount {
      SpatialPerformance.signposter.emitEvent(
        "Resolved peer count",
        "Count: \(resolvedPeerCount)"
      )
    }

    return peers
  }

  private func resetTargetMatcher() {
    instrumentationLock.lock()
    lastSignpostedTargetCount = nil
    lastSignpostedFusionSummary = nil
    lastSignpostedBodyDuplicateSummary = nil
    #if DEBUG
      didSignpostFirstDebugPhoneMarker = false
    #endif
    instrumentationLock.unlock()

    fusionQueue.async { [weak self] in
      guard let self else {
        return
      }
      self.targetMatcher.reset()
      self.latestWorldSnapshot = nil
      self.hasSpatialInputs = false
      self.advanceRenderGeneration()
      self.publishRenderStates([])
    }
  }

  private func finishCameraMetricsAndResetMatcher() {
    instrumentationLock.lock()
    lastSignpostedTargetCount = nil
    lastSignpostedFusionSummary = nil
    lastSignpostedBodyDuplicateSummary = nil
    instrumentationLock.unlock()

    fusionQueue.async { [weak self] in
      guard let self else {
        return
      }

      self.finishCameraMetrics()
      self.targetMatcher.reset()
      self.latestWorldSnapshot = nil
      self.hasSpatialInputs = false
      self.advanceRenderGeneration()
      self.publishRenderStates([])
    }
  }

  private func beginCameraMetrics() {
    instrumentationLock.lock()
    lastSignpostedFusionSummary = nil
    lastSignpostedBodyDuplicateSummary = nil
    instrumentationLock.unlock()
    targetMatcher.reset()
    cameraSessionStartedAt = CACurrentMediaTime()
    firstOverlayAcquiredAt = nil
    lastOverlayLostAt = nil
    maximumDetectedBodyCount = 0
    maximumVisibleTargetCount = 0
    overlayLossCount = 0
    overlayReacquisitionCount = 0
    overlayReacquisitionDuration = 0
    previousVisiblePeerIds.removeAll()
    processedVisionFrameCount = 0
    #if DEBUG
      didSignpostFirstDebugPhoneMarker = false
    #endif
    SpatialPerformance.signposter.emitEvent(
      "Camera spatial session started"
    )
  }

  private func recordCameraMetrics(
    detectionCount: Int,
    targets: [SpatialMatchedTarget]
  ) {
    guard let cameraSessionStartedAt else {
      return
    }

    let now = CACurrentMediaTime()
    let visiblePeerIds = Set(targets.map(\.peerId))
    processedVisionFrameCount += 1
    maximumDetectedBodyCount = max(
      maximumDetectedBodyCount,
      detectionCount
    )
    maximumVisibleTargetCount = max(
      maximumVisibleTargetCount,
      visiblePeerIds.count
    )

    if firstOverlayAcquiredAt == nil, !visiblePeerIds.isEmpty {
      firstOverlayAcquiredAt = now
      let latencyMilliseconds = Int(
        (now - cameraSessionStartedAt) * 1_000
      )
      SpatialPerformance.signposter.emitEvent(
        "First overlay acquired",
        "Latency milliseconds: \(latencyMilliseconds)"
      )
    }

    if !previousVisiblePeerIds.isEmpty, visiblePeerIds.isEmpty {
      overlayLossCount += 1
      lastOverlayLostAt = now
      SpatialPerformance.signposter.emitEvent("Overlay targets lost")
    } else if previousVisiblePeerIds.isEmpty,
      !visiblePeerIds.isEmpty,
      let lastOverlayLostAt
    {
      let reacquisitionDuration = now - lastOverlayLostAt
      overlayReacquisitionCount += 1
      overlayReacquisitionDuration += reacquisitionDuration
      self.lastOverlayLostAt = nil
      SpatialPerformance.signposter.emitEvent(
        "Overlay targets reacquired",
        "Latency milliseconds: \(Int(reacquisitionDuration * 1_000))"
      )
    }

    previousVisiblePeerIds = visiblePeerIds
  }

  private func finishCameraMetrics() {
    guard let cameraSessionStartedAt else {
      return
    }

    let now = CACurrentMediaTime()
    let durationMilliseconds = Int(
      (now - cameraSessionStartedAt) * 1_000
    )
    let firstOverlayLatencyMilliseconds =
      firstOverlayAcquiredAt.map {
        Int(($0 - cameraSessionStartedAt) * 1_000)
      } ?? -1
    let averageReacquisitionMilliseconds =
      overlayReacquisitionCount > 0
      ? Int(
        overlayReacquisitionDuration
          / Double(overlayReacquisitionCount) * 1_000
      )
      : -1
    let ambiguousAssignmentCount =
      targetMatcher.ambiguousMatchRejectionCount
    let bodyReassignmentCount =
      targetMatcher.confirmedBodyReassignmentCount
    let confirmedReacquisitionCount =
      targetMatcher.confirmedReacquisitionCount
    let confirmedInitialMatchCount =
      targetMatcher.confirmedInitialMatchCount
    let directionalContradictionRejectionCount =
      targetMatcher.directionalContradictionRejectionCount
    let distanceOnlyIdentityRejectionCount =
      targetMatcher.distanceOnlyIdentityRejectionCount
    let singletonStartedCount =
      targetMatcher.singletonPlausibleRenderStartedCount
    let singletonPromotedCount =
      targetMatcher.singletonPlausibleRenderPromotedCount
    let singletonExpiredCount =
      targetMatcher.singletonPlausibleRenderExpiredCount
    let groupStartedCount = targetMatcher.groupFallbackStartedCount
    let groupPromotedCount = targetMatcher.groupFallbackPromotedCount
    let groupExpiredCount = targetMatcher.groupFallbackExpiredCount
    let visibilityCandidateCount =
      targetMatcher.lastRenderVisibilityCandidateCount
    let visibilityEligibleCount =
      targetMatcher.lastRenderVisibilityEligibleCount
    let visibilitySelectedCount =
      targetMatcher.lastRenderVisibilitySelectedCount
    let visibilityDistanceSuppressedCount =
      targetMatcher.lastRenderVisibilityDistanceSuppressedCount
    let visibilityCapacitySuppressedCount =
      targetMatcher.lastRenderVisibilityCapacitySuppressedCount
    let visibilityRetainedCount =
      targetMatcher.lastRenderVisibilityRetainedCount
    let visibilityReliableDistanceCount =
      targetMatcher.lastRenderVisibilityReliableDistanceCount
    let visibilityWeakDistanceCount =
      targetMatcher.lastRenderVisibilityWeakDistanceCount
    let visibilityReplacementCount =
      targetMatcher.renderVisibilitySelectionReplacementCount
    let visibilitySelectionChangeCount =
      targetMatcher.renderVisibilitySelectionChangeCount
    let renderBodyLossGraceStartedCount =
      targetMatcher.renderBodyLossGraceStartedCount
    let renderBodyLossGraceRecoveredCount =
      targetMatcher.renderBodyLossGraceRecoveredCount
    let renderBodyLossGraceExpiredCount =
      targetMatcher.renderBodyLossGraceExpiredCount
    let visibleRenderModes = targetMatcher.visibleRenderModeCounts
    let visibleExactRenderCount = visibleRenderModes[.exact] ?? 0
    let visiblePlausibleRenderCount = visibleRenderModes[.plausible] ?? 0
    let visibleGroupRenderCount = visibleRenderModes[.group] ?? 0
    let frameCount = processedVisionFrameCount
    let lossCount = overlayLossCount
    let maximumBodyCount = maximumDetectedBodyCount
    let maximumTargetCount = maximumVisibleTargetCount
    let reacquisitionCount = overlayReacquisitionCount

    SpatialPerformance.signposter.emitEvent(
      "Camera spatial session summary",
      "Duration milliseconds: \(durationMilliseconds), frames: \(frameCount), first overlay milliseconds: \(firstOverlayLatencyMilliseconds), maximum bodies: \(maximumBodyCount), maximum targets: \(maximumTargetCount), losses: \(lossCount), overlay reacquisitions: \(reacquisitionCount), average overlay reacquisition milliseconds: \(averageReacquisitionMilliseconds), confirmed body reacquisitions: \(confirmedReacquisitionCount), ambiguous assignments: \(ambiguousAssignmentCount), directional contradictions: \(directionalContradictionRejectionCount), distance-only identity rejections: \(distanceOnlyIdentityRejectionCount), confirmed initial matches: \(confirmedInitialMatchCount), identity switches: \(bodyReassignmentCount), singleton plausible started: \(singletonStartedCount), singleton promoted: \(singletonPromotedCount), singleton expired: \(singletonExpiredCount), group fallback started: \(groupStartedCount), group promoted: \(groupPromotedCount), group expired: \(groupExpiredCount), render body-loss grace started: \(renderBodyLossGraceStartedCount), render body-loss grace recovered: \(renderBodyLossGraceRecoveredCount), render body-loss grace expired: \(renderBodyLossGraceExpiredCount), visibility candidates: \(visibilityCandidateCount), visibility eligible: \(visibilityEligibleCount), visibility selected: \(visibilitySelectedCount), visibility reliable distance: \(visibilityReliableDistanceCount), visibility weak distance: \(visibilityWeakDistanceCount), visibility distance suppressed: \(visibilityDistanceSuppressedCount), visibility capacity suppressed: \(visibilityCapacitySuppressedCount), visibility retained: \(visibilityRetainedCount), visibility replacements: \(visibilityReplacementCount), visibility selection changes: \(visibilitySelectionChangeCount), visible exact: \(visibleExactRenderCount), visible plausible: \(visiblePlausibleRenderCount), visible group: \(visibleGroupRenderCount)"
    )

    self.cameraSessionStartedAt = nil
    firstOverlayAcquiredAt = nil
    lastOverlayLostAt = nil
    previousVisiblePeerIds.removeAll()
  }

  private func signpostFusionMetrics() {
    let candidatePairCount = targetMatcher.lastCandidatePairCount
    let gatedCandidatePairCount = targetMatcher.lastGatedCandidatePairCount
    let activeBodyTrackCount = targetMatcher.lastActiveBodyTrackCount
    let tentativeCount = targetMatcher.tentativePeerIds.count
    let verifiedCount = targetMatcher.verifiedPeerIds.count
    let ambiguousRejectionCount = targetMatcher.ambiguousMatchRejectionCount
    let directionalContradictionRejectionCount =
      targetMatcher.directionalContradictionRejectionCount
    let distanceOnlyIdentityRejectionCount =
      targetMatcher.distanceOnlyIdentityRejectionCount
    let reassignmentCount = targetMatcher.confirmedBodyReassignmentCount
    let reacquisitionCount = targetMatcher.confirmedReacquisitionCount
    let groupMemberCount = targetMatcher.lastGroupMemberCount
    let groupPeerCount = targetMatcher.lastGroupRenderedPeerCount
    let renderModes = targetMatcher.renderModeCounts
    let visibleRenderModes = targetMatcher.visibleRenderModeCounts
    let exactRenderCount = renderModes[.exact] ?? 0
    let plausibleRenderCount = renderModes[.plausible] ?? 0
    let groupRenderCount = renderModes[.group] ?? 0
    let visibleExactRenderCount = visibleRenderModes[.exact] ?? 0
    let visiblePlausibleRenderCount = visibleRenderModes[.plausible] ?? 0
    let visibleGroupRenderCount = visibleRenderModes[.group] ?? 0
    let visibilityCandidateCount =
      targetMatcher.lastRenderVisibilityCandidateCount
    let visibilityEligibleCount =
      targetMatcher.lastRenderVisibilityEligibleCount
    let visibilitySelectedCount =
      targetMatcher.lastRenderVisibilitySelectedCount
    let visibilityDistanceSuppressedCount =
      targetMatcher.lastRenderVisibilityDistanceSuppressedCount
    let visibilityCapacitySuppressedCount =
      targetMatcher.lastRenderVisibilityCapacitySuppressedCount
    let visibilityRetainedCount =
      targetMatcher.lastRenderVisibilityRetainedCount
    let visibilityReliableDistanceCount =
      targetMatcher.lastRenderVisibilityReliableDistanceCount
    let visibilityWeakDistanceCount =
      targetMatcher.lastRenderVisibilityWeakDistanceCount
    let visibilityReplacementCount =
      targetMatcher.renderVisibilitySelectionReplacementCount
    let visibilitySelectionChangeCount =
      targetMatcher.renderVisibilitySelectionChangeCount
    let renderBodyLossGraceStartedCount =
      targetMatcher.renderBodyLossGraceStartedCount
    let renderBodyLossGraceRecoveredCount =
      targetMatcher.renderBodyLossGraceRecoveredCount
    let renderBodyLossGraceExpiredCount =
      targetMatcher.renderBodyLossGraceExpiredCount
    let associations = latestWorldSnapshot?.associations ?? []
    let cameraAssistedCount = associations.filter {
      $0.mode == .cameraAssisted
    }.count
    let directionalCount = associations.filter {
      $0.mode == .directional
    }.count
    let distanceOnlyCount = associations.filter {
      $0.mode == .distanceOnly
    }.count
    let distanceResiduals = associations.compactMap {
      $0.evidence?.distanceNormalizedResidual
    }
    let maximumDistanceResidual = distanceResiduals.max() ?? -1
    let associationSummary: [String] = [
      String(candidatePairCount),
      String(gatedCandidatePairCount),
      String(activeBodyTrackCount),
      String(tentativeCount),
      String(verifiedCount),
      String(ambiguousRejectionCount),
      String(directionalContradictionRejectionCount),
      String(distanceOnlyIdentityRejectionCount),
      String(reassignmentCount),
      String(reacquisitionCount),
      String(cameraAssistedCount),
      String(directionalCount),
      String(distanceOnlyCount),
      String(format: "%.2f", maximumDistanceResidual),
      String(exactRenderCount),
      String(plausibleRenderCount),
      String(groupRenderCount),
      String(visibleExactRenderCount),
      String(visiblePlausibleRenderCount),
      String(visibleGroupRenderCount),
      String(groupMemberCount),
      String(groupPeerCount),
      String(renderBodyLossGraceStartedCount),
      String(renderBodyLossGraceRecoveredCount),
      String(renderBodyLossGraceExpiredCount),
    ]
    let visibilitySummary: [String] = [
      String(visibilityCandidateCount),
      String(visibilityEligibleCount),
      String(visibilitySelectedCount),
      String(visibilityReliableDistanceCount),
      String(visibilityWeakDistanceCount),
      String(visibilityDistanceSuppressedCount),
      String(visibilityCapacitySuppressedCount),
      String(visibilityRetainedCount),
      String(visibilityReplacementCount),
      String(visibilitySelectionChangeCount),
    ]
    let summary = (associationSummary + visibilitySummary)
      .joined(separator: ":")

    instrumentationLock.lock()
    let shouldSignpost = lastSignpostedFusionSummary != summary
    if shouldSignpost {
      lastSignpostedFusionSummary = summary
    }
    instrumentationLock.unlock()

    guard shouldSignpost else {
      return
    }

    SpatialPerformance.signposter.emitEvent(
      "Fusion candidate counts",
      "Before gating: \(candidatePairCount), after gating: \(gatedCandidatePairCount), active body tracks: \(activeBodyTrackCount)"
    )
    SpatialPerformance.signposter.emitEvent(
      "Fusion association state",
      "Tentative: \(tentativeCount), verified: \(verifiedCount), ambiguous rejections: \(ambiguousRejectionCount), directional contradictions: \(directionalContradictionRejectionCount), distance-only identity rejections: \(distanceOnlyIdentityRejectionCount), confirmed reacquisitions: \(reacquisitionCount), confirmed identity switches: \(reassignmentCount)"
    )
    SpatialPerformance.signposter.emitEvent(
      "Fusion association modes",
      "Camera-assisted: \(cameraAssistedCount), directional: \(directionalCount), distance-only: \(distanceOnlyCount), maximum normalized distance residual: \(String(format: "%.2f", maximumDistanceResidual))"
    )
    SpatialPerformance.signposter.emitEvent(
      "Fusion render states",
      "All exact: \(exactRenderCount), all plausible singleton: \(plausibleRenderCount), all group: \(groupRenderCount), visible exact: \(visibleExactRenderCount), visible plausible singleton: \(visiblePlausibleRenderCount), visible group: \(visibleGroupRenderCount), group members: \(groupMemberCount), group peers: \(groupPeerCount)"
    )
    SpatialPerformance.signposter.emitEvent(
      "Fusion render visibility",
      "Candidates: \(visibilityCandidateCount), eligible: \(visibilityEligibleCount), selected: \(visibilitySelectedCount), reliable distance: \(visibilityReliableDistanceCount), weak distance: \(visibilityWeakDistanceCount), distance suppressed: \(visibilityDistanceSuppressedCount), capacity suppressed: \(visibilityCapacitySuppressedCount), retained: \(visibilityRetainedCount), replacements: \(visibilityReplacementCount), selection changes: \(visibilitySelectionChangeCount)"
    )
    SpatialPerformance.signposter.emitEvent(
      "Fusion render continuity",
      "Body-loss grace started: \(renderBodyLossGraceStartedCount), recovered: \(renderBodyLossGraceRecoveredCount), expired: \(renderBodyLossGraceExpiredCount)"
    )
  }

  private func signpostBodyDuplicateDiagnostics(
    _ diagnostics: SpatialBodyPipelineDiagnostics
  ) {
    let summary = "\(diagnostics.rawVisionObservationCount):\(diagnostics.uniqueVisionDetectionCount):\(diagnostics.detectorTrackedBodyCount):\(diagnostics.matcherTrackedBodyCount):\(diagnostics.visionDuplicateSuppressionCount):\(diagnostics.detectorTrackDuplicateSuppressionCount):\(diagnostics.matcherDuplicateTrackSuppressionCount):\(diagnostics.matcherDuplicateTrackRetirementCount)"
    instrumentationLock.lock()
    let shouldSignpost: Bool
    if diagnostics.totalDuplicateSuppressionCount > 0 {
      shouldSignpost = lastSignpostedBodyDuplicateSummary != summary
      if shouldSignpost {
        lastSignpostedBodyDuplicateSummary = summary
      }
    } else {
      shouldSignpost = false
      lastSignpostedBodyDuplicateSummary = nil
    }
    instrumentationLock.unlock()

    guard shouldSignpost else {
      return
    }

    SpatialPerformance.signposter.emitEvent(
      "Vision duplicate body suppressed",
      "Raw Vision observations: \(diagnostics.rawVisionObservationCount), unique physical bodies: \(diagnostics.uniqueVisionDetectionCount), detector tracked bodies: \(diagnostics.detectorTrackedBodyCount), matcher-visible body tracks: \(diagnostics.matcherTrackedBodyCount), Vision duplicates suppressed: \(diagnostics.visionDuplicateSuppressionCount), detector-track duplicates suppressed: \(diagnostics.detectorTrackDuplicateSuppressionCount), matcher duplicate tracks suppressed: \(diagnostics.matcherDuplicateTrackSuppressionCount), matcher duplicate tracks retired: \(diagnostics.matcherDuplicateTrackRetirementCount)"
    )
  }

  private static func worldPosition(from transform: simd_float4x4) -> SIMD3<Float> {
    SIMD3<Float>(
      transform.columns.3.x,
      transform.columns.3.y,
      transform.columns.3.z
    )
  }

  private static func horizontalProjectionScale(
    for camera: ARCamera,
    orientation: UIInterfaceOrientation,
    viewportSize: CGSize
  ) -> Float? {
    let projection = cameraProjectionMatrix(
      for: camera,
      orientation: orientation,
      viewportSize: viewportSize
    )
    let scale = projection.columns.0.x
    return scale.isFinite && scale > 0 ? scale : nil
  }

  private static func cameraProjectionMatrix(
    for camera: ARCamera,
    orientation: UIInterfaceOrientation,
    viewportSize: CGSize
  ) -> simd_float4x4 {
    camera.projectionMatrix(
      for: orientation,
      viewportSize: viewportSize,
      zNear: 0.01,
      zFar: 100
    )
  }

  private static func viewerTrackingQuality(
    _ trackingState: ARCamera.TrackingState
  ) -> SpatialViewerTrackingQuality {
    switch trackingState {
    case .normal:
      return .normal
    case .limited:
      return .limited
    case .notAvailable:
      return .unknown
    @unknown default:
      return .unknown
    }
  }
}

private struct NearbyDiscoverySession: Codable {
  let credential: String
  let eventScope: String
  let expiresAt: Double
  let transportKey: String
}

private struct NearbyDiscoveryStartError: LocalizedError {
  var errorDescription: String? {
    "Unable to start nearby attendee detection."
  }
}

private final class NearbyDiscoverySessionStore {
  private static let service = "io.areach.spatial"
  private static let activeSessionAccount = "active-nearby-session"
  private static let backgroundResponderStateAccount = "background-responder-active"
  private static let peerIdAccount = "nearby-peer-id"
  private static let signingKeyAccount = "nearby-signing-key"

  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  lazy var signingPrivateKey: P256.Signing.PrivateKey = {
    if let data = read(account: Self.signingKeyAccount),
      let key = try? P256.Signing.PrivateKey(rawRepresentation: data)
    {
      return key
    }

    let key = P256.Signing.PrivateKey()
    save(key.rawRepresentation, account: Self.signingKeyAccount)
    return key
  }()

  lazy var peerId: String = {
    if let data = read(account: Self.peerIdAccount),
      let value = String(data: data, encoding: .utf8)?.lowercased(),
      UUID(uuidString: value) != nil
    {
      return value
    }

    let value = UUID().uuidString.lowercased()
    save(Data(value.utf8), account: Self.peerIdAccount)
    return value
  }()

  var activeSession: NearbyDiscoverySession? {
    guard let data = read(account: Self.activeSessionAccount) else {
      return nil
    }

    return try? decoder.decode(NearbyDiscoverySession.self, from: data)
  }

  func saveActiveSession(_ session: NearbyDiscoverySession) {
    guard let data = try? encoder.encode(session) else {
      return
    }

    save(data, account: Self.activeSessionAccount)
  }

  func clearActiveSession() {
    SecItemDelete(query(account: Self.activeSessionAccount) as CFDictionary)
  }

  var backgroundResponderActive: Bool {
    read(account: Self.backgroundResponderStateAccount)?.first == 1
  }

  func saveBackgroundResponderActive(_ active: Bool) {
    save(
      Data([active ? UInt8(1) : UInt8(0)]),
      account: Self.backgroundResponderStateAccount
    )
  }

  func clearBackgroundResponderActive() {
    SecItemDelete(
      query(account: Self.backgroundResponderStateAccount) as CFDictionary
    )
  }

  private func read(account: String) -> Data? {
    var query = query(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    guard
      SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    else {
      return nil
    }

    return result as? Data
  }

  private func save(_ data: Data, account: String) {
    let itemQuery = query(account: account)
    let attributes = [kSecValueData as String: data]

    if SecItemUpdate(
      itemQuery as CFDictionary,
      attributes as CFDictionary
    ) == errSecItemNotFound {
      var item = itemQuery
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] =
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(item as CFDictionary, nil)
    }
  }

  private func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: account,
      kSecAttrService as String: Self.service,
    ]
  }
}
