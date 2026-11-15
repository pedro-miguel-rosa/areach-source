import Foundation

@main
struct SpatialBodyDuplicateHarness {
  static func main() {
    testIdenticalSkeletonsAreDuplicates()
    testSmallOffsetDuplicateSkeletonsAreDuplicates()
    testLowerConfidenceDuplicateIsSuppressed()
    testPartialGhostDuplicateIsSuppressedWhenCoreGeometryMatches()
    testShoulderToShoulderPeopleRemainSeparate()
    testOverlappingRealPeopleRemainSeparate()
    testDifferentTorsoCentersRemainSeparate()
    testSimilarBoundingBoxesWithDifferentSkeletonsRemainSeparate()
    testBoundingBoxOverlapAloneIsInsufficient()
    testThreeDistinctPeopleRemainThreeBodies()
    testCrossingPeopleRemainSeparate()
    testSameDistancePeopleRemainSeparate()
    testStalePredictedDuplicateSuppressedWhileAwaitingConfirmation()
    testStaleDuplicateRetiresAfterRepeatedFreshConfirmation()
    testReportedSinglePersonCannotCreateTwoMatcherBodies()
    print("SpatialBodyDuplicateHarness: PASS")
  }

  private static let policy = SpatialBodyDuplicatePolicy()

  private static func testIdenticalSkeletonsAreDuplicates() {
    requireDuplicate(person(), person(), "identical skeletons")
  }

  private static func testSmallOffsetDuplicateSkeletonsAreDuplicates() {
    requireDuplicate(person(x: 0), person(x: 6), "small-offset duplicate skeletons")
  }

  private static func testLowerConfidenceDuplicateIsSuppressed() {
    let highQuality = person(confidence: 0.94)
    let lowQuality = person(confidence: 0.51)
    let result = policy.suppressDuplicates(in: [lowQuality, highQuality])
    require(result.retainedIndices == [1], "higher-quality duplicate observation did not win")
    require(result.suppressedIndices == [0], "lower-quality duplicate was not suppressed")
  }

  private static func testPartialGhostDuplicateIsSuppressedWhenCoreGeometryMatches() {
    let complete = person()
    let partial = person(
      bounds: SpatialBodyDuplicateBounds(x: -30, y: -36, width: 60, height: 56),
      scale: 80,
      joints: [
        joint("root", 0, 0),
        joint("leftShoulder", -18, -28),
        joint("rightShoulder", 18, -28),
      ]
    )
    requireDuplicate(complete, partial, "partial ghost with matching core geometry")
  }

  private static func testShoulderToShoulderPeopleRemainSeparate() {
    let left = person(x: -22, boundsX: -45, boundsWidth: 90)
    let right = person(x: 22, boundsX: -45, boundsWidth: 90)
    requireSeparate(left, right, "shoulder-to-shoulder people with strongly overlapping boxes")
  }

  private static func testOverlappingRealPeopleRemainSeparate() {
    let frontPerson = person(x: -14, boundsX: -45, boundsWidth: 90)
    let partlyOccludedPerson = person(
      x: 14,
      boundsX: -45,
      boundsWidth: 90,
      scale: 108
    )
    requireSeparate(frontPerson, partlyOccludedPerson, "partly overlapping real people")
  }

  private static func testDifferentTorsoCentersRemainSeparate() {
    let first = person(x: 0, boundsX: -40, boundsWidth: 80)
    let second = person(x: 18, boundsX: -40, boundsWidth: 80)
    requireSeparate(first, second, "different torso centers")
  }

  private static func testSimilarBoundingBoxesWithDifferentSkeletonsRemainSeparate() {
    let first = person(boundsX: -40, boundsWidth: 80)
    let second = person(
      boundsX: -40,
      boundsWidth: 80,
      rootY: 20,
      shoulderY: -4,
      hipY: 42
    )
    requireSeparate(first, second, "similar boxes with different skeletons")
  }

  private static func testBoundingBoxOverlapAloneIsInsufficient() {
    let identicalBounds = SpatialBodyDuplicateBounds(
      x: -50,
      y: -50,
      width: 100,
      height: 100
    )
    let first = person(x: -20, bounds: identicalBounds)
    let second = person(x: 20, bounds: identicalBounds)
    requireSeparate(first, second, "full box overlap with distinct body geometry")
  }

  private static func testThreeDistinctPeopleRemainThreeBodies() {
    let people = [person(x: -42), person(x: 0), person(x: 42)]
    let result = policy.suppressDuplicates(in: people)
    require(result.retainedIndices.count == 3, "three distinct people were reduced to fewer bodies")
  }

  private static func testCrossingPeopleRemainSeparate() {
    let crossingFrames: [[SpatialBodyDuplicateCandidate]] = [
      [person(x: -42), person(x: 42)],
      [person(x: -24), person(x: 24)],
      [person(x: -16), person(x: 16)],
      [person(x: 16), person(x: -16)],
      [person(x: 24), person(x: -24)],
      [person(x: 42), person(x: -42)],
    ]

    for (frameIndex, frame) in crossingFrames.enumerated() {
      let result = policy.suppressDuplicates(in: frame)
      require(
        result.retainedIndices.count == 2,
        "crossing frame \(frameIndex) collapsed two people"
      )
    }
  }

