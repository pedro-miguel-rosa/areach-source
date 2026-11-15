import CoreGraphics
import Foundation

/// Deterministic coverage for the camera-card visibility policy. It tests
/// selection only; the matcher and native spatial state remain responsible for
/// keeping hidden peers alive.
@main
struct SpatialRenderVisibilityHarness {
  private static let viewport = CGSize(width: 1_000, height: 1_000)
  private static let center = CGPoint(x: 500, y: 500)

  static func main() {
    testNearbyAttendeeIsSelected()
    testBackgroundCrowdIsSuppressed()
    testMaximumVisibleCount()
    testCenterRelevance()
    testNewCandidateEntryDistance()
    testDistanceHysteresis()
    testScoreHysteresisAndReplacementMargin()
    testMissingDistanceCanStillRender()
    testReliableFarDistanceSuppresses()
    testWeakFarDistanceDoesNotHardReject()
    testWeakDistanceRanksLower()
    testBetterBodyEvidenceBeatsWeakUWB()
    testStrongAgreeingEvidenceIsHardGateEligible()
    testStrongContradictoryEvidenceIsNotHardGateEligible()
    testStaleDistanceIsNotUsedAsHardGate()
    testGroupPeersConsumeIndependentSlots()
    testForegroundGroupBeatsBackgroundCrowd()
    testHiddenCandidateCanEnterAfterVisibleTargetLeaves()
    testCanonicalSelectedOrderDrivesBothRenderOutputs()
    testStrictIdentityPolicyRemainsUnchanged()
    print("SpatialRenderVisibilityHarness: PASS")
  }

