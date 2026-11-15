import Foundation

/// Deterministic lifecycle coverage for the native matcher contract. It
/// intentionally models the body-track result and evidence gates without
/// ARKit, Vision, Nearby Interaction, or camera pixels.
@main
struct SpatialAssociationReacquisitionHarness {
  private struct Fixture {
    let peerId = "peer-A"
    let userId = "user-pedro"
    var state: SpatialAssociationState = .unmatched
    var bodyTrackId: String?
    var lastBodyTrackId: String?
    var hasFreshBodyEvidence = false

    var identityIsKnown: Bool {
      !peerId.isEmpty && !userId.isEmpty
    }

    var overlayIsVisible: Bool {
      state == .verified && bodyTrackId != nil && hasFreshBodyEvidence
    }

    mutating func setInitialMatch() {
      state = .verified
      bodyTrackId = "body-0"
      lastBodyTrackId = bodyTrackId
      hasFreshBodyEvidence = true
    }

    mutating func observeBody(
      trackId: String,
      isRecoverable: Bool,
      hasFreshEvidence: Bool
    ) {
      if SpatialAssociationLifecyclePolicy.shouldDetachBodyTrack(
        bodyTrackId: bodyTrackId,
        isRecoverable: isRecoverable
      ) {
        lastBodyTrackId = bodyTrackId
        bodyTrackId = nil
        state = .awaitingReacquisition
        hasFreshBodyEvidence = false
        return
      }

      bodyTrackId = trackId
      state = SpatialAssociationLifecyclePolicy.stateAfterBodyObservation(
        currentState: state,
        bodyTrackIsRecoverable: isRecoverable,
        hasFreshBodyEvidence: hasFreshEvidence
      )
      hasFreshBodyEvidence = hasFreshEvidence
    }

    mutating func commitReacquisition(_ newBodyTrackId: String) {
      bodyTrackId = newBodyTrackId
      lastBodyTrackId = newBodyTrackId
      state = .verified
      hasFreshBodyEvidence = true
    }
  }

  static func main() {
    testNormalInitialMatch()
    testShortBodyMiss()
    testBodyTrackExpirationDetachesOnlyTheBody()
    testSamePersonReturnsWithNewBodyId()
    testRepeatedReacquisition()
    testTrueSwitchKeepsStrictPath()
    testStrongerCandidateWinsAfterOcclusion()
    testAmbiguousReacquisitionStaysHidden()
    testRangingWithoutBodyNeverRendersCard()
    testStaleSpatialEvidenceCannotReacquire()
    print("SpatialAssociationReacquisitionHarness: PASS")
  }

  private static func testNormalInitialMatch() {
    var fixture = Fixture()
    require(
      SpatialAssociationLifecyclePolicy.path(
        previousState: nil,
        activeBodyTrackId: nil,
        detectionId: "body-0"
      ) == .initial,
      "a peer without history did not use the initial path"
    )
    let policy = SpatialAssociationConfirmationPolicy.forPath(
      .initial,
      distanceOnly: false
    )
    require(
      !policy.accepts(
        confidence: 0.75,
        ambiguityMargin: 0.25,
        confirmationCount: 1
      ),
      "initial match skipped confirmation"
    )
    require(
      policy.accepts(
        confidence: 0.75,
        ambiguityMargin: 0.25,
        confirmationCount: 2
      ),
      "strong initial match did not confirm"
    )
    fixture.state = .tentative
    fixture.setInitialMatch()
    require(fixture.overlayIsVisible, "verified initial match was not visible")
  }

  private static func testShortBodyMiss() {
    var fixture = verifiedFixture()
    fixture.observeBody(
      trackId: "body-0",
      isRecoverable: true,
      hasFreshEvidence: false
    )
    require(
      fixture.state == .temporarilyOccluded,
      "a recoverable short miss did not become temporary occlusion"
    )
    require(
      fixture.bodyTrackId == "body-0",
      "a recoverable body track was detached too early"
    )
    require(
      SpatialAssociationLifecyclePolicy.path(
        previousState: fixture.state,
        activeBodyTrackId: fixture.bodyTrackId,
        detectionId: "body-0"
      ) == .continuation,
      "a recovered old track did not use continuation"
    )
    fixture.observeBody(
      trackId: "body-0",
      isRecoverable: true,
      hasFreshEvidence: true
    )
    require(fixture.state == .verified, "body continuation did not recover")
  }

  private static func testBodyTrackExpirationDetachesOnlyTheBody() {
    var fixture = verifiedFixture()
    fixture.observeBody(
      trackId: "body-0",
      isRecoverable: false,
      hasFreshEvidence: false
    )
    require(
      fixture.state == .awaitingReacquisition,
      "expired body track did not enter awaiting reacquisition"
    )
    require(fixture.bodyTrackId == nil, "expired body ID remained authoritative")
    require(fixture.lastBodyTrackId == "body-0", "old body context was lost")
    require(fixture.identityIsKnown, "peer-to-user identity was cleared")
    require(!fixture.overlayIsVisible, "card remained visible without a body")
  }

  private static func testSamePersonReturnsWithNewBodyId() {
    var fixture = detachedFixture()
    let path = SpatialAssociationLifecyclePolicy.path(
      previousState: fixture.state,
      activeBodyTrackId: fixture.bodyTrackId,
      detectionId: "body-1"
    )
    require(path == .reacquisition, "new body ID was classified as a switch")
    let policy = SpatialAssociationConfirmationPolicy.forPath(
      path,
      distanceOnly: false
    )
    require(
      policy.accepts(
        confidence: 0.75,
        ambiguityMargin: 0.24,
        confirmationCount: 2
      ),
      "strong reacquisition evidence did not pass its dedicated gate"
    )
    fixture.commitReacquisition("body-1")
    require(fixture.bodyTrackId == "body-1", "new body ID was not installed")
    require(fixture.state == .verified, "reacquisition did not become verified")
    require(fixture.overlayIsVisible, "reacquired attendee remained hidden")
  }

