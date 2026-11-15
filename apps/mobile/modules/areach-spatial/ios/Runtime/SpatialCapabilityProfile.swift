import ARKit
import Foundation
import NearbyInteraction
import Vision

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Immutable hardware and OS capability snapshot shared by the spatial
/// runtime. Feature decisions should be made from this value rather than by
/// probing unrelated frameworks in hot paths.
struct SpatialCapabilityProfile: CustomStringConvertible {
  let nearbyInteractionSupported: Bool
  let preciseDistanceMeasurement: Bool
  let directionMeasurement: Bool
  let cameraAssistance: Bool
  let extendedDistanceMeasurement: Bool
  let arWorldTracking: Bool
  let sceneDepth: Bool
  let smoothedSceneDepth: Bool
  let lidarDerivedDepth: Bool
  let vision2DBodyPose: Bool
  let vision3DBodyPose: Bool
  /// Immutable hardware/OS support. Live Activity authorization is dynamic
  /// and is intentionally queried separately below.
  let backgroundResponderHardwareSupported: Bool

  var liveActivityAuthorized: Bool {
    Self.areLiveActivitiesEnabled
  }

  var backgroundResponderSupported: Bool {
    backgroundResponderHardwareSupported && liveActivityAuthorized
  }

  static let current = makeCurrent()

  var description: String {
    [
      "ni=\(nearbyInteractionSupported)",
      "preciseDistance=\(preciseDistanceMeasurement)",
      "direction=\(directionMeasurement)",
      "cameraAssistance=\(cameraAssistance)",
      "edm=\(extendedDistanceMeasurement)",
      "arWorld=\(arWorldTracking)",
      "sceneDepth=\(sceneDepth)",
      "smoothedDepth=\(smoothedSceneDepth)",
      "vision2D=\(vision2DBodyPose)",
      "vision3D=\(vision3DBodyPose)",
      "liveActivity=\(liveActivityAuthorized)",
      "backgroundResponder=\(backgroundResponderSupported)",
    ].joined(separator: ",")
  }

  private static func makeCurrent() -> SpatialCapabilityProfile {
    let nearbyCapabilities: NIDeviceCapability?
    if #available(iOS 16.0, *) {
      nearbyCapabilities = NISession.deviceCapabilities
    } else {
      nearbyCapabilities = nil
    }

    let preciseDistance = nearbyCapabilities?.supportsPreciseDistanceMeasurement ?? false
    let direction = nearbyCapabilities?.supportsDirectionMeasurement ?? false
    let cameraAssistance = nearbyCapabilities?.supportsCameraAssistance ?? false
    let extendedDistance: Bool
    if #available(iOS 17.0, *) {
      extendedDistance = nearbyCapabilities?.supportsExtendedDistanceMeasurement ?? false
    } else {
      extendedDistance = false
    }

    let arWorldTracking = ARWorldTrackingConfiguration.isSupported
    let sceneDepth: Bool
    let smoothedSceneDepth: Bool
    if #available(iOS 14.0, *) {
      sceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
      smoothedSceneDepth = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    } else {
      sceneDepth = false
      smoothedSceneDepth = false
    }

    let vision2D: Bool
    if #available(iOS 14.0, *) {
      vision2D = true
    } else {
      vision2D = false
    }
    let vision3D: Bool
    if #available(iOS 17.0, *) {
      let request = VNDetectHumanBodyPose3DRequest()
      vision3D = !((try? request.supportedJointNames) ?? []).isEmpty
    } else {
      vision3D = false
    }

    let backgroundResponderSupported: Bool
    if #available(iOS 18.4, *) {
      backgroundResponderSupported = direction
    } else {
      backgroundResponderSupported = false
    }

    return SpatialCapabilityProfile(
      nearbyInteractionSupported: preciseDistance || direction,
      preciseDistanceMeasurement: preciseDistance,
      directionMeasurement: direction,
      cameraAssistance: cameraAssistance,
      extendedDistanceMeasurement: extendedDistance,
      arWorldTracking: arWorldTracking,
      sceneDepth: sceneDepth,
      smoothedSceneDepth: smoothedSceneDepth,
      // Scene-depth support is the capability exposed by ARKit for LiDAR
      // world-depth frames. Runtime frames still remain the final authority.
      lidarDerivedDepth: sceneDepth,
      vision2DBodyPose: vision2D,
      vision3DBodyPose: vision3D,
      backgroundResponderHardwareSupported: backgroundResponderSupported
    )
  }

  private static var areLiveActivitiesEnabled: Bool {
    #if canImport(ActivityKit)
      if #available(iOS 16.1, *) {
        return ActivityAuthorizationInfo().areActivitiesEnabled
      }
    #endif

    return false
  }
}

enum SpatialBackgroundResponderState: String {
  case unavailable
  case capabilityOnly
  case active
  case suspended
}
