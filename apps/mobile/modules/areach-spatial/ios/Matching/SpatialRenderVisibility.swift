import CoreGraphics
import Foundation
import QuartzCore

/// Distance evidence that is current enough to guide camera-card ranking. The
/// matcher keeps provenance and uncertainty with the scalar so the selector
/// can distinguish ranking evidence from a hard visibility gate.
struct SpatialRenderDistanceEvidence {
  let distance: Float
  let quality: Double
  let uncertainty: Float
  let source: SpatialDepthSource
  let age: CFTimeInterval
  let hardGateEligible: Bool

  fileprivate init(
    distance: Float,
    quality: Double,
    uncertainty: Float,
    source: SpatialDepthSource,
    age: CFTimeInterval,
    hardGateEligible: Bool
  ) {
    self.distance = distance
    self.quality = quality
    self.uncertainty = uncertainty
    self.source = source
    self.age = age
    self.hardGateEligible = hardGateEligible
  }

  func withHardGateEligibility(_ eligible: Bool) -> Self {
    SpatialRenderDistanceEvidence(
      distance: distance,
      quality: quality,
      uncertainty: uncertainty,
      source: source,
      age: age,
      hardGateEligible: eligible
    )
  }
}

/// The selector deliberately receives render information rather than identity
/// state. A candidate may be plausible or a group fallback and can still win
/// a camera slot without changing the strict body/peer association graph.
struct SpatialRenderVisibilityCandidate {
  let peerId: String
  let renderMode: SpatialRenderMode
  let screenPoint: CGPoint
  let selectionDistanceEvidence: SpatialRenderDistanceEvidence?
  let associationConfidence: Double
  let spatialQuality: Double
}

/// The selector should receive a single canonical selected order. Both direct
/// matcher targets and render snapshots use this helper, so a future output
/// path cannot accidentally bypass the visibility decision.
struct SpatialRenderOutputSelection {
  let selectedPeerOrder: [String]

  init(selectedPeerIds: [String]) {
    var seen = Set<String>()
    self.selectedPeerOrder = selectedPeerIds.filter { peerId in
      guard !seen.contains(peerId) else {
        return false
      }
      seen.insert(peerId)
      return true
    }
  }

  func orderedPeerIds(presentIn availablePeerIds: Set<String>) -> [String] {
    selectedPeerOrder.filter(availablePeerIds.contains)
  }
}

/// Small, deterministic policy for choosing which fresh distance evidence
/// guides render visibility. It deliberately does not alter identity
/// association or assignment decisions.
enum SpatialRenderDistancePolicy {
  static func makeEvidence(
    measurement: SpatialDepthMeasurement,
    now: CFTimeInterval
  ) -> SpatialRenderDistanceEvidence? {
    guard
      measurement.isFinite,
      now.isFinite,
      measurement.measuredAt.isFinite,
      measurement.measuredAt <= now
    else {
      return nil
    }

    let age = max(0, now - measurement.measuredAt)
    return SpatialRenderDistanceEvidence(
      distance: measurement.distance,
      quality: Double(max(0, min(1, measurement.quality))),
      uncertainty: measurement.uncertainty,
      source: measurement.source,
      age: age,
      hardGateEligible: isHardGateEligible(
        measurement,
        age: age
      )
    )
  }

  /// Select the strongest current source. Reliable evidence wins over weak
  /// evidence; quality, uncertainty, and freshness break ties. A direct UWB
  /// measurement is only a final tie-breaker, never an unconditional winner.
  static func select(
    measurements: [SpatialDepthMeasurement],
    now: CFTimeInterval
  ) -> SpatialRenderDistanceEvidence? {
    let evidence = measurements.compactMap {
      makeEvidence(measurement: $0, now: now)
    }
    guard !evidence.isEmpty else {
      return nil
    }

    let reliableMeasurements = measurements.filter { measurement in
      guard let evidence = makeEvidence(measurement: measurement, now: now)
      else {
        return false
      }
      return evidence.hardGateEligible
    }
    let hasStrongConflict: Bool
    if reliableMeasurements.count > 1 {
      hasStrongConflict = (0..<(reliableMeasurements.count - 1)).contains {
        lhsIndex in
        ((lhsIndex + 1)..<reliableMeasurements.count).contains { rhsIndex in
          SpatialDistanceAssociationPolicy.compare(
            peer: reliableMeasurements[lhsIndex],
            body: reliableMeasurements[rhsIndex]
          )?.isPhysicallyPlausible == false
        }
      }
    } else {
      hasStrongConflict = false
    }

    let selected = evidence.sorted { lhs, rhs in
      if lhs.hardGateEligible != rhs.hardGateEligible {
        return lhs.hardGateEligible
      }

      let lhsScore = rankingScore(lhs)
      let rhsScore = rankingScore(rhs)
      if lhsScore != rhsScore {
        return lhsScore > rhsScore
      }

      return sourcePriority(lhs.source) > sourcePriority(rhs.source)
    }.first!

    return hasStrongConflict
      ? selected.withHardGateEligibility(false)
      : selected
  }

