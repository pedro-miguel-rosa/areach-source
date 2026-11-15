import CoreGraphics
import Foundation

/// Deterministic coverage for the render-only continuity and anchor policies.
/// Matching confidence and directional/FOV authority remain separate from all
/// of these decisions.
@main
struct SpatialRenderContinuityHarness {
  static func main() {
    testFreshAndRetainedStatesAreSeparate()
    testShortBodyLossIsRetained()
    testLongBodyLossExpires()
    testStalePeerEvidenceExpires()
    testPersistentContradictionExpires()
    testAnchorDeadZoneSuppressesJitter()
    testSustainedMovementCatchesUp()
    testAnchorSourceTransitionIsBounded()
    print("SpatialRenderContinuityHarness: PASS")
  }

  private static func testFreshAndRetainedStatesAreSeparate() {
    require(
      SpatialRenderContinuityPolicy.state(
        now: 10,
        lastBodyEvidenceAt: 9.9,
        lastPeerEvidenceAt: 9.9,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: false
      ) == .visible,
      "fresh body evidence was not classified as visible"
    )
    require(
      SpatialRenderContinuityPolicy.state(
        now: 10,
        lastBodyEvidenceAt: 9.5,
        lastPeerEvidenceAt: 9.9,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: false
      ) == .retained,
      "stale matching evidence did not enter render retention"
    )
  }

  private static func testShortBodyLossIsRetained() {
    require(
      SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.5,
        lastPeerEvidenceAt: 9.8,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: false
      ),
      "a 500 ms body gap removed a recoverable display"
    )
  }

  private static func testLongBodyLossExpires() {
    require(
      !SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.14,
        lastPeerEvidenceAt: 9.8,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: false
      ),
      "a body loss beyond track retention kept a stale display"
    )
    require(
      !SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.8,
        lastPeerEvidenceAt: 9.8,
        peerIsRecoverable: false,
        hasContradictorySpatialEvidence: false
      ),
      "an unrecoverable peer kept a display"
    )
  }

  private static func testStalePeerEvidenceExpires() {
    require(
      !SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.9,
        lastPeerEvidenceAt: 7.4,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: false
      ),
      "stale peer evidence kept a display alive"
    )
  }

  private static func testPersistentContradictionExpires() {
    require(
      SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.9,
        lastPeerEvidenceAt: 9.9,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: true,
        contradictoryEvidenceSince: 9.7
      ),
      "a transient directional contradiction removed a display"
    )
    require(
      !SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.9,
        lastPeerEvidenceAt: 9.9,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: true,
        contradictoryEvidenceSince: 9.4
      ),
      "a persistent directional contradiction kept a display"
    )
  }

  private static func testAnchorDeadZoneSuppressesJitter() {
    var current = CGPoint(x: 500, y: 300)
    var previousRaw = current
    var rawTravel: CGFloat = 0
    var stabilizedTravel: CGFloat = 0
    let samples = [
      CGPoint(x: 500, y: 300),
      CGPoint(x: 504, y: 298),
      CGPoint(x: 497, y: 302),
      CGPoint(x: 503, y: 301),
      CGPoint(x: 499, y: 299),
    ]

    for raw in samples {
      rawTravel += distance(previousRaw, raw)
      let update = SpatialRenderAnchorStabilityPolicy.update(
        current: current,
        raw: raw,
        previousSource: .body,
        source: .body,
        elapsed: 1 / 30
      )
      stabilizedTravel += distance(current, update.point)
      current = update.point
      previousRaw = raw
    }

    require(
      stabilizedTravel < rawTravel * 0.65,
      "anchor filter followed Vision jitter too closely"
    )
  }

  private static func testSustainedMovementCatchesUp() {
    var current = CGPoint(x: 500, y: 300)
    for index in 1...15 {
      current = SpatialRenderAnchorStabilityPolicy.update(
        current: current,
        raw: CGPoint(x: 500 + CGFloat(index * 10), y: 300),
        previousSource: .body,
        source: .body,
        elapsed: 1 / 30
      ).point
    }

    require(
      current.x > 600,
      "anchor filter lagged excessively behind sustained movement"
    )
  }

  private static func testAnchorSourceTransitionIsBounded() {
    let first = SpatialRenderAnchorStabilityPolicy.update(
      current: CGPoint(x: 500, y: 300),
      raw: CGPoint(x: 650, y: 300),
      previousSource: .body,
      source: .projectedPeer,
      elapsed: 1 / 60
    )
    let second = SpatialRenderAnchorStabilityPolicy.update(
      current: first.point,
      raw: CGPoint(x: 502, y: 300),
      previousSource: .projectedPeer,
      source: .body,
      elapsed: 1 / 60
    )

    require(
      first.point.x < 540 && abs(second.point.x - first.point.x) < 20,
      "anchor source transition produced a large screen discontinuity"
    )
  }

  private static func distance(_ first: CGPoint, _ second: CGPoint) -> CGFloat {
    hypot(first.x - second.x, first.y - second.y)
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fputs("SpatialRenderContinuityHarness: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
