import ImageIO
import QuartzCore
import simd
import UIKit
import Vision

enum SpatialCarryRegionKind: String {
  case leftFrontPocket
  case rightFrontPocket
  case hipOrBackPocket
  case torsoPocket
  case handHeld
  case generic
}

struct SpatialCarryRegion {
  let center: CGPoint
  let confidence: CGFloat
  let kind: SpatialCarryRegionKind
  let radius: CGFloat

  init(
    center: CGPoint,
    confidence: CGFloat,
    radius: CGFloat,
    kind: SpatialCarryRegionKind = .generic
  ) {
    self.center = center
    self.confidence = confidence
    self.kind = kind
    self.radius = radius
  }
}

struct SpatialBodyJoint {
  let confidence: Float
  let name: String
  let point: CGPoint
}

struct SpatialBodyDetection {
  let bodyDepth: Float?
  let bodyDepthQuality: Float
  let bodyDepthSampleCount: Int
  let bodyDepthSpread: Float?
  let bodyDepthUncertainty: Float?
  let bodyDepthSource: SpatialDepthSource?
  let bodyDepthMeasuredAt: CFTimeInterval?
  let bodyScale: CGFloat
  let boundingBox: CGRect
  let carryRegions: [SpatialCarryRegion]
  let confidence: Float
  let hasMotionEstimate: Bool
  let id: String
  let joints: [SpatialBodyJoint]
  let labelPoint: CGPoint
  let isFreshPose: Bool
  let poseAge: CFTimeInterval
  let poseTimestamp: CFTimeInterval
  let trackingPoint: CGPoint
  let trackingVelocity: CGVector
  let worldGeometry: SpatialBodyDepthGeometry?

  var bodyDepthMeasurement: SpatialDepthMeasurement? {
    guard
      let bodyDepth,
      let bodyDepthUncertainty,
      let bodyDepthSource,
      let bodyDepthMeasuredAt
    else {
      return nil
    }

    return SpatialDepthMeasurement(
      distance: bodyDepth,
      quality: bodyDepthQuality,
      uncertainty: bodyDepthUncertainty,
      source: bodyDepthSource,
      measuredAt: bodyDepthMeasuredAt
    )
  }

  func withDepth(_ bodyDepth: Float?) -> SpatialBodyDetection {
    withDepth(
      bodyDepth,
      quality: bodyDepthQuality,
      sampleCount: bodyDepthSampleCount,
      spread: bodyDepthSpread,
      geometry: worldGeometry,
      measurement: bodyDepthMeasurement
    )
  }

  func withDepth(
    _ bodyDepth: Float?,
    quality: Float,
    sampleCount: Int,
    spread: Float?,
    geometry: SpatialBodyDepthGeometry? = nil,
    measurement: SpatialDepthMeasurement? = nil
  ) -> SpatialBodyDetection {
    SpatialBodyDetection(
      bodyDepth: bodyDepth,
      bodyDepthQuality: quality,
      bodyDepthSampleCount: sampleCount,
      bodyDepthSpread: spread,
      bodyDepthUncertainty: measurement?.uncertainty,
      bodyDepthSource: measurement?.source,
      bodyDepthMeasuredAt: measurement?.measuredAt,
      bodyScale: bodyScale,
      boundingBox: boundingBox,
      carryRegions: carryRegions,
      confidence: confidence,
      hasMotionEstimate: hasMotionEstimate,
      id: id,
      joints: joints,
      labelPoint: labelPoint,
      isFreshPose: isFreshPose,
      poseAge: poseAge,
      poseTimestamp: poseTimestamp,
      trackingPoint: trackingPoint,
      trackingVelocity: trackingVelocity,
      worldGeometry: geometry
    )
  }

