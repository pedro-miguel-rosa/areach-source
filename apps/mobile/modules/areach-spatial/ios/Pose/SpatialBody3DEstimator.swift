import CoreVideo
import Foundation
import QuartzCore
import simd
import UIKit
import Vision

/// Sparse Vision 3D body evidence. The request is intentionally kept
/// separate from the existing 2D detector and is only used to supplement
/// uncertain associations or devices without reliable scene depth.
@available(iOS 17.0, *)
final class SpatialBody3DEstimator {
  private var request: VNDetectHumanBodyPose3DRequest?
  private(set) var lastProcessingDuration: CFTimeInterval = 0
  private(set) var lastObservationCount = 0

  init() {
    if SpatialCapabilityProfile.current.vision3DBodyPose {
      request = VNDetectHumanBodyPose3DRequest()
    }
  }

  var isSupported: Bool {
    request != nil
  }

  func reset() {
    lastProcessingDuration = 0
    lastObservationCount = 0
    if SpatialCapabilityProfile.current.vision3DBodyPose {
      request = VNDetectHumanBodyPose3DRequest()
    }
  }

  func estimate(
    in pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize,
    cameraTransform: simd_float4x4,
    detections: [SpatialBodyDetection],
    at time: CFTimeInterval
  ) -> [SpatialBodyDepthGeometry?] {
    guard let request, !detections.isEmpty else {
      return Array(repeating: nil, count: detections.count)
    }

    let startedAt = CACurrentMediaTime()
    defer {
      lastProcessingDuration = CACurrentMediaTime() - startedAt
    }

    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: orientation,
      options: [:]
    )

    do {
      try handler.perform([request])
    } catch {
      lastObservationCount = 0
      return Array(repeating: nil, count: detections.count)
    }

    let observations = request.results ?? []
    lastObservationCount = observations.count
    guard !observations.isEmpty else {
      return Array(repeating: nil, count: detections.count)
    }

    var output = Array<SpatialBodyDepthGeometry?>(
      repeating: nil,
      count: detections.count
    )
    var assignedDetectionIndices = Set<Int>()

    for observation in observations {
      guard
        let rootPoint = viewPoint(
          for: observation,
          displayTransform: displayTransform,
          viewportSize: viewportSize
        ),
        let detectionIndex = nearestDetectionIndex(
          to: rootPoint,
          detections: detections,
          assignedDetectionIndices: assignedDetectionIndices
        ),
        let geometry = geometry(
          for: observation,
          cameraTransform: cameraTransform,
          at: time
        )
      else {
        continue
      }

      assignedDetectionIndices.insert(detectionIndex)
      output[detectionIndex] = geometry
    }

