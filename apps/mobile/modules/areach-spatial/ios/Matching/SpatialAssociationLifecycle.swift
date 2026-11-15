import CoreGraphics
import Foundation

/// The identity of an attendee is persistent for the lifetime of a nearby
/// event, while a Vision body-track identifier is only valid for the current
/// visible/recoverable track.
enum SpatialAssociationState: String, Equatable {
  case unmatched
  case tentative
  case verified
  case temporarilyOccluded
  case awaitingReacquisition
}

/// The path used to confirm a peer/body candidate.  Reacquisition is kept
/// separate from a true switch so a new Vision track does not inherit switch
/// protections merely because its identifier changed.
enum SpatialAssociationPath: String, Equatable {
  case initial
  case continuation
  case reacquisition
  case identitySwitch
}

enum SpatialAssociationMode: String {
  case cameraAssisted
  case directional
  case distanceOnly

  static func from(
    worldTransformAvailable: Bool,
    directionalMeasurementAvailable: Bool,
    cameraAssistanceConverged: Bool
  ) -> SpatialAssociationMode {
    guard worldTransformAvailable || directionalMeasurementAvailable else {
      return .distanceOnly
    }

    return worldTransformAvailable && cameraAssistanceConverged
      ? .cameraAssisted
      : .directional
  }
}

/// Rendering can be useful before the identity matcher is allowed to claim a
/// body. These modes never change `SpatialAssociationState` or one-to-one
/// identity assignment.
enum SpatialRenderMode: String, Equatable, Hashable {
  case exact
  case plausible
  case group
}

/// Identifies the source of a render point without implying anything about
/// identity confidence.  The overlay keeps this metadata so a source change
/// can be blended rather than presented as a discontinuous jump.
enum SpatialRenderAnchorSource: String, Equatable {
  case body
  case projectedPeer
  case group
  case retainedScreen
  case fallback
}

enum SpatialAssociationLifecyclePolicy {
  static func path(
    previousState: SpatialAssociationState?,
    activeBodyTrackId: String?,
    detectionId: String
  ) -> SpatialAssociationPath {
    guard let previousState else {
      return .initial
    }

    if activeBodyTrackId == detectionId {
      return .continuation
    }

    if previousState == .awaitingReacquisition {
      return .reacquisition
    }

    return .identitySwitch
  }

  static func shouldDetachBodyTrack(
    bodyTrackId: String?,
    isRecoverable: Bool
  ) -> Bool {
    bodyTrackId != nil && !isRecoverable
  }

  static func stateAfterBodyObservation(
    currentState: SpatialAssociationState,
    bodyTrackIsRecoverable: Bool,
    hasFreshBodyEvidence: Bool
  ) -> SpatialAssociationState {
    guard bodyTrackIsRecoverable else {
      return .awaitingReacquisition
    }

    guard hasFreshBodyEvidence else {
      return currentState == .awaitingReacquisition
        ? .awaitingReacquisition
        : .temporarilyOccluded
    }

    return .verified
  }
}

/// Association tuning is kept with the lifecycle policy so the same
/// continuation/reacquisition/switch ordering can be exercised by a
/// deterministic harness without importing ARKit or UIKit.
enum SpatialAssociationTuning {
  // These weights describe the relative value of normalized evidence. Carry
  // geometry and continuity dominate because a phone is usually in clothing
  // and identity switches are much more dangerous than a missed overlay.
  static let screenGeometryWeight = 0.13
  static let carryRegionWeight = 0.18
  static let carryWorldWeight = 0.22
  static let bodyWorldWeight = 0.14
  static let distanceConsistencyWeight = 0.08
  static let directionalAlignmentWeight = 0.14
  static let measurementQualityWeight = 0.08
  static let cameraAssistanceWeight = 0.05
  static let bodyPoseWeight = 0.08
  static let peerFreshnessWeight = 0.05
  static let poseFreshnessWeight = 0.04
  static let motionAgreementWeight = 0.04
  static let continuityWeight = 0.18
  static let switchPenaltyWeight = 0.12

