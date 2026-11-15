import Foundation
import QuartzCore
import UIKit
import simd

struct SpatialMatchedTarget {
  let anchorSource: SpatialRenderAnchorSource
  let distance: Float?
  let peerId: String
  let renderMode: SpatialRenderMode
  let screenPoint: CGPoint
  let userId: String
}

struct SpatialRenderTargetState {
  let anchorSource: SpatialRenderAnchorSource
  let distance: Float?
  let fallbackScreenPoint: CGPoint
  let lastBodyEvidenceAt: CFTimeInterval
  let lastRenderableBodyAt: CFTimeInterval
  let lastSpatialEvidenceAt: CFTimeInterval
  let lastPeerEvidenceAt: CFTimeInterval
  let peerId: String
  let associationMode: SpatialAssociationMode
  let associationConfidence: Double
  let distanceNormalizedResidual: Double?
  let hasContradictorySpatialEvidence: Bool
  let contradictoryEvidenceSince: CFTimeInterval?
  let renderMode: SpatialRenderMode
  let screenOffsetFromPeer: CGVector?
  let usesBodyAnchor: Bool
  let userId: String
  let renderWorldTransform: simd_float4x4?
}

/// Converts the immutable world snapshot into conservative, one-to-one
/// attendee associations. Candidate gating happens before Hungarian assignment
/// so a stale or physically impossible pair cannot win by being merely less
/// bad than another invalid pair.
final class SpatialTargetMatcher {
  private struct PreviousMatch {
    var bodyTrackId: String?
    var lastBodyTrackId: String?
    var carryKind: SpatialCarryRegionKind?
    var confidence: Double
    var mode: SpatialAssociationMode
    var distance: Float?
    var evidence: SpatialAssociationEvidence?
    var ambiguityMargin: Double
    var lastDistanceNormalizedResidual: Double?
    var lastBodyEvidenceAt: CFTimeInterval
    var lastSpatialEvidenceAt: CFTimeInterval
    var lastPeerEvidenceAt: CFTimeInterval
    var lastTrackingPoint: CGPoint
    var lastUpdatedAt: CFTimeInterval
    var screenOffsetFromPeer: CGVector?
    var screenPoint: CGPoint
    var state: SpatialAssociationState
    var path: SpatialAssociationPath
    var awaitingReacquisitionAt: CFTimeInterval?
    var reacquisitionContextExpiresAt: CFTimeInterval?
    let userId: String
    var verifiedWorldTransform: simd_float4x4?
  }

  private struct PendingMatch {
    let bodyTrackId: String
    let userId: String
    let path: SpatialAssociationPath
    let mode: SpatialAssociationMode
    let distanceMeasurement: SpatialDepthMeasurement?
    var confirmationCount: Int
    var lastUpdatedAt: CFTimeInterval
    var confidence: Double
    var ambiguityMargin: Double
    var lastDistanceNormalizedResidual: Double?
  }

  private struct PeerMotionState {
    var hasVelocity: Bool
    var lastPoint: CGPoint
    var lastUpdatedAt: CFTimeInterval
    var velocity: CGVector
  }

  private struct RenderMatch {
    var distance: Float?
    var selectionDistanceEvidence: SpatialRenderDistanceEvidence?
    var fallbackScreenPoint: CGPoint
    var lastBodyEvidenceAt: CFTimeInterval
    var lastRenderableBodyAt: CFTimeInterval
    var lastSpatialEvidenceAt: CFTimeInterval
    var lastPeerEvidenceAt: CFTimeInterval
    var associationMode: SpatialAssociationMode
    var associationConfidence: Double
    var distanceNormalizedResidual: Double?
    var hasContradictorySpatialEvidence: Bool
    var contradictoryEvidenceSince: CFTimeInterval?
    var anchorSource: SpatialRenderAnchorSource
    var renderMode: SpatialRenderMode
    var screenOffsetFromPeer: CGVector?
    var usesBodyAnchor: Bool
    let userId: String
    var renderWorldTransform: simd_float4x4?
  }

  private struct RenderAnchor {
    let anchorSource: SpatialRenderAnchorSource
    let screenPoint: CGPoint
    let screenOffsetFromPeer: CGVector?
    let renderWorldTransform: simd_float4x4?
    let hasFreshProjectableEvidence: Bool
    let usesBodyAnchor: Bool
  }

  private struct PeerCandidate {
    let capturedScreenPoint: CGPoint?
    let currentScreenPoint: CGPoint?
    let distance: Float?
    let displayDistance: Float?
    let distanceMeasurement: SpatialDepthMeasurement?
    let directionalMeasurement: SpatialDirectionalMeasurement?
    let hasFreshDirectionalEvidence: Bool
    let isEligibleForNewIdentity: Bool
    let isEligibleForRender: Bool
    let mode: SpatialAssociationMode
    let motionVelocity: CGVector?
    let peerId: String
    let quality: SpatialMeasurementQuality
    let lastPeerEvidenceAt: CFTimeInterval
    let sampleAge: CFTimeInterval
    let userId: String
    let worldPosition: SIMD3<Float>?
    let worldTransform: simd_float4x4?
    let displayWorldTransform: simd_float4x4?
  }

  private let bodyTrackManager = SpatialBodyTrackManager()
  private let bodyClusterer = SpatialBodyClusterer()
  private let renderVisibilitySelector = SpatialRenderVisibilitySelector()
  private var peerMotionStates: [String: PeerMotionState] = [:]
  private var pendingMatches: [String: PendingMatch] = [:]
  private var previousMatches: [String: PreviousMatch] = [:]
  /// Render state is intentionally separate so plausible/group cards cannot
  /// become identity continuity evidence or one-to-one assignments.
  private var renderMatches: [String: RenderMatch] = [:]
  /// Keeps a persistent render contradiction from being recreated as a new
  /// exact render record on the next matcher frame.
  private var renderContradictionSince: [String: CFTimeInterval] = [:]
  private var renderBodyLossGraceSince: [String: CFTimeInterval] = [:]
  private var selectedRenderPeerSelection = SpatialRenderOutputSelection(
    selectedPeerIds: []
  )
  private(set) var ambiguousMatchRejectionCount = 0
  private(set) var confirmedInitialMatchCount = 0
  private(set) var confirmedReacquisitionCount = 0
  private(set) var confirmedBodyReassignmentCount = 0
  private(set) var singletonPlausibleRenderStartedCount = 0
  private(set) var singletonPlausibleRenderPromotedCount = 0
  private(set) var singletonPlausibleRenderExpiredCount = 0
  private(set) var groupFallbackStartedCount = 0
  private(set) var groupFallbackPromotedCount = 0
  private(set) var groupFallbackExpiredCount = 0
  private(set) var lastGroupMemberCount = 0
  private(set) var lastGroupRenderedPeerCount = 0
  private(set) var lastRenderVisibilityCandidateCount = 0
  private(set) var lastRenderVisibilityEligibleCount = 0
  private(set) var lastRenderVisibilitySelectedCount = 0
  private(set) var lastRenderVisibilityDistanceSuppressedCount = 0
  private(set) var lastRenderVisibilityCapacitySuppressedCount = 0
  private(set) var lastRenderVisibilityRetainedCount = 0
  private(set) var lastRenderVisibilityReliableDistanceCount = 0
  private(set) var lastRenderVisibilityWeakDistanceCount = 0
  private(set) var renderBodyLossGraceStartedCount = 0
  private(set) var renderBodyLossGraceRecoveredCount = 0
  private(set) var renderBodyLossGraceExpiredCount = 0
  private(set) var renderVisibilitySelectionReplacementCount = 0
  private(set) var renderVisibilitySelectionChangeCount = 0
  private(set) var lastCandidatePairCount = 0
  private(set) var lastGatedCandidatePairCount = 0
  private(set) var lastActiveBodyTrackCount = 0
  private(set) var lastDuplicateDetectionSuppressionCount = 0
  private(set) var lastDuplicateTrackSuppressionCount = 0
  private(set) var lastDuplicateTrackRetirementCount = 0
  private(set) var directionalContradictionRejectionCount = 0
  private(set) var distanceOnlyIdentityRejectionCount = 0
  private var lastReacquisitionObservation: String?
  private var lastIdentitySwitchObservation: String?
  private var directionalRejectionObservations = Set<String>()
  private var distanceOnlyIdentityRejectionObservations = Set<String>()

  var verifiedPeerIds: Set<String> {
    Set(
      previousMatches.compactMap { peerId, match in
        switch match.state {
        case .verified, .temporarilyOccluded, .awaitingReacquisition:
          return peerId
        case .unmatched, .tentative:
          return nil
        }
      }
    )
  }

  var tentativePeerIds: Set<String> {
    Set(pendingMatches.keys)
  }

  var renderModeCounts: [SpatialRenderMode: Int] {
    renderMatches.values.reduce(into: [:]) { counts, match in
      counts[match.renderMode, default: 0] += 1
    }
  }

  var visibleRenderModeCounts: [SpatialRenderMode: Int] {
    selectedRenderPeerSelection.selectedPeerOrder.reduce(into: [:]) { counts, peerId in
      guard let renderMatch = renderMatches[peerId] else {
        return
      }
      counts[renderMatch.renderMode, default: 0] += 1
    }
  }

  func reset() {
    bodyTrackManager.reset()
    bodyClusterer.reset()
    pendingMatches.removeAll()
    peerMotionStates.removeAll()
    previousMatches.removeAll()
    renderMatches.removeAll()
    renderContradictionSince.removeAll()
    renderBodyLossGraceSince.removeAll()
    renderVisibilitySelector.reset()
    selectedRenderPeerSelection = SpatialRenderOutputSelection(
      selectedPeerIds: []
    )
    ambiguousMatchRejectionCount = 0
    confirmedInitialMatchCount = 0
    confirmedReacquisitionCount = 0
    confirmedBodyReassignmentCount = 0
    singletonPlausibleRenderStartedCount = 0
    singletonPlausibleRenderPromotedCount = 0
    singletonPlausibleRenderExpiredCount = 0
    groupFallbackStartedCount = 0
    groupFallbackPromotedCount = 0
    groupFallbackExpiredCount = 0
    lastGroupMemberCount = 0
    lastGroupRenderedPeerCount = 0
    lastRenderVisibilityCandidateCount = 0
    lastRenderVisibilityEligibleCount = 0
    lastRenderVisibilitySelectedCount = 0
    lastRenderVisibilityDistanceSuppressedCount = 0
    lastRenderVisibilityCapacitySuppressedCount = 0
    lastRenderVisibilityRetainedCount = 0
    lastRenderVisibilityReliableDistanceCount = 0
    lastRenderVisibilityWeakDistanceCount = 0
    renderBodyLossGraceStartedCount = 0
    renderBodyLossGraceRecoveredCount = 0
    renderBodyLossGraceExpiredCount = 0
    renderVisibilitySelectionReplacementCount = 0
    renderVisibilitySelectionChangeCount = 0
    lastCandidatePairCount = 0
    lastGatedCandidatePairCount = 0
    lastActiveBodyTrackCount = 0
    lastDuplicateDetectionSuppressionCount = 0
    lastDuplicateTrackSuppressionCount = 0
    lastDuplicateTrackRetirementCount = 0
    directionalContradictionRejectionCount = 0
    distanceOnlyIdentityRejectionCount = 0
    lastReacquisitionObservation = nil
    lastIdentitySwitchObservation = nil
    directionalRejectionObservations.removeAll()
    distanceOnlyIdentityRejectionObservations.removeAll()
  }