  static func isHardGateEligible(
    _ measurement: SpatialDepthMeasurement,
    age: CFTimeInterval
  ) -> Bool {
    guard
      measurement.isFinite,
      age.isFinite,
      age >= 0,
      age <= SpatialRenderTuning.maximumHardGateDistanceAge
    else {
      return false
    }

    let relativeUncertainty = measurement.uncertainty
      / max(measurement.distance, 0.5)
    return Double(max(0, min(1, measurement.quality)))
        >= SpatialRenderTuning.minimumHardGateDistanceQuality
      && measurement.uncertainty
        <= SpatialRenderTuning.maximumHardGateDistanceUncertainty
      && relativeUncertainty
        <= SpatialRenderTuning.maximumHardGateRelativeUncertainty
  }

  private static func rankingScore(
    _ evidence: SpatialRenderDistanceEvidence
  ) -> Double {
    let relativeUncertainty = Double(evidence.uncertainty)
      / Double(max(evidence.distance, 0.5))
    let uncertaintyScore = max(
      0,
      min(
        1,
        1 - relativeUncertainty
          / Double(SpatialRenderTuning.maximumHardGateRelativeUncertainty)
      )
    )
    let freshnessScore = exp(
      -evidence.age / SpatialRenderTuning.distanceEvidenceFreshnessScale
    )
    return evidence.quality * SpatialRenderTuning.distanceEvidenceQualityWeight
      + uncertaintyScore
        * SpatialRenderTuning.distanceEvidenceUncertaintyWeight
      + freshnessScore * SpatialRenderTuning.distanceEvidenceFreshnessWeight
  }

  private static func sourcePriority(
    _ source: SpatialDepthSource
  ) -> Int {
    switch source {
    case .uwbDistance:
      return 5
    case .rawSceneDepth:
      return 4
    case .smoothedSceneDepth:
      return 3
    case .vision3D:
      return 2
    case .fallback:
      return 1
    }
  }
}

struct SpatialRenderVisibilitySelection {
  let selectedPeerIds: [String]
  let eligibleCandidateCount: Int
  let reliableDistanceCandidateCount: Int
  let weakDistanceCandidateCount: Int
  let distanceSuppressedCount: Int
  let capacitySuppressedCount: Int
  let retainedByHysteresisCount: Int
  let replacementCount: Int
  let selectionChanged: Bool
}

/// Small-N, stateful selection policy for the camera overlay. It is separate
/// from `SpatialTargetMatcher` so ranking and hysteresis can be replayed in a
/// deterministic harness without importing ARKit, Vision, or NearbyInteraction.
final class SpatialRenderVisibilitySelector {
  private struct SelectionState {
    let selectedAt: CFTimeInterval
  }

  private var selectedPeerIds: [String] = []
  private var selectionStates: [String: SelectionState] = [:]

  func reset() {
    selectedPeerIds.removeAll()
    selectionStates.removeAll()
  }

