import ARKit
import CoreVideo
import UIKit
import simd

struct SpatialWorldPoint {
  let position: SIMD3<Float>
  let quality: Float
}

struct SpatialCarryWorldPoint {
  let kind: SpatialCarryRegionKind
  let position: SIMD3<Float>
  let quality: Float
}

struct SpatialCarryWorldVolume {
  let kind: SpatialCarryRegionKind
  let center: SIMD3<Float>
  let radii: SIMD3<Float>
  let quality: Float

  func proximity(to position: SIMD3<Float>) -> Double {
    let offset = position - center
    let normalizedDistance = sqrt(
      pow(offset.x / max(radii.x, 0.01), 2)
        + pow(offset.y / max(radii.y, 0.01), 2)
        + pow(offset.z / max(radii.z, 0.01), 2)
    )
    return exp(-Double(normalizedDistance))
      * Double(max(0, min(1, quality)))
  }
}

enum SpatialBodyGeometrySource: String {
  case lidarDepth
  case vision3D
  case fused
}

struct SpatialBodyDepthGeometry {
  let bodyPoint: SpatialWorldPoint?
  let carryPoints: [SpatialCarryWorldPoint]
  let carryVolumes: [SpatialCarryWorldVolume]
  let source: SpatialBodyGeometrySource

  func merged(with supplementary: SpatialBodyDepthGeometry)
    -> SpatialBodyDepthGeometry
  {
    SpatialBodyDepthGeometry(
      bodyPoint: bodyPoint ?? supplementary.bodyPoint,
      carryPoints: carryPoints + supplementary.carryPoints,
      carryVolumes: carryVolumes + supplementary.carryVolumes,
      source: bodyPoint != nil && supplementary.bodyPoint != nil
        ? .fused
        : source
    )
  }
}

struct SpatialBodyDepthEstimate {
  let depth: Float?
  let quality: Float
  let sampleCount: Int
  let spread: Float?
  let geometry: SpatialBodyDepthGeometry?
  let measurement: SpatialDepthMeasurement?
}

private struct SpatialDepthPointSample {
  let normalizedImagePoint: CGPoint
  let depth: Float
  let radialDistance: Float
  let quality: Float
}