  func withSupplementaryWorldGeometry(
    _ supplementary: SpatialBodyDepthGeometry?,
    cameraTransform: simd_float4x4? = nil,
    measuredAt: CFTimeInterval? = nil
  ) -> SpatialBodyDetection {
    guard let supplementary else {
      return self
    }

    return withDepth(
      bodyDepth,
      quality: bodyDepthQuality,
      sampleCount: bodyDepthSampleCount,
      spread: bodyDepthSpread,
      geometry: worldGeometry?.merged(with: supplementary) ?? supplementary,
      measurement: bodyDepthMeasurement ?? supplementary.bodyPoint.flatMap {
        guard let cameraTransform else {
          return nil
        }

        let cameraPosition = SIMD3<Float>(
          cameraTransform.columns.3.x,
          cameraTransform.columns.3.y,
          cameraTransform.columns.3.z
        )
        let distance = simd_distance($0.position, cameraPosition)
        guard distance.isFinite, distance > 0 else {
          return nil
        }

        return SpatialDepthMeasurement(
          distance: distance,
          quality: min(1, max(0, $0.quality * 0.96)),
          uncertainty: max(0.35, distance * 0.15),
          source: .vision3D,
          measuredAt: measuredAt ?? CACurrentMediaTime()
        )
      }
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
    translated(
      by: CGVector(
        dx: point.x - trackingPoint.x,
        dy: point.y - trackingPoint.y
      ),
      id: id,
      confidence: confidence,
      velocity: velocity,
      hasMotionEstimate: hasMotionEstimate,
      at: time,
      isFreshPose: isFreshPose
    )
  }

  func transformed(
    from sourceBounds: CGRect,
    to destinationBounds: CGRect,
    confidence: Float
  ) -> SpatialBodyDetection {
    guard
      sourceBounds.width > 0,
      sourceBounds.height > 0,
      destinationBounds.width > 0,
      destinationBounds.height > 0
    else {
      return self
    }

    let horizontalScale = destinationBounds.width / sourceBounds.width
    let verticalScale = destinationBounds.height / sourceBounds.height
    let scale = max(
      0.5,
      min(2, (horizontalScale + verticalScale) / 2)
    )

    func transform(_ point: CGPoint) -> CGPoint {
      CGPoint(
        x: destinationBounds.minX
          + (point.x - sourceBounds.minX) * horizontalScale,
        y: destinationBounds.minY
          + (point.y - sourceBounds.minY) * verticalScale
      )
    }

    return SpatialBodyDetection(
      bodyDepth: bodyDepth,
      bodyDepthQuality: bodyDepthQuality,
      bodyDepthSampleCount: bodyDepthSampleCount,
      bodyDepthSpread: bodyDepthSpread,
      bodyDepthUncertainty: bodyDepthUncertainty,
      bodyDepthSource: bodyDepthSource,
      bodyDepthMeasuredAt: bodyDepthMeasuredAt,
      bodyScale: bodyScale * scale,
      boundingBox: destinationBounds,
      carryRegions: carryRegions.map {
        SpatialCarryRegion(
          center: transform($0.center),
          confidence: $0.confidence,
          radius: $0.radius * scale,
          kind: $0.kind
        )
      },
      confidence: min(self.confidence, confidence),
      hasMotionEstimate: hasMotionEstimate,
      id: id,
      joints: joints.map {
        SpatialBodyJoint(
          confidence: $0.confidence,
          name: $0.name,
          point: transform($0.point)
        )
      },
      labelPoint: transform(labelPoint),
      isFreshPose: isFreshPose,
      poseAge: poseAge,
      poseTimestamp: poseTimestamp,
      trackingPoint: transform(trackingPoint),
      trackingVelocity: trackingVelocity,
      worldGeometry: worldGeometry
    )
  }

  private func translated(
    by offset: CGVector,
    id: String,
    confidence: Float,
    velocity: CGVector,
    hasMotionEstimate: Bool,
    at time: CFTimeInterval,
    isFreshPose: Bool
  ) -> SpatialBodyDetection {
    func translate(_ point: CGPoint) -> CGPoint {
      CGPoint(x: point.x + offset.dx, y: point.y + offset.dy)
    }

    return SpatialBodyDetection(
      bodyDepth: bodyDepth,
      bodyDepthQuality: bodyDepthQuality,
      bodyDepthSampleCount: bodyDepthSampleCount,
      bodyDepthSpread: bodyDepthSpread,
      bodyDepthUncertainty: bodyDepthUncertainty,
      bodyDepthSource: bodyDepthSource,
      bodyDepthMeasuredAt: bodyDepthMeasuredAt,
      bodyScale: bodyScale,
      boundingBox: boundingBox.offsetBy(dx: offset.dx, dy: offset.dy),
      carryRegions: carryRegions.map {
        SpatialCarryRegion(
          center: translate($0.center),
          confidence: $0.confidence,
          radius: $0.radius,
          kind: $0.kind
        )
      },
      confidence: confidence,
      hasMotionEstimate: hasMotionEstimate,
      id: id,
      joints: joints.map {
        SpatialBodyJoint(
          confidence: $0.confidence,
          name: $0.name,
          point: translate($0.point)
        )
      },
      labelPoint: translate(labelPoint),
      isFreshPose: isFreshPose,
      poseAge: max(0, time - poseTimestamp),
      poseTimestamp: poseTimestamp,
      trackingPoint: translate(trackingPoint),
      trackingVelocity: velocity,
      worldGeometry: worldGeometry
    )
  }
}

extension SpatialBodyDetection {
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
}

private struct SpatialRecognizedJoint {
  let confidence: Float
  let name: VNHumanBodyPoseObservation.JointName
  let point: CGPoint
}

private struct SpatialTrackedPerson {
  var detection: SpatialBodyDetection
  var observation: VNDetectedObjectObservation
}

final class BodyPoseDetector {
  private static let minimumTrackingConfidence = SpatialVisionTuning.minimumTrackingConfidence