  func update(
    world: SpatialWorldSnapshot,
    now: CFTimeInterval,
    projectAtCapture: (simd_float4x4) -> CGPoint?,
    projectCurrent: (simd_float4x4) -> CGPoint?
  ) -> [SpatialMatchedTarget] {
    let trackedDetections = bodyTrackManager.update(
      world.bodies,
      now: now
    ).sorted { $0.id < $1.id }
    lastActiveBodyTrackCount = trackedDetections.count
    lastDuplicateDetectionSuppressionCount =
      bodyTrackManager.lastDuplicateDetectionSuppressionCount
    lastDuplicateTrackSuppressionCount =
      bodyTrackManager.lastDuplicateTrackSuppressionCount
    lastDuplicateTrackRetirementCount =
      bodyTrackManager.lastDuplicateTrackRetirementCount
    detachExpiredBodyTracks(now: now)
    let candidates = world.peers.compactMap { peer -> PeerCandidate? in
      guard
        let identity = peer.identity,
        let userId = identity.userId,
        !userId.isEmpty,
        peer.isRecoverable(at: now)
      else {
        return nil
      }

      let quality = peer.quality(at: now)
      let distanceMeasurement = peer.distanceMeasurement(at: now)
      let directionalMeasurement = peer.directionalMeasurement(at: now)
      let hasFreshTransform = peer.effectiveRawWorldTransform != nil
        && quality.transformAge
          <= SpatialMeasurementTuning.newMatchMaximumTransformAge
      let capturedScreenPoint = hasFreshTransform
        ? peer.effectiveRawWorldTransform.flatMap(projectAtCapture)
        : nil
      let mode = SpatialAssociationMode.from(
        worldTransformAvailable: hasFreshTransform,
        directionalMeasurementAvailable: directionalMeasurement != nil,
        cameraAssistanceConverged: peer.convergence == .converged
      )
      let hasFreshDisplayTransform = peer.effectiveDisplayWorldTransform != nil
        && quality.transformAge <= SpatialMeasurementTuning.renderMaximumTransformAge
      let currentScreenPoint = hasFreshDisplayTransform
        ? peer.effectiveDisplayWorldTransform.flatMap(projectCurrent)
        : nil
      return PeerCandidate(
        capturedScreenPoint: capturedScreenPoint,
        currentScreenPoint: currentScreenPoint,
        distance: peer.distance,
        displayDistance: peer.displayDistance,
        distanceMeasurement: distanceMeasurement,
        directionalMeasurement: directionalMeasurement,
        hasFreshDirectionalEvidence: directionalMeasurement != nil,
        isEligibleForNewIdentity: peer.isEligibleForNewIdentity(at: now),
        isEligibleForRender: SpatialRenderFreshnessPolicy.canUsePeerForFallback(
          worldTransformAvailable: peer.effectiveRawWorldTransform != nil,
          transformAge: quality.transformAge,
          directionIsFresh: directionalMeasurement != nil,
          distanceIsFresh: distanceMeasurement?.isFresh(
            at: now,
            maximumAge: SpatialMeasurementTuning.newMatchMaximumDistanceAge
          ) == true
        ),
        mode: mode,
        motionVelocity: updatePeerMotion(
          peerId: peer.peerId,
          point: capturedScreenPoint,
          now: now
        ),
        peerId: peer.peerId,
        quality: quality,
        lastPeerEvidenceAt: peer.lastUpdatedAt,
        sampleAge: max(0, now - peer.lastUpdatedAt),
        userId: userId,
        worldPosition: hasFreshTransform
          ? peer.effectiveRawWorldTransform.map(Self.worldPosition)
          : nil,
        worldTransform: hasFreshTransform
          ? peer.effectiveRawWorldTransform
          : nil,
        displayWorldTransform: hasFreshDisplayTransform
          ? peer.effectiveDisplayWorldTransform
          : nil
      )
    }.sorted { $0.peerId < $1.peerId }

    prunePreviousMatches(
      activePeerIds: Set(candidates.map(\.peerId)),
      now: now
    )
    prunePendingMatches(
      activePeerIds: Set(candidates.map(\.peerId)),
      now: now
    )
    prunePeerMotionStates(
      activePeerIds: Set(candidates.map(\.peerId)),
      now: now
    )
    pruneRenderMatches(
      now: now
    )

    lastCandidatePairCount = candidates.count * trackedDetections.count
    var evidenceMatrix = Array(
      repeating: Array<SpatialAssociationEvidence?>(
        repeating: nil,
        count: trackedDetections.count
      ),
      count: candidates.count
    )
    var renderEvidenceMatrix = Array(
      repeating: Array<SpatialAssociationEvidence?>(
        repeating: nil,
        count: trackedDetections.count
      ),
      count: candidates.count
    )
    let cameraPosition = Self.worldPosition(world.viewer.cameraTransform)
    var gatedCandidateCount = 0
    for peerIndex in candidates.indices {
      for detectionIndex in trackedDetections.indices {
        let evidence = associationEvidence(
          peer: candidates[peerIndex],
          detection: trackedDetections[detectionIndex],
          viewer: world.viewer,
          cameraPosition: cameraPosition,
          now: now,
          allowRenderFallback: false
        )
        evidenceMatrix[peerIndex][detectionIndex] = evidence
        if evidence != nil {
          gatedCandidateCount += 1
        }
        renderEvidenceMatrix[peerIndex][detectionIndex] =
          associationEvidence(
            peer: candidates[peerIndex],
            detection: trackedDetections[detectionIndex],
            viewer: world.viewer,
            cameraPosition: cameraPosition,
            now: now,
            allowRenderFallback: true
          ) ?? evidence
      }
    }
    lastGatedCandidatePairCount = gatedCandidateCount
    expireRenderMatchesContradictedByCurrentDirection(
      candidates: candidates,
      detections: trackedDetections,
      viewer: world.viewer,
      now: now
    )

    let assignments = SpatialAssignment.assign(
      rowCount: candidates.count,
      columnCount: trackedDetections.count,
      unmatchedCost: SpatialAssociationTuning.unmatchedCost
    ) { peerIndex, detectionIndex in
      evidenceMatrix[peerIndex][detectionIndex]?.cost
        ?? Double.greatestFiniteMagnitude
    }

    var matchedPeerIds = Set<String>()
    for (peerIndex, detectionIndex) in assignments.enumerated() {
      guard
        let detectionIndex,
        detectionIndex < trackedDetections.count,
        let evidence = evidenceMatrix[peerIndex][detectionIndex]
      else {
        continue
      }

      let peer = candidates[peerIndex]
      let detection = trackedDetections[detectionIndex]
      let ambiguityMargin = ambiguityMargin(
        peerIndex: peerIndex,
        detectionIndex: detectionIndex,
        candidates: candidates,
        detections: trackedDetections,
        evidenceMatrix: evidenceMatrix,
        confidence: evidence.confidence
      )
      let previous = previousMatches[peer.peerId]
      let path = SpatialAssociationLifecyclePolicy.path(
        previousState: previous?.state,
        activeBodyTrackId: previous?.bodyTrackId,
        detectionId: detection.id
      )
      guard isConfirmedMatch(
        peer: peer,
        detection: detection,
        evidence: evidence,
        confidence: evidence.confidence,
        ambiguityMargin: ambiguityMargin,
        now: now
      ) else {
        continue
      }

      let hasCurrentBodyEvidence = hasFreshBodyEvidence(detection)
      let hasRenderableBody = hasMeaningfulBodyForRender(detection)
      let canProjectCurrentTransform = hasFreshProjectableEvidence(peer)
      let retainedWorldTransform: simd_float4x4? = path == .reacquisition
        ? previous?.reacquisitionContextExpiresAt.flatMap { expiresAt in
          expiresAt >= now ? previous?.verifiedWorldTransform : nil
        }
        : previous?.verifiedWorldTransform
      let renderAnchor = makeRenderAnchor(
        peer: peer,
        preferredScreenPoint: hasRenderableBody ? detection.labelPoint : nil,
        previousScreenOffset: renderMatches[peer.peerId]?.screenOffsetFromPeer
          ?? previous?.screenOffsetFromPeer,
        previousRenderMatch: renderMatches[peer.peerId],
        projectCurrent: projectCurrent,
        shouldSmoothOffset: path == .continuation
      )
      let target = SpatialMatchedTarget(
        anchorSource: renderAnchor.anchorSource,
        distance: peer.displayDistance ?? peer.distance ?? previous?.distance,
        peerId: peer.peerId,
        renderMode: .exact,
        screenPoint: renderAnchor.screenPoint,
        userId: peer.userId
      )

      previousMatches[peer.peerId] = PreviousMatch(
        bodyTrackId: detection.id,
        lastBodyTrackId: detection.id,
        carryKind: bestCarryKind(peer: peer, detection: detection),
        confidence: evidence.confidence,
        mode: evidence.mode,
        distance: target.distance,
        evidence: evidence,
        ambiguityMargin: ambiguityMargin,
        lastDistanceNormalizedResidual: evidence.distanceNormalizedResidual,
        lastBodyEvidenceAt: hasCurrentBodyEvidence
          ? now
          : previous?.lastBodyEvidenceAt ?? now,
        lastSpatialEvidenceAt: renderAnchor.hasFreshProjectableEvidence
          ? now
          : previous?.lastSpatialEvidenceAt ?? now,
        lastPeerEvidenceAt: peer.lastPeerEvidenceAt,
        lastTrackingPoint: detection.trackingPoint,
        lastUpdatedAt: now,
        screenOffsetFromPeer: renderAnchor.screenOffsetFromPeer,
        screenPoint: target.screenPoint,
        state: hasCurrentBodyEvidence ? .verified : .temporarilyOccluded,
        path: path,
        awaitingReacquisitionAt: nil,
        reacquisitionContextExpiresAt: nil,
        userId: peer.userId,
        verifiedWorldTransform: canProjectCurrentTransform
          ? peer.displayWorldTransform ?? retainedWorldTransform
          : nil
      )
      upsertRenderMatch(
        peer: peer,
        mode: .exact,
        distance: target.distance,
        evidence: evidence,
        anchor: renderAnchor,
        bodyEvidenceAt: hasCurrentBodyEvidence ? now : nil,
        hasRenderableBody: hasRenderableBody,
        now: now,
        cameraPosition: cameraPosition,
        bodyMeasurement: bodyMeasurement(
          for: detection,
          cameraPosition: cameraPosition,
          now: now
        )
      )
      matchedPeerIds.insert(peer.peerId)
    }

    for peer in candidates where !matchedPeerIds.contains(peer.peerId) {
      guard var previous = previousMatches[peer.peerId] else {
        continue
      }

      if !trackedDetections.isEmpty,
        trackedDetections.allSatisfy({ detection in
          directionalAssociationEvidence(
            peer: peer,
            detection: detection,
            viewer: world.viewer,
            now: now
          ).hasHardContradiction
        })
      {
        markDirectionalRenderContradiction(
          for: peer.peerId,
          now: now,
          reason: "directional contradiction"
        )
        previous.lastPeerEvidenceAt = peer.lastPeerEvidenceAt
        previous.lastUpdatedAt = now
        previousMatches[peer.peerId] = previous
        continue
      }

      previous.lastPeerEvidenceAt = peer.lastPeerEvidenceAt
      let canProjectCurrentTransform = hasFreshProjectableEvidence(peer)
      if canProjectCurrentTransform {
        previous.lastSpatialEvidenceAt = now
      }

      guard previous.state != .awaitingReacquisition,
        let bodyTrackId = previous.bodyTrackId
      else {
        previous.distance = peer.displayDistance ?? peer.distance ?? previous.distance
        previous.lastUpdatedAt = now
        previousMatches[peer.peerId] = previous
        refreshRetainedExactRenderMatch(
          peer: peer,
          previous: previous,
          projectCurrent: projectCurrent,
          now: now,
          cameraPosition: cameraPosition
        )
        continue
      }

      guard bodyTrackManager.isTrackRecoverable(bodyTrackId) else {
        enterAwaitingReacquisition(
          for: peer.peerId,
          previous: &previous,
          now: now
        )
        previous.lastUpdatedAt = now
        previousMatches[peer.peerId] = previous
        refreshRetainedExactRenderMatch(
          peer: peer,
          previous: previous,
          projectCurrent: projectCurrent,
          now: now,
          cameraPosition: cameraPosition
        )
        continue
      }

      let currentBody = trackedDetections.first {
        $0.id == bodyTrackId
      }
      let currentRenderEvidence: SpatialAssociationEvidence?
      if let currentBody,
        let peerIndex = candidates.firstIndex(where: {
          $0.peerId == peer.peerId
        }),
        let detectionIndex = trackedDetections.firstIndex(where: {
          $0.id == currentBody.id
        })
      {
        currentRenderEvidence = renderEvidenceMatrix[peerIndex][detectionIndex]
      } else {
        currentRenderEvidence = nil
      }
      let hasCurrentBodyEvidence = currentBody.map {
        hasFreshBodyEvidence($0)
      } == true
      if hasCurrentBodyEvidence {
        previous.lastBodyEvidenceAt = now
      }

      if !hasCurrentBodyEvidence,
        previous.state != .temporarilyOccluded
      {
        previous.state = SpatialAssociationLifecyclePolicy.stateAfterBodyObservation(
          currentState: previous.state,
          bodyTrackIsRecoverable: true,
          hasFreshBodyEvidence: false
        )
        SpatialPerformance.signposter.emitEvent(
          "Association temporarily occluded",
          "Peer: \(peer.peerId.prefix(8), privacy: .public), body: \(bodyTrackId, privacy: .public)"
        )
      }

      if canProjectCurrentTransform,
        let displayWorldTransform = peer.displayWorldTransform
      {
        previous.verifiedWorldTransform = displayWorldTransform
      } else if !canProjectCurrentTransform {
        // Distance may keep the identity association alive, but it can never
        // justify projecting the last world coordinate as the phone's current
        // position.
        previous.verifiedWorldTransform = nil
      }
      let renderAnchor = makeRenderAnchor(
        peer: peer,
        preferredScreenPoint: currentBody.flatMap {
          hasMeaningfulBodyForRender($0) ? $0.labelPoint : nil
        },
        previousScreenOffset: renderMatches[peer.peerId]?.screenOffsetFromPeer
          ?? previous.screenOffsetFromPeer,
        previousRenderMatch: renderMatches[peer.peerId],
        projectCurrent: projectCurrent,
        shouldSmoothOffset: true
      )
      previous.screenOffsetFromPeer = renderAnchor.screenOffsetFromPeer
      previous.screenPoint = renderAnchor.screenPoint
      previous.distance = peer.displayDistance ?? peer.distance ?? previous.distance
      previous.lastUpdatedAt = now
      previousMatches[peer.peerId] = previous
      refreshRetainedExactRenderMatch(
        peer: peer,
        previous: previous,
        anchor: renderAnchor,
        hasRenderableBody: currentBody.map(hasMeaningfulBodyForRender) == true,
        hasCurrentBodyForRender: currentBody.map(hasFreshBodyEvidence) == true,
        now: now,
        cameraPosition: cameraPosition,
        evidence: currentRenderEvidence,
        bodyMeasurement: currentBody.flatMap {
          bodyMeasurement(
            for: $0,
            cameraPosition: cameraPosition,
            now: now
          )
        }
      )
    }

    let meaningfulDetections = trackedDetections.filter {
      hasMeaningfulBodyForRender($0)
    }
    let clusters = bodyClusterer.clusters(
      for: meaningfulDetections.map { detection in
        SpatialBodyClusterSample(
          id: detection.id,
          boundingBox: detection.boundingBox,
          bodyScale: detection.bodyScale,
          labelPoint: detection.labelPoint,
          trackingPoint: detection.trackingPoint,
          worldPosition: detection.worldGeometry?.bodyPoint?.position,
          worldQuality: detection.worldGeometry?.bodyPoint?.quality ?? 0
        )
      },
      now: now
    )
    let renderEligiblePeerIndices = candidates.indices.filter {
      candidates[$0].isEligibleForRender
    }

    if meaningfulDetections.count == 1,
      renderEligiblePeerIndices.count == 1,
      let peerIndex = renderEligiblePeerIndices.first,
      let detectionIndex = trackedDetections.firstIndex(where: {
        $0.id == meaningfulDetections[0].id
      }),
      !matchedPeerIds.contains(candidates[peerIndex].peerId),
      canRenderFallbackWithoutVerifiedIdentity(
        for: candidates[peerIndex].peerId
      ),
      let evidence = renderEvidenceMatrix[peerIndex][detectionIndex],
      SpatialRenderDecisionPolicy.acceptsSingleton(
        bodyCount: meaningfulDetections.count,
        eligiblePeerCount: renderEligiblePeerIndices.count,
        evidence: renderEvidenceSummary(evidence)
      )
    {
      let peer = candidates[peerIndex]
      let detection = trackedDetections[detectionIndex]
      let anchor = makeRenderAnchor(
        peer: peer,
        preferredScreenPoint: detection.labelPoint,
        previousScreenOffset: renderMatches[peer.peerId]?.screenOffsetFromPeer,
        previousRenderMatch: renderMatches[peer.peerId],
        projectCurrent: projectCurrent,
        shouldSmoothOffset: true
      )
      upsertRenderMatch(
        peer: peer,
        mode: .plausible,
        distance: peer.displayDistance ?? peer.distance,
        evidence: evidence,
        anchor: anchor,
        bodyEvidenceAt: hasFreshBodyEvidence(detection) ? now : nil,
        hasRenderableBody: true,
        now: now,
        cameraPosition: cameraPosition,
        bodyMeasurement: bodyMeasurement(
          for: detection,
          cameraPosition: cameraPosition,
          now: now
        )
      )
    }

    var currentGroupMemberCount = 0
    // Keep a peer on one deterministic cluster anchor even when the relaxed
    // screen gate makes two separated clusters plausible for the same phone.
    var bestGroupCandidateByPeerId: [
      String: (
        peerIndex: Int,
        cluster: SpatialBodyCluster,
        evidence: SpatialAssociationEvidence,
        bodyMeasurement: SpatialDepthMeasurement?
      )
    ] = [:]
    for cluster in clusters where cluster.count > 1 {
      let memberIndices = trackedDetections.indices.filter {
        cluster.contains(trackedDetections[$0].id)
      }
      guard !memberIndices.isEmpty else {
        continue
      }

      currentGroupMemberCount = max(
        currentGroupMemberCount,
        cluster.count
      )
      for peerIndex in renderEligiblePeerIndices {
        let peer = candidates[peerIndex]
        guard !matchedPeerIds.contains(peer.peerId),
          canRenderFallbackWithoutVerifiedIdentity(for: peer.peerId),
          let bestEvidence = memberIndices.compactMap({
            renderEvidenceMatrix[peerIndex][$0]
          }).max(by: { $0.confidence < $1.confidence }),
          SpatialRenderDecisionPolicy.acceptsGroup(
            clusterMemberCount: cluster.count,
            evidence: renderEvidenceSummary(bestEvidence)
          )
        else {
          continue
        }

        let candidate = (
          peerIndex: peerIndex,
          cluster: cluster,
          evidence: bestEvidence,
          bodyMeasurement: memberIndices.compactMap {
            bodyMeasurement(
              for: trackedDetections[$0],
              cameraPosition: cameraPosition,
              now: now
            )
          }.max { $0.quality < $1.quality }
        )
        guard let previousCandidate = bestGroupCandidateByPeerId[peer.peerId]
        else {
          bestGroupCandidateByPeerId[peer.peerId] = candidate
          continue
        }

        if bestEvidence.confidence > previousCandidate.evidence.confidence
          || (
            bestEvidence.confidence == previousCandidate.evidence.confidence
              && cluster.id < previousCandidate.cluster.id
          )
        {
          bestGroupCandidateByPeerId[peer.peerId] = candidate
        }
      }
    }
    for peerId in bestGroupCandidateByPeerId.keys.sorted() {
      guard let candidate = bestGroupCandidateByPeerId[peerId] else {
        continue
      }
      let peer = candidates[candidate.peerIndex]
      let anchor = makeRenderAnchor(
        peer: peer,
        preferredScreenPoint: candidate.cluster.anchor,
        preferredAnchorSource: .group,
        previousScreenOffset: renderMatches[peer.peerId]?.screenOffsetFromPeer,
        previousRenderMatch: renderMatches[peer.peerId],
        projectCurrent: projectCurrent,
        shouldSmoothOffset: true
      )
      upsertRenderMatch(
        peer: peer,
        mode: .group,
        distance: peer.displayDistance ?? peer.distance,
        evidence: candidate.evidence,
        anchor: anchor,
        bodyEvidenceAt: candidate.cluster.memberIds.contains { bodyId in
          trackedDetections.first(where: { $0.id == bodyId })
            .map(hasFreshBodyEvidence) == true
        } ? now : nil,
        hasRenderableBody: true,
        now: now,
        cameraPosition: cameraPosition,
        bodyMeasurement: candidate.bodyMeasurement,
        groupMemberCount: candidate.cluster.count
      )
    }
    let currentGroupPeerCount = bestGroupCandidateByPeerId.count
    lastGroupMemberCount = currentGroupMemberCount
    lastGroupRenderedPeerCount = currentGroupPeerCount

    pruneExpiredRenderMatches(now: now)
    refreshRenderVisibility(
      viewportSize: world.viewer.viewport.size,
      now: now
    )
    return matchedTargets(now: now)
  }