/// Samples several body/carry landmarks instead of trusting a single centre
/// pixel.  Depth is supplementary evidence: invalid or low-confidence samples
/// simply reduce the matcher quality rather than inventing a distance.
final class SpatialBodyDepthEstimator {
  func estimate(
    for detection: SpatialBodyDetection,
    depthData: ARDepthData?,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize,
    cameraTransform: simd_float4x4,
    cameraIntrinsics: simd_float3x3,
    imageResolution: CGSize,
    source: SpatialDepthSource = .fallback,
    measuredAt: CFTimeInterval = 0
  ) -> SpatialBodyDepthEstimate {
    guard
      let depthData,
      viewportSize.width > 0,
      viewportSize.height > 0,
      imageResolution.width > 0,
      imageResolution.height > 0,
      cameraIntrinsics.columns.0.x > 0,
      cameraIntrinsics.columns.1.y > 0
    else {
      return SpatialBodyDepthEstimate(
        depth: nil,
        quality: 0,
        sampleCount: 0,
        spread: nil,
        geometry: nil,
        measurement: nil
      )
    }

    var points = [CGPoint]()
    points.reserveCapacity(8)
    points.append(detection.trackingPoint)
    points.append(detection.boundingBox.center)
    let prioritizedCarryRegions = detection.carryRegions.sorted {
      Self.carryPriority($0) < Self.carryPriority($1)
    }
    points.append(
      contentsOf: prioritizedCarryRegions
        .prefix(SpatialDepthTuning.maximumCarryRegions)
        .map(\.center)
    )
    let hipPoints: [CGPoint] = detection.joints.compactMap { joint in
      let name = joint.name.lowercased()
      guard name.contains("hip") || name.contains("root") else {
        return nil
      }

      return joint.point
    }
    points.append(contentsOf: hipPoints)

    let depthMap = depthData.depthMap
    guard
      CVPixelBufferGetPixelFormatType(depthMap)
        == kCVPixelFormatType_DepthFloat32
    else {
      return SpatialBodyDepthEstimate(
        depth: nil,
        quality: 0,
        sampleCount: 0,
        spread: nil,
        geometry: nil,
        measurement: nil
      )
    }

    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    let confidenceMap = depthData.confidenceMap
    if let confidenceMap {
      CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
    }
    defer {
      if let confidenceMap {
        CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
      }
    }

    guard let depthAddress = CVPixelBufferGetBaseAddress(depthMap) else {
      return SpatialBodyDepthEstimate(
        depth: nil,
        quality: 0,
        sampleCount: 0,
        spread: nil,
        geometry: nil,
        measurement: nil
      )
    }
    let depthValues = depthAddress.assumingMemoryBound(to: Float32.self)

    let depthWidth = CVPixelBufferGetWidth(depthMap)
    let depthHeight = CVPixelBufferGetHeight(depthMap)
    guard depthWidth > 0, depthHeight > 0 else {
      return SpatialBodyDepthEstimate(
        depth: nil,
        quality: 0,
        sampleCount: 0,
        spread: nil,
        geometry: nil,
        measurement: nil
      )
    }
    let depthStride = CVPixelBufferGetBytesPerRow(depthMap)
      / MemoryLayout<Float32>.stride
    let confidenceAddress = confidenceMap.flatMap {
      CVPixelBufferGetBaseAddress($0)?.assumingMemoryBound(to: UInt8.self)
    }
    let confidenceWidth = confidenceMap.map(CVPixelBufferGetWidth) ?? 0
    let confidenceHeight = confidenceMap.map(CVPixelBufferGetHeight) ?? 0
    let confidenceStride = confidenceMap.map(CVPixelBufferGetBytesPerRow) ?? 0
    let neighborhoodDiameter = SpatialDepthTuning.neighborhoodRadius * 2 + 1

    func sampleDepth(at point: CGPoint) -> SpatialDepthPointSample? {
      guard
        let depthPoint = Self.depthPoint(
          from: point,
          displayTransform: displayTransform,
          viewportSize: viewportSize
        )
      else {
        return nil
      }

      let centerX = min(
        depthWidth - 1,
        max(0, Int(depthPoint.x * CGFloat(depthWidth)))
      )
      let centerY = min(
        depthHeight - 1,
        max(0, Int(depthPoint.y * CGFloat(depthHeight)))
      )
      let neighborhoodRange =
        (-SpatialDepthTuning.neighborhoodRadius)...SpatialDepthTuning.neighborhoodRadius
      var pointSamples = [Float]()
      pointSamples.reserveCapacity(
        neighborhoodDiameter * neighborhoodDiameter
      )

      for verticalOffset in neighborhoodRange {
        for horizontalOffset in neighborhoodRange {
          let x = min(
            depthWidth - 1,
            max(0, centerX + horizontalOffset)
          )
          let y = min(
            depthHeight - 1,
            max(0, centerY + verticalOffset)
          )

          if let confidenceAddress,
            confidenceWidth > 0,
            confidenceHeight > 0
          {
            let confidenceX = min(
              confidenceWidth - 1,
              x * confidenceWidth / depthWidth
            )
            let confidenceY = min(
              confidenceHeight - 1,
              y * confidenceHeight / depthHeight
            )

            if confidenceAddress[
              confidenceY * confidenceStride + confidenceX
            ] == 0 {
              continue
            }
          }

          let value = depthValues[y * depthStride + x]
          if value.isFinite,
            value >= SpatialDepthTuning.minimumDepth,
            value <= SpatialDepthTuning.maximumDepth
          {
            pointSamples.append(value)
          }
        }
      }

      guard !pointSamples.isEmpty else {
        return nil
      }

      pointSamples.sort()
      let median = pointSamples[pointSamples.count / 2]
      let deviations = pointSamples.map { abs($0 - median) }.sorted()
      let medianAbsoluteDeviation = deviations[deviations.count / 2]
      let inlierLimit = max(
        SpatialDepthTuning.minimumOutlierDistance,
        medianAbsoluteDeviation * SpatialDepthTuning.outlierMADMultiplier
      )
      let inliers = pointSamples.filter {
        abs($0 - median) <= inlierLimit
      }
      guard !inliers.isEmpty else {
        return nil
      }

      let robustDepth = inliers[inliers.count / 2]
      let spread = (inliers.last ?? robustDepth) - (inliers.first ?? robustDepth)
      let spreadQuality: Float = spread <= SpatialDepthTuning.acceptableSpread
        ? 1
        : max(
          SpatialDepthTuning.minimumSpreadQuality,
          SpatialDepthTuning.acceptableSpread / spread
        )
      let neighborhoodCoverage = Float(inliers.count)
        / Float(max(neighborhoodDiameter * neighborhoodDiameter, 1))
      let quality = min(1, neighborhoodCoverage) * spreadQuality
      let imageX = Float(depthPoint.x * imageResolution.width)
      let imageY = Float(depthPoint.y * imageResolution.height)
      let cameraPoint = SIMD3<Float>(
        (imageX - cameraIntrinsics.columns.2.x) * robustDepth
          / cameraIntrinsics.columns.0.x,
        -(imageY - cameraIntrinsics.columns.2.y) * robustDepth
          / cameraIntrinsics.columns.1.y,
        -robustDepth
      )
      let radialDistance = simd_length(cameraPoint)
      guard radialDistance.isFinite, radialDistance > 0 else {
        return nil
      }

      return SpatialDepthPointSample(
        normalizedImagePoint: depthPoint,
        depth: robustDepth,
        radialDistance: radialDistance,
        quality: quality
      )
    }

    var samples = [Float]()
    samples.reserveCapacity(points.count * neighborhoodDiameter * neighborhoodDiameter)
    var pointSamples: [(point: CGPoint, sample: SpatialDepthPointSample)] = []
    pointSamples.reserveCapacity(points.count)

    for point in points {
      if let sample = sampleDepth(at: point) {
        // Nearby Interaction reports a range, so compare it with the
        // camera-space radial distance rather than the depth-map Z component.
        samples.append(sample.radialDistance)
        pointSamples.append((point, sample))
      }
    }

    guard !samples.isEmpty else {
      return SpatialBodyDepthEstimate(
        depth: nil,
        quality: 0,
        sampleCount: 0,
        spread: nil,
        geometry: nil,
        measurement: nil
      )
    }

    samples.sort()
    let median = samples[samples.count / 2]
    let deviations = samples.map { abs($0 - median) }.sorted()
    let medianAbsoluteDeviation = deviations[deviations.count / 2]
    let inliers = samples.filter {
      abs($0 - median) <= max(
        SpatialDepthTuning.minimumOutlierDistance,
        medianAbsoluteDeviation * SpatialDepthTuning.outlierMADMultiplier
      )
    }
    let robustMedian = inliers[inliers.count / 2]
    let minimum = inliers.first ?? robustMedian
    let maximum = inliers.last ?? robustMedian
    let spread = maximum - minimum
    let sampleCoverage = Float(pointSamples.count) / Float(max(points.count, 1))
    let spreadQuality: Float = spread <= SpatialDepthTuning.acceptableSpread
      ? 1
      : max(
        SpatialDepthTuning.minimumSpreadQuality,
        SpatialDepthTuning.acceptableSpread / spread
      )
    let quality = min(1.0, sampleCoverage) * spreadQuality
    let depthUncertainty = min(
      1.5,
      max(
        0.08,
        (max(spread * 0.5, 0.04)
          + 0.18 / sqrt(Float(max(inliers.count, 1))))
          / max(0.3, quality)
      )
    )

    let bodySample = pointSamples.first {
      $0.point == detection.trackingPoint
    }?.sample
    let bodyPoint = bodySample.flatMap { sample -> SIMD3<Float>? in
      guard sample.quality >= SpatialDepthTuning.minimumGeometryQuality else {
        return nil
      }

      return Self.worldPoint(
        from: sample,
        cameraTransform: cameraTransform,
        cameraIntrinsics: cameraIntrinsics,
        imageResolution: imageResolution
      )
    }
    let carryWorldPoints = prioritizedCarryRegions.prefix(
      SpatialDepthTuning.maximumCarryRegions
    ).compactMap { region -> SpatialCarryWorldPoint? in
      guard let sampled = pointSamples.first(where: { $0.point == region.center }),
        let worldPoint = Self.worldPoint(
          from: sampled.sample,
          cameraTransform: cameraTransform,
          cameraIntrinsics: cameraIntrinsics,
          imageResolution: imageResolution
        ),
        sampled.sample.quality >= SpatialDepthTuning.minimumGeometryQuality
      else {
        return nil
      }

      return SpatialCarryWorldPoint(
        kind: region.kind,
        position: worldPoint,
        quality: sampled.sample.quality * Float(region.confidence)
      )
    }
    let geometry: SpatialBodyDepthGeometry?
    if bodyPoint != nil || !carryWorldPoints.isEmpty {
      geometry = SpatialBodyDepthGeometry(
        bodyPoint: bodyPoint.map {
          SpatialWorldPoint(
            position: $0,
            quality: bodySample?.quality ?? quality
          )
        },
        carryPoints: carryWorldPoints,
        carryVolumes: carryWorldPoints.map {
          SpatialCarryWorldVolume(
            kind: $0.kind,
            center: $0.position,
            radii: Self.carryVolumeRadii(for: $0.kind),
            quality: $0.quality
          )
        },
        source: .lidarDepth
      )
    } else {
      geometry = nil
    }

    return SpatialBodyDepthEstimate(
      depth: robustMedian,
      quality: quality,
      sampleCount: inliers.count,
      spread: spread,
      geometry: geometry,
      measurement: SpatialDepthMeasurement(
        distance: robustMedian,
        quality: quality,
        uncertainty: depthUncertainty,
        source: source,
        measuredAt: measuredAt
      )
    )
  }