  private let poseRequest = VNDetectHumanBodyPoseRequest()
  private let duplicatePolicy = SpatialBodyDuplicatePolicy()
  private var lastFullDetectionAt: CFTimeInterval = 0
  private var sequenceHandler = VNSequenceRequestHandler()
  private var trackedPeople: [SpatialTrackedPerson] = []
  private var shouldRefreshPose = false
  private(set) var lastWasFullPose = false
  private(set) var lastTrackingConfidence: Float = 1
  private(set) var hasOverlapPressure = false
  private(set) var lastDetectionCount = 0
  private(set) var lastRawVisionObservationCount = 0
  private(set) var lastDeduplicatedVisionDetectionCount = 0
  private(set) var lastVisionDuplicateSuppressionCount = 0
  private(set) var lastTrackDuplicateSuppressionCount = 0

  var diagnostics: SpatialBodyPipelineDiagnostics {
    SpatialBodyPipelineDiagnostics(
      rawVisionObservationCount: lastRawVisionObservationCount,
      uniqueVisionDetectionCount: lastDeduplicatedVisionDetectionCount,
      detectorTrackedBodyCount: lastDetectionCount,
      visionDuplicateSuppressionCount: lastVisionDuplicateSuppressionCount,
      detectorTrackDuplicateSuppressionCount: lastTrackDuplicateSuppressionCount,
      matcherTrackedBodyCount: 0,
      matcherDuplicateTrackSuppressionCount: 0,
      matcherDuplicateTrackRetirementCount: 0
    )
  }

  func detectPeople(
    in pixelBuffer: CVPixelBuffer,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize,
    orientation: CGImagePropertyOrientation,
    fullDetectionInterval: CFTimeInterval,
    cameraMotion: Float,
    at time: CFTimeInterval
  ) -> [SpatialBodyDetection] {
    if trackedPeople.isEmpty
      || time - lastFullDetectionAt >= fullDetectionInterval
      || cameraMotion >= SpatialVisionTuning.cameraMotionThreshold
      || hasOverlapPressure
      || shouldRefreshPose
    {
      return detectAndSeedPeople(
        in: pixelBuffer,
        displayTransform: displayTransform,
        viewportSize: viewportSize,
        orientation: orientation,
        at: time
      )
    }

    let trackedDetections = trackPeople(
      in: pixelBuffer,
      displayTransform: displayTransform,
      viewportSize: viewportSize,
      orientation: orientation,
      at: time
    )

    if trackedDetections.isEmpty {
      return detectAndSeedPeople(
        in: pixelBuffer,
        displayTransform: displayTransform,
        viewportSize: viewportSize,
        orientation: orientation,
        at: time
      )
    }

    return trackedDetections
  }

