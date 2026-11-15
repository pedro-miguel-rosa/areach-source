import CoreGraphics
import Foundation
import simd

/// The clusterer consumes only body geometry needed for ambiguous rendering.
/// It deliberately has no peer or identity knowledge.
struct SpatialBodyClusterSample {
  let id: String
  let boundingBox: CGRect
  let bodyScale: CGFloat
  let labelPoint: CGPoint
  let trackingPoint: CGPoint
  let worldPosition: SIMD3<Float>?
  let worldQuality: Float
}

struct SpatialBodyCluster {
  let id: String
  let memberIds: [String]
  let anchor: CGPoint

  var count: Int {
    memberIds.count
  }

  func contains(_ bodyId: String) -> Bool {
    memberIds.contains(bodyId)
  }
}

/// Lightweight complete-linkage clustering for the small number of Vision
/// bodies normally visible in the camera. World/depth evidence always gets a
/// chance to reject a visual-only grouping, including when a third body would
/// otherwise connect two distant bodies transitively.
final class SpatialBodyClusterer {
  private struct AnchorState {
    let id: String
    var memberIds: [String]
    var point: CGPoint
    var lastUpdatedAt: CFTimeInterval
  }

  private var nextClusterId = 0
  private var anchorStates: [String: AnchorState] = [:]

  func reset() {
    nextClusterId = 0
    anchorStates.removeAll()
  }

  func clusters(
    for samples: [SpatialBodyClusterSample],
    now: CFTimeInterval
  ) -> [SpatialBodyCluster] {
    guard !samples.isEmpty else {
      pruneAnchorStates(now: now)
      return []
    }

    var components = samples.indices.map { [$0] }
    var index = 0
    while index < components.count {
      var nextIndex = index + 1
      while nextIndex < components.count {
        let shouldMerge = components[index].allSatisfy { firstIndex in
          components[nextIndex].allSatisfy { secondIndex in
            Self.shouldGroup(samples[firstIndex], samples[secondIndex])
          }
        }
        if shouldMerge {
          components[index].append(contentsOf: components[nextIndex])
          components.remove(at: nextIndex)
        } else {
          nextIndex += 1
        }
      }
      index += 1
    }

    var nextAnchorStates: [String: AnchorState] = [:]
    var usedPreviousAnchorIds = Set<String>()
    let clusters = components.map { component -> SpatialBodyCluster in
      let memberIds = component
        .map { samples[$0].id }
        .sorted()
      let rawAnchor = Self.anchor(for: component.map { samples[$0] })
      let prior = bestPreviousAnchor(
        for: memberIds,
        excluding: usedPreviousAnchorIds
      )
      let anchor: CGPoint
      let clusterId: String
      if let prior {
        usedPreviousAnchorIds.insert(prior.id)
        anchor = Self.interpolate(
          from: prior.point,
          to: rawAnchor,
          alpha: SpatialRenderTuning.clusterAnchorSmoothingAlpha
        )
        clusterId = prior.id
      } else {
        anchor = rawAnchor
        clusterId = "cluster-\(nextClusterId)"
        nextClusterId += 1
      }

      nextAnchorStates[clusterId] = AnchorState(
        id: clusterId,
        memberIds: memberIds,
        point: anchor,
        lastUpdatedAt: now
      )
      return SpatialBodyCluster(
        id: clusterId,
        memberIds: memberIds,
        anchor: anchor
      )
    }

    anchorStates = nextAnchorStates
    return clusters.sorted {
      if $0.memberIds == $1.memberIds {
        return $0.id < $1.id
      }
      return $0.memberIds.lexicographicallyPrecedes($1.memberIds)
    }
  }

  private func bestPreviousAnchor(
    for memberIds: [String],
    excluding excludedIds: Set<String>
  ) -> AnchorState? {
    anchorStates.values
      .filter { !excludedIds.contains($0.id) }
      .map { state in
        let overlap = state.memberIds.filter(memberIds.contains).count
        return (state, overlap)
      }
      .filter { $0.1 > 0 }
      .sorted {
        if $0.1 == $1.1 {
          return $0.0.id < $1.0.id
        }
        return $0.1 > $1.1
      }
      .first?
      .0
  }

  private func pruneAnchorStates(now: CFTimeInterval) {
    anchorStates = anchorStates.filter { _, state in
      now - state.lastUpdatedAt
        <= SpatialRenderTuning.maximumRenderContinuityBodyLoss
    }
  }

  private static func shouldGroup(
    _ first: SpatialBodyClusterSample,
    _ second: SpatialBodyClusterSample
  ) -> Bool {
    if let firstWorld = reliableWorldPosition(for: first),
      let secondWorld = reliableWorldPosition(for: second)
    {
      // Reliable depth is authoritative over an overlapping 2D projection.
      guard simd_distance(firstWorld, secondWorld)
        <= SpatialRenderTuning.maximumClusterWorldDistance
      else {
        return false
      }

      return true
    }

    let bodyScale = max(first.bodyScale, max(second.bodyScale, 60))
    let expandedFirst = first.boundingBox.insetBy(
      dx: -bodyScale * SpatialRenderTuning.clusterScreenBoundsExpansion,
      dy: -bodyScale * SpatialRenderTuning.clusterScreenBoundsExpansion
    )
    let expandedSecond = second.boundingBox.insetBy(
      dx: -bodyScale * SpatialRenderTuning.clusterScreenBoundsExpansion,
      dy: -bodyScale * SpatialRenderTuning.clusterScreenBoundsExpansion
    )
    if expandedFirst.intersects(expandedSecond) {
      return true
    }

    let trackingDistance = hypot(
      Double(first.trackingPoint.x - second.trackingPoint.x),
      Double(first.trackingPoint.y - second.trackingPoint.y)
    )
    return trackingDistance
      <= Double(bodyScale * SpatialRenderTuning.maximumClusterScreenDistanceScale)
  }

  private static func reliableWorldPosition(
    for sample: SpatialBodyClusterSample
  ) -> SIMD3<Float>? {
    guard sample.worldQuality >= SpatialRenderTuning.minimumReliableClusterDepthQuality
    else {
      return nil
    }
    return sample.worldPosition
  }

  private static func anchor(
    for samples: [SpatialBodyClusterSample]
  ) -> CGPoint {
    guard !samples.isEmpty else {
      return .zero
    }

    let count = CGFloat(samples.count)
    return CGPoint(
      x: samples.reduce(CGFloat.zero) { $0 + $1.trackingPoint.x } / count,
      y: samples.reduce(CGFloat.zero) { $0 + $1.labelPoint.y } / count
    )
  }

  private static func interpolate(
    from previous: CGPoint,
    to current: CGPoint,
    alpha: CGFloat
  ) -> CGPoint {
    CGPoint(
      x: previous.x + (current.x - previous.x) * alpha,
      y: previous.y + (current.y - previous.y) * alpha
    )
  }
}