  private static func testNearbyAttendeeIsSelected() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [candidate(id: "alice", distance: 2, point: center)],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds == ["alice"], "nearby attendee was not selected")
  }

  private static func testBackgroundCrowdIsSuppressed() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(id: "pedro", distance: 1.7, point: center),
        candidate(id: "ana", distance: 4.8, point: CGPoint(x: 360, y: 500)),
        candidate(id: "joao", distance: 5.2, point: CGPoint(x: 640, y: 500)),
        candidate(id: "maria", distance: 6, point: CGPoint(x: 500, y: 260)),
      ],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds == ["pedro"], "background attendees filled the camera")
    require(selection.distanceSuppressedCount == 3, "distance suppression count was incorrect")
  }

  private static func testMaximumVisibleCount() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(id: "one", distance: 1.4, point: CGPoint(x: 470, y: 500)),
        candidate(id: "two", distance: 1.8, point: CGPoint(x: 530, y: 500)),
        candidate(id: "three", distance: 2.1, point: CGPoint(x: 440, y: 500)),
        candidate(id: "four", distance: 2.3, point: CGPoint(x: 700, y: 500)),
        candidate(id: "five", distance: 2.5, point: CGPoint(x: 300, y: 500)),
      ],
      viewportSize: viewport,
      now: 0
    )
    require(
      selection.selectedPeerIds.count == SpatialRenderTuning.maximumVisibleOverlayCount,
      "visibility selector exceeded the card cap"
    )
    require(selection.capacitySuppressedCount == 2, "capacity suppression count was incorrect")
  }

  private static func testCenterRelevance() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(id: "edge", distance: 1.4, point: CGPoint(x: 30, y: 500)),
        candidate(id: "center", distance: 1.9, point: center),
      ],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds.first == "center", "camera center did not affect ranking")
  }

  private static func testNewCandidateEntryDistance() {
    let selector = SpatialRenderVisibilitySelector()
    _ = selector.select(
      candidates: [candidate(id: "near", distance: 2, point: center)],
      viewportSize: viewport,
      now: 0
    )
    let selection = selector.select(
      candidates: [
        candidate(id: "near", distance: 2, point: center),
        candidate(id: "hidden", distance: 4.6, point: center),
      ],
      viewportSize: viewport,
      now: 0.1
    )
    require(!selection.selectedPeerIds.contains("hidden"), "a 4.6m hidden peer entered")
  }

  private static func testDistanceHysteresis() {
    let selector = SpatialRenderVisibilitySelector()
    for (time, distance) in [(0.0, 3.8), (0.2, 4.2), (0.4, 4.6)] {
      let selection = selector.select(
        candidates: [candidate(id: "walk", distance: Float(distance), point: center)],
        viewportSize: viewport,
        now: time
      )
      require(selection.selectedPeerIds == ["walk"], "selected card flickered inside retention range")
    }
    let expired = selector.select(
      candidates: [candidate(id: "walk", distance: 5.1, point: center)],
      viewportSize: viewport,
      now: 0.6
    )
    require(expired.selectedPeerIds.isEmpty, "card remained beyond retained distance")
  }

  private static func testScoreHysteresisAndReplacementMargin() {
    let selector = SpatialRenderVisibilitySelector()
    let initial = selector.select(
      candidates: scoreFixture(fourthPoint: CGPoint(x: 950, y: 500), fourthDistance: 2.1),
      viewportSize: viewport,
      now: 0
    )
    require(!initial.selectedPeerIds.contains("fourth"), "fixture did not leave a fourth candidate hidden")

    let nearTie = selector.select(
      candidates: scoreFixture(fourthPoint: CGPoint(x: 805, y: 500), fourthDistance: 2.1),
      viewportSize: viewport,
      now: 0.1
    )
    require(!nearTie.selectedPeerIds.contains("fourth"), "near-tie candidate replaced a stable card")

    let clearWinner = selector.select(
      candidates: scoreFixture(fourthPoint: center, fourthDistance: 1.0),
      viewportSize: viewport,
      now: 0.2
    )
    require(clearWinner.selectedPeerIds.contains("fourth"), "clearly better candidate did not replace a card")
    require(clearWinner.replacementCount == 1, "replacement instrumentation was incorrect")
  }

  private static func testMissingDistanceCanStillRender() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [candidate(id: "focused", distance: nil, point: center)],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds == ["focused"], "focused candidate without distance was discarded")
  }

  private static func testReliableFarDistanceSuppresses() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(
          id: "far",
          distance: 5.5,
          point: center,
          distanceQuality: 0.92,
          distanceUncertainty: 0.2
        )
      ],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds.isEmpty, "reliable far distance was ignored")
    require(selection.distanceSuppressedCount == 1, "reliable far suppression was not recorded")
  }

  private static func testWeakFarDistanceDoesNotHardReject() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(
          id: "uncertain",
          distance: 4.4,
          point: center,
          distanceQuality: 0.68,
          distanceUncertainty: 0.9
        )
      ],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds == ["uncertain"], "weak far distance hard-rejected a candidate")
    require(selection.distanceSuppressedCount == 0, "weak distance was counted as hard suppression")
    require(selection.weakDistanceCandidateCount == 1, "weak distance was not instrumented")
  }

  private static func testWeakDistanceRanksLower() {
    let reliable = candidate(
      id: "reliable",
      distance: 2.5,
      point: center,
      distanceQuality: 0.92,
      distanceUncertainty: 0.2
    )
    let weak = candidate(
      id: "weak",
      distance: 2.5,
      point: center,
      distanceQuality: 0.42,
      distanceUncertainty: 0.8
    )
    require(
      SpatialRenderVisibilitySelector.rankingScore(
        for: reliable,
        viewportSize: viewport
      ) > SpatialRenderVisibilitySelector.rankingScore(
        for: weak,
        viewportSize: viewport
      ),
      "weak distance did not rank below reliable distance"
    )
  }

  private static func testBetterBodyEvidenceBeatsWeakUWB() {
    let evidence = SpatialRenderDistancePolicy.select(
      measurements: [
        SpatialDepthMeasurement(
          distance: 4.3,
          quality: 0.68,
          uncertainty: 1.1,
          source: .uwbDistance,
          measuredAt: 0
        ),
        SpatialDepthMeasurement(
          distance: 3.7,
          quality: 0.85,
          uncertainty: 0.45,
          source: .vision3D,
          measuredAt: 0
        ),
      ],
      now: 0
    )
    require(evidence?.source == .vision3D, "weak UWB incorrectly won over body evidence")
    require(abs((evidence?.distance ?? 0) - 3.7) < 0.01, "effective render distance ignored body evidence")
    require(evidence?.hardGateEligible == true, "better body evidence was not hard-gate eligible")
  }

  private static func testStrongAgreeingEvidenceIsHardGateEligible() {
    let evidence = SpatialRenderDistancePolicy.select(
      measurements: [
        SpatialDepthMeasurement(
          distance: 3.2,
          quality: 0.9,
          uncertainty: 0.2,
          source: .uwbDistance,
          measuredAt: 0
        ),
        SpatialDepthMeasurement(
          distance: 3.3,
          quality: 0.85,
          uncertainty: 0.45,
          source: .vision3D,
          measuredAt: 0
        ),
      ],
      now: 0
    )
    require(evidence?.hardGateEligible == true, "agreeing near evidence was treated as weak")
  }

  private static func testStrongContradictoryEvidenceIsNotHardGateEligible() {
    let evidence = SpatialRenderDistancePolicy.select(
      measurements: [
        SpatialDepthMeasurement(
          distance: 5.8,
          quality: 0.9,
          uncertainty: 0.2,
          source: .uwbDistance,
          measuredAt: 0
        ),
        SpatialDepthMeasurement(
          distance: 2.0,
          quality: 0.85,
          uncertainty: 0.35,
          source: .vision3D,
          measuredAt: 0
        ),
      ],
      now: 0
    )
    require(evidence?.hardGateEligible == false, "contradictory evidence was treated as reliable")
  }

  private static func testStaleDistanceIsNotUsedAsHardGate() {
    // A stale measurement remains useful as ranking context but cannot become
    // the reason a card is hidden at the 4m/5m boundary.
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(
          id: "stale",
          distance: 4.6,
          point: center,
          distanceAge: 1.2
        )
      ],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds == ["stale"], "stale distance became a hard visibility gate")
    require(selection.distanceSuppressedCount == 0, "stale distance was counted as hard suppression")

    let missingDistance = SpatialRenderVisibilitySelector().select(
      candidates: [candidate(id: "missing", distance: nil, point: center)],
      viewportSize: viewport,
      now: 0
    )
    require(missingDistance.selectedPeerIds == ["missing"], "missing distance blocked valid spatial focus")
  }

  private static func testGroupPeersConsumeIndependentSlots() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(id: "alice", distance: 2, point: center, mode: .group),
        candidate(id: "bob", distance: 2, point: center, mode: .group),
        candidate(id: "carol", distance: 2.4, point: CGPoint(x: 560, y: 500)),
      ],
      viewportSize: viewport,
      now: 0
    )
    require(selection.selectedPeerIds.contains("alice"), "first group peer was suppressed")
    require(selection.selectedPeerIds.contains("bob"), "second group peer was suppressed")
    require(selection.selectedPeerIds.count == 3, "group peers did not consume independent slots")
  }

  private static func testForegroundGroupBeatsBackgroundCrowd() {
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: [
        candidate(id: "alice", distance: 2, point: center, mode: .group),
        candidate(id: "bob", distance: 2, point: center, mode: .group),
        candidate(id: "background-a", distance: 5, point: CGPoint(x: 380, y: 500)),
        candidate(id: "background-b", distance: 5.5, point: CGPoint(x: 620, y: 500)),
      ],
      viewportSize: viewport,
      now: 0
    )
    require(
      selection.selectedPeerIds == ["alice", "bob"],
      "background crowd displaced foreground group cards"
    )
  }

  private static func testHiddenCandidateCanEnterAfterVisibleTargetLeaves() {
    let selector = SpatialRenderVisibilitySelector()
    let initial = selector.select(
      candidates: scoreFixture(fourthPoint: CGPoint(x: 950, y: 500), fourthDistance: 2.1),
      viewportSize: viewport,
      now: 0
    )
    require(initial.selectedPeerIds.count == 3, "hidden-state fixture did not fill three slots")
    let afterDeparture = selector.select(
      candidates: [
        candidate(id: "one", distance: 1.4, point: CGPoint(x: 470, y: 500)),
        candidate(id: "two", distance: 1.8, point: CGPoint(x: 530, y: 500)),
        candidate(id: "fourth", distance: 2.1, point: CGPoint(x: 950, y: 500)),
      ],
      viewportSize: viewport,
      now: 0.1
    )
    require(afterDeparture.selectedPeerIds.contains("fourth"), "hidden candidate could not enter after a slot opened")
  }

  private static func testCanonicalSelectedOrderDrivesBothRenderOutputs() {
    // SpatialTargetMatcher.selectedRenderPeerIdsForOutput is the production
    // boundary used by both matchedTargets() and renderSnapshot(). Keep this
    // contract pure so it can be replayed without UIKit/Vision.
    let candidates = [
      candidate(id: "visible", distance: 2, point: center),
      candidate(id: "hidden", distance: 4.8, point: center),
    ]
    let selection = SpatialRenderVisibilitySelector().select(
      candidates: candidates,
      viewportSize: viewport,
      now: 0
    )
    let availablePeerIds = Set(candidates.map(\.peerId))
    let canonicalSelection = SpatialRenderOutputSelection(
      selectedPeerIds: selection.selectedPeerIds
    )
    let matcherTargets = canonicalSelection.orderedPeerIds(
      presentIn: availablePeerIds
    )
    let projectedTargets = canonicalSelection.orderedPeerIds(
      presentIn: availablePeerIds
    )
    require(
      matcherTargets == ["visible"] && projectedTargets == matcherTargets,
      "render outputs disagreed about selected peer IDs"
    )

    // A selected ID that is not in the current render-match map must not make
    // either production output resurrect an unselected/render-hidden peer.
    let withExtraRenderMatch = canonicalSelection.orderedPeerIds(
      presentIn: availablePeerIds.union(["unselected-render-match"])
    )
    require(
      withExtraRenderMatch == matcherTargets,
      "canonical output selection leaked an unselected render match"
    )
  }

  private static func testStrictIdentityPolicyRemainsUnchanged() {
    let policy = SpatialAssociationConfirmationPolicy.forPath(
      .initial,
      distanceOnly: false
    )
    require(
      !policy.accepts(
        confidence: 0.5,
        ambiguityMargin: 0.03,
        confirmationCount: 1
      ),
      "visibility selection weakened strict identity confirmation"
    )
  }

  private static func scoreFixture(
    fourthPoint: CGPoint,
    fourthDistance: Float
  ) -> [SpatialRenderVisibilityCandidate] {
    [
      candidate(id: "one", distance: 1.4, point: CGPoint(x: 470, y: 500)),
      candidate(id: "two", distance: 1.8, point: CGPoint(x: 530, y: 500)),
      candidate(id: "three", distance: 2.1, point: CGPoint(x: 900, y: 500)),
      candidate(id: "fourth", distance: fourthDistance, point: fourthPoint),
    ]
  }

  private static func candidate(
    id: String,
    distance: Float?,
    point: CGPoint,
    mode: SpatialRenderMode = .exact,
    confidence: Double = 0.8,
    distanceQuality: Double = 0.85,
    distanceUncertainty: Float = 0.2,
    distanceSource: SpatialDepthSource = .uwbDistance,
    distanceAge: CFTimeInterval = 0
  ) -> SpatialRenderVisibilityCandidate {
    let distanceEvidence = distance.flatMap { distance in
      SpatialRenderDistancePolicy.makeEvidence(
        measurement: SpatialDepthMeasurement(
          distance: distance,
          quality: Float(distanceQuality),
          uncertainty: distanceUncertainty,
          source: distanceSource,
          measuredAt: -distanceAge
        ),
        now: 0
      )
    }
    return SpatialRenderVisibilityCandidate(
      peerId: id,
      renderMode: mode,
      screenPoint: point,
      selectionDistanceEvidence: distanceEvidence,
      associationConfidence: confidence,
      spatialQuality: 0.8
    )
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fputs("SpatialRenderVisibilityHarness: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