  func reset() {
    lastFullDetectionAt = 0
    sequenceHandler = VNSequenceRequestHandler()
    trackedPeople.removeAll()
    shouldRefreshPose = false
    lastWasFullPose = false
    lastTrackingConfidence = 1
    hasOverlapPressure = false
    lastDetectionCount = 0
    lastRawVisionObservationCount = 0
    lastDeduplicatedVisionDetectionCount = 0
    lastVisionDuplicateSuppressionCount = 0
    lastTrackDuplicateSuppressionCount = 0
  }

  private func detectAndSeedPeople(
    in pixelBuffer: CVPixelBuffer,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize,
    orientation: CGImagePropertyOrientation,
    at time: CFTimeInterval
  ) -> [SpatialBodyDetection] {
    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: orientation,
      options: [:]
    )

    do {
      try handler.perform([poseRequest])
    } catch {
      trackedPeople.removeAll()
      lastRawVisionObservationCount = 0
      lastDeduplicatedVisionDetectionCount = 0
      lastVisionDuplicateSuppressionCount = 0
      lastTrackDuplicateSuppressionCount = 0
      lastDetectionCount = 0
      hasOverlapPressure = false
      return []
    }

    let observations = poseRequest.results ?? []
    let detections = observations.enumerated().compactMap {
      index,
      observation -> (SpatialBodyDetection, VNDetectedObjectObservation)? in
      guard
        let payload = Self.detectionPayload(
          from: observation,
          index: index,
          displayTransform: displayTransform,
          viewportSize: viewportSize,
          at: time
        )
      else {
        return nil
      }

      return (
        payload.detection,
        VNDetectedObjectObservation(boundingBox: payload.normalizedBounds)
      )
    }

    let deduplication = duplicatePolicy.suppressDuplicates(
      in: detections.map { $0.0.duplicateBodyCandidate }
    )
    let uniqueDetections = deduplication.retainedIndices.map { detections[$0] }

    sequenceHandler = VNSequenceRequestHandler()
    trackedPeople = uniqueDetections.map {
      SpatialTrackedPerson(detection: $0.0, observation: $0.1)
    }
    shouldRefreshPose = false
    lastFullDetectionAt = time
    lastWasFullPose = true
    lastTrackingConfidence = uniqueDetections.map { $0.0.confidence }.min() ?? 0
    lastRawVisionObservationCount = observations.count
    lastDeduplicatedVisionDetectionCount = uniqueDetections.count
    lastVisionDuplicateSuppressionCount = deduplication.suppressedIndices.count
    lastTrackDuplicateSuppressionCount = 0
    lastDetectionCount = uniqueDetections.count
    hasOverlapPressure = Self.hasOverlapPressure(
      uniqueDetections.map(\.0.boundingBox)
    )
    return uniqueDetections.map(\.0)
  }