  private func detachExpiredBodyTracks(now: CFTimeInterval) {
    for peerId in previousMatches.keys.sorted() {
      guard var previous = previousMatches[peerId],
        let bodyTrackId = previous.bodyTrackId,
        SpatialAssociationLifecyclePolicy.shouldDetachBodyTrack(
          bodyTrackId: previous.bodyTrackId,
          isRecoverable: bodyTrackManager.isTrackRecoverable(bodyTrackId)
        )
      else {
        continue
      }

      enterAwaitingReacquisition(
        for: peerId,
        previous: &previous,
        now: now
      )
      previousMatches[peerId] = previous
    }
  }

  private func enterAwaitingReacquisition(
    for peerId: String,
    previous: inout PreviousMatch,
    now: CFTimeInterval
  ) {
    guard let oldBodyTrackId = previous.bodyTrackId else {
      previous.state = .awaitingReacquisition
      previous.path = .reacquisition
      return
    }

    previous.lastBodyTrackId = oldBodyTrackId
    previous.bodyTrackId = nil
    previous.state = .awaitingReacquisition
    previous.path = .reacquisition
    previous.awaitingReacquisitionAt = now
    previous.reacquisitionContextExpiresAt =
      now + SpatialAssociationTuning.reacquisitionContextRetentionDuration
    pendingMatches.removeValue(forKey: peerId)
    lastReacquisitionObservation = nil

    let bodyLossDuration = max(0, now - previous.lastBodyEvidenceAt)
    SpatialPerformance.signposter.emitEvent(
      "Association awaiting reacquisition",
      "Peer: \(peerId.prefix(8), privacy: .public), old body: \(oldBodyTrackId, privacy: .public), body loss milliseconds: \(Int(bodyLossDuration * 1_000))"
    )
  }

