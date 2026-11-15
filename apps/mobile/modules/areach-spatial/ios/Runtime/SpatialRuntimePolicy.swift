import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
import simd
import UIKit

/// The native spatial runtime has different responsibilities depending on
/// whether it is rendering a camera view or merely keeping an event presence
/// channel alive.  Keeping this explicit prevents background devices from
/// accidentally participating in the foreground ranging rotation.
enum SpatialRuntimeRole: String {
  case cameraViewer
  case foregroundProximity
  case backgroundResponder
  case suspended

  init(
    isAppActive: Bool,
    cameraConsumerActive: Bool,
    activeLiveEventPresence: Bool,
    backgroundResponderActive: Bool
  ) {
    if !isAppActive, backgroundResponderActive {
      self = .backgroundResponder
    } else if !isAppActive {
      self = .suspended
    } else if cameraConsumerActive {
      self = .cameraViewer
    } else if activeLiveEventPresence {
      self = .foregroundProximity
    } else {
      self = .suspended
    }
  }

  var allowsProactiveRanging: Bool {
    self == .cameraViewer || self == .foregroundProximity
  }
}

enum SpatialPresencePhase: String {
  case idle
  case credentialReady
  case presenceReady
  case backgroundCapable
  case active
  case stopping
}

enum SpatialAssociationUncertainty: String {
  case stable
  case uncertain
  case highlyAmbiguous
}

enum SpatialBluetoothDiscoveryIntensity: String {
  case backgroundPassive
  case foregroundNormal
  case cameraAcquisition
}

enum SpatialVisionTuning {
  static let stableFullPoseInterval: CFTimeInterval = 0.25
  static let activeFullPoseInterval: CFTimeInterval = 0.12
  static let uncertainFullPoseInterval: CFTimeInterval = 0.1
  static let highlyAmbiguousFullPoseInterval: CFTimeInterval = 0.08
  static let thermalFullPoseInterval: CFTimeInterval = 0.4
  static let severeThermalFrameInterval: CFTimeInterval = 0.25
  static let minimumTrackingConfidence: Float = 0.3
  static let ambiguousOverlapThreshold: Double = 0.25
  static let cameraMotionThreshold: Float = 0.08
  static let trackingRefreshCenterMotion: Double = 0.1
  static let trackingRefreshExtentRatio: CGFloat = 1.12
  static let trackingRefreshAspectChange: Double = 0.16
  static let trackingRefreshConfidence: Float = 0.55
  static let maximumBodyPredictionInterval: CFTimeInterval = 0.35
  static let bodyTrackRetentionDuration: CFTimeInterval = 0.85
  static let bodyTrackMaximumCenterDisplacement: CGFloat = 1.1
  static let bodyTrackMaximumScaleRatio: CGFloat = 1.65
  static let bodyTrackMinimumFarIoU: Double = 0.02
  static let bodyTrackPositionMeasurementNoise: CGFloat = 24
  static let bodyTrackVelocityMeasurementNoise: CGFloat = 80
  static let vision3DMinimumInterval: CFTimeInterval = 0.32
  static let vision3DHighlyAmbiguousInterval: CFTimeInterval = 0.18
  static let vision3DMaximumBodyCount = 4
  static let vision3DPointQuality: Float = 0.62
  static let vision3DMinimumQuality: Float = 0.38
}

enum SpatialDepthTuning {
  static let maximumCarryRegions = 5
  static let neighborhoodRadius = 1
  static let minimumDepth: Float = 0.01
  static let maximumDepth: Float = 100
  static let minimumOutlierDistance: Float = 0.18
  static let outlierMADMultiplier: Float = 3
  static let acceptableSpread: Float = 0.75
  static let minimumSpreadQuality: Float = 0.2
  /// A point below this local coverage quality is not promoted into world
  /// geometry, but its scalar depth may still contribute to fallback fusion.
  static let minimumGeometryQuality: Float = 0.35
  static let carryVolumePocketRadii = SIMD3<Float>(0.32, 0.42, 0.28)
  static let carryVolumeTorsoRadii = SIMD3<Float>(0.38, 0.52, 0.32)
  static let carryVolumeHandRadii = SIMD3<Float>(0.25, 0.25, 0.25)
}

enum SpatialBluetoothTuning {
  static let maximumConcurrentConnections = 3
  static let normalRetryDelay: CFTimeInterval = 8
  static let cameraFirstRetryDelay: CFTimeInterval = 1.5
  static let maximumRetryDelay: CFTimeInterval = 30
  static let duplicateAdvertisementMinimumInterval: CFTimeInterval = 0.18
  static let advertisementStaleDuration: CFTimeInterval = 4
}

struct SpatialViewportSnapshot {
  let size: CGSize
  let orientation: UIInterfaceOrientation
  let version: UInt64
  let updatedAt: CFTimeInterval

  var isUsable: Bool {
    size.width > 0 && size.height > 0
  }
}

struct SpatialCameraInterest {
  let isNearBody: Bool
  let isNearCarryRegion: Bool
  let isTentative: Bool
  let isVerified: Bool
  let measuredAt: CFTimeInterval
  let peerId: String
  let projectedPoint: CGPoint?
  let score: Double
}

/// UIKit owns viewport updates. Processing queues read a value snapshot and
/// never reach back into a UIView or UIWindow for geometry.
final class SpatialViewportState {
  private let lock = NSLock()
  private var current = SpatialViewportSnapshot(
    size: .zero,
    orientation: .portrait,
    version: 0,
    updatedAt: 0
  )

  func update(size: CGSize, orientation: UIInterfaceOrientation) {
    lock.lock()
    defer { lock.unlock() }

    current = SpatialViewportSnapshot(
      size: size,
      orientation: Self.normalizedOrientation(orientation),
      version: current.version &+ 1,
      updatedAt: CACurrentMediaTime()
    )
  }

  func snapshot() -> SpatialViewportSnapshot {
    lock.lock()
    defer { lock.unlock() }
    return current
  }

  private static func normalizedOrientation(
    _ orientation: UIInterfaceOrientation
  ) -> UIInterfaceOrientation {
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

/// Vision receives the raw ARFrame capturedImage. Keep its coordinates in the
/// same image space that ARFrame.displayTransform expects; that transform is
/// responsible for adapting the image to the interface orientation.
enum SpatialVisionOrientation {
  static let capturedImage: CGImagePropertyOrientation = .up
}
