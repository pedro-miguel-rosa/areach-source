import ARKit

extension AReachSpatialView: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        processVisionIfNeeded(frame: frame)
    }

    func session(
        _ session: ARSession,
        cameraDidChangeTrackingState camera: ARCamera
    ) {
        AReachSpatialRuntime.shared.updateARTrackingState(camera.trackingState)
        handleCameraTrackingState(camera.trackingState)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onCameraStateChange([
                "state": "failed",
                "message": error.localizedDescription,
            ])
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        AReachSpatialRuntime.shared.notifyARSessionInterrupted()
        handleCameraInterruption()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        AReachSpatialRuntime.shared.notifyARSessionInterruptionEnded()
        DispatchQueue.main.async { [weak self] in
            self?.onCameraStateChange(["state": "initializing"])
        }
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        // Nearby Interaction camera assistance requires an AR session whose
        // delegate declines relocalization.
        false
    }
}
