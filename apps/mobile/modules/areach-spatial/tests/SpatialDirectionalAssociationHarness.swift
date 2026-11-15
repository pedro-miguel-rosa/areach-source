import CoreGraphics
import Foundation
import simd

/// Deterministic regression coverage for the distinction between directional
/// identity evidence and scalar distance. It exercises the pure policy only;
/// the physical-device scenario remains part of the validation runbook.
@main
struct SpatialDirectionalAssociationHarness {
  private static let viewport = CGSize(width: 1_000, height: 1_000)
  private static let projection = perspectiveProjection()

  static func main() {
    testEqualDistanceOppositeDirections()
    testEqualDistanceSideDirectionAndCameraRotation()
    testDirectDirectionUsesCurrentProjection()
    testProjectedPeerViewportBoundaries()
    testEqualDistanceWithoutDirectionHasNoIdentityAuthority()
    testTwoVisibleBodiesPreferDirectionalPairing()
    testDirectionLossCanContinueOnlyOnTheSameTrack()
    testDirectionLossCannotReacquireADifferentBodyUsingDistance()
    testStaleDirectionLosesAuthority()
    testProjectionUnavailableCannotClaimNewIdentity()
    print("SpatialDirectionalAssociationHarness: PASS")
  }

  private static func testEqualDistanceOppositeDirections() {
    let frontPosition = SIMD3<Float>(0, 0, -1.5)
    let rearPosition = SIMD3<Float>(0, 0, 1.5)
    let frontProjection = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: frontPosition,
      cameraTransform: matrix_identity_float4x4,
      projectionMatrix: projection,
      viewportSize: viewport
    )
    let rearProjection = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: rearPosition,
      cameraTransform: matrix_identity_float4x4,
      projectionMatrix: projection,
      viewportSize: viewport
    )
    let front = SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: SpatialDirectionalAssociationPolicy.bearing(
        for: frontPosition,
        cameraTransform: matrix_identity_float4x4
      ),
      bodyBearingRadians: 0,
      measurementAge: 0,
      now: 10,
      peerViewportProjection: frontProjection
    )
    let rear = SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: SpatialDirectionalAssociationPolicy.bearing(
        for: rearPosition,
        cameraTransform: matrix_identity_float4x4
      ),
      bodyBearingRadians: 0,
      measurementAge: 0,
      now: 10,
      peerViewportProjection: rearProjection
    )

    require(
      frontProjection.relation == .inside
        && front.reason == .bodyAligned,
      "front peer was not aligned with the visible body"
    )
    require(
      rearProjection.relation == .behind
        && rear.reason == .behindCamera
        && rear.hasHardContradiction
        && rear.blocksNewIdentity,
      "rear equal-distance peer was not hard-gated by projection"
    )
  }

  private static func testEqualDistanceSideDirectionAndCameraRotation() {
    let sidePosition = SIMD3<Float>(-1.5, 0, 0)
    let sideProjection = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: sidePosition,
      cameraTransform: matrix_identity_float4x4,
      projectionMatrix: projection,
      viewportSize: viewport
    )
    let sideEvidence = SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: SpatialDirectionalAssociationPolicy.bearing(
        for: sidePosition,
        cameraTransform: matrix_identity_float4x4
      ),
      bodyBearingRadians: 0,
      measurementAge: 0,
      now: 10,
      peerViewportProjection: sideProjection
    )

    require(
      sideProjection.relation == .outside
        && sideEvidence.reason == .outsideViewport
        && sideEvidence.hasHardContradiction,
      "a far-side peer was not rejected by the projected viewport"
    )

    // Rotate the viewer toward the side peer. In camera space that peer is
    // now directly forward, so it becomes eligible under the new pose.
    var rotatedTowardSide = matrix_identity_float4x4
    rotatedTowardSide.columns.0 = SIMD4<Float>(0, 0, 1, 0)
    rotatedTowardSide.columns.2 = SIMD4<Float>(1, 0, 0, 0)
    let rotatedProjection = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: sidePosition,
      cameraTransform: rotatedTowardSide,
      projectionMatrix: projection,
      viewportSize: viewport
    )
    let rotatedEvidence = SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: SpatialDirectionalAssociationPolicy.bearing(
        for: sidePosition,
        cameraTransform: rotatedTowardSide
      ),
      bodyBearingRadians: 0,
      measurementAge: 0,
      now: 10,
      peerViewportProjection: rotatedProjection
    )
    require(
      rotatedProjection.relation == .inside
        && rotatedEvidence.reason == .bodyAligned
        && !rotatedEvidence.hasHardContradiction
        && SpatialAssociationTuning.allowsNewIdentityEvidence(
          mode: .directional,
          hasFreshProjectableEvidence: false,
          hasFreshDirectionalEvidence: true
        ),
      "a peer did not become eligible after rotating the camera toward it"
    )
  }

  private static func testProjectedPeerViewportBoundaries() {
    let leftNearEdge = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: CGPoint(x: -20, y: 500),
      viewportSize: viewport
    )
    let rightNearEdge = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: CGPoint(x: 1_020, y: 500),
      viewportSize: viewport
    )
    let topNearEdge = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: CGPoint(x: 500, y: -20),
      viewportSize: viewport
    )
    let bottomNearEdge = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: CGPoint(x: 500, y: 1_020),
      viewportSize: viewport
    )
    let farLeft = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: CGPoint(x: -200, y: 500),
      viewportSize: viewport
    )
    let visible = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: CGPoint(x: 500, y: 500),
      viewportSize: viewport
    )

    require(
      [leftNearEdge, rightNearEdge, topNearEdge, bottomNearEdge].allSatisfy {
        $0.relation == .nearEdge
      },
      "a peer just outside an image edge did not enter the edge tolerance"
    )
    require(
      [leftNearEdge, rightNearEdge, topNearEdge, bottomNearEdge].allSatisfy {
        $0.relation.blocksNewIdentity
      },
      "near-edge projection was allowed to create a new identity"
    )
    require(
      farLeft.relation == .outside
        && farLeft.relation.isHardContradiction,
      "a peer far outside the viewport was not rejected"
    )
    require(
      visible.relation == .inside
        && !visible.relation.blocksNewIdentity,
      "an in-frame projected peer was incorrectly gated"
    )
  }

  private static func testDirectDirectionUsesCurrentProjection() {
    let frontMeasurement = SpatialDirectionalMeasurement(
      direction: SIMD3<Float>(0, 0, -1),
      horizontalAngle: nil,
      measuredAt: 10
    )
    let sideMeasurement = SpatialDirectionalMeasurement(
      direction: SIMD3<Float>(1, 0, -0.25),
      horizontalAngle: nil,
      measuredAt: 10
    )
    let front = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: frontMeasurement,
      projectionMatrix: projection,
      viewportSize: viewport
    )
    let side = SpatialDirectionalAssociationPolicy.viewportProjection(
      for: sideMeasurement,
      projectionMatrix: projection,
      viewportSize: viewport
    )

    require(
      front.relation == .inside && side.relation == .outside,
      "direct NI direction was not classified through the camera projection"
    )
  }

  private static func testEqualDistanceWithoutDirectionHasNoIdentityAuthority() {
    let unavailable = SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: nil,
      bodyBearingRadians: 0,
      measurementAge: nil,
      now: 10
    )
    require(
      unavailable.reason == .unavailable,
      "missing direction was not represented explicitly"
    )
    require(
      !SpatialAssociationTuning.allowsNewIdentityEvidence(
        mode: .distanceOnly,
        hasFreshProjectableEvidence: false,
        hasFreshDirectionalEvidence: false
      ),
      "distance-only evidence gained new identity authority"
    )
  }

  private static func testTwoVisibleBodiesPreferDirectionalPairing() {
    let peerA = evaluate(
      peer: -0.244,
      body: -0.262,
      projection: insideProjection
    )
    let peerB = evaluate(
      peer: -0.244,
      body: 0.349,
      projection: insideProjection
    )
    let otherPeerA = evaluate(
      peer: 0.349,
      body: -0.262,
      projection: insideProjection
    )
    let otherPeerB = evaluate(
      peer: 0.349,
      body: 0.349,
      projection: insideProjection
    )

    require(
      peerA.alignmentScore > peerB.alignmentScore
        && otherPeerB.alignmentScore > otherPeerA.alignmentScore,
      "direction did not prefer the correct one-to-one body pairing"
    )
  }

  private static func testDirectionLossCanContinueOnlyOnTheSameTrack() {
    let continuation = SpatialAssociationConfirmationPolicy.forPath(
      .continuation,
      distanceOnly: true
    )
    require(
      continuation.accepts(
        confidence: 0.5,
        ambiguityMargin: 0.1,
        confirmationCount: 1
      ),
      "same-track continuity was blocked during temporary direction loss"
    )
    require(
      !SpatialAssociationTuning.allowsNewIdentityEvidence(
        mode: .distanceOnly,
        hasFreshProjectableEvidence: false,
        hasFreshDirectionalEvidence: false
      ),
      "same-track continuity exception leaked into acquisition authority"
    )
  }

  private static func testDirectionLossCannotReacquireADifferentBodyUsingDistance() {
    let reacquisition = SpatialAssociationConfirmationPolicy.forPath(
      .reacquisition,
      distanceOnly: true
    )
    require(
      reacquisition.accepts(
        confidence: 0.9,
        ambiguityMargin: 0.4,
        confirmationCount: 4
      ),
      "fixture did not reach the strong reacquisition range"
    )
    require(
      !SpatialAssociationTuning.allowsNewIdentityEvidence(
        mode: .distanceOnly,
        hasFreshProjectableEvidence: false,
        hasFreshDirectionalEvidence: false
      ),
      "distance-only reacquisition transferred identity to a new body"
    )
  }

  private static func testStaleDirectionLosesAuthority() {
    let stale = SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: 0,
      bodyBearingRadians: 0,
      measurementAge: SpatialMeasurementTuning.newMatchMaximumDirectionAge + 0.01,
      now: 10,
      peerViewportProjection: insideProjection
    )
    require(stale.reason == .stale, "stale direction remained usable")
    require(
      !stale.hasFreshDirectionalEvidence,
      "stale direction retained identity authority"
    )
  }

  private static func testProjectionUnavailableCannotClaimNewIdentity() {
    let unavailableProjection = SpatialDirectionalViewportProjection(
      relation: .unavailable,
      point: nil
    )
    let evidence = SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: 0,
      bodyBearingRadians: 0,
      measurementAge: 0,
      now: 10,
      peerViewportProjection: unavailableProjection
    )
    require(
      evidence.reason == .projectionUnavailable
        && evidence.blocksNewIdentity,
      "direction without usable camera projection gained identity authority"
    )
  }

  private static var insideProjection: SpatialDirectionalViewportProjection {
    SpatialDirectionalAssociationPolicy.viewportProjection(
      for: CGPoint(x: 500, y: 500),
      viewportSize: viewport
    )
  }

  private static func perspectiveProjection() -> simd_float4x4 {
    // A deterministic perspective matrix with unit horizontal/vertical
    // focal scales. Its x/y clip coordinates are sufficient to verify the
    // viewport gate; z values only need to preserve front-facing depth.
    simd_float4x4(
      SIMD4<Float>(1, 0, 0, 0),
      SIMD4<Float>(0, 1, 0, 0),
      SIMD4<Float>(0, 0, -1.002, -1),
      SIMD4<Float>(0, 0, -0.2, 0)
    )
  }

  private static func evaluate(
    peer: Double,
    body: Double,
    projection: SpatialDirectionalViewportProjection
  ) -> SpatialDirectionalAssociationResult {
    SpatialDirectionalAssociationPolicy.evaluate(
      peerBearingRadians: peer,
      bodyBearingRadians: body,
      measurementAge: 0,
      now: 10,
      peerViewportProjection: projection
    )
  }

  private static func require(_ condition: Bool, _ message: String) {
    guard condition else {
      fputs("SpatialDirectionalAssociationHarness: FAIL: \(message)\n", stderr)
      exit(1)
    }
  }
}