  private func trackPeople(
    in pixelBuffer: CVPixelBuffer,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize,
    orientation: CGImagePropertyOrientation,
    at time: CFTimeInterval
  ) -> [SpatialBodyDetection] {
    let requests = trackedPeople.map { person in
      let request = VNTrackObjectRequest(
        detectedObjectObservation: person.observation
      )
      request.trackingLevel = .fast
      return request
    }

    do {
      try sequenceHandler.perform(
        requests,
        on: pixelBuffer,
        orientation: orientation
      )
    } catch {
      trackedPeople.removeAll()
      return []
    }

    var nextTrackedPeople: [SpatialTrackedPerson] = []
    var detections: [SpatialBodyDetection] = []
    var minimumConfidence: Float = 1
    var shouldRefreshPose = false

    for (person, request) in zip(trackedPeople, requests) {
      guard
        let observation = request.results?.first
          as? VNDetectedObjectObservation,
        observation.confidence >= Self.minimumTrackingConfidence
      else {
        continue
      }

      minimumConfidence = min(minimumConfidence, observation.confidence)

      let destinationBounds = Self.viewBounds(
        from: observation.boundingBox,
        displayTransform: displayTransform,
        viewportSize: viewportSize
      )
      guard destinationBounds.intersects(
        CGRect(origin: .zero, size: viewportSize)
      ) else {
        continue
      }

      let previousBounds = person.detection.boundingBox
      let previousExtent = max(
        previousBounds.width,
        previousBounds.height,
        60
      )
      let destinationExtent = max(
        destinationBounds.width,
        destinationBounds.height,
        60
      )
      let centerMotion = distance(
        previousBounds.center,
        destinationBounds.center
      ) / Double(previousExtent)
      let extentRatio = max(
        destinationExtent / previousExtent,
        previousExtent / destinationExtent
      )
      let previousAspect = previousBounds.width
        / max(previousBounds.height, 1)
      let destinationAspect = destinationBounds.width
        / max(destinationBounds.height, 1)
      let aspectChange = abs(
        log(max(destinationAspect, 0.01) / max(previousAspect, 0.01))
      )

      if centerMotion >= SpatialVisionTuning.trackingRefreshCenterMotion
        || extentRatio >= SpatialVisionTuning.trackingRefreshExtentRatio
        || aspectChange >= SpatialVisionTuning.trackingRefreshAspectChange
        || observation.confidence < SpatialVisionTuning.trackingRefreshConfidence
      {
        shouldRefreshPose = true
      }

      let transformedDetection = person.detection.transformed(
        from: person.detection.boundingBox,
        to: destinationBounds,
        confidence: observation.confidence
      )
      let detection = transformedDetection.withTracking(
        id: person.detection.id,
        point: transformedDetection.trackingPoint,
        velocity: .zero,
        hasMotionEstimate: false,
        at: time,
        isFreshPose: false
      )
      nextTrackedPeople.append(
        SpatialTrackedPerson(
          detection: detection,
          observation: observation
        )
      )
      detections.append(detection)
    }

    let deduplication = duplicatePolicy.suppressDuplicates(
      in: detections.map(\.duplicateBodyCandidate)
    )
    let uniquePeople = deduplication.retainedIndices.map { nextTrackedPeople[$0] }
    let uniqueDetections = deduplication.retainedIndices.map { detections[$0] }
    if !deduplication.suppressedIndices.isEmpty {
      shouldRefreshPose = true
    }

    trackedPeople = uniquePeople
    self.shouldRefreshPose = shouldRefreshPose
    lastWasFullPose = false
    lastTrackingConfidence = uniqueDetections.isEmpty ? 0 : minimumConfidence
    lastTrackDuplicateSuppressionCount = deduplication.suppressedIndices.count
    lastDetectionCount = uniqueDetections.count
    hasOverlapPressure = Self.hasOverlapPressure(
      uniqueDetections.map(\.boundingBox)
    )
    return uniqueDetections
  }

  private static func detectionPayload(
    from observation: VNHumanBodyPoseObservation,
    index: Int,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize,
    at time: CFTimeInterval
  ) -> (detection: SpatialBodyDetection, normalizedBounds: CGRect)? {
    guard
      let recognizedPoints = try? observation.recognizedPoints(
        VNHumanBodyPoseObservation.JointsGroupName.all
      )
    else {
      return nil
    }

    let recognizedJoints = recognizedPoints.compactMap {
      jointName,
      point -> (VNHumanBodyPoseObservation.JointName, VNRecognizedPoint)? in
      guard point.confidence >= 0.01 else {
        return nil
      }

      return (jointName, point)
    }
    let confidentRecognizedJoints = recognizedJoints.filter {
      $0.1.confidence >= 0.2
    }

    guard confidentRecognizedJoints.count >= 3 else {
      return nil
    }

    let normalizedBounds = paddedNormalizedBounds(
      for: confidentRecognizedJoints.map { $0.1.location }
    )
    let screenJoints = recognizedJoints.map {
      SpatialRecognizedJoint(
        confidence: $0.1.confidence,
        name: $0.0,
        point: viewPoint(
          from: $0.1.location,
          displayTransform: displayTransform,
          viewportSize: viewportSize
        )
      )
    }
    let jointsByName = Dictionary(
      uniqueKeysWithValues: screenJoints.map { ($0.name, $0) }
    )
    let bodyBounds = viewBounds(
      from: normalizedBounds,
      displayTransform: displayTransform,
      viewportSize: viewportSize
    )
    let bodyScale = bodyScale(
      points: jointsByName,
      bounds: bodyBounds
    )
    let trackingPoint = trackingPoint(
      from: jointsByName,
      fallbackBounds: bodyBounds
    )
    let confidence =
      confidentRecognizedJoints.reduce(Float.zero) {
        $0 + $1.1.confidence
      } / Float(confidentRecognizedJoints.count)

    return (
      SpatialBodyDetection(
        bodyDepth: nil,
        bodyDepthQuality: 0,
        bodyDepthSampleCount: 0,
        bodyDepthSpread: nil,
        bodyDepthUncertainty: nil,
        bodyDepthSource: nil,
        bodyDepthMeasuredAt: nil,
        bodyScale: bodyScale,
        boundingBox: bodyBounds,
        carryRegions: carryRegions(
          from: jointsByName,
          trackingPoint: trackingPoint,
          bodyScale: bodyScale
        ),
        confidence: confidence,
        hasMotionEstimate: false,
        id: "\(index)",
        joints: screenJoints.map {
          SpatialBodyJoint(
            confidence: $0.confidence,
            name: "\($0.name)",
            point: $0.point
          )
        },
        labelPoint: labelTargetPoint(
          from: jointsByName,
          fallbackBounds: bodyBounds
        ),
        isFreshPose: true,
        poseAge: 0,
        poseTimestamp: time,
        trackingPoint: trackingPoint,
        trackingVelocity: .zero,
        worldGeometry: nil
      ),
      normalizedBounds
    )
  }