  static let assignmentCostScale = 100.0
  static let unmatchedCost = assignmentCostScale
  /// The fallback path must work before camera assistance converges and on
  /// devices without scene depth. Fresh screen/carry evidence plus the
  /// ambiguity margin and two observations still keep this conservative.
  static let minimumNewConfidence = 0.62
  /// A detached, previously verified peer may use a dedicated middle path:
  /// stronger than first acquisition, but less conservative than moving an
  /// identity between two bodies that are still tracked.
  static let minimumReacquisitionConfidence = 0.68
  static let minimumSwitchConfidence = 0.78
  static let minimumContinuityConfidence = 0.42
  static let minimumNewAmbiguityMargin = 0.18
  static let minimumReacquisitionAmbiguityMargin = 0.20
  static let minimumSwitchAmbiguityMargin = 0.28
  static let minimumContinuityAmbiguityMargin = 0.07
  static let maximumWorldCarryDistance: Float = 1.35
  static let maximumWorldBodyDistance: Float = 1.75
  static let strongWorldCarryDistance: Float = 0.65
  static let maximumScreenOwnershipDistance = 1.15
  static let maximumPoseAgeForNewIdentity: CFTimeInterval = 0.6
  static let maximumTrackedBodyEvidenceAge: CFTimeInterval = 0.35
  static let initialConfirmationCount = 2
  static let reacquisitionConfirmationCount = 2
  static let switchConfirmationCount = 4
  static let pendingRetentionDuration: CFTimeInterval = 0.8
  /// Historical body/carry hints are bounded separately from peer identity.
  /// The peer-to-user identity is retained while the peer remains recoverable.
  static let reacquisitionContextRetentionDuration: CFTimeInterval = 8
  static let targetRetentionDuration: CFTimeInterval = 8
  static let screenOffsetSmoothingAlpha: CGFloat = 0.25

  /// Distance-only evidence can rank or render a candidate, but it cannot
  /// acquire, reacquire, or switch a peer to a body identity.
  static func allowsNewIdentityEvidence(
    mode: SpatialAssociationMode,
    hasFreshProjectableEvidence: Bool,
    hasFreshDirectionalEvidence: Bool
  ) -> Bool {
    switch mode {
    case .cameraAssisted, .directional:
      return hasFreshProjectableEvidence || hasFreshDirectionalEvidence
    case .distanceOnly:
      return false
    }
  }
}

/// Render-only tuning deliberately lives apart from identity confirmation.
/// These values make cards responsive without lowering the strict matcher
/// gates above.
enum SpatialRenderTuning {
  /// Camera cards are a small attention surface. This cap applies only to
  /// rendered attendee cards; discovery, ranging, and identity matching keep
  /// their existing peer sets.
  static let maximumVisibleOverlayCount = 3
  /// A reliable distance is an eligibility signal, not an identity signal.
  /// New cards enter inside this range, while selected cards get a wider exit
  /// range so they do not flicker at the boundary.
  static let strongProximityDistance: Float = 3.0
  static let newOverlayMaximumDistance: Float = 4.0
  static let retainedOverlayMaximumDistance: Float = 5.0
  static let selectionHysteresisDuration: CFTimeInterval = 0.75
  static let replacementScoreMargin = 0.12
  static let visibilityCenterWeight = 0.42
  static let visibilityProximityWeight = 0.38
  static let visibilityQualityWeight = 0.20
  static let visibilityContinuityBonus = 0.08
  static let visibilityMissingDistanceScore = 0.24
  static let maximumHardGateDistanceAge: CFTimeInterval = 0.9
  static let minimumHardGateDistanceQuality: Double = 0.68
  static let maximumHardGateDistanceUncertainty: Float = 0.9
  static let maximumHardGateRelativeUncertainty: Float = 0.18
  static let distanceEvidenceFreshnessScale: CFTimeInterval = 0.9
  static let distanceEvidenceQualityWeight = 0.60
  static let distanceEvidenceUncertaintyWeight = 0.25
  static let distanceEvidenceFreshnessWeight = 0.15

  /// Fresh body evidence remains a short-lived matching signal. It is kept
  /// separate from the longer render-continuity window below.
  static let maximumFreshBodyEvidenceAge: CFTimeInterval = 0.35
  /// An established card may bridge the same bounded interval in which the
  /// body-track manager can still recover a short Vision dropout. This is not
  /// identity evidence and is never used to acquire or switch a body.
  static let maximumRenderContinuityBodyLoss: CFTimeInterval = 0.85
  /// A display-link/output gap is shorter than body-track retention. It keeps
  /// the view from beginning a removal animation for one transient hand-off.
  static let maximumTransientTargetOutputGap: CFTimeInterval = 0.2
  static let maximumPeerEvidenceAge: CFTimeInterval = 2.5
  /// Directional/FOV acquisition remains strict, while an established render
  /// state gets enough time for one or two noisy projection samples to recover.
  static let maximumTransientContradiction: CFTimeInterval = 0.45

