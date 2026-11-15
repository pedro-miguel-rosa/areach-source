import ExpoModulesCore
import UIKit

struct SpatialAttendeeProfile: Record {
  @Field var askMeAbout: [String] = []
  @Field var headline: String = ""
  @Field var name: String = ""
  @Field var userId: String = ""
}

public class AReachSpatialModule: Module {
  public func definition() -> ModuleDefinition {
    Name("AReachSpatial")

    Events(
      "onNearbyCredentialDiscovered",
      "onNearbyPeerUpdate",
      "onNearbyPeerLost",
      "onNearbySessionState"
    )

    OnCreate { [weak self] in
      AReachSpatialRuntime.shared.sendEvent = {
        [weak self] eventName, payload in
        self?.sendEvent(eventName, payload)
      }
    }

    Function("isNearbyInteractionSupported") {
      NearbyDiscoveryService.isSupported
    }

    Function("nearbyIdentity") {
      AReachSpatialRuntime.shared.nearbyIdentity()
    }

    Function("nearbyPeerPresenceSnapshot") {
      AReachSpatialRuntime.shared.nearbyPeerPresenceSnapshot()
    }

    Function("nearbyCredentialSnapshot") {
      AReachSpatialRuntime.shared.nearbyCredentialSnapshot()
    }

    Function("nearbySessionStateSnapshot") {
      AReachSpatialRuntime.shared.nearbySessionStateSnapshot()
    }

    Function("isBackgroundNearbyInteractionSupported") {
      SpatialCapabilityProfile.current.backgroundResponderSupported
    }

    Function("isBackgroundResponderActive") {
      AReachSpatialRuntime.shared.isBackgroundResponderActive()
    }

    #if DEBUG
      Function("debugReplayData") {
        AReachSpatialRuntime.shared.debugReplayData()?.base64EncodedString()
      }

      Function("clearDebugReplay") {
        AReachSpatialRuntime.shared.clearDebugReplay()
      }
    #endif

    AsyncFunction("startNearbyDiscovery") {
      (
        eventScope: String,
        credential: String,
        transportKey: String,
        expiresAt: Double
      ) in
      try AReachSpatialRuntime.shared.startNearbyDiscovery(
        eventScope: eventScope,
        credential: credential,
        transportKey: transportKey,
        expiresAt: expiresAt
      )
    }

    AsyncFunction("updateNearbyDiscoveryCredential") {
      (eventScope: String, credential: String, expiresAt: Double) in
      AReachSpatialRuntime.shared.updateNearbyDiscoveryCredential(
        eventScope: eventScope,
        credential: credential,
        expiresAt: expiresAt
      )
    }

    AsyncFunction("resolveNearbyPeer") {
      (
        peerId: String,
        credential: String,
        publicKey: String,
        userId: String
      ) in
      AReachSpatialRuntime.shared.resolveNearbyPeer(
        peerId: peerId,
        credential: credential,
        publicKey: publicKey,
        userId: userId
      )
    }

    AsyncFunction("setNearbyRangingMode") { (mode: String) in
      AReachSpatialRuntime.shared.setNearbyRangingMode(mode)
    }

    AsyncFunction("setBackgroundResponderActive") { (active: Bool) in
      _ = AReachSpatialRuntime.shared.setBackgroundResponderActive(active)
    }

    AsyncFunction("stopNearbyDiscovery") {
      AReachSpatialRuntime.shared.stopNearbyDiscovery()
    }

    View(AReachSpatialView.self) {
      Events(
        "onCameraStateChange",
        "onOverlayPress"
      )
      Prop("attendeeProfiles", [SpatialAttendeeProfile]()) {
        (view: AReachSpatialView, profiles: [SpatialAttendeeProfile]) in
        view.setAttendeeProfiles(profiles)
      }
    }
  }
}

public final class AReachSpatialAppDelegateSubscriber:
  ExpoAppDelegateSubscriber
{
  public func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions:
      [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let isBluetoothRestorationLaunch =
      application.applicationState == .background
      || launchOptions?[.bluetoothCentrals] != nil
      || launchOptions?[.bluetoothPeripherals] != nil
    AReachSpatialRuntime.shared.prepareNearbyDiscoveryForLaunch(
      restoringInBackground: isBluetoothRestorationLaunch
    )
    AReachSpatialRuntime.shared.setNearbyDiscoveryAppActive(
      application.applicationState == .active
    )
    return true
  }

  public func applicationDidBecomeActive(_ application: UIApplication) {
    AReachSpatialRuntime.shared.setNearbyDiscoveryAppActive(true)
  }

  public func applicationDidEnterBackground(_ application: UIApplication) {
    AReachSpatialRuntime.shared.setNearbyDiscoveryAppActive(false)
  }
}
