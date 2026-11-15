import CoreGraphics
import Foundation
import simd

/// Deterministic coverage for render-only singleton/group decisions and the
/// depth-aware body clusterer. It does not weaken or replace identity gates.
@main
struct SpatialRenderFallbackHarness {
  static func main() {
    testObviousSingletonUsesPlausibleMode()
    testFreshDirectionalPeerCanRenderWithoutStrictRanging()
    testSingletonRejectsImpossibleDistance()
    testShortDisplayLossIsRetained()
    testProlongedDisplayLossExpires()
    testCloseBodiesFormOneGroup()
    testClusterAnchorIsSmoothed()
    testMultiplePeersCanShareGroupFallback()
    testSeparatedBodiesLeaveGroupFallback()
    testOverlappingScreenPositionsWithDifferentDepthStaySeparate()
    testCrossingKeepsIdentityPolicyStrict()
    print("SpatialRenderFallbackHarness: PASS")
  }

  private static func testObviousSingletonUsesPlausibleMode() {
    let evidence = usableEvidence()
    require(
      SpatialRenderDecisionPolicy.acceptsSingleton(
        bodyCount: 1,
        eligiblePeerCount: 1,
        evidence: evidence
      ),
      "obvious singleton was not renderable"
    )
    require(
      SpatialRenderMode.plausible != SpatialRenderMode.exact,
      "plausible render mode collapsed into exact identity"
    )

    let identityPolicy = SpatialAssociationConfirmationPolicy.forPath(
      .initial,
      distanceOnly: false
    )
    require(
      !identityPolicy.accepts(
        confidence: 0.5,
        ambiguityMargin: 0.03,
        confirmationCount: 1
      ),
      "singleton render evidence bypassed the strict identity gate"
    )
  }

  private static func testSingletonRejectsImpossibleDistance() {
    require(
      !SpatialRenderDecisionPolicy.acceptsSingleton(
        bodyCount: 1,
        eligiblePeerCount: 1,
        evidence: usableEvidence(
          distanceNormalizedResidual: 8,
          isPhysicallyPlausible: false
        )
      ),
      "an impossible singleton distance rendered a card"
    )
  }

  private static func testFreshDirectionalPeerCanRenderWithoutStrictRanging() {
    require(
      SpatialRenderFreshnessPolicy.canUsePeerForFallback(
        worldTransformAvailable: true,
        transformAge: 0.4,
        distanceIsFresh: false
      ),
      "a fresh directional peer was blocked by strict ranging eligibility"
    )
    require(
      !SpatialRenderFreshnessPolicy.canUsePeerForFallback(
        worldTransformAvailable: true,
        transformAge: 2.0,
        distanceIsFresh: false
      ),
      "a stale directional peer regained render eligibility"
    )
  }