  /// Predicted body tracks are useful for rendering, but are never allowed to
  /// become identity evidence by this path.
  static let maximumMeaningfulBodyAge: CFTimeInterval =
    maximumRenderContinuityBodyLoss

  /// Singleton/group rendering accepts broader screen geometry than identity
  /// confirmation while still requiring a physically plausible signal.
  static let maximumFallbackScreenOwnershipDistance: Double = 1.75
  static let minimumFallbackScreenGeometry: Double = 0.08
  static let minimumFallbackCarryProximity: Double = 0.16
  static let minimumFallbackWorldProximity: Double = 0.18
  static let minimumFallbackDistanceConsistency: Double = 0.18
  static let maximumFallbackWorldDistance: Float = 1.75

  /// Persistent screen-anchor filtering. The dead zone suppresses tiny Vision
  /// joint changes; larger sustained movement receives a faster response.
  static let renderAnchorDeadZone: CGFloat = 2.5
  static let renderAnchorResponsiveDistance: CGFloat = 48
  static let renderAnchorMinimumResponseTime: CGFloat = 0.08
  static let renderAnchorMaximumResponseTime: CGFloat = 0.18
  static let renderAnchorSourceTransitionResponseTime: CGFloat = 0.16

  /// Body clustering is intentionally small-N and conservative when depth is
  /// available. The screen fallback is used only when depth cannot contradict
  /// the visual cluster.
  static let clusterScreenBoundsExpansion: CGFloat = 0.08
  static let maximumClusterScreenDistanceScale: CGFloat = 0.95
  static let maximumClusterWorldDistance: Float = 1.35
  static let minimumReliableClusterDepthQuality: Float = 0.45
  static let clusterAnchorSmoothingAlpha: CGFloat = 0.28
}

struct SpatialRenderAnchorUpdate: Equatable {
  let point: CGPoint
  let sourceChanged: Bool
  let suppressedJitter: Bool
}

/// Pure, display-rate anchor stabilization. This deliberately runs after the
/// matcher has chosen the semantically correct anchor, so it cannot weaken
/// identity or FOV gates. It is adaptive: tiny changes are ignored, while
/// larger movement converges more quickly.
enum SpatialRenderAnchorStabilityPolicy {
  static func update(
    current: CGPoint,
    raw: CGPoint,
    previousSource: SpatialRenderAnchorSource?,
    source: SpatialRenderAnchorSource,
    elapsed: CGFloat
  ) -> SpatialRenderAnchorUpdate {
    let sourceChanged = previousSource != nil && previousSource != source
    guard raw.x.isFinite, raw.y.isFinite,
      current.x.isFinite, current.y.isFinite
    else {
      return SpatialRenderAnchorUpdate(
        point: current,
        sourceChanged: sourceChanged,
        suppressedJitter: false
      )
    }

    let delta = hypot(raw.x - current.x, raw.y - current.y)
    guard delta > SpatialRenderTuning.renderAnchorDeadZone else {
      return SpatialRenderAnchorUpdate(
        point: current,
        sourceChanged: sourceChanged,
        suppressedJitter: true
      )
    }

    let movementProgress = min(
      1,
      max(
        0,
        (delta - SpatialRenderTuning.renderAnchorDeadZone)
          / SpatialRenderTuning.renderAnchorResponsiveDistance
      )
    )
    var responseTime = SpatialRenderTuning.renderAnchorMaximumResponseTime
      - (
        SpatialRenderTuning.renderAnchorMaximumResponseTime
          - SpatialRenderTuning.renderAnchorMinimumResponseTime
      ) * movementProgress
    if sourceChanged {
      responseTime = max(
        responseTime,
        SpatialRenderTuning.renderAnchorSourceTransitionResponseTime
      )
    }

    let response = CGFloat(
      1 - exp(
        -Double(max(0, elapsed)) / Double(max(responseTime, 0.001))
      )
    )
    return SpatialRenderAnchorUpdate(
      point: CGPoint(
        x: current.x + (raw.x - current.x) * response,
        y: current.y + (raw.y - current.y) * response
      ),
      sourceChanged: sourceChanged,
      suppressedJitter: false
    )
  }
}