  private static func testRepeatedReacquisition() {
    var fixture = verifiedFixture()
    for index in 1...3 {
      let nextBodyId = "body-\(index)"
      fixture.observeBody(
        trackId: fixture.bodyTrackId ?? "body-unknown",
        isRecoverable: false,
        hasFreshEvidence: false
      )
      let path = SpatialAssociationLifecyclePolicy.path(
        previousState: fixture.state,
        activeBodyTrackId: fixture.bodyTrackId,
        detectionId: nextBodyId
      )
      require(path == .reacquisition, "repeat (nextBodyId) used the wrong path")
      let policy = SpatialAssociationConfirmationPolicy.forPath(
        path,
        distanceOnly: false
      )
      require(
        policy.accepts(
          confidence: 0.76,
          ambiguityMargin: 0.25,
          confirmationCount: 2
        ),
        "repeat (nextBodyId) did not pass reacquisition"
      )
      fixture.commitReacquisition(nextBodyId)
      require(fixture.overlayIsVisible, "repeat (nextBodyId) did not restore the card")
    }
  }

  private static func testTrueSwitchKeepsStrictPath() {
    let path = SpatialAssociationLifecyclePolicy.path(
      previousState: .verified,
      activeBodyTrackId: "body-0",
      detectionId: "body-1"
    )
    require(path == .identitySwitch, "a visible old body was treated as reacquisition")
    let reacquisitionPolicy = SpatialAssociationConfirmationPolicy.forPath(
      .reacquisition,
      distanceOnly: false
    )
    let switchPolicy = SpatialAssociationConfirmationPolicy.forPath(
      path,
      distanceOnly: false
    )
    require(
      reacquisitionPolicy.accepts(
        confidence: 0.75,
        ambiguityMargin: 0.24,
        confirmationCount: 2
      ),
      "test evidence was not in the reacquisition range"
    )
    require(
      !switchPolicy.accepts(
        confidence: 0.75,
        ambiguityMargin: 0.24,
        confirmationCount: 2
      ),
      "true switch accepted reacquisition-level evidence"
    )
    require(
      switchPolicy.accepts(
        confidence: 0.82,
        ambiguityMargin: 0.35,
        confirmationCount: 4
      ),
      "strong confirmed switch was incorrectly blocked by its own gate"
    )
  }

  private static func testStrongerCandidateWinsAfterOcclusion() {
    let fixture = detachedFixture()
    let path = SpatialAssociationLifecyclePolicy.path(
      previousState: fixture.state,
      activeBodyTrackId: fixture.bodyTrackId,
      detectionId: "body-1"
    )
    let policy = SpatialAssociationConfirmationPolicy.forPath(
      path,
      distanceOnly: false
    )
    require(
      policy.accepts(
        confidence: 0.82,
        ambiguityMargin: 0.24,
        confirmationCount: 2
      ),
      "clear stronger reacquisition candidate was rejected"
    )
    require(
      !policy.accepts(
        confidence: 0.75,
        ambiguityMargin: 0.10,
        confirmationCount: 2
      ),
      "weaker competing candidate bypassed the ambiguity gate"
    )
  }

  private static func testAmbiguousReacquisitionStaysHidden() {
    let fixture = detachedFixture()
    let path = SpatialAssociationLifecyclePolicy.path(
      previousState: fixture.state,
      activeBodyTrackId: fixture.bodyTrackId,
      detectionId: "body-1"
    )
    let policy = SpatialAssociationConfirmationPolicy.forPath(
      path,
      distanceOnly: false
    )
    require(
      !policy.accepts(
        confidence: 0.80,
        ambiguityMargin: 0.05,
        confirmationCount: 2
      ),
      "near-equal reacquisition evidence was accepted"
    )
    require(!fixture.overlayIsVisible, "ambiguous reacquisition rendered a card")
  }

  private static func testRangingWithoutBodyNeverRendersCard() {
    let fixture = detachedFixture()
    require(fixture.identityIsKnown, "ranging fixture lost attendee identity")
    require(!fixture.overlayIsVisible, "phone ranging alone rendered an attendee card")
  }

  private static func testStaleSpatialEvidenceCannotReacquire() {
    let path = SpatialAssociationLifecyclePolicy.path(
      previousState: .awaitingReacquisition,
      activeBodyTrackId: nil,
      detectionId: "body-1"
    )
    let policy = SpatialAssociationConfirmationPolicy.forPath(
      path,
      distanceOnly: false
    )
    require(
      !policy.accepts(
        confidence: 0.82,
        ambiguityMargin: 0.25,
        confirmationCount: 2,
        hasFreshSpatialEvidence: false
      ),
      "stale phone evidence reacquired a body"
    )
  }

  private static func verifiedFixture() -> Fixture {
    var fixture = Fixture()
    fixture.setInitialMatch()
    return fixture
  }

  private static func detachedFixture() -> Fixture {
    var fixture = verifiedFixture()
    fixture.observeBody(
      trackId: "body-0",
      isRecoverable: false,
      hasFreshEvidence: false
    )
    return fixture
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fputs("SpatialAssociationReacquisitionHarness: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
