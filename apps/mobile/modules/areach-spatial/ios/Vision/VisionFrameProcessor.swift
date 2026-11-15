import ARKit
import QuartzCore
import UIKit
import Vision
import simd
import os

final class VisionFrameProcessor {
  private let bodyDepthEstimator = SpatialBodyDepthEstimator()
  private var body3DEstimator: Any?
  private let bodyPoseDetector = BodyPoseDetector()
  private let visionQueue = DispatchQueue(
    label: "io.areach.spatial.vision",
    qos: .userInitiated
  )
  private let stateLock = NSLock()
  private let baseFrameInterval: CFTimeInterval

  private var generation = 0
  private var isRequestInFlight = false
  private var lastRequestAt: CFTimeInterval = 0
  private var lastProcessingDuration: CFTimeInterval = 0
  private var lastThermalState: ProcessInfo.ThermalState?
  private var lastLowPowerMode: Bool?
  private var lastDetectionCount = 0
  private var lastTrackingConfidence: Float = 1
  private var lastHadOverlapPressure = false
  private var associationUncertainty: SpatialAssociationUncertainty = .uncertain
  private var lastCameraTransform: simd_float4x4?
  private var lastCoalescedSignpostAt: CFTimeInterval = 0
  private var frameCadenceWindowStartedAt: CFTimeInterval?
  private var frameCadenceFrameCount = 0
  private var processedCadenceWindowStartedAt: CFTimeInterval?
  private var processedCadenceFrameCount = 0
  private var didSignpostDepthUse = false
  private var lastViewportOrientation: UIInterfaceOrientation?
  private var lastVision3DRequestAt: CFTimeInterval = 0
  private var lastVision3DSignpostAt: CFTimeInterval = 0