enum SpatialRenderContinuityState: Equatable {
  case visible
  case retained
  case expired
}

/// Render continuity is intentionally independent from identity freshness.
/// The same predicate is used before publishing a target and again while the
/// display link reprojects it, preventing two render paths from disagreeing.
enum SpatialRenderContinuityPolicy {
  static func state(
    now: CFTimeInterval,
    lastBodyEvidenceAt: CFTimeInterval,
    lastPeerEvidenceAt: CFTimeInterval,
    peerIsRecoverable: Bool,
    hasContradictorySpatialEvidence: Bool,
    contradictoryEvidenceSince: CFTimeInterval? = nil
  ) -> SpatialRenderContinuityState {
    guard peerIsRecoverable,
      now - lastPeerEvidenceAt <= SpatialRenderTuning.maximumPeerEvidenceAge
    else {
      return .expired
    }

    let contradictionIsTransient = !hasContradictorySpatialEvidence
      || contradictoryEvidenceSince.map {
        now - $0 <= SpatialRenderTuning.maximumTransientContradiction
      } == true
    guard contradictionIsTransient else {
      return .expired
    }

    let bodyAge = max(0, now - lastBodyEvidenceAt)
    if bodyAge <= SpatialRenderTuning.maximumFreshBodyEvidenceAge {
      return .visible
    }
    if bodyAge <= SpatialRenderTuning.maximumRenderContinuityBodyLoss {
      return .retained
    }
    return .expired
  }
}

struct SpatialRenderEvidence {
  let screenGeometry: Double
  let carryRegionProximity: Double
  let carryWorldProximity: Double
  let bodyWorldProximity: Double
  let distanceConsistency: Double
  let distanceNormalizedResidual: Double?
  let hasScreenGeometry: Bool
  let hasCarryRegionProximity: Bool
  let hasCarryWorldProximity: Bool
  let hasBodyWorldProximity: Bool
  let hasDistanceConsistency: Bool
  let isPhysicallyPlausible: Bool
}

/// Pure render predicates shared by the matcher and its deterministic
/// harness. They intentionally know nothing about identity state.
enum SpatialRenderDecisionPolicy {
  static func acceptsSingleton(
    bodyCount: Int,
    eligiblePeerCount: Int,
    evidence: SpatialRenderEvidence?
  ) -> Bool {
    bodyCount == 1
      && eligiblePeerCount == 1
      && acceptsFallbackEvidence(evidence)
  }

  static func acceptsGroup(
    clusterMemberCount: Int,
    evidence: SpatialRenderEvidence?
  ) -> Bool {
    clusterMemberCount > 1 && acceptsFallbackEvidence(evidence)
  }

  static func acceptsFallbackEvidence(
    _ evidence: SpatialRenderEvidence?
  ) -> Bool {
    guard let evidence, evidence.isPhysicallyPlausible else {
      return false
    }

    let hasScreenEvidence = evidence.hasScreenGeometry
      && evidence.screenGeometry >= SpatialRenderTuning.minimumFallbackScreenGeometry
    let hasCarryEvidence = evidence.hasCarryRegionProximity
      && evidence.carryRegionProximity
        >= SpatialRenderTuning.minimumFallbackCarryProximity
    let hasWorldEvidence = (
      evidence.hasCarryWorldProximity
        && evidence.carryWorldProximity
          >= SpatialRenderTuning.minimumFallbackWorldProximity
    ) || (
      evidence.hasBodyWorldProximity
        && evidence.bodyWorldProximity
          >= SpatialRenderTuning.minimumFallbackWorldProximity
    )
    let hasDistanceEvidence = evidence.hasDistanceConsistency
      && evidence.distanceConsistency
        >= SpatialRenderTuning.minimumFallbackDistanceConsistency
    return hasScreenEvidence
      || hasCarryEvidence
      || hasWorldEvidence
      || hasDistanceEvidence
  }