  private static func testSameDistancePeopleRemainSeparate() {
    // Distance is intentionally absent from SpatialBodyDuplicateCandidate;
    // equal UWB/body-depth distance cannot influence this decision.
    let sameDistanceFirst = person(x: -22, boundsX: -45, boundsWidth: 90)
    let sameDistanceSecond = person(x: 22, boundsX: -45, boundsWidth: 90)
    requireSeparate(sameDistanceFirst, sameDistanceSecond, "same-distance real people")
  }

  private static func testStalePredictedDuplicateSuppressedWhileAwaitingConfirmation() {
    let decision = SpatialBodyDuplicateTrackPolicy.decision(
      isStrongDuplicate: true,
      hasFreshPoseConfirmation: true,
      previousFreshDuplicateConfirmationCount: 0
    )
    require(decision.disposition == .suppress, "first fresh duplicate confirmation retired a track")
    require(
      decision.freshDuplicateConfirmationCount == 1,
      "first fresh duplicate confirmation was not recorded"
    )
  }

  private static func testStaleDuplicateRetiresAfterRepeatedFreshConfirmation() {
    let waiting = SpatialBodyDuplicateTrackPolicy.decision(
      isStrongDuplicate: true,
      hasFreshPoseConfirmation: false,
      previousFreshDuplicateConfirmationCount: 1
    )
    require(waiting.disposition == .suppress, "predicted duplicate was not hidden while waiting")
    require(
      waiting.freshDuplicateConfirmationCount == 1,
      "object-tracker frame counted as a fresh-pose confirmation"
    )

    let confirmed = SpatialBodyDuplicateTrackPolicy.decision(
      isStrongDuplicate: true,
      hasFreshPoseConfirmation: true,
      previousFreshDuplicateConfirmationCount: waiting.freshDuplicateConfirmationCount
    )
    require(confirmed.disposition == .retire, "repeated fresh duplicate evidence did not retire stale track")
    require(
      confirmed.freshDuplicateConfirmationCount == 2,
      "stale duplicate retirement did not require two fresh pose cycles"
    )
  }

  private static func testReportedSinglePersonCannotCreateTwoMatcherBodies() {
    let rawVisionObservations = [person(), person(x: 4)]
    let unique = policy.suppressDuplicates(in: rawVisionObservations)
    let matcherInput = unique.retainedIndices.map { rawVisionObservations[$0] }
    require(rawVisionObservations.count == 2, "regression fixture must contain two raw observations")
    require(unique.retainedIndices.count == 1, "one physical person did not reduce to one body")
    require(matcherInput.count == 1, "duplicate body remained as a second matcher candidate")
  }

  private static func requireDuplicate(
    _ first: SpatialBodyDuplicateCandidate,
    _ second: SpatialBodyDuplicateCandidate,
    _ label: String
  ) {
    require(policy.areDuplicates(first, second), "\(label) were not classified as duplicates")
    require(
      policy.suppressDuplicates(in: [first, second]).retainedIndices.count == 1,
      "\(label) produced more than one unique physical body"
    )
  }

  private static func requireSeparate(
    _ first: SpatialBodyDuplicateCandidate,
    _ second: SpatialBodyDuplicateCandidate,
    _ label: String
  ) {
    require(!policy.areDuplicates(first, second), "\(label) were classified as duplicates")
    require(
      policy.suppressDuplicates(in: [first, second]).retainedIndices.count == 2,
      "\(label) did not remain two physical-body candidates"
    )
  }

  private static func person(
    x: Double = 0,
    boundsX: Double? = nil,
    boundsWidth: Double = 60,
    bounds: SpatialBodyDuplicateBounds? = nil,
    scale: Double = 100,
    confidence: Double = 0.9,
    rootY: Double = 0,
    shoulderY: Double = -28,
    hipY: Double = 20,
    joints suppliedJoints: [SpatialBodyDuplicateJoint]? = nil
  ) -> SpatialBodyDuplicateCandidate {
    let bodyBounds = bounds ?? SpatialBodyDuplicateBounds(
      x: boundsX ?? x - boundsWidth / 2,
      y: -50,
      width: boundsWidth,
      height: 100
    )
    let bodyJoints = suppliedJoints ?? [
      joint("root", x, rootY, confidence: confidence),
      joint("leftShoulder", x - 18, shoulderY, confidence: confidence),
      joint("rightShoulder", x + 18, shoulderY, confidence: confidence),
      joint("leftHip", x - 12, hipY, confidence: confidence),
      joint("rightHip", x + 12, hipY, confidence: confidence),
      joint("neck", x, shoulderY - 8, confidence: confidence),
      joint("leftWrist", x - 34, shoulderY + 16, confidence: confidence),
    ]
    return SpatialBodyDuplicateCandidate(
      bounds: bodyBounds,
      confidence: confidence,
      bodyScale: scale,
      joints: bodyJoints,
      trackingPoint: SpatialBodyDuplicatePoint(x: x, y: rootY)
    )
  }

  private static func joint(
    _ name: String,
    _ x: Double,
    _ y: Double,
    confidence: Double = 0.9
  ) -> SpatialBodyDuplicateJoint {
    SpatialBodyDuplicateJoint(
      name: name,
      confidence: confidence,
      point: SpatialBodyDuplicatePoint(x: x, y: y)
    )
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
      fatalError(message)
    }
  }
}
