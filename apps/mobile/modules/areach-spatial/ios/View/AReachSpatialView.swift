import ARKit
import ExpoModulesCore
import QuartzCore
import UIKit

class AReachSpatialView: ExpoView {
  let onCameraStateChange = EventDispatcher()
  let onOverlayPress = EventDispatcher()

  private let cameraSession = CameraSession()
  private let visionFrameProcessor = VisionFrameProcessor()
  private let overlayView = SpatialOverlayView()
  private let attendeeLock = NSLock()
  private let peerAvailabilityLock = NSLock()
  private var attendeeUserIds = Set<String>()
  private var didClearForEmptyPeerSnapshot = false
  private var renderDisplayLink: CADisplayLink?
  private var renderMetricsWindowStartedAt: CFTimeInterval?
  private var renderTickCount = 0
  private var lateRenderTickCount = 0
  private var lastRenderTickAt: CFTimeInterval?
  private var limitedTrackingWorkItem: DispatchWorkItem?
  private var isCameraConsumerRegistered = false
  #if DEBUG
    private let debugOverlayView = CameraDebugOverlayView()
  #endif

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)

    clipsToBounds = true
    backgroundColor = UIColor(
      red: 0.02,
      green: 0.03,
      blue: 0.04,
      alpha: 1.0
    )

    cameraSession.setDelegate(self)
    addSubview(cameraSession.arView)
    #if DEBUG
      addSubview(debugOverlayView)
    #endif
    addSubview(overlayView)

    overlayView.onTargetPress = { [weak self] target, profile, action in
      self?.onOverlayPress([
        "action": action,
        "peerId": target.peerId,
        "userId": profile.userId,
      ])
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()

    if window == nil {
      stopRenderCoordinator()
      stopSession()
      unregisterCameraConsumerIfNeeded()
      return
    }

    registerCameraConsumerIfNeeded()
    startRenderCoordinator()
    startSession()
  }

  private func registerCameraConsumerIfNeeded() {
    guard !isCameraConsumerRegistered else {
      return
    }

    isCameraConsumerRegistered = true
    AReachSpatialRuntime.shared.registerCameraConsumer()
  }

  private func unregisterCameraConsumerIfNeeded() {
    guard isCameraConsumerRegistered else {
      return
    }

    isCameraConsumerRegistered = false
    AReachSpatialRuntime.shared.unregisterCameraConsumer()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    cameraSession.arView.frame = bounds
    #if DEBUG
      debugOverlayView.frame = bounds
    #endif
    overlayView.frame = bounds

    AReachSpatialRuntime.shared.updateViewport(
      size: bounds.size,
      orientation: currentInterfaceOrientation
    )
  }

  private func startSession() {
    cameraSession.start(
      shouldStart: { [weak self] in
        self?.window != nil
      },
      onStateChange: { [weak self] payload in
        self?.onCameraStateChange(payload)
      },
      onSessionChange: { [weak self] session in
        self?.updateRuntimeSession(session)
      }
    )
  }

  private func stopSession() {
    if cameraSession.isRunning {
      cameraSession.stop { [weak self] session in
        self?.updateRuntimeSession(session)
      }
    } else {
      updateRuntimeSession(nil)
    }

    limitedTrackingWorkItem?.cancel()
    limitedTrackingWorkItem = nil
    visionFrameProcessor.reset()
    overlayView.clearTargetsImmediately()
    renderDisplayLink?.isPaused = true
    #if DEBUG
      debugOverlayView.clear()
    #endif
  }

  func setAttendeeProfiles(_ profiles: [SpatialAttendeeProfile]) {
    attendeeLock.lock()
    attendeeUserIds = Set(profiles.lazy.map(\.userId).filter { !$0.isEmpty })
    attendeeLock.unlock()
    overlayView.setAttendeeProfiles(profiles)
    resumeRenderCoordinator()
    #if DEBUG
      debugOverlayView.setAttendeeProfiles(profiles)
    #endif
  }

  func processVisionIfNeeded(frame: ARFrame) {
    AReachSpatialRuntime.shared.updateARCamera(frame.camera)
    let viewport = AReachSpatialRuntime.shared.viewportSnapshot()
    visionFrameProcessor.setAssociationUncertainty(
      AReachSpatialRuntime.shared.associationUncertainty()
    )

    visionFrameProcessor.processIfNeeded(
      frame: frame,
      viewport: viewport,
      captureContext: { [weak self] in
        self?.capturePeersForVision()
      },
      completion: {
        [weak self]
        detections,
        sourceCamera,
        viewportSize,
        orientation,
        peers,
        bodyDiagnostics in
        AReachSpatialRuntime.shared.processDetections(
          for: detections,
          peers: peers,
          sourceCamera: sourceCamera,
          viewportSize: viewportSize,
          orientation: orientation,
          bodyDiagnostics: bodyDiagnostics,
          completion: { [weak self] targets, renderGeneration, finalBodyDiagnostics in
            guard
              AReachSpatialRuntime.shared.isCurrentRenderGeneration(
                renderGeneration
              )
            else {
              return
            }

            DispatchQueue.main.async {
              guard
                let self,
                self.cameraSession.isRunning,
                AReachSpatialRuntime.shared.isCurrentRenderGeneration(
                  renderGeneration
                )
              else {
                return
              }

              self.overlayView.updateTargets(targets)
              self.resumeRenderCoordinator()
              #if DEBUG
                // Skeletons reflect the latest Vision pass. Phone markers
                // are reprojected independently on the display-link below.
                self.debugOverlayView.updateSkeleton(detections: detections)
                self.debugOverlayView.updateBodyDiagnostics(finalBodyDiagnostics)
              #endif
            }
          }
        )
      }
    )
  }

  private func capturePeersForVision() -> [NearbyPeerSpatialSnapshot]? {
    let now = CACurrentMediaTime()
    attendeeLock.lock()
    let attendeeUserIds = attendeeUserIds
    attendeeLock.unlock()
    let peers = AReachSpatialRuntime.shared.peerSpatialSnapshots().filter {
      guard let userId = $0.identity?.userId else {
        return false
      }

      return attendeeUserIds.contains(userId) && $0.isRecoverable(at: now)
    }

    peerAvailabilityLock.lock()
    let shouldClearForEmptySnapshot: Bool
    if peers.isEmpty {
      shouldClearForEmptySnapshot = !didClearForEmptyPeerSnapshot
      didClearForEmptyPeerSnapshot = true
    } else {
      shouldClearForEmptySnapshot = false
      didClearForEmptyPeerSnapshot = false
    }
    peerAvailabilityLock.unlock()

    if shouldClearForEmptySnapshot {
      AReachSpatialRuntime.shared.clearSpatialTargets()
      DispatchQueue.main.async { [weak self] in
        guard let self else {
          return
        }

        self.overlayView.clearTargetsImmediately()
        self.renderDisplayLink?.isPaused = true
        #if DEBUG
          self.debugOverlayView.clear()
        #endif
      }
    }

    #if DEBUG
      return peers
    #else
      return peers.isEmpty ? nil : peers
    #endif
  }

  func handleCameraTrackingState(_ trackingState: ARCamera.TrackingState) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }

      self.limitedTrackingWorkItem?.cancel()
      self.limitedTrackingWorkItem = nil

      switch trackingState {
      case .normal:
        self.onCameraStateChange(["state": "running"])
      case .notAvailable:
        self.onCameraStateChange([
          "state": "failed",
          "message": "AR tracking is unavailable.",
        ])
      case .limited(let reason):
        if case .insufficientFeatures = reason {
          return
        }

        let workItem = DispatchWorkItem { [weak self] in
          self?.onCameraStateChange([
            "state": "limited",
            "message": Self.trackingGuidance(for: reason),
          ])
        }
        self.limitedTrackingWorkItem = workItem
        DispatchQueue.main.asyncAfter(
          deadline: .now() + 1,
          execute: workItem
        )
      }
    }
  }

  func handleCameraInterruption() {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }

      self.limitedTrackingWorkItem?.cancel()
      self.limitedTrackingWorkItem = nil
      self.onCameraStateChange([
        "state": "interrupted",
        "message": "AR camera paused.",
      ])
    }
  }

  private func startRenderCoordinator() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard renderDisplayLink == nil else {
      return
    }

    renderMetricsWindowStartedAt = nil
    renderTickCount = 0
    lateRenderTickCount = 0
    lastRenderTickAt = nil

    let displayLink = CADisplayLink(
      target: self,
      selector: #selector(updateProjectedTargets)
    )
    displayLink.preferredFrameRateRange = CAFrameRateRange(
      minimum: 30,
      maximum: 60,
      preferred: 60
    )
    displayLink.add(to: .main, forMode: .common)
    displayLink.isPaused = true
    renderDisplayLink = displayLink
  }

  private func stopRenderCoordinator() {
    renderDisplayLink?.invalidate()
    renderDisplayLink = nil
    renderMetricsWindowStartedAt = nil
    renderTickCount = 0
    lateRenderTickCount = 0
    lastRenderTickAt = nil
  }

  private func resumeRenderCoordinator() {
    dispatchPrecondition(condition: .onQueue(.main))
    guard cameraSession.isRunning else {
      return
    }
    renderDisplayLink?.isPaused = false
  }

  @objc private func updateProjectedTargets(_ displayLink: CADisplayLink) {
    guard cameraSession.isRunning else {
      displayLink.isPaused = true
      return
    }

    recordRenderTick(displayLink)

    overlayView.updateProjectedTargets(
      AReachSpatialRuntime.shared.projectedTargets()
    )
    #if DEBUG
      let phoneMarkers = AReachSpatialRuntime.shared.debugPhoneMarkers()
      debugOverlayView.updatePhoneMarkers(phoneMarkers)
      let hasDebugPhoneMarkers = !phoneMarkers.isEmpty
    #else
      let hasDebugPhoneMarkers = false
    #endif

    let hasMovingProductionOverlay = overlayView.renderTick(
      timestamp: displayLink.timestamp,
      duration: displayLink.duration
    )
    if !hasMovingProductionOverlay && !hasDebugPhoneMarkers {
      displayLink.isPaused = true
    }
  }

  private func recordRenderTick(_ displayLink: CADisplayLink) {
    dispatchPrecondition(condition: .onQueue(.main))
    let now = CACurrentMediaTime()
    let expectedFrameDuration = max(displayLink.duration, 1.0 / 60.0)

    if let lastRenderTickAt,
      now - lastRenderTickAt > expectedFrameDuration * 1.5
    {
      lateRenderTickCount += 1
    }
    self.lastRenderTickAt = now

    guard let renderMetricsWindowStartedAt else {
      self.renderMetricsWindowStartedAt = now
      renderTickCount = 1
      return
    }

    renderTickCount += 1
    let elapsed = now - renderMetricsWindowStartedAt
    guard elapsed >= 1 else {
      return
    }

    let framesPerSecond = Double(renderTickCount) / elapsed
    SpatialPerformance.signposter.emitEvent(
      "Native render cadence",
      "FPS: \(String(format: "%.1f", framesPerSecond)), ticks: \(self.renderTickCount), late ticks: \(self.lateRenderTickCount)"
    )
    self.renderMetricsWindowStartedAt = now
    renderTickCount = 0
    lateRenderTickCount = 0
  }

  private static func trackingGuidance(
    for reason: ARCamera.TrackingState.Reason
  ) -> String {
    switch reason {
    case .initializing:
      return "Move your iPhone slowly while AR tracking prepares."
    case .excessiveMotion:
      return "Move your iPhone more slowly."
    case .insufficientFeatures:
      return "Move your iPhone slowly while AR tracking prepares."
    case .relocalizing:
      return "Return to the area where camera tracking started."
    @unknown default:
      return "Move your iPhone slowly while AR tracking recovers."
    }
  }

  private func updateRuntimeSession(_ session: ARSession?) {
    AReachSpatialRuntime.shared.setARSession(
      session,
      viewportSize: bounds.size,
      orientation: currentInterfaceOrientation
    )
  }

  private var currentInterfaceOrientation: UIInterfaceOrientation {
    let orientation = window?.windowScene?.interfaceOrientation ?? .portrait

    switch orientation {
    case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
      return orientation
    case .unknown:
      return .portrait
    @unknown default:
      return .portrait
    }
  }

}