  static func retainsDisplay(
    now: CFTimeInterval,
    lastBodyEvidenceAt: CFTimeInterval,
    lastPeerEvidenceAt: CFTimeInterval,
    peerIsRecoverable: Bool,
    hasContradictorySpatialEvidence: Bool,
    contradictoryEvidenceSince: CFTimeInterval? = nil
  ) -> Bool {
    SpatialRenderContinuityPolicy.state(
      now: now,
      lastBodyEvidenceAt: lastBodyEvidenceAt,
      lastPeerEvidenceAt: lastPeerEvidenceAt,
      peerIsRecoverable: peerIsRecoverable,
      hasContradictorySpatialEvidence: hasContradictorySpatialEvidence,
      contradictoryEvidenceSince: contradictoryEvidenceSince
    ) != .expired
  }
}

struct SpatialAssociationConfirmationPolicy {
  let minimumConfidence: Double
  let minimumAmbiguityMargin: Double
  let requiredConfirmationCount: Int

  static func forPath(
    _ path: SpatialAssociationPath,
    distanceOnly: Bool
  ) -> SpatialAssociationConfirmationPolicy {
    switch (path, distanceOnly) {
    case (.initial, true):
      return SpatialAssociationConfirmationPolicy(
        minimumConfidence: SpatialDistanceAssociationTuning.minimumNewConfidence,
        minimumAmbiguityMargin: SpatialDistanceAssociationTuning.minimumNewAmbiguityMargin,
        requiredConfirmationCount: SpatialDistanceAssociationTuning.initialConfirmationCount
      )
    case (.reacquisition, true):
      return SpatialAssociationConfirmationPolicy(
        minimumConfidence: SpatialDistanceAssociationTuning.minimumReacquisitionConfidence,
        minimumAmbiguityMargin: SpatialDistanceAssociationTuning.minimumReacquisitionAmbiguityMargin,
        requiredConfirmationCount: SpatialDistanceAssociationTuning.reacquisitionConfirmationCount
      )
    case (.identitySwitch, true):
      return SpatialAssociationConfirmationPolicy(
        minimumConfidence: SpatialDistanceAssociationTuning.minimumSwitchConfidence,
        minimumAmbiguityMargin: SpatialDistanceAssociationTuning.minimumSwitchAmbiguityMargin,
        requiredConfirmationCount: SpatialDistanceAssociationTuning.switchConfirmationCount
      )
    case (.initial, false):
      return SpatialAssociationConfirmationPolicy(
        minimumConfidence: SpatialAssociationTuning.minimumNewConfidence,
        minimumAmbiguityMargin: SpatialAssociationTuning.minimumNewAmbiguityMargin,
        requiredConfirmationCount: SpatialAssociationTuning.initialConfirmationCount
      )
    case (.reacquisition, false):
      return SpatialAssociationConfirmationPolicy(
        minimumConfidence: SpatialAssociationTuning.minimumReacquisitionConfidence,
        minimumAmbiguityMargin: SpatialAssociationTuning.minimumReacquisitionAmbiguityMargin,
        requiredConfirmationCount: SpatialAssociationTuning.reacquisitionConfirmationCount
      )
    case (.identitySwitch, false):
      return SpatialAssociationConfirmationPolicy(
        minimumConfidence: SpatialAssociationTuning.minimumSwitchConfidence,
        minimumAmbiguityMargin: SpatialAssociationTuning.minimumSwitchAmbiguityMargin,
        requiredConfirmationCount: SpatialAssociationTuning.switchConfirmationCount
      )
    case (.continuation, _):
      return SpatialAssociationConfirmationPolicy(
        minimumConfidence: SpatialAssociationTuning.minimumContinuityConfidence,
        minimumAmbiguityMargin: SpatialAssociationTuning.minimumContinuityAmbiguityMargin,
        requiredConfirmationCount: 1
      )
    }
  }

  func accepts(
    confidence: Double,
    ambiguityMargin: Double,
    confirmationCount: Int,
    hasFreshSpatialEvidence: Bool = true,
    hasFreshBodyEvidence: Bool = true
  ) -> Bool {
    hasFreshSpatialEvidence
      && hasFreshBodyEvidence
      && confidence >= minimumConfidence
      && ambiguityMargin >= minimumAmbiguityMargin
      && confirmationCount >= requiredConfirmationCount
  }
}