  private func signpostReacquisitionRejection(
    peer: PeerCandidate,
    detection: SpatialBodyDetection,
    reason: String
  ) {
    let observationKey = "\(peer.peerId):\(detection.id):\(reason)"
    guard lastReacquisitionObservation != observationKey else {
      return
    }

    lastReacquisitionObservation = observationKey
    let eventName: StaticString
    switch reason {
    case "low-confidence":
      eventName = "Reacquisition rejected - low confidence"
    case "ambiguous":
      eventName = "Reacquisition rejected - ambiguous"
    default:
      eventName = "Reacquisition rejected"
    }
    SpatialPerformance.signposter.emitEvent(
      eventName,
      "Reason: \(reason, privacy: .public), peer: \(peer.peerId.prefix(8), privacy: .public), old body: \(self.previousMatches[peer.peerId]?.lastBodyTrackId ?? "none", privacy: .public), new body: \(detection.id, privacy: .public)"
    )
  }

  private func signpostDirectionalRejection(
    peer: PeerCandidate,
    detection: SpatialBodyDetection,
    reason: String,
    path: SpatialAssociationPath
  ) {
    let observationKey = "\(peer.peerId):\(detection.id):\(path.rawValue):\(reason)"
    guard directionalRejectionObservations.insert(observationKey).inserted else {
      return
    }

    directionalContradictionRejectionCount += 1
    SpatialPerformance.signposter.emitEvent(
      "Directional candidate rejected",
      "Peer: \(peer.peerId.prefix(8), privacy: .public), body: \(detection.id, privacy: .public), path: \(path.rawValue, privacy: .public), reason: \(reason, privacy: .public)"
    )
  }

