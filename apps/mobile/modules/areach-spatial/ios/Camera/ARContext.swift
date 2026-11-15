import ARKit
import QuartzCore
import UIKit
import simd

struct ARProjectionSnapshot {
  let camera: ARCamera
  let viewport: SpatialViewportSnapshot
  let capturedAt: CFTimeInterval
}

/// Thread-safe hand-off of the small amount of AR state needed for projection.
/// ARSession itself remains owned by ARKit/NI; frame processing consumes the
/// latest camera and viewport snapshots instead of reading currentFrame from
/// an arbitrary queue.
final class ARContext {
  private let viewportState = SpatialViewportState()
  private let cameraLock = NSLock()
  private var latestCamera: ARCamera?

  func setARSession(
    _ session: ARSession?,
    viewportSize: CGSize,
    orientation: UIInterfaceOrientation
  ) {
    dispatchPrecondition(condition: .onQueue(.main))
    viewportState.update(size: viewportSize, orientation: orientation)

    if session == nil {
      cameraLock.lock()
      latestCamera = nil
      cameraLock.unlock()
    }
  }

  func updateViewport(size: CGSize, orientation: UIInterfaceOrientation) {
    dispatchPrecondition(condition: .onQueue(.main))
    viewportState.update(size: size, orientation: orientation)
  }

  func viewportSnapshot() -> SpatialViewportSnapshot {
    viewportState.snapshot()
  }

  func updateCamera(_ camera: ARCamera) {
    cameraLock.lock()
    latestCamera = camera
    cameraLock.unlock()
  }

  func project(worldPosition: SIMD3<Float>) -> CGPoint? {
    guard let snapshot = projectionSnapshot() else {
      return nil
    }

    return project(worldPosition: worldPosition, using: snapshot)
  }

  /// Captures one immutable camera/viewport pair for a fusion pass. The
  /// caller can project many peers without repeatedly taking the camera lock
  /// or observing mixed-frame camera state.
  func projectionSnapshot(
    camera: ARCamera,
    viewport: SpatialViewportSnapshot,
    capturedAt: CFTimeInterval = CACurrentMediaTime()
  ) -> ARProjectionSnapshot? {
    guard viewport.isUsable else {
      return nil
    }

    return ARProjectionSnapshot(
      camera: camera,
      viewport: viewport,
      capturedAt: capturedAt
    )
  }

  func projectionSnapshot() -> ARProjectionSnapshot? {
    let viewport = viewportState.snapshot()
    guard viewport.isUsable else {
      return nil
    }

    cameraLock.lock()
    let camera = latestCamera
    cameraLock.unlock()

    guard let camera else {
      return nil
    }

    return projectionSnapshot(camera: camera, viewport: viewport)
  }

  func project(
    worldPosition: SIMD3<Float>,
    using snapshot: ARProjectionSnapshot
  ) -> CGPoint? {
    Self.project(
      worldPosition: worldPosition,
      camera: snapshot.camera,
      viewport: snapshot.viewport
    )
  }

  func project(
    worldPosition: SIMD3<Float>,
    camera: ARCamera,
    viewport: SpatialViewportSnapshot
  ) -> CGPoint? {
    guard viewport.isUsable else {
      return nil
    }

    return Self.project(
      worldPosition: worldPosition,
      camera: camera,
      viewport: viewport
    )
  }

  private static func project(
    worldPosition: SIMD3<Float>,
    camera: ARCamera,
    viewport: SpatialViewportSnapshot
  ) -> CGPoint? {
    let cameraSpacePoint = simd_mul(
      simd_inverse(camera.transform),
      SIMD4<Float>(worldPosition.x, worldPosition.y, worldPosition.z, 1)
    )

    guard cameraSpacePoint.z < 0 else {
      return nil
    }

    let point = camera.projectPoint(
      worldPosition,
      orientation: viewport.orientation,
      viewportSize: viewport.size
    )

    guard point.x.isFinite, point.y.isFinite else {
      return nil
    }

    let horizontalMargin = viewport.size.width * 0.2
    let verticalMargin = viewport.size.height * 0.2

    guard
      point.x >= -horizontalMargin,
      point.x <= viewport.size.width + horizontalMargin,
      point.y >= -verticalMargin,
      point.y <= viewport.size.height + verticalMargin
    else {
      return nil
    }

    return point
  }
}
