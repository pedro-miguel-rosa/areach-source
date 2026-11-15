import ARKit
import AVFoundation
import RealityKit
import UIKit

final class CameraSession {
  private let arSessionQueue = DispatchQueue(
    label: "io.areach.spatial.ar-session",
    qos: .userInitiated
  )

  let arView = ARView(
    frame: .zero,
    cameraMode: .ar,
    automaticallyConfigureSession: false
  )

  private(set) var isRunning = false

  var session: ARSession {
    arView.session
  }

  init() {
    arView.backgroundColor = .black
  }

  func setDelegate(_ delegate: ARSessionDelegate?) {
    dispatchPrecondition(condition: .onQueue(.main))
    arView.session.delegateQueue = arSessionQueue
    arView.session.delegate = delegate
  }

  func start(
    shouldStart: @escaping () -> Bool,
    onStateChange: @escaping ([String: Any]) -> Void,
    onSessionChange: @escaping (ARSession?) -> Void
  ) {
    guard ARWorldTrackingConfiguration.isSupported else {
      onStateChange([
        "state": "unsupported",
        "message": "AR world tracking is unavailable on this device.",
      ])
      return
    }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      runIfNeeded(
        shouldStart: shouldStart,
        onStateChange: onStateChange,
        onSessionChange: onSessionChange
      )
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) {
        [weak self] isGranted in
        DispatchQueue.main.async {
          guard let self, shouldStart() else {
            return
          }

          if isGranted {
            self.runIfNeeded(
              shouldStart: shouldStart,
              onStateChange: onStateChange,
              onSessionChange: onSessionChange
            )
          } else {
            onStateChange([
              "state": "failed",
              "message": "Camera permission denied.",
              "reason": "permission_denied",
            ])
          }
        }
      }
    case .denied, .restricted:
      onStateChange([
        "state": "failed",
        "message": "Camera permission denied.",
        "reason": "permission_denied",
      ])
    @unknown default:
      onStateChange([
        "state": "failed",
        "message": "Camera unavailable.",
      ])
    }
  }

  func stop(onSessionChange: (ARSession?) -> Void) {
    guard isRunning else {
      return
    }

    arView.session.pause()
    isRunning = false
    onSessionChange(nil)
  }

  private func runIfNeeded(
    shouldStart: () -> Bool,
    onStateChange: ([String: Any]) -> Void,
    onSessionChange: (ARSession?) -> Void
  ) {
    guard shouldStart(), !isRunning else {
      return
    }

    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravity
    configuration.isCollaborationEnabled = false

    if #available(iOS 13.0, *) {
      configuration.userFaceTrackingEnabled = false
    }

    let capabilities = SpatialCapabilityProfile.current
    // Matching prefers the frame-local, unsmoothed depth signal. Vision keeps
    // the source tag on every scalar measurement and can fall back to the
    // smoothed semantic when raw scene depth is unavailable.
    if capabilities.sceneDepth {
      configuration.frameSemantics.insert(.sceneDepth)
    }
    if capabilities.smoothedSceneDepth {
      configuration.frameSemantics.insert(.smoothedSceneDepth)
    }

    arView.session.run(
      configuration,
      options: [.resetTracking, .removeExistingAnchors]
    )
    isRunning = true

    onSessionChange(arView.session)
    onStateChange(["state": "initializing"])
  }
}