  private func directionalAssociationEvidence(
    peer: PeerCandidate,
    detection: SpatialBodyDetection,
    viewer: SpatialViewerState,
    now: CFTimeInterval
  ) -> SpatialDirectionalAssociationResult {
    let peerBearing = peer.worldPosition.flatMap {
      SpatialDirectionalAssociationPolicy.bearing(
        for: $0,
        cameraTransform: viewer.cameraTransform
      )
    } ?? peer.directionalMeasurement?.bearingRadians
    let peerViewportProjection: SpatialDirectionalViewportProjection? = {
      if let worldPosition = peer.worldPosition {
        return SpatialDirectionalAssociationPolicy.viewportProjection(
          for: worldPosition,
          cameraTransform: viewer.cameraTransform,
          projectionMatrix: viewer.cameraProjectionMatrix,
          viewportSize: viewer.viewport.size
        )
      }

      if let directionalMeasurement = peer.directionalMeasurement {
        return SpatialDirectionalAssociationPolicy.viewportProjection(
          for: directionalMeasurement,
          projectionMatrix: viewer.cameraProjectionMatrix,
          viewportSize: viewer.viewport.size
        )
      }

      return nil
    }()
    let bodyBearing = detection.worldGeometry?.bodyPoint.flatMap {
      SpatialDirectionalAssociationPolicy.bearing(
        for: $0.position,
        cameraTransform: viewer.cameraTransform
      )
    } ?? SpatialDirectionalAssociationPolicy.bearing(
      for: detection.trackingPoint,
      viewportSize: viewer.viewport.size,
      cameraHorizontalProjectionScale: viewer.cameraHorizontalProjectionScale
    )
    let measurementAge: CFTimeInterval? = peer.worldPosition != nil
      ? peer.quality.transformAge
      : peer.directionalMeasurement.map { max(0, now - $0.measuredAt) }
    return SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: peerBearing,
      bodyBearingRadians: bodyBearing,
      measurementAge: measurementAge,
      now: now,
      peerViewportProjection: peerViewportProjection
    )
  }

  private func markDirectionalRenderContradiction(
    for peerId: String,
    now: CFTimeInterval,
    reason: String
  ) {
    guard var renderMatch = renderMatches[peerId] else {
      return
    }

    let wasContradictory = renderMatch.hasContradictorySpatialEvidence
    let contradictionSince = renderMatch.contradictoryEvidenceSince
      ?? renderContradictionSince[peerId]
      ?? now
    renderMatch.hasContradictorySpatialEvidence = true
    renderMatch.contradictoryEvidenceSince = contradictionSince
    renderContradictionSince[peerId] = contradictionSince
    renderMatches[peerId] = renderMatch

    guard !wasContradictory else {
      return
    }

    SpatialPerformance.signposter.emitEvent(
      "Direction contradiction started",
      "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public)"
    )
  }

  private func expireRenderMatchesContradictedByCurrentDirection(
    candidates: [PeerCandidate],
    detections: [SpatialBodyDetection],
    viewer: SpatialViewerState,
    now: CFTimeInterval
  ) {
    let meaningfulDetectionIndices = detections.indices.filter {
      hasMeaningfulBodyForRender(detections[$0])
    }
    guard !meaningfulDetectionIndices.isEmpty else {
      return
    }

    for peerIndex in candidates.indices {
      let peerId = candidates[peerIndex].peerId
      guard renderMatches[peerId] != nil,
        meaningfulDetectionIndices.allSatisfy({ detectionIndex in
          directionalAssociationEvidence(
            peer: candidates[peerIndex],
            detection: detections[detectionIndex],
            viewer: viewer,
            now: now
          ).hasHardContradiction
        })
      else {
        continue
      }

      markDirectionalRenderContradiction(
        for: peerId,
        now: now,
        reason: "directional contradiction"
      )
    }
  }

  func associationsSnapshot(now: CFTimeInterval) -> [SpatialAssociation] {
    let remembered = previousMatches.compactMap { peerId, previous -> SpatialAssociation? in
      guard now - previous.lastPeerEvidenceAt
        <= SpatialAssociationTuning.targetRetentionDuration
      else {
        return nil
      }

      return SpatialAssociation(
        peerId: peerId,
        userId: previous.userId,
        bodyTrackId: previous.bodyTrackId,
        state: previous.state,
        path: previous.path,
        mode: previous.mode,
        confidence: previous.confidence,
        ambiguityMargin: previous.ambiguityMargin,
        evidence: previous.evidence,
        lastUpdatedAt: previous.lastUpdatedAt,
        lastBodyEvidenceAt: previous.lastBodyEvidenceAt,
        lastSpatialEvidenceAt: previous.lastSpatialEvidenceAt
      )
    }
    let tentative = pendingMatches.map { peerId, pending in
      SpatialAssociation(
        peerId: peerId,
        userId: pending.userId,
        bodyTrackId: pending.bodyTrackId,
        state: .tentative,
        path: pending.path,
        mode: pending.mode,
        confidence: pending.confidence,
        ambiguityMargin: pending.ambiguityMargin,
        evidence: nil,
        lastUpdatedAt: pending.lastUpdatedAt,
        lastBodyEvidenceAt: pending.lastUpdatedAt,
        lastSpatialEvidenceAt: pending.lastUpdatedAt
      )
    }
    return (remembered + tentative).sorted { $0.peerId < $1.peerId }
  }

  func renderSnapshot(now: CFTimeInterval) -> [SpatialRenderTargetState] {
    pruneExpiredRenderMatches(now: now)

    let selectedPeerIds = selectedRenderPeerIdsForOutput()
    return selectedPeerIds.compactMap { peerId in
      guard let renderMatch = renderMatches[peerId] else {
        return nil
      }

      return SpatialRenderTargetState(
        anchorSource: renderMatch.anchorSource,
        distance: renderMatch.distance,
        fallbackScreenPoint: renderMatch.fallbackScreenPoint,
        lastBodyEvidenceAt: renderMatch.lastBodyEvidenceAt,
        lastRenderableBodyAt: renderMatch.lastRenderableBodyAt,
        lastSpatialEvidenceAt: renderMatch.lastSpatialEvidenceAt,
        lastPeerEvidenceAt: renderMatch.lastPeerEvidenceAt,
        peerId: peerId,
        associationMode: renderMatch.associationMode,
        associationConfidence: renderMatch.associationConfidence,
        distanceNormalizedResidual: renderMatch.distanceNormalizedResidual,
        hasContradictorySpatialEvidence:
          renderMatch.hasContradictorySpatialEvidence,
        contradictoryEvidenceSince: renderMatch.contradictoryEvidenceSince,
        renderMode: renderMatch.renderMode,
        screenOffsetFromPeer: renderMatch.screenOffsetFromPeer,
        usesBodyAnchor: renderMatch.usesBodyAnchor,
        userId: renderMatch.userId,
        renderWorldTransform: renderMatch.renderWorldTransform
      )
    }
  }

  private func associationEvidence(
    peer: PeerCandidate,
    detection: SpatialBodyDetection,
    viewer: SpatialViewerState,
    cameraPosition: SIMD3<Float>,
    now: CFTimeInterval,
    allowRenderFallback: Bool
  ) -> SpatialAssociationEvidence? {
    let previous = previousMatches[peer.peerId]
    let path = SpatialAssociationLifecyclePolicy.path(
      previousState: previous?.state,
      activeBodyTrackId: previous?.bodyTrackId,
      detectionId: detection.id
    )
    let isPreviousBody = path == .continuation
    let isFreshBody = detection.isFreshPose
      && detection.poseAge <= SpatialAssociationTuning.maximumPoseAgeForNewIdentity
    let isFreshPeer = peer.isEligibleForNewIdentity
    let isFreshRenderPeer = peer.isEligibleForRender
    let bodyMeasurement = detection.bodyDepthMeasurement
      ?? Self.bodyDepthMeasurement(
        for: detection,
        cameraPosition: cameraPosition,
        measuredAt: now
      )
    let distanceComparison: SpatialDistanceAssociationResult? = {
      guard
        let peerMeasurement = peer.distanceMeasurement,
        let bodyMeasurement
      else {
        return nil
      }

      return SpatialDistanceAssociationPolicy.compare(
        peer: peerMeasurement,
        body: bodyMeasurement
      )
    }()
    let directionalEvidence = directionalAssociationEvidence(
      peer: peer,
      detection: detection,
      viewer: viewer,
      now: now
    )
    let hasDirectionalContradiction = directionalEvidence.hasHardContradiction
    let blocksNewIdentity = directionalEvidence.blocksNewIdentity
    let hasDirectionalOwnership = directionalEvidence.hasViewportAuthority
      && directionalEvidence.hasFreshDirectionalEvidence
      && directionalEvidence.alignmentScore
        >= SpatialMeasurementTuning.minimumDirectionalOwnershipScore
    if blocksNewIdentity {
      signpostDirectionalRejection(
        peer: peer,
        detection: detection,
        reason: directionalEvidence.reason.rawValue,
        path: path
      )
      if directionalEvidence.hasHardContradiction || path != .continuation {
        return nil
      }
    }

    if path != .continuation {
      guard (allowRenderFallback ? isFreshRenderPeer : isFreshPeer) else {
        return nil
      }
      guard isFreshBody
        || (allowRenderFallback && hasMeaningfulBodyForRender(detection))
      else {
        return nil
      }
    }

    let bodyScale = max(detection.bodyScale, 60)
    let screenPoint = peer.capturedScreenPoint
      ?? (allowRenderFallback ? peer.currentScreenPoint : nil)
    let hasScreenGeometry = screenPoint != nil
    let ownershipBounds = detection.boundingBox.insetBy(
      dx: -bodyScale * 0.32,
      dy: -bodyScale * 0.24
    )
    let outsideOwnershipDistance = screenPoint.map {
      distance(from: $0, to: ownershipBounds) / Double(bodyScale)
    } ?? Double.greatestFiniteMagnitude
    let screenGeometry: Double
    if let screenPoint {
      let trackingDistance = distance(screenPoint, detection.trackingPoint)
        / Double(bodyScale)
      let screenGeometryDistance = allowRenderFallback
        ? SpatialRenderTuning.maximumFallbackScreenOwnershipDistance
        : SpatialAssociationTuning.maximumScreenOwnershipDistance
      screenGeometry = max(
        0,
        min(1, 1 - outsideOwnershipDistance / screenGeometryDistance)
      ) * max(0, min(1, 1 - trackingDistance / 1.5))
    } else {
      screenGeometry = isPreviousBody ? 0.15 : 0
    }

    let carryCandidate = screenPoint.flatMap { point in
      detection.carryRegions.max { first, second in
        carryScore(point, region: first) < carryScore(point, region: second)
      }
    }
    let carryRegionProximity = carryCandidate.map {
      carryScore(screenPoint ?? .zero, region: $0)
    } ?? 0
    let hasCarryRegionProximity = carryCandidate != nil

    let worldCarry = nearestWorldCarryPoint(
      peerPosition: peer.worldPosition,
      detection: detection
    )
    let worldBodyObservation = nearestWorldBodyPoint(
      peerPosition: peer.worldPosition,
      detection: detection
    )
    let maximumWorldBodyDistance = allowRenderFallback
      ? SpatialRenderTuning.maximumFallbackWorldDistance
      : SpatialAssociationTuning.maximumWorldBodyDistance
    let worldBody = worldBodyObservation.flatMap {
      $0.distance <= maximumWorldBodyDistance ? $0 : nil
    }
    if path != .continuation,
      let worldCarry,
      worldCarry.distance > (
        allowRenderFallback
          ? SpatialRenderTuning.maximumFallbackWorldDistance
          : SpatialAssociationTuning.maximumWorldCarryDistance
      )
    {
      return nil
    }
    if path != .continuation,
      let worldBodyObservation,
      worldBodyObservation.distance > maximumWorldBodyDistance
    {
      return nil
    }
    if allowRenderFallback,
      path != .continuation,
      let distanceComparison,
      !distanceComparison.isPhysicallyPlausible
    {
      return nil
    }
    let maximumScreenOwnershipDistance = allowRenderFallback
      ? SpatialRenderTuning.maximumFallbackScreenOwnershipDistance
      : SpatialAssociationTuning.maximumScreenOwnershipDistance
    let minimumCarryRegionProximity = allowRenderFallback
      ? SpatialRenderTuning.minimumFallbackCarryProximity
      : 0.35
    let minimumWorldProximity = allowRenderFallback
      ? SpatialRenderTuning.minimumFallbackWorldProximity
      : 0.45
    if path != .continuation,
      outsideOwnershipDistance > maximumScreenOwnershipDistance,
      carryRegionProximity < minimumCarryRegionProximity,
      (worldCarry?.proximity ?? 0) < minimumWorldProximity,
      (worldBody?.proximity ?? 0) < minimumWorldProximity,
      !hasDirectionalOwnership,
      !(allowRenderFallback && distanceComparison?.isPhysicallyPlausible == true)
    {
      return nil
    }
    if path != .continuation,
      screenPoint == nil,
      worldCarry == nil,
      worldBody == nil,
      !hasDirectionalOwnership,
      !(allowRenderFallback && distanceComparison?.isPhysicallyPlausible == true)
    {
      return nil
    }

    let distanceConsistency: Double
    let distanceNormalizedResidual: Double?
    let hasDistanceConsistency: Bool
    if let distanceComparison
    {
      distanceConsistency = distanceComparison.score
      distanceNormalizedResidual = Double(distanceComparison.normalizedResidual)
      hasDistanceConsistency = true
    } else if worldCarry != nil {
      distanceConsistency = 0.72
      distanceNormalizedResidual = nil
      hasDistanceConsistency = true
    } else if let worldBody {
      distanceConsistency = worldBody.proximity * 0.82
      distanceNormalizedResidual = nil
      hasDistanceConsistency = true
    } else {
      distanceConsistency = 0.34
      distanceNormalizedResidual = nil
      hasDistanceConsistency = false
    }

    let motionAgreement: Double
    let hasMotionAgreement: Bool
    if let peerVelocity = peer.motionVelocity, detection.hasMotionEstimate {
      let velocityDifference = hypot(
        peerVelocity.dx - detection.trackingVelocity.dx,
        peerVelocity.dy - detection.trackingVelocity.dy
      ) / Double(bodyScale)
      motionAgreement = exp(-velocityDifference / 0.8)
      hasMotionAgreement = true
    } else {
      motionAgreement = 0.4
      hasMotionAgreement = false
    }

    let continuity: Double
    let hasContinuity: Bool
    if let previous, isPreviousBody {
      let continuityDistance = distance(
        previous.lastTrackingPoint,
        detection.trackingPoint
      ) / Double(bodyScale)
      continuity = exp(-continuityDistance / 0.8)
      hasContinuity = true
    } else if path == .identitySwitch {
      continuity = 0.04
      hasContinuity = true
    } else if path == .reacquisition {
      // The old screen track is retained as recovery context, but it is not
      // current continuity evidence once the body track has expired. Fresh
      // phone/body geometry must carry this decision.
      continuity = 0
      hasContinuity = false
    } else {
      continuity = 0.22
      hasContinuity = false
    }

    let cameraAssistance: Double
    switch peer.quality.convergence {
    case .converged:
      cameraAssistance = 1
    case .unknown:
      cameraAssistance = 0.5
    case .notConverged:
      cameraAssistance = 0.22
    }

    return SpatialAssociationEvidence(
      mode: peer.mode,
      screenGeometry: screenGeometry,
      carryRegionProximity: carryRegionProximity,
      carryWorldProximity: worldCarry?.proximity ?? 0,
      bodyWorldProximity: worldBody?.proximity ?? 0,
      distanceConsistency: distanceConsistency,
      distanceNormalizedResidual: distanceNormalizedResidual,
      directionalAlignment: directionalEvidence.alignmentScore,
      measurementQuality: peer.quality.freshness,
      cameraAssistance: cameraAssistance,
      bodyPoseConfidence: Double(max(0, min(1, detection.confidence))),
      peerFreshness: exp(-Double(peer.sampleAge) / 1.35),
      poseFreshness: exp(-Double(max(0, detection.poseAge)) / 0.35)
        * (detection.isFreshPose ? 1 : 0.45),
      motionAgreement: motionAgreement,
      continuity: continuity,
      switchPenalty: path == .identitySwitch ? 1 : 0,
      hasScreenGeometry: hasScreenGeometry,
      hasCarryRegionProximity: hasCarryRegionProximity,
      hasCarryWorldProximity: worldCarry != nil,
      hasBodyWorldProximity: worldBody != nil,
      hasDistanceConsistency: hasDistanceConsistency,
      hasDirectionalAlignment: directionalEvidence.hasFreshDirectionalEvidence,
      hasDirectionalContradiction: hasDirectionalContradiction,
      hasMotionAgreement: hasMotionAgreement,
      hasContinuity: hasContinuity,
      hasContradictorySpatialEvidence:
        distanceComparison?.isPhysicallyPlausible == false
        || hasDirectionalContradiction
        || (path == .continuation
          && (worldCarry?.distance ?? 0)
            > SpatialRenderTuning.maximumFallbackWorldDistance)
        || (path == .continuation
          && (worldBodyObservation?.distance ?? 0)
            > SpatialRenderTuning.maximumFallbackWorldDistance)
    )
  }

  private func makeRenderAnchor(
    peer: PeerCandidate,
    preferredScreenPoint: CGPoint?,
    preferredAnchorSource: SpatialRenderAnchorSource = .body,
    previousScreenOffset: CGVector?,
    previousRenderMatch: RenderMatch?,
    projectCurrent: (simd_float4x4) -> CGPoint?,
    shouldSmoothOffset: Bool
  ) -> RenderAnchor {
    let hasCurrentProjectableEvidence = hasFreshProjectableEvidence(peer)
    let renderWorldTransform = hasCurrentProjectableEvidence
      ? peer.displayWorldTransform
      : previousRenderMatch?.renderWorldTransform
    let projectedPeerPoint = hasCurrentProjectableEvidence
      ? peer.displayWorldTransform.flatMap(projectCurrent)
      : nil
    let rawScreenOffset = preferredScreenPoint.flatMap { point in
      peer.capturedScreenPoint.map {
        CGVector(
          dx: point.x - $0.x,
          dy: point.y - $0.y
        )
      }
    }
    let screenOffsetFromPeer = Self.stabilizedScreenOffset(
      current: rawScreenOffset,
      previous: previousScreenOffset,
      shouldSmooth: shouldSmoothOffset
    )
    let projectedScreenPoint: CGPoint?
    if let projectedPeerPoint {
      projectedScreenPoint = Self.projectedScreenPoint(
        peerPoint: projectedPeerPoint,
        offset: screenOffsetFromPeer,
        fallback: projectedPeerPoint
      )
    } else {
      projectedScreenPoint = nil
    }
    // Keep the source choice explicit: the display-link must not replace a
    // current/predicted body anchor with an older phone projection.
    let screenPoint: CGPoint
    let anchorSource: SpatialRenderAnchorSource
    if let preferredScreenPoint {
      screenPoint = preferredScreenPoint
      anchorSource = preferredAnchorSource
    } else if let projectedScreenPoint {
      screenPoint = projectedScreenPoint
      anchorSource = .projectedPeer
    } else if let previousScreenPoint = previousRenderMatch?.fallbackScreenPoint {
      screenPoint = previousScreenPoint
      anchorSource = .retainedScreen
    } else {
      screenPoint = .zero
      anchorSource = .fallback
    }

    return RenderAnchor(
      anchorSource: anchorSource,
      screenPoint: screenPoint,
      screenOffsetFromPeer: screenOffsetFromPeer,
      renderWorldTransform: renderWorldTransform,
      hasFreshProjectableEvidence: hasCurrentProjectableEvidence,
      usesBodyAnchor: preferredScreenPoint != nil
    )
  }

  private func upsertRenderMatch(
    peer: PeerCandidate,
    mode: SpatialRenderMode,
    distance: Float?,
    evidence: SpatialAssociationEvidence?,
    anchor: RenderAnchor,
    bodyEvidenceAt: CFTimeInterval?,
    hasRenderableBody: Bool,
    now: CFTimeInterval,
    cameraPosition: SIMD3<Float>,
    bodyMeasurement: SpatialDepthMeasurement? = nil,
    groupMemberCount: Int? = nil
  ) {
    let previousMode = renderMatches[peer.peerId]?.renderMode
    let selectionDistanceEvidence = renderSelectionDistanceEvidence(
      peer: peer,
      bodyMeasurement: bodyMeasurement,
      cameraPosition: cameraPosition,
      now: now
    )
    var renderMatch = renderMatches[peer.peerId]
      ?? RenderMatch(
        distance: distance,
        selectionDistanceEvidence: selectionDistanceEvidence,
        fallbackScreenPoint: anchor.screenPoint,
        lastBodyEvidenceAt: bodyEvidenceAt ?? now,
        lastRenderableBodyAt: hasRenderableBody ? now : bodyEvidenceAt ?? 0,
        lastSpatialEvidenceAt: anchor.hasFreshProjectableEvidence ? now : 0,
        lastPeerEvidenceAt: peer.lastPeerEvidenceAt,
        associationMode: evidence?.mode ?? peer.mode,
        associationConfidence: evidence?.confidence ?? 0,
        distanceNormalizedResidual: evidence?.distanceNormalizedResidual,
        hasContradictorySpatialEvidence: false,
        contradictoryEvidenceSince: nil,
        anchorSource: anchor.anchorSource,
        renderMode: mode,
        screenOffsetFromPeer: anchor.screenOffsetFromPeer,
        usesBodyAnchor: anchor.usesBodyAnchor,
        userId: peer.userId,
        renderWorldTransform: anchor.renderWorldTransform
      )

    renderMatch.distance = distance ?? renderMatch.distance
    renderMatch.selectionDistanceEvidence = selectionDistanceEvidence
    renderMatch.fallbackScreenPoint = anchor.screenPoint
    if let bodyEvidenceAt {
      renderMatch.lastBodyEvidenceAt = bodyEvidenceAt
    }
    if hasRenderableBody {
      renderMatch.lastRenderableBodyAt = now
    }
    if anchor.hasFreshProjectableEvidence {
      renderMatch.lastSpatialEvidenceAt = now
    }
    renderMatch.lastPeerEvidenceAt = peer.lastPeerEvidenceAt
    renderMatch.associationMode = evidence?.mode ?? renderMatch.associationMode
    renderMatch.associationConfidence = evidence?.confidence
      ?? renderMatch.associationConfidence
    renderMatch.distanceNormalizedResidual = evidence?.distanceNormalizedResidual
    let hasContradictoryDistanceEvidence = evidence?.distanceNormalizedResidual.map {
      !$0.isFinite
        || $0 > Double(SpatialDistanceAssociationTuning.maximumNormalizedResidual)
    } ?? false
    let hasContradictorySpatialEvidence =
      evidence?.hasContradictorySpatialEvidence == true
      || hasContradictoryDistanceEvidence
      || evidence?.hasDirectionalContradiction == true
    let wasContradictory = renderMatch.hasContradictorySpatialEvidence
    renderMatch.hasContradictorySpatialEvidence = hasContradictorySpatialEvidence
    if hasContradictorySpatialEvidence {
      let contradictionSince = renderMatch.contradictoryEvidenceSince
        ?? renderContradictionSince[peer.peerId]
        ?? now
      renderMatch.contradictoryEvidenceSince = contradictionSince
      renderContradictionSince[peer.peerId] = contradictionSince
      if !wasContradictory {
        SpatialPerformance.signposter.emitEvent(
          "Direction contradiction started",
          "Peer: \(peer.peerId.prefix(8), privacy: .public)"
        )
      }
    } else {
      renderMatch.contradictoryEvidenceSince = nil
      if wasContradictory {
        SpatialPerformance.signposter.emitEvent(
          "Direction contradiction recovered",
          "Peer: \(peer.peerId.prefix(8), privacy: .public)"
        )
      }
      renderContradictionSince.removeValue(forKey: peer.peerId)
    }
    renderMatch.renderMode = mode
    renderMatch.anchorSource = anchor.anchorSource
    renderMatch.screenOffsetFromPeer = anchor.screenOffsetFromPeer
      ?? renderMatch.screenOffsetFromPeer
    renderMatch.usesBodyAnchor = anchor.usesBodyAnchor
    renderMatch.renderWorldTransform = anchor.renderWorldTransform
      ?? renderMatch.renderWorldTransform
    renderMatches[peer.peerId] = renderMatch

    recordRenderModeTransition(
      peerId: peer.peerId,
      from: previousMode,
      to: mode,
      groupMemberCount: groupMemberCount
    )
  }

  private func refreshRetainedExactRenderMatch(
    peer: PeerCandidate,
    previous: PreviousMatch,
    projectCurrent: (simd_float4x4) -> CGPoint?,
    now: CFTimeInterval,
    cameraPosition: SIMD3<Float>,
    evidence: SpatialAssociationEvidence? = nil
  ) {
    let anchor = makeRenderAnchor(
      peer: peer,
      preferredScreenPoint: nil,
      previousScreenOffset: renderMatches[peer.peerId]?.screenOffsetFromPeer
        ?? previous.screenOffsetFromPeer,
      previousRenderMatch: renderMatches[peer.peerId],
      projectCurrent: projectCurrent,
      shouldSmoothOffset: true
    )
    refreshRetainedExactRenderMatch(
      peer: peer,
      previous: previous,
      anchor: anchor,
      hasRenderableBody: false,
      hasCurrentBodyForRender: false,
      now: now,
      cameraPosition: cameraPosition,
      evidence: evidence
    )
  }

  private func refreshRetainedExactRenderMatch(
    peer: PeerCandidate,
    previous: PreviousMatch,
    anchor: RenderAnchor,
    hasRenderableBody: Bool,
    hasCurrentBodyForRender: Bool,
    now: CFTimeInterval,
    cameraPosition: SIMD3<Float>,
    evidence: SpatialAssociationEvidence? = nil,
    bodyMeasurement: SpatialDepthMeasurement? = nil
  ) {
    guard renderMatches[peer.peerId] != nil else {
      return
    }

    upsertRenderMatch(
      peer: peer,
      mode: .exact,
      distance: peer.displayDistance ?? peer.distance ?? previous.distance,
      evidence: evidence ?? previous.evidence,
      anchor: anchor,
      bodyEvidenceAt: hasCurrentBodyForRender ? now : nil,
      hasRenderableBody: hasRenderableBody,
      now: now,
      cameraPosition: cameraPosition,
      bodyMeasurement: bodyMeasurement
    )
  }

  private func renderEvidenceSummary(
    _ evidence: SpatialAssociationEvidence
  ) -> SpatialRenderEvidence {
    SpatialRenderEvidence(
      screenGeometry: evidence.screenGeometry,
      carryRegionProximity: evidence.carryRegionProximity,
      carryWorldProximity: evidence.carryWorldProximity,
      bodyWorldProximity: evidence.bodyWorldProximity,
      distanceConsistency: evidence.distanceConsistency,
      distanceNormalizedResidual: evidence.distanceNormalizedResidual,
      hasScreenGeometry: evidence.hasScreenGeometry,
      hasCarryRegionProximity: evidence.hasCarryRegionProximity,
      hasCarryWorldProximity: evidence.hasCarryWorldProximity,
      hasBodyWorldProximity: evidence.hasBodyWorldProximity,
      hasDistanceConsistency: evidence.hasDistanceConsistency,
      isPhysicallyPlausible: !evidence.hasContradictorySpatialEvidence
        && (evidence.distanceNormalizedResidual.map {
          $0.isFinite
            && $0 <= Double(SpatialDistanceAssociationTuning.maximumNormalizedResidual)
        } ?? true)
    )
  }

  private func bodyMeasurement(
    for detection: SpatialBodyDetection,
    cameraPosition: SIMD3<Float>,
    now: CFTimeInterval
  ) -> SpatialDepthMeasurement? {
    detection.bodyDepthMeasurement
      ?? Self.bodyDepthMeasurement(
        for: detection,
        cameraPosition: cameraPosition,
        measuredAt: now
      )
  }

  private func renderSelectionDistanceEvidence(
    peer: PeerCandidate,
    bodyMeasurement: SpatialDepthMeasurement?,
    cameraPosition: SIMD3<Float>,
    now: CFTimeInterval
  ) -> SpatialRenderDistanceEvidence? {
    var measurements: [SpatialDepthMeasurement] = []
    if let peerMeasurement = peer.distanceMeasurement,
      peerMeasurement.isFresh(
        at: now,
        maximumAge: SpatialMeasurementTuning.newMatchMaximumDistanceAge
      )
    {
      measurements.append(peerMeasurement)
    }

    if let bodyMeasurement,
      bodyMeasurement.isFresh(
        at: now,
        maximumAge: SpatialDistanceAssociationTuning.maximumBodyMeasurementAge
      )
    {
      measurements.append(bodyMeasurement)
    }

    let transform = peer.displayWorldTransform ?? peer.worldTransform
    let maximumTransformAge = peer.displayWorldTransform != nil
      ? SpatialMeasurementTuning.renderMaximumTransformAge
      : SpatialMeasurementTuning.newMatchMaximumTransformAge
    guard
      let transform = transform,
      peer.quality.transformAge.isFinite,
      peer.quality.transformAge <= maximumTransformAge
    else {
      return SpatialRenderDistancePolicy.select(
        measurements: measurements,
        now: now
      )
    }

    let distance = simd_distance(
      Self.worldPosition(transform),
      cameraPosition
    )
    guard distance.isFinite, distance > 0 else {
      return SpatialRenderDistancePolicy.select(
        measurements: measurements,
        now: now
      )
    }

    let transformAge = max(0, peer.quality.transformAge)
    let freshness = exp(
      -transformAge / SpatialRenderTuning.distanceEvidenceFreshnessScale
    )
    measurements.append(
      SpatialDepthMeasurement(
        distance: distance,
        quality: max(0.25, min(0.9, Float(freshness))),
        uncertainty: max(0.35, distance * 0.15),
        source: .fallback,
        measuredAt: now - transformAge
      )
    )

    return SpatialRenderDistancePolicy.select(
      measurements: measurements,
      now: now
    )
  }

  private func refreshRenderVisibility(
    viewportSize: CGSize,
    now: CFTimeInterval
  ) {
    let candidates = renderMatches.keys.sorted().compactMap { peerId -> SpatialRenderVisibilityCandidate? in
      guard let renderMatch = renderMatches[peerId] else {
        return nil
      }

      let modeQuality: Double
      switch renderMatch.associationMode {
      case .cameraAssisted:
        modeQuality = 1
      case .directional:
        modeQuality = 0.78
      case .distanceOnly:
        modeQuality = 0.52
      }
      let distanceQuality = renderMatch.selectionDistanceEvidence == nil
        ? SpatialRenderTuning.visibilityMissingDistanceScore
        : max(
          0,
          min(1, renderMatch.selectionDistanceEvidence?.quality ?? 0)
        )

      return SpatialRenderVisibilityCandidate(
        peerId: peerId,
        renderMode: renderMatch.renderMode,
        screenPoint: renderMatch.fallbackScreenPoint,
        selectionDistanceEvidence: renderMatch.selectionDistanceEvidence,
        associationConfidence: renderMatch.associationConfidence,
        spatialQuality: modeQuality * 0.7 + distanceQuality * 0.3
      )
    }
    let selection = renderVisibilitySelector.select(
      candidates: candidates,
      viewportSize: viewportSize,
      now: now
    )
    selectedRenderPeerSelection = SpatialRenderOutputSelection(
      selectedPeerIds: selection.selectedPeerIds
    )
    lastRenderVisibilityCandidateCount = candidates.count
    lastRenderVisibilityEligibleCount = selection.eligibleCandidateCount
    lastRenderVisibilitySelectedCount = selection.selectedPeerIds.count
    lastRenderVisibilityDistanceSuppressedCount = selection.distanceSuppressedCount
    lastRenderVisibilityCapacitySuppressedCount = selection.capacitySuppressedCount
    lastRenderVisibilityRetainedCount = selection.retainedByHysteresisCount
    lastRenderVisibilityReliableDistanceCount =
      selection.reliableDistanceCandidateCount
    lastRenderVisibilityWeakDistanceCount = selection.weakDistanceCandidateCount
    renderVisibilitySelectionReplacementCount += selection.replacementCount
    if selection.selectionChanged {
      renderVisibilitySelectionChangeCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Overlay visibility selection changed",
        "Candidates: \(selection.eligibleCandidateCount), selected: \(selection.selectedPeerIds.count), retained: \(selection.retainedByHysteresisCount)"
      )
    }
    if selection.replacementCount > 0 {
      SpatialPerformance.signposter.emitEvent(
        "Overlay visibility replacement",
        "Count: \(selection.replacementCount), selected: \(selection.selectedPeerIds.count)"
      )
    }
  }

  private func hasMeaningfulBodyForRender(
    _ detection: SpatialBodyDetection
  ) -> Bool {
    detection.confidence >= SpatialVisionTuning.minimumTrackingConfidence
      && detection.poseAge <= SpatialRenderTuning.maximumMeaningfulBodyAge
  }

  /// A peer that is already verified keeps the strict exact path. A peer that
  /// is awaiting reacquisition may use the render-only path again when the
  /// scene has returned to one physically plausible body/peer candidate. This
  /// does not write a new body track into `previousMatches`.
  private func canRenderFallbackWithoutVerifiedIdentity(for peerId: String)
    -> Bool
  {
    guard let previous = previousMatches[peerId] else {
      return true
    }

    return previous.state == .awaitingReacquisition
  }

  /// Keep the render record through a transient peer-candidate gap. The
  /// display-link still gates projection on peer recoverability, while this
  /// prevents a temporary measurement-tier change from recreating the state.
  private func pruneRenderMatches(
    now: CFTimeInterval
  ) {
    for peerId in renderMatches.keys.sorted() {
      guard let renderMatch = renderMatches[peerId] else {
        continue
      }

      if now - renderMatch.lastPeerEvidenceAt
        > SpatialRenderTuning.maximumPeerEvidenceAge
      {
        renderMatches.removeValue(forKey: peerId)
        renderContradictionSince.removeValue(forKey: peerId)
        renderBodyLossGraceSince.removeValue(forKey: peerId)
        recordRenderExpiration(
          peerId: peerId,
          mode: renderMatch.renderMode,
          reason: "peer evidence stale"
        )
      }
    }
  }

  private func pruneExpiredRenderMatches(now: CFTimeInterval) {
    updateRenderContinuityDiagnostics(now: now)

    for peerId in renderMatches.keys.sorted() {
      guard let renderMatch = renderMatches[peerId] else {
        continue
      }

      if !SpatialRenderDecisionPolicy.retainsDisplay(
        now: now,
        lastBodyEvidenceAt: renderMatch.lastBodyEvidenceAt,
        lastPeerEvidenceAt: renderMatch.lastPeerEvidenceAt,
        peerIsRecoverable: isRenderBodyRecoverable(peerId: peerId),
        hasContradictorySpatialEvidence:
          renderMatch.hasContradictorySpatialEvidence,
        contradictoryEvidenceSince: renderMatch.contradictoryEvidenceSince
      ) {
        renderMatches.removeValue(forKey: peerId)
        renderContradictionSince.removeValue(forKey: peerId)
        renderBodyLossGraceSince.removeValue(forKey: peerId)
        let bodyLossExpired = now - renderMatch.lastBodyEvidenceAt
          > SpatialRenderTuning.maximumRenderContinuityBodyLoss
        if bodyLossExpired {
          renderBodyLossGraceExpiredCount += 1
          SpatialPerformance.signposter.emitEvent(
            "Render body-loss grace expired",
            "Peer: \(peerId.prefix(8), privacy: .public)"
          )
        } else if renderMatch.hasContradictorySpatialEvidence {
          SpatialPerformance.signposter.emitEvent(
            "Direction contradiction expired",
            "Peer: \(peerId.prefix(8), privacy: .public)"
          )
        }
        recordRenderExpiration(
          peerId: peerId,
          mode: renderMatch.renderMode,
          reason: "display grace expired"
        )
      }
    }
  }

  private func updateRenderContinuityDiagnostics(now: CFTimeInterval) {
    for peerId in renderMatches.keys.sorted() {
      guard let renderMatch = renderMatches[peerId] else {
        continue
      }

      let bodyAge = max(0, now - renderMatch.lastBodyEvidenceAt)
      if bodyAge > SpatialRenderTuning.maximumFreshBodyEvidenceAge,
        bodyAge <= SpatialRenderTuning.maximumRenderContinuityBodyLoss
      {
        guard renderBodyLossGraceSince[peerId] == nil else {
          continue
        }

        let graceStartedAt = renderMatch.lastBodyEvidenceAt
          + SpatialRenderTuning.maximumFreshBodyEvidenceAge
        renderBodyLossGraceSince[peerId] = graceStartedAt
        renderBodyLossGraceStartedCount += 1
        SpatialPerformance.signposter.emitEvent(
          "Render body-loss grace started",
          "Peer: \(peerId.prefix(8), privacy: .public)"
        )
      } else if bodyAge <= SpatialRenderTuning.maximumFreshBodyEvidenceAge,
        renderBodyLossGraceSince.removeValue(forKey: peerId) != nil
      {
        renderBodyLossGraceRecoveredCount += 1
        SpatialPerformance.signposter.emitEvent(
          "Render body-loss grace recovered",
          "Peer: \(peerId.prefix(8), privacy: .public)"
        )
      }
    }
  }

  private func isRenderBodyRecoverable(peerId: String) -> Bool {
    guard let bodyTrackId = previousMatches[peerId]?.bodyTrackId else {
      return true
    }

    return bodyTrackManager.isTrackRecoverable(bodyTrackId)
  }

  private func recordRenderExpiration(
    peerId: String,
    mode: SpatialRenderMode,
    reason: String
  ) {
    switch mode {
    case .exact:
      SpatialPerformance.signposter.emitEvent(
        "Exact render expired",
        "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public)"
      )
    case .plausible:
      singletonPlausibleRenderExpiredCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Singleton plausible render expired",
        "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public)"
      )
    case .group:
      groupFallbackExpiredCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Group fallback expired",
        "Peer: \(peerId.prefix(8), privacy: .public), reason: \(reason, privacy: .public)"
      )
    }
  }

  private func recordRenderModeTransition(
    peerId: String,
    from previousMode: SpatialRenderMode?,
    to newMode: SpatialRenderMode,
    groupMemberCount: Int?
  ) {
    guard previousMode != newMode else {
      return
    }

    switch newMode {
    case .exact:
      if previousMode == .plausible {
        singletonPlausibleRenderPromotedCount += 1
        SpatialPerformance.signposter.emitEvent(
          "Singleton plausible render promoted to exact",
          "Peer: \(peerId.prefix(8), privacy: .public)"
        )
      } else if previousMode == .group {
        groupFallbackPromotedCount += 1
        SpatialPerformance.signposter.emitEvent(
          "Group fallback promoted to exact",
          "Peer: \(peerId.prefix(8), privacy: .public)"
        )
      }
    case .plausible:
      singletonPlausibleRenderStartedCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Singleton plausible render started",
        "Peer: \(peerId.prefix(8), privacy: .public)"
      )
    case .group:
      groupFallbackStartedCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Group fallback started",
        "Peer: \(peerId.prefix(8), privacy: .public), members: \(groupMemberCount ?? 0)"
      )
    }
  }

  private func matchedTargets(now: CFTimeInterval) -> [SpatialMatchedTarget] {
    let selectedPeerIds = selectedRenderPeerIdsForOutput()
    return selectedPeerIds.compactMap { peerId in
      guard let renderMatch = renderMatches[peerId],
        SpatialRenderDecisionPolicy.retainsDisplay(
          now: now,
          lastBodyEvidenceAt: renderMatch.lastBodyEvidenceAt,
          lastPeerEvidenceAt: renderMatch.lastPeerEvidenceAt,
          peerIsRecoverable: isRenderBodyRecoverable(peerId: peerId),
          hasContradictorySpatialEvidence:
            renderMatch.hasContradictorySpatialEvidence,
          contradictoryEvidenceSince: renderMatch.contradictoryEvidenceSince
        )
      else {
        return nil
      }

      return SpatialMatchedTarget(
        anchorSource: renderMatch.anchorSource,
        distance: renderMatch.distance,
        peerId: peerId,
        renderMode: renderMatch.renderMode,
        screenPoint: renderMatch.fallbackScreenPoint,
        userId: renderMatch.userId
      )
    }
  }

  /// Both direct matcher targets and projected render snapshots must consume
  /// this same selected order. Hidden render matches remain stored, but only
  /// IDs selected by the visibility policy can cross either output boundary.
  private func selectedRenderPeerIdsForOutput() -> [String] {
    selectedRenderPeerSelection.orderedPeerIds(
      presentIn: Set(renderMatches.keys)
    )
  }

  private func isConfirmedMatch(
    peer: PeerCandidate,
    detection: SpatialBodyDetection,
    evidence: SpatialAssociationEvidence,
    confidence: Double,
    ambiguityMargin: Double,
    now: CFTimeInterval
  ) -> Bool {
    let previous = previousMatches[peer.peerId]
    let path = SpatialAssociationLifecyclePolicy.path(
      previousState: previous?.state,
      activeBodyTrackId: previous?.bodyTrackId,
      detectionId: detection.id
    )
    guard !evidence.hasDirectionalContradiction else {
      return false
    }
    let isFreshPeer = hasFreshMeasurementEvidence(peer)
    if path == .continuation {
      guard
        hasFreshBodyEvidence(detection) || isFreshPeer,
        confidence >= SpatialAssociationTuning.minimumContinuityConfidence,
        ambiguityMargin >= SpatialAssociationTuning.minimumContinuityAmbiguityMargin
      else {
        ambiguousMatchRejectionCount += 1
        return false
      }
      pendingMatches.removeValue(forKey: peer.peerId)
      return true
    }

    guard
      SpatialAssociationTuning.allowsNewIdentityEvidence(
        mode: peer.mode,
        hasFreshProjectableEvidence: peer.worldTransform != nil,
        hasFreshDirectionalEvidence: peer.hasFreshDirectionalEvidence
      ),
      peer.isEligibleForNewIdentity,
      detection.isFreshPose,
      detection.poseAge <= SpatialAssociationTuning.maximumPoseAgeForNewIdentity
    else {
      if peer.mode == .distanceOnly {
        let observationKey = "\(peer.peerId):\(detection.id):\(path.rawValue)"
        if distanceOnlyIdentityRejectionObservations.insert(observationKey).inserted {
          distanceOnlyIdentityRejectionCount += 1
          SpatialPerformance.signposter.emitEvent(
            "Distance-only identity rejected",
            "Peer: \(peer.peerId.prefix(8), privacy: .public), path: \(path.rawValue, privacy: .public), reason: distance-only-no-identity-authority"
          )
        }
      }
      return false
    }
    if path == .identitySwitch {
      let observationKey = "\(peer.peerId):\(previous?.bodyTrackId ?? "none"):\(detection.id)"
      if lastIdentitySwitchObservation != observationKey {
        lastIdentitySwitchObservation = observationKey
        SpatialPerformance.signposter.emitEvent(
          "True switch candidate",
          "Peer: \(peer.peerId.prefix(8), privacy: .public), old body: \(previous?.bodyTrackId ?? "none", privacy: .public), new body: \(detection.id, privacy: .public), confidence: \(confidence), margin: \(ambiguityMargin)"
        )
      }
    }
    let confirmationPolicy = SpatialAssociationConfirmationPolicy.forPath(
      path,
      distanceOnly: false
    )
    if confidence < confirmationPolicy.minimumConfidence {
      pendingMatches.removeValue(forKey: peer.peerId)
      ambiguousMatchRejectionCount += 1
      if path == .reacquisition {
        signpostReacquisitionRejection(
          peer: peer,
          detection: detection,
          reason: "low-confidence"
        )
      }
      return false
    }
    if ambiguityMargin < confirmationPolicy.minimumAmbiguityMargin {
      pendingMatches.removeValue(forKey: peer.peerId)
      ambiguousMatchRejectionCount += 1
      if path == .reacquisition {
        signpostReacquisitionRejection(
          peer: peer,
          detection: detection,
          reason: "ambiguous"
        )
      }
      return false
    }

    var pending: PendingMatch
    let existingPending = pendingMatches[peer.peerId]
    if var pendingMatch = existingPending,
      pendingMatch.bodyTrackId == detection.id,
      pendingMatch.path == path,
      pendingMatch.mode == peer.mode,
      now - pendingMatch.lastUpdatedAt
        <= SpatialAssociationTuning.pendingRetentionDuration
    {
      let isDistanceObservationConsistent: Bool
      if peer.mode == .distanceOnly,
        let previousResidual = pendingMatch.lastDistanceNormalizedResidual,
        let currentResidual = evidence.distanceNormalizedResidual
      {
        isDistanceObservationConsistent = currentResidual
          <= previousResidual + 0.75
      } else {
        isDistanceObservationConsistent = true
      }
      pendingMatch.confirmationCount = isDistanceObservationConsistent
        ? pendingMatch.confirmationCount + 1
        : 1
      pendingMatch.lastUpdatedAt = now
      pendingMatch.confidence = confidence
      pendingMatch.ambiguityMargin = ambiguityMargin
      pendingMatch.lastDistanceNormalizedResidual = evidence.distanceNormalizedResidual
      pending = pendingMatch
    } else {
      if path == .reacquisition,
        existingPending?.bodyTrackId != detection.id
          || existingPending?.path != path
      {
        SpatialPerformance.signposter.emitEvent(
          "Reacquisition candidate started",
          "Peer: \(peer.peerId.prefix(8), privacy: .public), old body: \(previous?.lastBodyTrackId ?? "none", privacy: .public), new body: \(detection.id, privacy: .public), confidence: \(confidence), margin: \(ambiguityMargin)"
        )
      }
      pending = PendingMatch(
        bodyTrackId: detection.id,
        userId: peer.userId,
        path: path,
        mode: peer.mode,
        distanceMeasurement: peer.distanceMeasurement,
        confirmationCount: 1,
        lastUpdatedAt: now,
        confidence: confidence,
        ambiguityMargin: ambiguityMargin,
        lastDistanceNormalizedResidual: evidence.distanceNormalizedResidual
      )
    }

    guard pending.confirmationCount >= confirmationPolicy.requiredConfirmationCount else {
      pendingMatches[peer.peerId] = pending
      return false
    }

    pendingMatches.removeValue(forKey: peer.peerId)
    lastReacquisitionObservation = nil
    switch path {
    case .initial:
      confirmedInitialMatchCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Association verified",
        "Peer: \(peer.peerId.prefix(8), privacy: .public), body: \(detection.id, privacy: .public), mode: \(peer.mode.rawValue, privacy: .public), confidence: \(confidence), margin: \(ambiguityMargin)"
      )
    case .reacquisition:
      confirmedReacquisitionCount += 1
      let oldBodyTrackId = previous?.lastBodyTrackId ?? "none"
      let reacquisitionDuration = previous?.awaitingReacquisitionAt.map {
        max(0, now - $0)
      } ?? -1
      SpatialPerformance.signposter.emitEvent(
        "Association reacquired",
        "Peer: \(peer.peerId.prefix(8), privacy: .public), old body: \(oldBodyTrackId, privacy: .public), new body: \(detection.id, privacy: .public), mode: \(peer.mode.rawValue, privacy: .public), confidence: \(confidence), margin: \(ambiguityMargin), latency milliseconds: \(Int(reacquisitionDuration * 1_000))"
      )
    case .identitySwitch:
      confirmedBodyReassignmentCount += 1
      SpatialPerformance.signposter.emitEvent(
        "Association switched",
        "Peer: \(peer.peerId.prefix(8), privacy: .public), old body: \(previous?.bodyTrackId ?? "none", privacy: .public), new body: \(detection.id, privacy: .public), mode: \(peer.mode.rawValue, privacy: .public), confidence: \(confidence), margin: \(ambiguityMargin)"
      )
    case .continuation:
      break
    }
    return true
  }

  private func ambiguityMargin(
    peerIndex: Int,
    detectionIndex: Int,
    candidates: [PeerCandidate],
    detections: [SpatialBodyDetection],
    evidenceMatrix: [[SpatialAssociationEvidence?]],
    confidence: Double
  ) -> Double {
    let alternativeBodyConfidence = detections.indices
      .filter { $0 != detectionIndex }
      .compactMap { evidenceMatrix[peerIndex][$0]?.confidence }
      .max() ?? 0
    let alternativePeerConfidence = candidates.indices
      .filter { $0 != peerIndex }
      .compactMap { evidenceMatrix[$0][detectionIndex]?.confidence }
      .max() ?? 0
    return confidence - max(alternativeBodyConfidence, alternativePeerConfidence)
  }

  private func nearestWorldCarryPoint(
    peerPosition: SIMD3<Float>?,
    detection: SpatialBodyDetection
  ) -> (distance: Float, proximity: Double)? {
    guard let peerPosition, let worldGeometry = detection.worldGeometry,
      !worldGeometry.carryPoints.isEmpty || !worldGeometry.carryVolumes.isEmpty
    else {
      return nil
    }

    var best: (distance: Float, proximity: Double)?
    for point in worldGeometry.carryPoints {
      let distance = simd_distance(point.position, peerPosition)
      let proximity = exp(
        -Double(distance) / Double(SpatialAssociationTuning.strongWorldCarryDistance)
      ) * Double(max(0, min(1, point.quality)))
      if best == nil || proximity > (best?.proximity ?? -1) {
        best = (distance, proximity)
      }
    }

    for volume in worldGeometry.carryVolumes {
      let distance = simd_distance(volume.center, peerPosition)
      let proximity = volume.proximity(to: peerPosition)
      if best == nil || proximity > (best?.proximity ?? -1) {
        best = (distance, proximity)
      }
    }

    return best
  }

  private func nearestWorldBodyPoint(
    peerPosition: SIMD3<Float>?,
    detection: SpatialBodyDetection
  ) -> (distance: Float, proximity: Double)? {
    guard let peerPosition, let bodyPoint = detection.worldGeometry?.bodyPoint else {
      return nil
    }

    let distance = simd_distance(bodyPoint.position, peerPosition)
    guard distance.isFinite else {
      return nil
    }

    let proximity = exp(-Double(distance) / 0.85)
      * Double(max(0, min(1, bodyPoint.quality)))
    return (distance, proximity)
  }

  private func carryScore(
    _ point: CGPoint,
    region: SpatialCarryRegion
  ) -> Double {
    max(
      0,
      1 - distance(point, region.center)
        / Double(max(region.radius * 1.5, 1))
    ) * Double(max(0, min(1, region.confidence)))
  }

  private func bestCarryKind(
    peer: PeerCandidate,
    detection: SpatialBodyDetection
  ) -> SpatialCarryRegionKind? {
    guard let point = peer.capturedScreenPoint else {
      return nil
    }
    return detection.carryRegions.max {
      carryScore(point, region: $0) < carryScore(point, region: $1)
    }?.kind
  }

  private func hasFreshMeasurementEvidence(_ peer: PeerCandidate) -> Bool {
    peer.quality.transformAge
      <= SpatialMeasurementTuning.associationMaximumSingleSensorLoss
      || peer.quality.directionAge
        <= SpatialMeasurementTuning.associationMaximumSingleSensorLoss
      || peer.quality.distanceAge
        <= SpatialMeasurementTuning.associationMaximumSingleSensorLoss
  }

  private func hasFreshProjectableEvidence(_ peer: PeerCandidate) -> Bool {
    SpatialRenderFreshnessPolicy.canRenderSolidPhoneMarker(
      worldTransformAvailable: peer.displayWorldTransform != nil,
      transformAge: peer.quality.transformAge
    )
  }

  private func hasFreshBodyEvidence(_ detection: SpatialBodyDetection) -> Bool {
    detection.confidence >= SpatialVisionTuning.minimumTrackingConfidence
      && detection.poseAge <= SpatialAssociationTuning.maximumTrackedBodyEvidenceAge
  }

  private func prunePreviousMatches(
    activePeerIds: Set<String>,
    now: CFTimeInterval
  ) {
    previousMatches = previousMatches.filter { peerId, previous in
      activePeerIds.contains(peerId)
        && now - previous.lastPeerEvidenceAt
          <= SpatialAssociationTuning.targetRetentionDuration
    }
  }

  private func prunePendingMatches(
    activePeerIds: Set<String>,
    now: CFTimeInterval
  ) {
    pendingMatches = pendingMatches.filter { peerId, pending in
      activePeerIds.contains(peerId)
        && now - pending.lastUpdatedAt
          <= SpatialAssociationTuning.pendingRetentionDuration
    }
  }

  private func prunePeerMotionStates(
    activePeerIds: Set<String>,
    now: CFTimeInterval
  ) {
    peerMotionStates = peerMotionStates.filter { peerId, state in
      activePeerIds.contains(peerId)
        && now - state.lastUpdatedAt
          <= SpatialAssociationTuning.targetRetentionDuration
    }
  }

  private func updatePeerMotion(
    peerId: String,
    point: CGPoint?,
    now: CFTimeInterval
  ) -> CGVector? {
    guard let point else {
      return peerMotionStates[peerId]?.hasVelocity == true
        ? peerMotionStates[peerId]?.velocity
        : nil
    }
    guard var state = peerMotionStates[peerId] else {
      peerMotionStates[peerId] = PeerMotionState(
        hasVelocity: false,
        lastPoint: point,
        lastUpdatedAt: now,
        velocity: .zero
      )
      return nil
    }

    let elapsed = now - state.lastUpdatedAt
    guard elapsed >= 1 / 120 else {
      return state.hasVelocity ? state.velocity : nil
    }
    let measuredVelocity = CGVector(
      dx: (point.x - state.lastPoint.x) / CGFloat(elapsed),
      dy: (point.y - state.lastPoint.y) / CGFloat(elapsed)
    )
    state.velocity = CGVector(
      dx: state.velocity.dx * 0.7 + measuredVelocity.dx * 0.3,
      dy: state.velocity.dy * 0.7 + measuredVelocity.dy * 0.3
    )
    state.hasVelocity = true
    state.lastPoint = point
    state.lastUpdatedAt = now
    peerMotionStates[peerId] = state
    return state.velocity
  }

  private static func worldPosition(_ transform: simd_float4x4) -> SIMD3<Float> {
    SIMD3<Float>(
      transform.columns.3.x,
      transform.columns.3.y,
      transform.columns.3.z
    )
  }

  private static func bodyDepthMeasurement(
    for detection: SpatialBodyDetection,
    cameraPosition: SIMD3<Float>,
    measuredAt: CFTimeInterval
  ) -> SpatialDepthMeasurement? {
    guard
      let bodyPoint = detection.worldGeometry?.bodyPoint,
      measuredAt.isFinite
    else {
      return nil
    }

    let distance = simd_distance(bodyPoint.position, cameraPosition)
    guard distance.isFinite, distance > 0 else {
      return nil
    }

    return SpatialDepthMeasurement(
      distance: distance,
      quality: min(1, max(0, bodyPoint.quality)),
      uncertainty: max(0.35, distance * 0.15),
      source: .vision3D,
      measuredAt: measuredAt
    )
  }

  private static func stabilizedScreenOffset(
    current: CGVector?,
    previous: CGVector?,
    shouldSmooth: Bool
  ) -> CGVector? {
    guard let current else {
      return previous
    }
    guard shouldSmooth, let previous else {
      return current
    }
    let alpha = SpatialAssociationTuning.screenOffsetSmoothingAlpha
    return CGVector(
      dx: previous.dx + (current.dx - previous.dx) * alpha,
      dy: previous.dy + (current.dy - previous.dy) * alpha
    )
  }

  private static func projectedScreenPoint(
    peerPoint: CGPoint?,
    offset: CGVector?,
    fallback: CGPoint
  ) -> CGPoint {
    guard let peerPoint, let offset else {
      return fallback
    }
    return CGPoint(
      x: peerPoint.x + offset.dx,
      y: peerPoint.y + offset.dy
    )
  }

}