  func select(
    candidates: [SpatialRenderVisibilityCandidate],
    viewportSize: CGSize,
    now: CFTimeInterval
  ) -> SpatialRenderVisibilitySelection {
    let orderedCandidates = candidates.sorted {
      return $0.peerId < $1.peerId
    }
    let previousSelection = selectedPeerIds
    let previousSelectionSet = Set(previousSelection)

    let eligibleCandidates = orderedCandidates.filter { candidate in
      isEligible(
        candidate,
        wasSelected: previousSelectionSet.contains(candidate.peerId)
      )
    }
    let eligibleIds = Set(eligibleCandidates.map(\.peerId))
    let reliableDistanceCandidateCount = orderedCandidates.reduce(into: 0) {
      count,
      candidate in
      if candidate.selectionDistanceEvidence?.hardGateEligible == true {
        count += 1
      }
    }
    let weakDistanceCandidateCount = orderedCandidates.reduce(into: 0) {
      count,
      candidate in
      if candidate.selectionDistanceEvidence != nil,
        candidate.selectionDistanceEvidence?.hardGateEligible != true
      {
        count += 1
      }
    }
    let distanceSuppressedCount = orderedCandidates.reduce(into: 0) {
      count,
      candidate in
      guard hasReliableDistance(candidate) else {
        return
      }

      let limit = previousSelectionSet.contains(candidate.peerId)
        ? SpatialRenderTuning.retainedOverlayMaximumDistance
        : SpatialRenderTuning.newOverlayMaximumDistance
      if candidate.selectionDistanceEvidence!.distance > limit {
        count += 1
      }
    }

    var selected = previousSelection.filter { eligibleIds.contains($0) }
    let retainedByHysteresisCount = selected.count
    var selectedSet = Set(selected)
    let baseScores = Dictionary(
      uniqueKeysWithValues: eligibleCandidates.map { candidate in
        (
          candidate.peerId,
          Self.rankingScore(
            for: candidate,
            viewportSize: viewportSize
          )
        )
      }
    )

    let rankedEligible = eligibleCandidates.sorted { lhs, rhs in
      let lhsScore = baseScores[lhs.peerId] ?? 0
      let rhsScore = baseScores[rhs.peerId] ?? 0
      if lhsScore == rhsScore {
        return lhs.peerId < rhs.peerId
      }
      return lhsScore > rhsScore
    }

    for candidate in rankedEligible where selected.count < SpatialRenderTuning.maximumVisibleOverlayCount {
      guard !selectedSet.contains(candidate.peerId) else {
        continue
      }

      selected.append(candidate.peerId)
      selectedSet.insert(candidate.peerId)
    }

    var replacementCount = 0
    while selected.count == SpatialRenderTuning.maximumVisibleOverlayCount {
      guard
        let challenger = rankedEligible.first(where: {
          !selectedSet.contains($0.peerId)
        }),
        let incumbentIndex = selected.indices.min(by: { lhsIndex, rhsIndex in
          let lhsId = selected[lhsIndex]
          let rhsId = selected[rhsIndex]
          let lhsScore = effectiveScore(
            peerId: lhsId,
            baseScore: baseScores[lhsId] ?? 0,
            now: now
          )
          let rhsScore = effectiveScore(
            peerId: rhsId,
            baseScore: baseScores[rhsId] ?? 0,
            now: now
          )
          if lhsScore == rhsScore {
            return lhsId > rhsId
          }
          return lhsScore < rhsScore
        })
      else {
        break
      }

      let incumbentId = selected[incumbentIndex]
      let challengerScore = baseScores[challenger.peerId] ?? 0
      let incumbentScore = effectiveScore(
        peerId: incumbentId,
        baseScore: baseScores[incumbentId] ?? 0,
        now: now
      )
      guard challengerScore >= incumbentScore + SpatialRenderTuning.replacementScoreMargin else {
        break
      }

      selectedSet.remove(incumbentId)
      selected[incumbentIndex] = challenger.peerId
      selectedSet.insert(challenger.peerId)
      replacementCount += 1
    }

    let nextSelectionStates = selected.reduce(into: [String: SelectionState]()) { states, peerId in
      if let previousState = selectionStates[peerId], previousSelectionSet.contains(peerId) {
        states[peerId] = previousState
      } else {
        states[peerId] = SelectionState(selectedAt: now)
      }
    }
    selectedPeerIds = selected
    selectionStates = nextSelectionStates

    let selectionChanged = selected != previousSelection
    let capacitySuppressedCount = max(
      0,
      eligibleCandidates.count - selected.count
    )

    return SpatialRenderVisibilitySelection(
      selectedPeerIds: selected,
      eligibleCandidateCount: eligibleCandidates.count,
      reliableDistanceCandidateCount: reliableDistanceCandidateCount,
      weakDistanceCandidateCount: weakDistanceCandidateCount,
      distanceSuppressedCount: distanceSuppressedCount,
      capacitySuppressedCount: capacitySuppressedCount,
      retainedByHysteresisCount: retainedByHysteresisCount,
      replacementCount: replacementCount,
      selectionChanged: selectionChanged
    )
  }