    return output
  }

  @available(iOS 17.0, *)
  private func viewPoint(
    for observation: VNHumanBodyPose3DObservation,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize
  ) -> CGPoint? {
    guard
      let imagePoint = try? observation.pointInImage(.root),
      viewportSize.width > 0,
      viewportSize.height > 0
    else {
      return nil
    }

    let normalizedImagePoint = CGPoint(
      x: imagePoint.x,
      y: 1 - imagePoint.y
    )
    let normalizedViewPoint = normalizedImagePoint.applying(displayTransform)
    let point = CGPoint(
      x: normalizedViewPoint.x * viewportSize.width,
      y: normalizedViewPoint.y * viewportSize.height
    )
    guard point.x.isFinite, point.y.isFinite else {
      return nil
    }

    return point
  }

  private func nearestDetectionIndex(
    to point: CGPoint,
    detections: [SpatialBodyDetection],
    assignedDetectionIndices: Set<Int>
  ) -> Int? {
    detections.indices
      .filter { !assignedDetectionIndices.contains($0) }
      .map { index in
        let detection = detections[index]
        let bodyScale = max(detection.bodyScale, 60)
        return (
          index: index,
          score: distance(point, detection.trackingPoint) / Double(bodyScale)
        )
      }
      .filter { $0.score <= 1.45 }
      .min { $0.score < $1.score }?
      .index
  }

  @available(iOS 17.0, *)
  private func geometry(
    for observation: VNHumanBodyPose3DObservation,
    cameraTransform: simd_float4x4,
    at time: CFTimeInterval
  ) -> SpatialBodyDepthGeometry? {
    let root = worldPoint(
      for: .root,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let leftHip = worldPoint(
      for: .leftHip,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let rightHip = worldPoint(
      for: .rightHip,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let spine = worldPoint(
      for: .spine,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let centerShoulder = worldPoint(
      for: .centerShoulder,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let leftShoulder = worldPoint(
      for: .leftShoulder,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let rightShoulder = worldPoint(
      for: .rightShoulder,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let leftWrist = worldPoint(
      for: .leftWrist,
      observation: observation,
      cameraTransform: cameraTransform
    )
    let rightWrist = worldPoint(
      for: .rightWrist,
      observation: observation,
      cameraTransform: cameraTransform
    )

    let hipCenter = midpoint(leftHip, rightHip) ?? root
    let shoulderCenter = midpoint(leftShoulder, rightShoulder)
      ?? centerShoulder
    let bodyPoint = root ?? hipCenter
    let bodyQuality = [root, leftHip, rightHip, spine, shoulderCenter]
      .compactMap { $0?.quality }
      .min() ?? 0

    guard bodyPoint != nil || ![leftHip, rightHip, spine, shoulderCenter]
      .compactMap({ $0 })
      .isEmpty
    else {
      return nil
    }

    var carryPoints: [SpatialCarryWorldPoint] = []
    var carryVolumes: [SpatialCarryWorldVolume] = []

    func appendCarry(
      _ point: SpatialWorldPoint?,
      kind: SpatialCarryRegionKind,
      radii: SIMD3<Float>
    ) {
      guard let point else {
        return
      }

      carryPoints.append(
        SpatialCarryWorldPoint(
          kind: kind,
          position: point.position,
          quality: point.quality
        )
      )
      carryVolumes.append(
        SpatialCarryWorldVolume(
          kind: kind,
          center: point.position,
          radii: radii,
          quality: point.quality
        )
      )
    }

    appendCarry(
      leftHip,
      kind: .leftFrontPocket,
      radii: SpatialDepthTuning.carryVolumePocketRadii
    )
    appendCarry(
      rightHip,
      kind: .rightFrontPocket,
      radii: SpatialDepthTuning.carryVolumePocketRadii
    )
    appendCarry(
      shoulderCenter.map {
        SpatialWorldPoint(
          position: $0.position,
          quality: min($0.quality, hipCenter?.quality ?? $0.quality)
        )
      },
      kind: .torsoPocket,
      radii: SpatialDepthTuning.carryVolumeTorsoRadii
    )
    appendCarry(
      leftWrist,
      kind: .handHeld,
      radii: SpatialDepthTuning.carryVolumeHandRadii
    )
    appendCarry(
      rightWrist,
      kind: .handHeld,
      radii: SpatialDepthTuning.carryVolumeHandRadii
    )

    let geometryQuality = max(
      SpatialVisionTuning.vision3DMinimumQuality,
      min(1, bodyQuality)
    )
    guard geometryQuality.isFinite else {
      return nil
    }

    _ = time
    return SpatialBodyDepthGeometry(
      bodyPoint: bodyPoint?.mapQuality(geometryQuality),
      carryPoints: carryPoints,
      carryVolumes: carryVolumes,
      source: .vision3D
    )
  }

  @available(iOS 17.0, *)
  private func worldPoint(
    for joint: VNHumanBodyPose3DObservation.JointName,
    observation: VNHumanBodyPose3DObservation,
    cameraTransform: simd_float4x4
  ) -> SpatialWorldPoint? {
    guard
      observation.availableJointNames.contains(joint),
      let cameraRelativePosition = try? observation.cameraRelativePosition(joint)
    else {
      return nil
    }

    let cameraPosition = SIMD3<Float>(
      cameraRelativePosition.columns.3.x,
      cameraRelativePosition.columns.3.y,
      cameraRelativePosition.columns.3.z
    )
    guard
      cameraPosition.x.isFinite,
      cameraPosition.y.isFinite,
      cameraPosition.z.isFinite,
      simd_length(cameraPosition) >= 0.1,
      simd_length(cameraPosition) <= 30
    else {
      return nil
    }

    let worldPosition = simd_mul(
      cameraTransform,
      SIMD4<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z, 1)
    )
    guard
      worldPosition.x.isFinite,
      worldPosition.y.isFinite,
      worldPosition.z.isFinite
    else {
      return nil
    }

    return SpatialWorldPoint(
      position: SIMD3<Float>(
        worldPosition.x,
        worldPosition.y,
        worldPosition.z
      ),
      // Vision's 3D recognized point has no confidence scalar. Keep this
      // evidence below a LiDAR sample and let the matcher require agreement
      // with body/carry geometry before it can affect identity.
      quality: SpatialVisionTuning.vision3DPointQuality
    )
  }

  private func midpoint(
    _ first: SpatialWorldPoint?,
    _ second: SpatialWorldPoint?
  ) -> SpatialWorldPoint? {
    guard let first, let second else {
      return first ?? second
    }

    return SpatialWorldPoint(
      position: (first.position + second.position) / 2,
      quality: min(first.quality, second.quality)
    )
  }
}

private extension SpatialWorldPoint {
  func mapQuality(_ quality: Float) -> SpatialWorldPoint {
    SpatialWorldPoint(
      position: position,
      quality: min(self.quality, quality)
    )
  }
}
