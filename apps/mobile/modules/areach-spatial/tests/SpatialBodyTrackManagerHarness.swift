import Foundation

// This lightweight fixture supplies the subset of the app's Vision detection
// value used by the production track manager, keeping this harness runnable
// without an ARKit camera or Vision request.
struct SpatialBodyJoint {
  let confidence: Float
  let name: String
  let point: CGPoint
}

struct SpatialBodyDetection {
  let bodyScale: CGFloat
  let boundingBox: CGRect
  let confidence: Float
  let hasMotionEstimate: Bool
  let id: String
  let isFreshPose: Bool
  let joints: [SpatialBodyJoint]
  let poseAge: CFTimeInterval
  let poseTimestamp: CFTimeInterval
  let trackingPoint: CGPoint
  let trackingVelocity: CGVector

  var duplicateBodyCandidate: SpatialBodyDuplicateCandidate {
    SpatialBodyDuplicateCandidate(
      bounds: SpatialBodyDuplicateBounds(
        x: Double(boundingBox.minX),
        y: Double(boundingBox.minY),
        width: Double(boundingBox.width),
        height: Double(boundingBox.height)
      ),
      confidence: Double(confidence),
      bodyScale: Double(bodyScale),
      joints: joints.map {
        SpatialBodyDuplicateJoint(
          name: $0.name,
          confidence: Double($0.confidence),
          point: SpatialBodyDuplicatePoint(
            x: Double($0.point.x),
            y: Double($0.point.y)
          )
        )
      },
      trackingPoint: SpatialBodyDuplicatePoint(
        x: Double(trackingPoint.x),
        y: Double(trackingPoint.y)
      )
    )
  }

  func withDepth(
    _ bodyDepth: Float?,
    quality: Float,
    sampleCount: Int,
    spread: Float?,
    geometry: Any?
  ) -> SpatialBodyDetection {
    self
  }

  func transformed(
    from sourceBounds: CGRect,
    to destinationBounds: CGRect,
    confidence: Float
  ) -> SpatialBodyDetection {
    let horizontalScale = destinationBounds.width / sourceBounds.width
    let verticalScale = destinationBounds.height / sourceBounds.height
    let scale = max(0.5, min(2, (horizontalScale + verticalScale) / 2))
    func transform(_ point: CGPoint) -> CGPoint {
      CGPoint(
        x: destinationBounds.minX + (point.x - sourceBounds.minX) * horizontalScale,
        y: destinationBounds.minY + (point.y - sourceBounds.minY) * verticalScale
      )
    }
    return SpatialBodyDetection(
      bodyScale: bodyScale * scale,
      boundingBox: destinationBounds,
      confidence: min(self.confidence, confidence),
      hasMotionEstimate: hasMotionEstimate,
      id: id,
      isFreshPose: isFreshPose,
      joints: joints.map {
        SpatialBodyJoint(
          confidence: $0.confidence,
          name: $0.name,
          point: transform($0.point)
        )
      },
      poseAge: poseAge,
      poseTimestamp: poseTimestamp,
      trackingPoint: transform(trackingPoint),
      trackingVelocity: trackingVelocity
    )
  }

  func withTracking(
    id: String,
    point: CGPoint,
    velocity: CGVector,
    hasMotionEstimate: Bool,
    at time: CFTimeInterval,
    isFreshPose: Bool = false
  ) -> SpatialBodyDetection {
    SpatialBodyDetection(
      bodyScale: bodyScale,
      boundingBox: boundingBox,
      confidence: confidence,
      hasMotionEstimate: hasMotionEstimate,
      id: id,
      isFreshPose: isFreshPose,
      joints: joints,
      poseAge: max(0, time - poseTimestamp),
      poseTimestamp: poseTimestamp,
      trackingPoint: point,
      trackingVelocity: velocity
    )
  }
}

enum SpatialVisionTuning {
  static let maximumBodyPredictionInterval: CFTimeInterval = 0.35
  static let bodyTrackRetentionDuration: CFTimeInterval = 0.85
  static let bodyTrackMaximumCenterDisplacement: CGFloat = 1.1
  static let bodyTrackMaximumScaleRatio: CGFloat = 1.65
  static let bodyTrackMinimumFarIoU: Double = 0.02
  static let bodyTrackPositionMeasurementNoise: CGFloat = 24
  static let bodyTrackVelocityMeasurementNoise: CGFloat = 80
}

@main
struct SpatialBodyTrackManagerHarness {
  static func main() {
    testDuplicatePoseSeedsOnePersistentTrack()
    testDuplicateDisappearingNextFrameKeepsOnePersistentTrack()
    testUnmatchedDuplicateCannotSeedAnotherTrack()
    testShortPoseDropoutRetainsTrack()
    testFreshBodySuppressesStalePredictedDuplicate()
    testTwoRealBodiesCrossWithoutTrackCollapse()
    testCloseOverlappingBodiesRemainTwoTracks()
    print("SpatialBodyTrackManagerHarness: PASS")
  }

  private static func testDuplicatePoseSeedsOnePersistentTrack() {
    let manager = SpatialBodyTrackManager()
    let bodies = manager.update(
      [person("vision-a"), person("vision-b", x: 4)],
      now: 10
    )
    require(bodies.count == 1, "duplicate Vision observations created multiple manager tracks")
    require(bodies[0].id == "body-0", "unexpected track identity for the unique body")
    require(
      manager.lastDuplicateDetectionSuppressionCount == 1,
      "manager safety pass did not report the suppressed duplicate detection"
    )
  }