  static func rankingScore(
    for candidate: SpatialRenderVisibilityCandidate,
    viewportSize: CGSize
  ) -> Double {
    let centerScore = centerRelevance(
      for: candidate.screenPoint,
      viewportSize: viewportSize
    )
    let proximityScore = proximityRelevance(
      candidate.selectionDistanceEvidence?.distance
    )
    let associationQuality = max(
      0,
      min(1, candidate.associationConfidence)
    )
    let spatialQuality = max(
      0,
      min(1, candidate.spatialQuality)
    )
    let distanceQuality = candidate.selectionDistanceEvidence == nil
      ? SpatialRenderTuning.visibilityMissingDistanceScore
      : max(
        0,
        min(1, candidate.selectionDistanceEvidence?.quality ?? 0)
      )
    let renderModeQuality: Double
    switch candidate.renderMode {
    case .exact:
      renderModeQuality = 0.94
    case .plausible:
      renderModeQuality = 0.68
    case .group:
      renderModeQuality = 0.74
    }
    let qualityScore = associationQuality * 0.55
      + spatialQuality * 0.2
      + renderModeQuality * 0.15
      + distanceQuality * 0.1

    return centerScore * SpatialRenderTuning.visibilityCenterWeight
      + proximityScore * SpatialRenderTuning.visibilityProximityWeight
      + qualityScore * SpatialRenderTuning.visibilityQualityWeight
  }

  private func isEligible(
    _ candidate: SpatialRenderVisibilityCandidate,
    wasSelected: Bool
  ) -> Bool {
    guard let evidence = candidate.selectionDistanceEvidence else {
      // Missing distance is a ranking disadvantage, not an automatic render
      // rejection. This keeps non-LiDAR and temporary-UWB-gap cases usable.
      return true
    }

    let distance = evidence.distance
    guard distance.isFinite, distance > 0 else {
      return false
    }

    // Weak or conflicting distance still informs ranking, but cannot alone
    // hide an otherwise useful render candidate.
    guard evidence.hardGateEligible else {
      return true
    }

    let maximumDistance = wasSelected
      ? SpatialRenderTuning.retainedOverlayMaximumDistance
      : SpatialRenderTuning.newOverlayMaximumDistance
    return distance <= maximumDistance
  }

  private func hasReliableDistance(
    _ candidate: SpatialRenderVisibilityCandidate
  ) -> Bool {
    guard let evidence = candidate.selectionDistanceEvidence else {
      return false
    }
    return evidence.hardGateEligible
      && evidence.distance.isFinite
      && evidence.distance > 0
  }

  private func effectiveScore(
    peerId: String,
    baseScore: Double,
    now: CFTimeInterval
  ) -> Double {
    guard let state = selectionStates[peerId] else {
      return baseScore
    }

    let age = max(0, now - state.selectedAt)
    let fade = max(
      0,
      min(1, 1 - age / SpatialRenderTuning.selectionHysteresisDuration)
    )
    return baseScore + SpatialRenderTuning.visibilityContinuityBonus * fade
  }

  private static func centerRelevance(
    for point: CGPoint,
    viewportSize: CGSize
  ) -> Double {
    guard
      point.x.isFinite,
      point.y.isFinite,
      viewportSize.width > 0,
      viewportSize.height > 0
    else {
      return 0.5
    }

    let center = CGPoint(
      x: viewportSize.width / 2,
      y: viewportSize.height / 2
    )
    let normalizedX = (point.x - center.x) / max(viewportSize.width / 2, 1)
    let normalizedY = (point.y - center.y) / max(viewportSize.height / 2, 1)
    let radialDistance = hypot(normalizedX, normalizedY)
    return max(0, min(1, exp(-0.85 * radialDistance * radialDistance)))
  }

  private static func proximityRelevance(_ distance: Float?) -> Double {
    guard let distance, distance.isFinite, distance > 0 else {
      return SpatialRenderTuning.visibilityMissingDistanceScore
    }

    let value = Double(distance)
    if value <= Double(SpatialRenderTuning.strongProximityDistance) {
      return 1 - 0.22 * value / Double(SpatialRenderTuning.strongProximityDistance)
    }

    if value <= Double(SpatialRenderTuning.newOverlayMaximumDistance) {
      let progress = (value - Double(SpatialRenderTuning.strongProximityDistance))
        / Double(
          SpatialRenderTuning.newOverlayMaximumDistance
            - SpatialRenderTuning.strongProximityDistance
        )
      return 0.78 - progress * 0.30
    }

    let progress = min(
      1,
      (value - Double(SpatialRenderTuning.newOverlayMaximumDistance))
        / Double(
          SpatialRenderTuning.retainedOverlayMaximumDistance
            - SpatialRenderTuning.newOverlayMaximumDistance
        )
    )
    return max(0.2, 0.48 - progress * 0.28)
  }
}