  private static func carryRegions(
    from points: [VNHumanBodyPoseObservation.JointName: SpatialRecognizedJoint],
    trackingPoint: CGPoint,
    bodyScale: CGFloat
  ) -> [SpatialCarryRegion] {
    var regions: [SpatialCarryRegion] = []
    let leftHip = confidentJoint(points[.leftHip])
    let rightHip = confidentJoint(points[.rightHip])
    let leftShoulder = confidentJoint(points[.leftShoulder])
    let rightShoulder = confidentJoint(points[.rightShoulder])

    if let leftHip {
      regions.append(
        SpatialCarryRegion(
          center: leftHip.point,
          confidence: 1,
          radius: bodyScale * 0.24,
          kind: .leftFrontPocket
        )
      )

      let direction: CGFloat = leftHip.point.x < trackingPoint.x ? -1 : 1
      regions.append(
        SpatialCarryRegion(
          center: CGPoint(
            x: leftHip.point.x + direction * bodyScale * 0.18,
            y: leftHip.point.y + bodyScale * 0.08
          ),
          confidence: 0.55,
          radius: bodyScale * 0.42,
          kind: .hipOrBackPocket
        )
      )
    }

    if let rightHip {
      regions.append(
        SpatialCarryRegion(
          center: rightHip.point,
          confidence: 1,
          radius: bodyScale * 0.24,
          kind: .rightFrontPocket
        )
      )

      let direction: CGFloat = rightHip.point.x < trackingPoint.x ? -1 : 1
      regions.append(
        SpatialCarryRegion(
          center: CGPoint(
            x: rightHip.point.x + direction * bodyScale * 0.18,
            y: rightHip.point.y + bodyScale * 0.08
          ),
          confidence: 0.55,
          radius: bodyScale * 0.42,
          kind: .hipOrBackPocket
        )
      )
    }

    if let shoulderCenter = midpoint(leftShoulder, rightShoulder),
      let hipCenter = midpoint(leftHip, rightHip)
    {
      regions.append(
        SpatialCarryRegion(
          center: CGPoint(
            x: (shoulderCenter.x + hipCenter.x) / 2,
            y: (shoulderCenter.y + hipCenter.y) / 2
          ),
          confidence: 0.85,
          radius: bodyScale * 0.24,
          kind: .torsoPocket
        )
      )
    }

    for (wristName, elbowName) in [
      (
        VNHumanBodyPoseObservation.JointName.leftWrist,
        VNHumanBodyPoseObservation.JointName.leftElbow
      ),
      (.rightWrist, .rightElbow),
    ] {
      if let wrist = carryJoint(points[wristName]) {
        regions.append(
          SpatialCarryRegion(
            center: wrist.point,
            confidence: min(0.78, max(0.3, CGFloat(wrist.confidence))),
            radius: bodyScale * 0.28,
            kind: .handHeld
          )
        )

        if let elbow = carryJoint(points[elbowName]) {
          regions.append(
            SpatialCarryRegion(
              center: CGPoint(
                x: (wrist.point.x + elbow.point.x) / 2,
                y: (wrist.point.y + elbow.point.y) / 2
              ),
              confidence: min(
                0.55,
                max(0.24, CGFloat(min(wrist.confidence, elbow.confidence)))
              ),
              radius: bodyScale * 0.34,
              kind: .handHeld
            )
          )
        }
      }
    }

    let bodyCenter = midpoint(leftShoulder, rightShoulder).flatMap {
      shoulderCenter in
      midpoint(leftHip, rightHip).map { hipCenter in
        CGPoint(
          x: (shoulderCenter.x + hipCenter.x) / 2,
          y: (shoulderCenter.y + hipCenter.y) / 2
        )
      }
    } ?? trackingPoint

    regions.append(
      SpatialCarryRegion(
        center: bodyCenter,
        confidence: 0.28,
        radius: bodyScale * 0.5,
        kind: .generic
      )
    )

    regions.append(
      SpatialCarryRegion(
        center: trackingPoint,
        confidence: 0.34,
        radius: bodyScale * 0.44,
        kind: .generic
      )
    )
    return regions
  }

