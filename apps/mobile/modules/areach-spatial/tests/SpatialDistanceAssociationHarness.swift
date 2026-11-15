import Foundation

/// Deterministic tests for the scalar fallback used when Nearby Interaction
/// reports distance but cannot provide a projectable direction. These checks
/// intentionally avoid ARKit and do not claim that a physical phone can make
/// an identity decision without the matcher’s temporal/one-to-one gates.
@main
struct SpatialDistanceAssociationHarness {
  static func main() {
    testSeparatedBodiesPreferTheMatchingDepth()
    testNearEqualBodiesRemainAmbiguous()
    testStaleDistanceCannotStartAnIdentity()
    print("SpatialDistanceAssociationHarness: PASS")
  }

  private static func testSeparatedBodiesPreferTheMatchingDepth() {
    let peer = measurement(
      distance: 2.05,
      uncertainty: 0.12,
      quality: 0.9,
      measuredAt: 10
    )
    let bodyA = measurement(
      distance: 2.1,
      uncertainty: 0.16,
      quality: 0.9,
      measuredAt: 10
    )
    let bodyB = measurement(
      distance: 4.8,
      uncertainty: 0.2,
      quality: 0.9,
      measuredAt: 10
    )

    guard
      let matching = SpatialDistanceAssociationPolicy.compare(
        peer: peer,
        body: bodyA
      ),
      let distant = SpatialDistanceAssociationPolicy.compare(
        peer: peer,
        body: bodyB
      )
    else {
      fail("valid separated distance observations were rejected")
    }

    require(
      matching.score > distant.score,
      "the matching body did not outrank a distant body"
    )
    require(
      matching.isPhysicallyPlausible && matching.isHighQuality,
      "the matching body was not considered strong scalar evidence"
    )
    require(
      !distant.isPhysicallyPlausible,
      "a physically distant body passed the scalar plausibility gate"
    )
  }

  private static func testNearEqualBodiesRemainAmbiguous() {
    let peer = measurement(
      distance: 2.1,
      uncertainty: 0.16,
      quality: 0.9,
      measuredAt: 10
    )
    let bodyA = measurement(
      distance: 2.0,
      uncertainty: 0.16,
      quality: 0.9,
      measuredAt: 10
    )
    let bodyB = measurement(
      distance: 2.15,
      uncertainty: 0.16,
      quality: 0.9,
      measuredAt: 10
    )

    guard
      let scoreA = SpatialDistanceAssociationPolicy.compare(
        peer: peer,
        body: bodyA
      ),
      let scoreB = SpatialDistanceAssociationPolicy.compare(
        peer: peer,
        body: bodyB
      )
    else {
      fail("valid near-equal distance observations were rejected")
    }

    let margin = abs(scoreA.score - scoreB.score)
    require(
      margin < SpatialDistanceAssociationTuning.minimumNewAmbiguityMargin,
      "near-equal bodies produced a falsely clear scalar winner"
    )
  }

  private static func testStaleDistanceCannotStartAnIdentity() {
    let stalePeer = measurement(
      distance: 2.05,
      uncertainty: 0.12,
      quality: 0.9,
      measuredAt: 0
    )
    let freshBody = measurement(
      distance: 2.1,
      uncertainty: 0.16,
      quality: 0.9,
      measuredAt: 10
    )

    require(
      !stalePeer.isFresh(
        at: 10,
        maximumAge: SpatialDistanceAssociationTuning.maximumBodyMeasurementAge
      ),
      "stale peer distance was treated as fresh identity evidence"
    )
    require(
      freshBody.isFresh(
        at: 10,
        maximumAge: SpatialDistanceAssociationTuning.maximumBodyMeasurementAge
      ),
      "fresh body depth was unexpectedly rejected"
    )
  }

  private static func measurement(
    distance: Float,
    uncertainty: Float,
    quality: Float,
    measuredAt: CFTimeInterval
  ) -> SpatialDepthMeasurement {
    SpatialDepthMeasurement(
      distance: distance,
      quality: quality,
      uncertainty: uncertainty,
      source: .uwbDistance,
      measuredAt: measuredAt
    )
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fail(message)
    }
  }

  private static func fail(_ message: String) -> Never {
    fputs("SpatialDistanceAssociationHarness: FAIL: \(message)\n", stderr)
    exit(1)
  }
}