  private static func testDuplicateDisappearingNextFrameKeepsOnePersistentTrack() {
    let manager = SpatialBodyTrackManager()
    let initialBodies = manager.update(
      [person("vision-a"), person("vision-b", x: 4)],
      now: 20
    )
    let nextBodies = manager.update([person("vision-a")], now: 20.2)
    require(initialBodies.count == 1, "initial duplicate frame created a phantom track")
    require(nextBodies.count == 1, "phantom track survived after duplicate observation disappeared")
    require(nextBodies[0].id == initialBodies[0].id, "unique body did not retain its track ID")
  }

  private static func testUnmatchedDuplicateCannotSeedAnotherTrack() {
    let manager = SpatialBodyTrackManager()
    _ = manager.update([person("seed")], now: 25)
    let bodies = manager.update(
      [person("observed", x: -7), person("unmatched-ghost", x: 7)],
      now: 25.2
    )
    require(bodies.count == 1, "unmatched duplicate created a second body track")
    require(
      manager.lastDuplicateTrackSuppressionCount == 1,
      "unmatched duplicate safety check did not record its suppression"
    )
  }

  private static func testShortPoseDropoutRetainsTrack() {
    let manager = SpatialBodyTrackManager()
    let initialBodies = manager.update([person("vision-a")], now: 30)
    let predictedBodies = manager.update([], now: 30.18)
    require(initialBodies.count == 1, "single physical body did not seed a track")
    require(predictedBodies.count == 1, "short Vision dropout discarded the body track")
    require(predictedBodies[0].id == initialBodies[0].id, "dropout prediction changed track identity")
    require(!predictedBodies[0].isFreshPose, "dropout prediction was marked as fresh Vision evidence")
  }

  private static func testFreshBodySuppressesStalePredictedDuplicate() {
    let manager = SpatialBodyTrackManager()
    let initialBodies = manager.update(
      [person("existing-a", x: 0), person("existing-b", x: 14)],
      now: 35
    )
    require(initialBodies.count == 2, "distinct initial tracks were collapsed")

    let visibleBodies = manager.update([person("single-visible", x: 7)], now: 35.1)
    require(visibleBodies.count == 1, "stale predicted duplicate reached matcher-visible output")
    require(
      manager.lastDuplicateTrackSuppressionCount == 1,
      "manager did not report suppression of the stale predicted duplicate"
    )

    let confirmedBodies = manager.update(
      [person("single-visible-confirmed", x: 7)],
      now: 35.2
    )
    require(confirmedBodies.count == 1, "confirmed stale duplicate became matcher-visible")
    require(
      manager.lastDuplicateTrackRetirementCount == 1,
      "stale duplicate was not retired after repeated fresh-pose confirmation"
    )
  }

  private static func testTwoRealBodiesCrossWithoutTrackCollapse() {
    let manager = SpatialBodyTrackManager()
    let frames: [[SpatialBodyDetection]] = [
      [person("left", x: -45), person("right", x: 45)],
      [person("left", x: -24), person("right", x: 24)],
      [person("left", x: -16), person("right", x: 16)],
      [person("left", x: 16), person("right", x: -16)],
      [person("left", x: 24), person("right", x: -24)],
      [person("left", x: 45), person("right", x: -45)],
    ]

    var previousTrackIds: Set<String>?
    for (frameIndex, frame) in frames.enumerated() {
      let tracked = manager.update(frame, now: 40 + Double(frameIndex) * 0.1)
      let trackIds = Set(tracked.map(\.id))
      require(tracked.count == 2, "crossing frame \(frameIndex) collapsed two people")
      if let previousTrackIds {
        require(trackIds == previousTrackIds, "crossing changed the active body-track set")
      }
      previousTrackIds = trackIds
    }
  }

  private static func testCloseOverlappingBodiesRemainTwoTracks() {
    let manager = SpatialBodyTrackManager()
    let first = person("front", x: -22, boxWidth: 90)
    let second = person("partly-occluded", x: 22, boxWidth: 90, scale: 108)
    let bodies = manager.update([first, second], now: 50)
    require(bodies.count == 2, "overlapping distinct torso geometry was merged")
  }

  private static func person(
    _ id: String,
    x: CGFloat = 0,
    boxWidth: CGFloat = 100,
    scale: CGFloat = 100,
    confidence: Float = 0.9,
    isFreshPose: Bool = true
  ) -> SpatialBodyDetection {
    let bounds = CGRect(x: x - boxWidth / 2, y: -50, width: boxWidth, height: 100)
    let joints: [(String, CGFloat, CGFloat)] = [
      ("root", x, 0),
      ("leftShoulder", x - 18, -28),
      ("rightShoulder", x + 18, -28),
      ("leftHip", x - 12, 20),
      ("rightHip", x + 12, 20),
      ("neck", x, -36),
    ]
    return SpatialBodyDetection(
      bodyScale: scale,
      boundingBox: bounds,
      confidence: confidence,
      hasMotionEstimate: false,
      id: id,
      isFreshPose: isFreshPose,
      joints: joints.map {
        SpatialBodyJoint(
          confidence: confidence,
          name: $0.0,
          point: CGPoint(x: $0.1, y: $0.2)
        )
      },
      poseAge: 0,
      poseTimestamp: 0,
      trackingPoint: CGPoint(x: x, y: 0),
      trackingVelocity: .zero
    )
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
      fputs("SpatialBodyTrackManagerHarness: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