  private static func testShortDisplayLossIsRetained() {
    require(
      SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.82,
        lastPeerEvidenceAt: 9.8,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: false
      ),
      "short Vision loss did not retain the display state"
    )
  }

  private static func testProlongedDisplayLossExpires() {
    require(
      !SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.14,
        lastPeerEvidenceAt: 9.8,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: false
      ),
      "prolonged body loss kept a stale display state"
    )
    require(
      !SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.8,
        lastPeerEvidenceAt: 9.8,
        peerIsRecoverable: false,
        hasContradictorySpatialEvidence: false
      ),
      "an unrecoverable peer kept a display state"
    )
    require(
      !SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.8,
        lastPeerEvidenceAt: 9.8,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: true
      ),
      "contradictory spatial evidence kept a display state"
    )
    require(
      SpatialRenderDecisionPolicy.retainsDisplay(
        now: 10,
        lastBodyEvidenceAt: 9.9,
        lastPeerEvidenceAt: 9.9,
        peerIsRecoverable: true,
        hasContradictorySpatialEvidence: true,
        contradictoryEvidenceSince: 9.7
      ),
      "a transient contradiction removed the display state"
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
      "a prolonged contradiction kept the display state"
    )
  }

  private static func testCloseBodiesFormOneGroup() {
    let cluster = closeClusterer().clusters(
      for: [
        sample(
          id: "body-A",
          box: CGRect(x: 100, y: 100, width: 180, height: 360),
          trackingPoint: CGPoint(x: 190, y: 300),
          labelPoint: CGPoint(x: 190, y: 70)
        ),
        sample(
          id: "body-B",
          box: CGRect(x: 245, y: 105, width: 180, height: 360),
          trackingPoint: CGPoint(x: 335, y: 305),
          labelPoint: CGPoint(x: 335, y: 75)
        ),
      ],
      now: 1
    )
    require(cluster.count == 1, "close bodies did not form one cluster")
    require(cluster[0].count == 2, "close cluster lost a body")
    require(
      SpatialRenderDecisionPolicy.acceptsGroup(
        clusterMemberCount: cluster[0].count,
        evidence: usableEvidence()
      ),
      "a plausible close group was not renderable"
    )
  }

  private static func testMultiplePeersCanShareGroupFallback() {
    let evidence = usableEvidence()
    require(
      SpatialRenderDecisionPolicy.acceptsGroup(
        clusterMemberCount: 2,
        evidence: evidence
      ) && SpatialRenderDecisionPolicy.acceptsGroup(
        clusterMemberCount: 2,
        evidence: evidence
      ),
      "group fallback incorrectly enforced one peer per cluster"
    )
  }

  private static func testClusterAnchorIsSmoothed() {
    let clusterer = closeClusterer()
    let initial = clusterer.clusters(
      for: [
        sample(
          id: "body-A",
          box: CGRect(x: 100, y: 100, width: 140, height: 300),
          trackingPoint: CGPoint(x: 170, y: 270),
          labelPoint: CGPoint(x: 170, y: 70)
        ),
        sample(
          id: "body-B",
          box: CGRect(x: 190, y: 105, width: 140, height: 300),
          trackingPoint: CGPoint(x: 260, y: 275),
          labelPoint: CGPoint(x: 260, y: 75)
        ),
      ],
      now: 1
    )
    let moved = clusterer.clusters(
      for: [
        sample(
          id: "body-A",
          box: CGRect(x: 220, y: 100, width: 140, height: 300),
          trackingPoint: CGPoint(x: 290, y: 270),
          labelPoint: CGPoint(x: 290, y: 70)
        ),
        sample(
          id: "body-B",
          box: CGRect(x: 310, y: 105, width: 140, height: 300),
          trackingPoint: CGPoint(x: 380, y: 275),
          labelPoint: CGPoint(x: 380, y: 75)
        ),
      ],
      now: 1.1
    )
    let initialAnchor = initial[0].anchor.x
    let rawMovedAnchor = 335.0
    require(
      moved[0].anchor.x > initialAnchor
        && moved[0].anchor.x < rawMovedAnchor,
      "cluster anchor jumped directly to a changed membership position"
    )
  }

  private static func testSeparatedBodiesLeaveGroupFallback() {
    let clusterer = closeClusterer()
    let initial = clusterer.clusters(
      for: [
        sample(
          id: "body-A",
          box: CGRect(x: 100, y: 100, width: 140, height: 300),
          trackingPoint: CGPoint(x: 170, y: 270),
          labelPoint: CGPoint(x: 170, y: 70)
        ),
        sample(
          id: "body-B",
          box: CGRect(x: 190, y: 105, width: 140, height: 300),
          trackingPoint: CGPoint(x: 260, y: 275),
          labelPoint: CGPoint(x: 260, y: 75)
        ),
      ],
      now: 1
    )
    let separated = clusterer.clusters(
      for: [
        sample(
          id: "body-A",
          box: CGRect(x: 60, y: 100, width: 140, height: 300),
          trackingPoint: CGPoint(x: 130, y: 270),
          labelPoint: CGPoint(x: 130, y: 70)
        ),
        sample(
          id: "body-B",
          box: CGRect(x: 500, y: 105, width: 140, height: 300),
          trackingPoint: CGPoint(x: 570, y: 275),
          labelPoint: CGPoint(x: 570, y: 75)
        ),
      ],
      now: 1.1
    )
    require(initial.count == 1, "separation fixture did not start grouped")
    require(
      separated.filter({ $0.count > 1 }).isEmpty,
      "separated bodies remained in a group fallback"
    )
  }

  private static func testOverlappingScreenPositionsWithDifferentDepthStaySeparate() {
    let clusters = closeClusterer().clusters(
      for: [
        sample(
          id: "body-near",
          box: CGRect(x: 180, y: 100, width: 180, height: 360),
          trackingPoint: CGPoint(x: 270, y: 300),
          labelPoint: CGPoint(x: 270, y: 70),
          worldPosition: SIMD3<Float>(0, 0, 1),
          worldQuality: 0.9
        ),
        sample(
          id: "body-far",
          box: CGRect(x: 185, y: 105, width: 180, height: 360),
          trackingPoint: CGPoint(x: 275, y: 305),
          labelPoint: CGPoint(x: 275, y: 75),
          worldPosition: SIMD3<Float>(0, 0, 3.5),
          worldQuality: 0.9
        ),
      ],
      now: 1
    )
    require(
      clusters.count == 2,
      "reliable depth was ignored for overlapping bodies"
    )
  }

  private static func testCrossingKeepsIdentityPolicyStrict() {
    require(
      !SpatialRenderDecisionPolicy.acceptsSingleton(
        bodyCount: 2,
        eligiblePeerCount: 1,
        evidence: usableEvidence()
      ),
      "crossing bodies entered singleton render mode"
    )
    let policy = SpatialAssociationConfirmationPolicy.forPath(
      .identitySwitch,
      distanceOnly: false
    )
    require(
      !policy.accepts(
        confidence: 0.75,
        ambiguityMargin: 0.1,
        confirmationCount: 2
      ),
      "crossing accepted a weak identity switch"
    )
  }

  private static func closeClusterer() -> SpatialBodyClusterer {
    SpatialBodyClusterer()
  }

  private static func sample(
    id: String,
    box: CGRect,
    trackingPoint: CGPoint,
    labelPoint: CGPoint,
    worldPosition: SIMD3<Float>? = nil,
    worldQuality: Float = 0
  ) -> SpatialBodyClusterSample {
    SpatialBodyClusterSample(
      id: id,
      boundingBox: box,
      bodyScale: max(box.height, 60),
      labelPoint: labelPoint,
      trackingPoint: trackingPoint,
      worldPosition: worldPosition,
      worldQuality: worldQuality
    )
  }

  private static func usableEvidence(
    distanceNormalizedResidual: Double? = 0.4,
    isPhysicallyPlausible: Bool = true
  ) -> SpatialRenderEvidence {
    SpatialRenderEvidence(
      screenGeometry: 0.45,
      carryRegionProximity: 0.3,
      carryWorldProximity: 0.4,
      bodyWorldProximity: 0.4,
      distanceConsistency: 0.7,
      distanceNormalizedResidual: distanceNormalizedResidual,
      hasScreenGeometry: true,
      hasCarryRegionProximity: true,
      hasCarryWorldProximity: true,
      hasBodyWorldProximity: true,
      hasDistanceConsistency: true,
      isPhysicallyPlausible: isPhysicallyPlausible
    )
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fputs("SpatialRenderFallbackHarness: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