  private static func bodyScale(
    points: [VNHumanBodyPoseObservation.JointName: SpatialRecognizedJoint],
    bounds: CGRect
  ) -> CGFloat {
    let shoulderWidth = pairDistance(
      confidentJoint(points[.leftShoulder]),
      confidentJoint(points[.rightShoulder])
    )
    let hipWidth = pairDistance(
      confidentJoint(points[.leftHip]),
      confidentJoint(points[.rightHip])
    )

    return max(
      60,
      bounds.height,
      bounds.width * 1.35,
      shoulderWidth.map { $0 * 3 } ?? 0,
      hipWidth.map { $0 * 3.5 } ?? 0
    )
  }

  private static func trackingPoint(
    from points: [VNHumanBodyPoseObservation.JointName: SpatialRecognizedJoint],
    fallbackBounds: CGRect
  ) -> CGPoint {
    if let root = confidentJoint(points[.root]) {
      return root.point
    }

    if let hips = midpoint(
      confidentJoint(points[.leftHip]),
      confidentJoint(points[.rightHip])
    ) {
      return hips
    }

    if let shoulders = midpoint(
      confidentJoint(points[.leftShoulder]),
      confidentJoint(points[.rightShoulder])
    ) {
      return CGPoint(
        x: shoulders.x,
        y: shoulders.y + fallbackBounds.height * 0.22
      )
    }

    return fallbackBounds.center
  }

  private static func labelTargetPoint(
    from points: [VNHumanBodyPoseObservation.JointName: SpatialRecognizedJoint],
    fallbackBounds: CGRect
  ) -> CGPoint {
    var candidates: [(point: CGPoint, weight: CGFloat)] = []

    if let nose = confidentJoint(points[.nose]) {
      candidates.append(
        (
          point: CGPoint(x: nose.point.x, y: nose.point.y - 28),
          weight: CGFloat(nose.confidence) * 3
        )
      )
    }

    if let neck = confidentJoint(points[.neck]) {
      candidates.append(
        (
          point: CGPoint(x: neck.point.x, y: neck.point.y - 42),
          weight: CGFloat(neck.confidence) * 2
        )
      )
    }

    if let shoulderCenter = midpoint(
      confidentJoint(points[.leftShoulder]),
      confidentJoint(points[.rightShoulder])
    ) {
      candidates.append(
        (
          point: CGPoint(
            x: shoulderCenter.x,
            y: shoulderCenter.y - 48
          ),
          weight: 1
        )
      )
    }

    let totalWeight = candidates.reduce(CGFloat.zero) {
      $0 + $1.weight
    }

    guard totalWeight > 0 else {
      return CGPoint(
        x: fallbackBounds.midX,
        y: fallbackBounds.minY - 32
      )
    }

    return CGPoint(
      x: candidates.reduce(CGFloat.zero) {
        $0 + $1.point.x * $1.weight
      } / totalWeight,
      y: candidates.reduce(CGFloat.zero) {
        $0 + $1.point.y * $1.weight
      } / totalWeight
    )
  }