  private static func worldPoint(
    from sample: SpatialDepthPointSample,
    cameraTransform: simd_float4x4,
    cameraIntrinsics: simd_float3x3,
    imageResolution: CGSize
  ) -> SIMD3<Float>? {
    let focalX = cameraIntrinsics.columns.0.x
    let focalY = cameraIntrinsics.columns.1.y
    let principalX = cameraIntrinsics.columns.2.x
    let principalY = cameraIntrinsics.columns.2.y
    guard
      focalX.isFinite,
      focalY.isFinite,
      focalX > 0,
      focalY > 0,
      sample.depth.isFinite,
      sample.depth > 0
    else {
      return nil
    }

    let imageX = Float(sample.normalizedImagePoint.x * imageResolution.width)
    let imageY = Float(sample.normalizedImagePoint.y * imageResolution.height)
    let cameraPoint = SIMD3<Float>(
      (imageX - principalX) * sample.depth / focalX,
      -(imageY - principalY) * sample.depth / focalY,
      -sample.depth
    )
    let worldPoint = simd_mul(
      cameraTransform,
      SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1)
    )
    guard worldPoint.x.isFinite, worldPoint.y.isFinite, worldPoint.z.isFinite else {
      return nil
    }

    return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
  }

  private static func depthPoint(
    from point: CGPoint,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize
  ) -> CGPoint? {
    let normalizedViewPoint = CGPoint(
      x: point.x / viewportSize.width,
      y: point.y / viewportSize.height
    )
    let normalizedImagePoint = normalizedViewPoint.applying(
      displayTransform.inverted()
    )

    guard
      normalizedImagePoint.x.isFinite,
      normalizedImagePoint.y.isFinite,
      normalizedImagePoint.x >= 0,
      normalizedImagePoint.x <= 1,
      normalizedImagePoint.y >= 0,
      normalizedImagePoint.y <= 1
    else {
      return nil
    }

    return normalizedImagePoint
  }

  private static func carryPriority(
    _ region: SpatialCarryRegion
  ) -> Int {
    switch region.kind {
    case .handHeld:
      return 0
    case .leftFrontPocket, .rightFrontPocket:
      return 1
    case .torsoPocket:
      return 2
    case .hipOrBackPocket:
      return 3
    case .generic:
      return 4
    }
  }

  private static func carryVolumeRadii(
    for kind: SpatialCarryRegionKind
  ) -> SIMD3<Float> {
    switch kind {
    case .handHeld:
      return SpatialDepthTuning.carryVolumeHandRadii
    case .torsoPocket:
      return SpatialDepthTuning.carryVolumeTorsoRadii
    case .leftFrontPocket, .rightFrontPocket, .hipOrBackPocket, .generic:
      return SpatialDepthTuning.carryVolumePocketRadii
    }
  }
}