  init(frameInterval: CFTimeInterval = 0.08) {
    baseFrameInterval = frameInterval
    if #available(iOS 17.0, *) {
      body3DEstimator = SpatialBody3DEstimator()
    } else {
      body3DEstimator = nil
    }
  }

  func setAssociationUncertainty(
    _ uncertainty: SpatialAssociationUncertainty
  ) {
    stateLock.lock()
    associationUncertainty = uncertainty
    stateLock.unlock()
  }

  func processIfNeeded<Context>(
    frame: ARFrame,
    viewport: SpatialViewportSnapshot,
    captureContext: () -> Context?,
    completion: @escaping (
      [SpatialBodyDetection],
      ARCamera,
      CGSize,
      UIInterfaceOrientation,
      Context,
      SpatialBodyPipelineDiagnostics
    ) -> Void
  ) {
    guard viewport.isUsable else {
      return
    }

    let now = CACurrentMediaTime()
    let frameInterval = adaptiveFrameInterval()
    let sourceCamera = frame.camera
    let cameraMotion = cameraMotion(from: sourceCamera.transform)

    stateLock.lock()
    let orientationChanged = lastViewportOrientation.map {
      $0 != viewport.orientation
    } ?? false
    lastViewportOrientation = viewport.orientation
    var cadenceFrameCount: Int?
    var cadenceWindowDuration: CFTimeInterval = 0
    if let windowStartedAt = frameCadenceWindowStartedAt {
      frameCadenceFrameCount += 1
      let elapsed = now - windowStartedAt
      if elapsed >= 1 {
        cadenceFrameCount = frameCadenceFrameCount
        cadenceWindowDuration = elapsed
        frameCadenceWindowStartedAt = now
        frameCadenceFrameCount = 0
      }
    } else {
      frameCadenceWindowStartedAt = now
      frameCadenceFrameCount = 1
    }
    let canProcess = !isRequestInFlight && now - lastRequestAt >= frameInterval
    var shouldSignpostCoalesced = false
    if canProcess {
      isRequestInFlight = true
      lastRequestAt = now
    } else if now - lastCoalescedSignpostAt >= 1 {
      lastCoalescedSignpostAt = now
      shouldSignpostCoalesced = true
    }
    let requestGeneration = generation
    stateLock.unlock()

    if let cadenceFrameCount {
      SpatialPerformance.signposter.emitEvent(
        "AR frame callback cadence",
        "Frames: \(cadenceFrameCount), window milliseconds: \(Int(cadenceWindowDuration * 1_000))"
      )
    }

    guard canProcess else {
      if shouldSignpostCoalesced {
        SpatialPerformance.signposter.emitEvent("Vision frame coalesced")
      }
      return
    }

    guard let context = captureContext() else {
      stateLock.lock()
      isRequestInFlight = false
      stateLock.unlock()
      return
    }

    let pixelBuffer = frame.capturedImage
    let sourceTimestamp = frame.timestamp
    // ARFrame.timestamp is relative to the AR session. Fusion uses the
    // process monotonic clock, so sensor measurements need an explicit stamp
    // in that shared domain rather than the session-relative pose timestamp.
    let measurementTimestamp = now
    // Use unsmoothed depth for identity evidence when ARKit supplies it. The
    // selected source and its uncertainty are carried into fusion so device
    // traces can compare this choice with the smoothed fallback.
    let depthData: ARDepthData?
    let depthSource: SpatialDepthSource
    if let sceneDepth = frame.sceneDepth {
      depthData = sceneDepth
      depthSource = .rawSceneDepth
    } else if let smoothedSceneDepth = frame.smoothedSceneDepth {
      depthData = smoothedSceneDepth
      depthSource = .smoothedSceneDepth
    } else {
      depthData = nil
      depthSource = .fallback
    }
    let displayTransform = frame.displayTransform(
      for: viewport.orientation,
      viewportSize: viewport.size
    )
    let visionOrientation = SpatialVisionOrientation.capturedImage
    let fullPoseInterval = adaptiveFullPoseInterval(
      cameraMotion: cameraMotion
    )

    stateLock.lock()
    let shouldSignpostDepthUse = depthData != nil && !didSignpostDepthUse
    if shouldSignpostDepthUse {
      didSignpostDepthUse = true
    }
    stateLock.unlock()
    if shouldSignpostDepthUse {
      SpatialPerformance.signposter.emitEvent(
        "LiDAR scene depth available",
        "Source: \(depthSource.rawValue, privacy: .public)"
      )
    }

    visionQueue.async { [weak self] in
      guard let self else {
        return
      }

      let processingStartedAt = CACurrentMediaTime()
      var didRunFullPose = false
      var detections: [SpatialBodyDetection] = []
      var bodyDiagnostics = SpatialBodyPipelineDiagnostics.empty
      var processedCadenceCount: Int?
      var processedCadenceWindowDuration: CFTimeInterval = 0

      autoreleasepool {
        if orientationChanged {
          self.bodyPoseDetector.reset()
          SpatialPerformance.signposter.emitEvent(
            "Vision orientation changed"
          )
        }

        let bodyInterval = SpatialPerformance.signposter.beginInterval(
          "Vision body analysis"
        )
        detections = self.bodyPoseDetector.detectPeople(
          in: pixelBuffer,
          displayTransform: displayTransform,
          viewportSize: viewport.size,
          orientation: visionOrientation,
          fullDetectionInterval: fullPoseInterval,
          cameraMotion: cameraMotion,
          at: sourceTimestamp
        )
        didRunFullPose = self.bodyPoseDetector.lastWasFullPose
        bodyDiagnostics = self.bodyPoseDetector.diagnostics
        SpatialPerformance.signposter.endInterval(
          "Vision body analysis",
          bodyInterval
        )

        let depthInterval = SpatialPerformance.signposter.beginInterval(
          "Vision depth sampling"
        )
        detections = detections.map { detection in
          let estimate = self.bodyDepthEstimator.estimate(
            for: detection,
            depthData: depthData,
            displayTransform: displayTransform,
            viewportSize: viewport.size,
            cameraTransform: sourceCamera.transform,
            cameraIntrinsics: sourceCamera.intrinsics,
            imageResolution: sourceCamera.imageResolution,
            source: depthSource,
            measuredAt: measurementTimestamp
          )
          return detection.withDepth(
            estimate.depth,
            quality: estimate.quality,
            sampleCount: estimate.sampleCount,
            spread: estimate.spread,
            geometry: estimate.geometry,
            measurement: estimate.measurement
          )
        }
        SpatialPerformance.signposter.endInterval(
          "Vision depth sampling",
          depthInterval
        )

        let shouldRunVision3D = self.shouldRunVision3D(
          now: sourceTimestamp,
          detections: detections,
          hasDepthData: depthData != nil
        )
        if shouldRunVision3D,
          #available(iOS 17.0, *),
          let body3DEstimator = self.body3DEstimator
            as? SpatialBody3DEstimator
        {
          self.stateLock.lock()
          self.lastVision3DRequestAt = sourceTimestamp
          self.stateLock.unlock()
          let vision3DInterval = SpatialPerformance.signposter.beginInterval(
            "Vision 3D body analysis"
          )
          let supplementaryGeometry = body3DEstimator.estimate(
            in: pixelBuffer,
            orientation: visionOrientation,
            displayTransform: displayTransform,
            viewportSize: viewport.size,
            cameraTransform: sourceCamera.transform,
            detections: detections,
            at: sourceTimestamp
          )
          detections = detections.enumerated().map { index, detection in
            detection.withSupplementaryWorldGeometry(
              supplementaryGeometry[index],
              cameraTransform: sourceCamera.transform,
              measuredAt: measurementTimestamp
            )
          }
          SpatialPerformance.signposter.endInterval(
            "Vision 3D body analysis",
            vision3DInterval
          )

          let now = CACurrentMediaTime()
          self.stateLock.lock()
          let shouldEmitVision3DSignpost =
            now - self.lastVision3DSignpostAt >= 1
          if shouldEmitVision3DSignpost {
            self.lastVision3DSignpostAt = now
          }
          self.stateLock.unlock()
          if shouldEmitVision3DSignpost {
            SpatialPerformance.signposter.emitEvent(
              "Vision 3D pose completed",
              "Bodies: \(body3DEstimator.lastObservationCount), duration milliseconds: \(Int(body3DEstimator.lastProcessingDuration * 1_000))"
            )
          }
        }
      }

      let processingDuration = CACurrentMediaTime() - processingStartedAt
      self.stateLock.lock()
      let shouldDeliver = requestGeneration == self.generation
      self.isRequestInFlight = false
      self.lastProcessingDuration = processingDuration
      self.lastDetectionCount = detections.count
      self.lastTrackingConfidence = self.bodyPoseDetector.lastTrackingConfidence
      self.lastHadOverlapPressure = self.bodyPoseDetector.hasOverlapPressure
      if let windowStartedAt = self.processedCadenceWindowStartedAt {
        self.processedCadenceFrameCount += 1
        let elapsed = CACurrentMediaTime() - windowStartedAt
        if elapsed >= 1 {
          processedCadenceCount = self.processedCadenceFrameCount
          processedCadenceWindowDuration = elapsed
          self.processedCadenceWindowStartedAt = CACurrentMediaTime()
          self.processedCadenceFrameCount = 0
        }
      } else {
        self.processedCadenceWindowStartedAt = CACurrentMediaTime()
        self.processedCadenceFrameCount = 1
      }
      self.stateLock.unlock()

      guard shouldDeliver else {
        return
      }

      SpatialPerformance.signposter.emitEvent(
        didRunFullPose ? "Vision full pose completed" : "Vision tracking completed",
        "Bodies: \(detections.count), duration milliseconds: \(Int(processingDuration * 1_000))"
      )
      if let processedCadenceCount {
        SpatialPerformance.signposter.emitEvent(
          "Processed Vision cadence",
          "Frames: \(processedCadenceCount), window milliseconds: \(Int(processedCadenceWindowDuration * 1_000))"
        )
      }
      completion(
        detections,
        sourceCamera,
        viewport.size,
        viewport.orientation,
        context,
        bodyDiagnostics
      )
    }
  }

  func reset() {
    stateLock.lock()
    generation &+= 1
    lastRequestAt = 0
    lastProcessingDuration = 0
    lastLowPowerMode = nil
    lastDetectionCount = 0
    lastTrackingConfidence = 1
    lastHadOverlapPressure = false
    associationUncertainty = .uncertain
    lastCameraTransform = nil
    lastCoalescedSignpostAt = 0
    frameCadenceWindowStartedAt = nil
    frameCadenceFrameCount = 0
    processedCadenceWindowStartedAt = nil
    processedCadenceFrameCount = 0
    didSignpostDepthUse = false
    lastViewportOrientation = nil
    lastVision3DRequestAt = 0
    lastVision3DSignpostAt = 0
    stateLock.unlock()

    visionQueue.async { [weak self] in
      guard let self else {
        return
      }

      self.bodyPoseDetector.reset()
      if #available(iOS 17.0, *),
        let body3DEstimator = self.body3DEstimator
          as? SpatialBody3DEstimator
      {
        body3DEstimator.reset()
      }
    }
  }

  private func shouldRunVision3D(
    now: CFTimeInterval,
    detections: [SpatialBodyDetection],
    hasDepthData: Bool
  ) -> Bool {
    guard #available(iOS 17.0, *) else {
      return false
    }

    guard let body3DEstimator = body3DEstimator
      as? SpatialBody3DEstimator,
      body3DEstimator.isSupported,
      !detections.isEmpty,
      detections.count <= SpatialVisionTuning.vision3DMaximumBodyCount
    else {
      return false
    }

    stateLock.lock()
    let uncertainty = associationUncertainty
    let trackingConfidence = lastTrackingConfidence
    let lastRequestAt = lastVision3DRequestAt
    stateLock.unlock()

    let minimumInterval = uncertainty == .highlyAmbiguous
      ? SpatialVisionTuning.vision3DHighlyAmbiguousInterval
      : SpatialVisionTuning.vision3DMinimumInterval
    guard now - lastRequestAt >= minimumInterval else {
      return false
    }

    let missingWorldGeometry = detections.contains {
      $0.worldGeometry == nil
    }
    let ambiguityRequires3D = uncertainty != .stable
      || detections.count > 1
      || trackingConfidence < SpatialVisionTuning.trackingRefreshConfidence

    // On non-LiDAR devices this is the sparse spatial fallback. With depth,
    // 3D pose only spends work when the association needs another modality.
    return !hasDepthData || missingWorldGeometry && ambiguityRequires3D
  }

  private func adaptiveFrameInterval() -> CFTimeInterval {
    let processInfo = ProcessInfo.processInfo
    let thermalState = processInfo.thermalState
    let lowPowerMode = processInfo.isLowPowerModeEnabled

    stateLock.lock()
    let previousThermalState = lastThermalState
    let previousLowPowerMode = lastLowPowerMode
    lastThermalState = thermalState
    lastLowPowerMode = lowPowerMode
    let processingDuration = lastProcessingDuration
    stateLock.unlock()

    if thermalState != previousThermalState {
      SpatialPerformance.signposter.emitEvent(
        "Vision thermal state",
        "State: \(String(describing: thermalState), privacy: .public)"
      )
    }
    if lowPowerMode != previousLowPowerMode {
      SpatialPerformance.signposter.emitEvent(
        "Vision Low Power Mode",
        "Enabled: \(lowPowerMode)"
      )
    }

    let thermalInterval: CFTimeInterval
    switch thermalState {
    case .nominal:
      thermalInterval = baseFrameInterval
    case .fair:
      thermalInterval = 0.1
    case .serious:
      thermalInterval = 0.16
    case .critical:
      thermalInterval = SpatialVisionTuning.severeThermalFrameInterval
    @unknown default:
      thermalInterval = 0.16
    }

    let powerInterval: CFTimeInterval = lowPowerMode
      ? 0.14
      : baseFrameInterval
    let processingInterval = min(0.3, processingDuration * 1.2)

    return max(
      baseFrameInterval,
      thermalInterval,
      powerInterval,
      processingInterval
    )
  }

  private func adaptiveFullPoseInterval(
    cameraMotion: Float
  ) -> CFTimeInterval {
    let processInfo = ProcessInfo.processInfo
    let thermalState = processInfo.thermalState

    stateLock.lock()
    let bodyCount = lastDetectionCount
    let trackingConfidence = lastTrackingConfidence
    let overlapPressure = lastHadOverlapPressure
    let currentAssociationUncertainty = self.associationUncertainty
    stateLock.unlock()

    if thermalState == .serious || thermalState == .critical {
      return SpatialVisionTuning.thermalFullPoseInterval
    }

    switch currentAssociationUncertainty {
    case .highlyAmbiguous:
      return SpatialVisionTuning.highlyAmbiguousFullPoseInterval
    case .uncertain:
      return SpatialVisionTuning.uncertainFullPoseInterval
    case .stable:
      break
    }

    let active = bodyCount > 1
      || overlapPressure
      || trackingConfidence < 0.55
      || cameraMotion >= SpatialVisionTuning.cameraMotionThreshold

    return active
      ? SpatialVisionTuning.activeFullPoseInterval
      : SpatialVisionTuning.stableFullPoseInterval
  }

  private func cameraMotion(from transform: simd_float4x4) -> Float {
    stateLock.lock()
    defer {
      lastCameraTransform = transform
      stateLock.unlock()
    }

    guard let lastCameraTransform else {
      return 0
    }

    let translation = simd_distance(
      SIMD3<Float>(
        transform.columns.3.x,
        transform.columns.3.y,
        transform.columns.3.z
      ),
      SIMD3<Float>(
        lastCameraTransform.columns.3.x,
        lastCameraTransform.columns.3.y,
        lastCameraTransform.columns.3.z
      )
    )
    return translation
  }
}