  private static func paddedNormalizedBounds(
    for points: [CGPoint]
  ) -> CGRect {
    let bounds = boundingBox(for: points)
    let horizontalPadding = max(0.025, bounds.width * 0.18)
    let verticalPadding = max(0.035, bounds.height * 0.16)

    return
      bounds
      .insetBy(dx: -horizontalPadding, dy: -verticalPadding)
      .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
  }

  private static func viewBounds(
    from normalizedBounds: CGRect,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize
  ) -> CGRect {
    let points = [
      CGPoint(x: normalizedBounds.minX, y: normalizedBounds.minY),
      CGPoint(x: normalizedBounds.maxX, y: normalizedBounds.minY),
      CGPoint(x: normalizedBounds.minX, y: normalizedBounds.maxY),
      CGPoint(x: normalizedBounds.maxX, y: normalizedBounds.maxY),
    ].map {
      viewPoint(
        from: $0,
        displayTransform: displayTransform,
        viewportSize: viewportSize
      )
    }

    return boundingBox(for: points)
  }

  private static func boundingBox(for points: [CGPoint]) -> CGRect {
    guard let firstPoint = points.first else {
      return .zero
    }

    var minX = firstPoint.x
    var minY = firstPoint.y
    var maxX = firstPoint.x
    var maxY = firstPoint.y

    for point in points.dropFirst() {
      minX = min(minX, point.x)
      minY = min(minY, point.y)
      maxX = max(maxX, point.x)
      maxY = max(maxY, point.y)
    }

    return CGRect(
      x: minX,
      y: minY,
      width: maxX - minX,
      height: maxY - minY
    )
  }

  private static func midpoint(
    _ first: SpatialRecognizedJoint?,
    _ second: SpatialRecognizedJoint?
  ) -> CGPoint? {
    guard let first, let second else {
      return nil
    }

    return CGPoint(
      x: (first.point.x + second.point.x) / 2,
      y: (first.point.y + second.point.y) / 2
    )
  }

  private static func pairDistance(
    _ first: SpatialRecognizedJoint?,
    _ second: SpatialRecognizedJoint?
  ) -> CGFloat? {
    guard let first, let second else {
      return nil
    }

    return hypot(
      first.point.x - second.point.x,
      first.point.y - second.point.y
    )
  }

  private static func confidentJoint(
    _ joint: SpatialRecognizedJoint?
  ) -> SpatialRecognizedJoint? {
    guard let joint, joint.confidence >= 0.2 else {
      return nil
    }

    return joint
  }

  private static func carryJoint(
    _ joint: SpatialRecognizedJoint?
  ) -> SpatialRecognizedJoint? {
    guard let joint, joint.confidence >= 0.08 else {
      return nil
    }

    return joint
  }

  private static func viewPoint(
    from visionPoint: CGPoint,
    displayTransform: CGAffineTransform,
    viewportSize: CGSize
  ) -> CGPoint {
    let normalizedImagePoint = CGPoint(
      x: visionPoint.x,
      y: 1 - visionPoint.y
    )
    let normalizedViewPoint = normalizedImagePoint.applying(
      displayTransform
    )

    return CGPoint(
      x: normalizedViewPoint.x * viewportSize.width,
      y: normalizedViewPoint.y * viewportSize.height
    )
  }

  private static func hasOverlapPressure(_ bounds: [CGRect]) -> Bool {
    guard bounds.count > 1 else {
      return false
    }

    for firstIndex in bounds.indices {
      for secondIndex in bounds.indices where secondIndex > firstIndex {
        let first = bounds[firstIndex]
        let second = bounds[secondIndex]
        let intersection = first.intersection(second)

        guard !intersection.isNull, !intersection.isEmpty else {
          continue
        }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = first.width * first.height
          + second.width * second.height
          - intersectionArea

        guard unionArea > 0 else {
          continue
        }

        if Double(intersectionArea / unionArea)
          >= SpatialVisionTuning.ambiguousOverlapThreshold
        {
          return true
        }
      }
    }

    return false
  }
}
