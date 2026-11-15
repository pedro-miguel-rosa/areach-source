import Foundation
import QuartzCore
import simd

/// The small, immutable value graph exchanged between native spatial
/// subsystems.  It is deliberately kept native: JavaScript receives only
/// resolved peer/application events and verified overlay actions.
enum SpatialPeerPresenceState: String {
  case discovered
  case identityResolved
  case stale
}

enum SpatialPeerRangingState: String {
  case idle
  case requesting
  case activeLegacy
  case activeEDM
  case cooldown
}

enum SpatialPeerTransportState: String {
  case unavailable
  case bluetooth
  case localNetwork
  case authenticatedLocalNetwork
}

enum SpatialViewerTrackingQuality: String {
  case unknown
  case limited
  case normal
}

enum SpatialARTrackingState: String {
  case unknown
  case normal
  case limited
  case notAvailable
  case interrupted
}

struct SpatialViewerState {
  let cameraTransform: simd_float4x4
  /// The projection matrix is captured with the camera transform so matching
  /// can apply the same viewport/FOV geometry as the rendered camera frame.
  /// It is optional for backwards-compatible replay fixtures.
  let cameraProjectionMatrix: simd_float4x4?
  let viewport: SpatialViewportSnapshot
  let trackingQuality: SpatialViewerTrackingQuality
  let timestamp: CFTimeInterval
  /// The horizontal projection matrix scale lets pure matching policy derive
  /// a body bearing without assuming a portrait-only screen-X mapping.
  let cameraHorizontalProjectionScale: Float?

  init(
    cameraTransform: simd_float4x4,
    cameraProjectionMatrix: simd_float4x4? = nil,
    viewport: SpatialViewportSnapshot,
    trackingQuality: SpatialViewerTrackingQuality,
    timestamp: CFTimeInterval,
    cameraHorizontalProjectionScale: Float? = nil
  ) {
    self.cameraTransform = cameraTransform
    self.cameraProjectionMatrix = cameraProjectionMatrix
    self.viewport = viewport
    self.trackingQuality = trackingQuality
    self.timestamp = timestamp
    self.cameraHorizontalProjectionScale = cameraHorizontalProjectionScale
  }
}

struct SpatialAssociationEvidence {
  let mode: SpatialAssociationMode
  /// Every component is normalized to [0, 1]. Higher is better.
  let screenGeometry: Double
  let carryRegionProximity: Double
  let carryWorldProximity: Double
  let bodyWorldProximity: Double
  let distanceConsistency: Double
  let distanceNormalizedResidual: Double?
  let directionalAlignment: Double
  let measurementQuality: Double
  let cameraAssistance: Double
  let bodyPoseConfidence: Double
  let peerFreshness: Double
  let poseFreshness: Double
  let motionAgreement: Double
  let continuity: Double
  let switchPenalty: Double
  let hasScreenGeometry: Bool
  let hasCarryRegionProximity: Bool
  let hasCarryWorldProximity: Bool
  let hasBodyWorldProximity: Bool
  let hasDistanceConsistency: Bool
  let hasDirectionalAlignment: Bool
  let hasDirectionalContradiction: Bool
  let hasMotionAgreement: Bool
  let hasContinuity: Bool
  let hasContradictorySpatialEvidence: Bool

  var confidence: Double {
    var weightedScore = 0.0
    var availableWeight = 0.0

    func add(_ value: Double, weight: Double, available: Bool = true) {
      guard available else {
        return
      }

      weightedScore += value * weight
      availableWeight += weight
    }

    add(
      screenGeometry,
      weight: SpatialAssociationTuning.screenGeometryWeight,
      available: hasScreenGeometry
    )
    add(
      carryRegionProximity,
      weight: SpatialAssociationTuning.carryRegionWeight,
      available: hasCarryRegionProximity
    )
    add(
      carryWorldProximity,
      weight: SpatialAssociationTuning.carryWorldWeight,
      available: hasCarryWorldProximity
    )
    add(
      bodyWorldProximity,
      weight: SpatialAssociationTuning.bodyWorldWeight,
      available: hasBodyWorldProximity
    )
    add(
      distanceConsistency,
      weight: SpatialAssociationTuning.distanceConsistencyWeight,
      available: hasDistanceConsistency
    )
    add(
      directionalAlignment,
      weight: SpatialAssociationTuning.directionalAlignmentWeight,
      available: hasDirectionalAlignment
    )
    add(
      measurementQuality,
      weight: SpatialAssociationTuning.measurementQualityWeight
    )
    add(
      cameraAssistance,
      weight: SpatialAssociationTuning.cameraAssistanceWeight
    )
    add(bodyPoseConfidence, weight: SpatialAssociationTuning.bodyPoseWeight)
    add(peerFreshness, weight: SpatialAssociationTuning.peerFreshnessWeight)
    add(poseFreshness, weight: SpatialAssociationTuning.poseFreshnessWeight)
    add(
      motionAgreement,
      weight: SpatialAssociationTuning.motionAgreementWeight,
      available: hasMotionAgreement
    )
    add(
      continuity,
      weight: SpatialAssociationTuning.continuityWeight,
      available: hasContinuity
    )

    guard availableWeight > 0 else {
      return 0
    }

    let normalizedScore = weightedScore / availableWeight
      - switchPenalty * SpatialAssociationTuning.switchPenaltyWeight
    return max(0, min(1, normalizedScore))
  }

  /// Hungarian assignment consumes a cost. Invalid pairs use the unmatched
  /// cost before assignment and never enter this conversion.
  var cost: Double {
    (1 - confidence) * SpatialAssociationTuning.assignmentCostScale
  }
}

struct SpatialAssociation {
  let peerId: String
  let userId: String
  let bodyTrackId: String?
  let state: SpatialAssociationState
  let path: SpatialAssociationPath
  let mode: SpatialAssociationMode
  let confidence: Double
  let ambiguityMargin: Double
  let evidence: SpatialAssociationEvidence?
  let lastUpdatedAt: CFTimeInterval
  let lastBodyEvidenceAt: CFTimeInterval
  let lastSpatialEvidenceAt: CFTimeInterval
}

struct SpatialWorldSnapshot {
  let viewer: SpatialViewerState
  let peers: [NearbyPeerSpatialSnapshot]
  let bodies: [SpatialBodyDetection]
  let associations: [SpatialAssociation]
  let timestamp: CFTimeInterval

  func withAssociations(_ associations: [SpatialAssociation]) -> SpatialWorldSnapshot {
    SpatialWorldSnapshot(
      viewer: viewer,
      peers: peers,
      bodies: bodies,
      associations: associations,
      timestamp: timestamp
    )
  }
}
