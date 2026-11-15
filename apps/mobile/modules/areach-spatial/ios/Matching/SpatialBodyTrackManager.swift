import Foundation

/// Maintains persistent body identities between the more expensive Vision
/// observations. The small alpha-beta/Kalman-style filters predict position
/// and scale, while Hungarian assignment keeps crossing bodies from being
/// resolved by a greedy nearest-neighbour decision.
final class SpatialBodyTrackManager {
  private static let maximumMatchCost = 220.0

  private struct ScalarFilter {
    var value: CGFloat
    var velocity: CGFloat
    var positionVariance: CGFloat = 64
    var velocityVariance: CGFloat = 160
    var lastUpdatedAt: CFTimeInterval

    mutating func predict(to time: CFTimeInterval) -> CGFloat {
      let elapsed = min(
        SpatialVisionTuning.maximumBodyPredictionInterval,
        max(0, time - lastUpdatedAt)
      )
      guard elapsed > 0 else {
        return value
      }

      value += velocity * CGFloat(elapsed)
      positionVariance += velocityVariance * CGFloat(elapsed * elapsed) + 4
      lastUpdatedAt = time
      return value
    }

    mutating func update(
      with measurement: CGFloat,
      at time: CFTimeInterval,
      confidence: CGFloat
    ) -> CGFloat {
      let elapsed = max(1 / 120, time - lastUpdatedAt)
      let predicted = predict(to: time)
      let confidenceWeight = min(1, max(0.25, confidence))
      let measurementNoise =
        SpatialVisionTuning.bodyTrackPositionMeasurementNoise
        / confidenceWeight
      let gain = positionVariance
        / max(positionVariance + measurementNoise, 0.001)
      let innovation = measurement - predicted
      value += gain * innovation
      positionVariance = max(1, (1 - gain) * positionVariance)

      let velocityGain = min(
        0.72,
        velocityVariance
          / max(
            velocityVariance + SpatialVisionTuning.bodyTrackVelocityMeasurementNoise,
            0.001
          )
      )
      velocity += velocityGain * innovation / CGFloat(elapsed)
      velocity = min(2400, max(-2400, velocity))
      velocityVariance = max(
        4,
        velocityVariance * (1 - velocityGain) + measurementNoise
      )
      return value
    }
  }

  private struct TrackFilter {
    var centerX: ScalarFilter
    var centerY: ScalarFilter
    var width: ScalarFilter
    var height: ScalarFilter

    init(
      bounds: CGRect,
      point: CGPoint,
      at time: CFTimeInterval
    ) {
      centerX = ScalarFilter(value: point.x, velocity: 0, lastUpdatedAt: time)
      centerY = ScalarFilter(value: point.y, velocity: 0, lastUpdatedAt: time)
      width = ScalarFilter(value: max(1, bounds.width), velocity: 0, lastUpdatedAt: time)
      height = ScalarFilter(value: max(1, bounds.height), velocity: 0, lastUpdatedAt: time)
    }

    mutating func predict(at time: CFTimeInterval) -> TrackPrediction {
      let point = CGPoint(
        x: centerX.predict(to: time),
        y: centerY.predict(to: time)
      )
      let size = CGSize(
        width: max(1, width.predict(to: time)),
        height: max(1, height.predict(to: time))
      )
      return prediction(point: point, size: size)
    }

    mutating func update(
      with detection: SpatialBodyDetection,
      at time: CFTimeInterval
    ) -> TrackPrediction {
      let confidence = CGFloat(detection.confidence)
      let point = CGPoint(
        x: centerX.update(
          with: detection.trackingPoint.x,
          at: time,
          confidence: confidence
        ),
        y: centerY.update(
          with: detection.trackingPoint.y,
          at: time,
          confidence: confidence
        )
      )
      let size = CGSize(
        width: max(
          1,
          width.update(
            with: detection.boundingBox.width,
            at: time,
            confidence: confidence
          )
        ),
        height: max(
          1,
          height.update(
            with: detection.boundingBox.height,
            at: time,
            confidence: confidence
          )
        )
      )
      return prediction(point: point, size: size)
    }

    var currentVelocity: CGVector {
      CGVector(dx: centerX.velocity, dy: centerY.velocity)
    }

    private func prediction(point: CGPoint, size: CGSize) -> TrackPrediction {
      TrackPrediction(
        boundingBox: CGRect(
          x: point.x - size.width / 2,
          y: point.y - size.height / 2,
          width: size.width,
          height: size.height
        ),
        point: point
      )
    }
  }

  private struct TrackPrediction {
    let boundingBox: CGRect
    let point: CGPoint
  }

  private struct Track {
    let id: String
    var filter: TrackFilter
    var lastDetection: SpatialBodyDetection
    var lastObservedAt: CFTimeInterval
    var missCount: Int
    var duplicateFreshPoseConfirmationCount: Int
  }

  private var nextTrackId = 0
  private var tracks: [String: Track] = [:]
  private let duplicatePolicy = SpatialBodyDuplicatePolicy()
  private(set) var lastDuplicateDetectionSuppressionCount = 0
  private(set) var lastDuplicateTrackSuppressionCount = 0
  private(set) var lastDuplicateTrackRetirementCount = 0

  func reset() {
    nextTrackId = 0
    tracks.removeAll()
    lastDuplicateDetectionSuppressionCount = 0
    lastDuplicateTrackSuppressionCount = 0
    lastDuplicateTrackRetirementCount = 0
  }

  /// A track remains authoritative only while it is still present in this
  /// dictionary after the current update.  This includes short predicted
  /// gaps, but excludes tracks whose retention interval has elapsed.
  func isTrackRecoverable(_ trackId: String) -> Bool {
    tracks[trackId] != nil
  }

  func update(
    _ detections: [SpatialBodyDetection],
    now: CFTimeInterval
  ) -> [SpatialBodyDetection] {
    lastDuplicateDetectionSuppressionCount = 0
    lastDuplicateTrackSuppressionCount = 0
    lastDuplicateTrackRetirementCount = 0

    let deduplication = duplicatePolicy.suppressDuplicates(
      in: detections.map(\.duplicateBodyCandidate)
    )
    let uniqueDetections = deduplication.retainedIndices.map { detections[$0] }
    lastDuplicateDetectionSuppressionCount = deduplication.suppressedIndices.count

    let existingTracks = tracks.values.sorted { $0.id < $1.id }
    let assignments = SpatialAssignment.assign(
      rowCount: existingTracks.count,
      columnCount: uniqueDetections.count,
      unmatchedCost: Self.maximumMatchCost
    ) { trackIndex, detectionIndex in
      Self.matchCost(
        track: existingTracks[trackIndex],
        detection: uniqueDetections[detectionIndex],
        now: now
      )
    }

    var nextTracks: [String: Track] = [:]
    var matchedDetectionIndices = Set<Int>()
    var trackedDetections: [SpatialBodyDetection] = []
    trackedDetections.reserveCapacity(existingTracks.count + uniqueDetections.count)

    for (trackIndex, detectionIndex) in assignments.enumerated() {
      guard let detectionIndex, detectionIndex < uniqueDetections.count else {
        continue
      }

      var track = existingTracks[trackIndex]
      let detection = uniqueDetections[detectionIndex]
      guard Self.matchCost(track: track, detection: detection, now: now)
        < Self.maximumMatchCost
      else {
        continue
      }

      let prediction = track.filter.update(with: detection, at: now)
      let trackedDetection = Self.trackedDetection(
        detection,
        id: track.id,
        prediction: prediction,
        velocity: track.filter.currentVelocity,
        at: now,
        confidence: detection.confidence,
        isFreshPose: detection.isFreshPose
      )
      track.lastDetection = trackedDetection
      track.lastObservedAt = now
      track.missCount = 0
      track.duplicateFreshPoseConfirmationCount = 0
      nextTracks[track.id] = track
      matchedDetectionIndices.insert(detectionIndex)
      trackedDetections.append(trackedDetection)
    }

    for (index, detection) in uniqueDetections.enumerated()
    where !matchedDetectionIndices.contains(index)
    {
      if trackedDetections.contains(where: {
        duplicatePolicy.areDuplicates(
          $0.duplicateBodyCandidate,
          detection.duplicateBodyCandidate
        )
      }) {
        lastDuplicateTrackSuppressionCount += 1
        continue
      }

      let id = "body-\(nextTrackId)"
      nextTrackId += 1
      var filter = TrackFilter(
        bounds: detection.boundingBox,
        point: detection.trackingPoint,
        at: now
      )
      let prediction = filter.update(with: detection, at: now)
      let trackedDetection = Self.trackedDetection(
        detection,
        id: id,
        prediction: prediction,
        velocity: filter.currentVelocity,
        at: now,
        confidence: detection.confidence,
        isFreshPose: detection.isFreshPose
      )
      nextTracks[id] = Track(
        id: id,
        filter: filter,
        lastDetection: trackedDetection,
        lastObservedAt: now,
        missCount: 0,
        duplicateFreshPoseConfirmationCount: 0
      )
      trackedDetections.append(trackedDetection)
    }

    let observedDetections = trackedDetections
    for var track in existingTracks where nextTracks[track.id] == nil {
      guard now - track.lastObservedAt <= SpatialVisionTuning.bodyTrackRetentionDuration
      else {
        continue
      }

      let prediction = track.filter.predict(at: now)
      track.missCount += 1
      let confidence = max(
        0.12,
        track.lastDetection.confidence * pow(0.82, Float(track.missCount))
      )
      let predictedDetection = Self.trackedDetection(
        track.lastDetection.withDepth(
          nil,
          quality: 0,
          sampleCount: 0,
          spread: nil,
          geometry: nil
        ),
        id: track.id,
        prediction: prediction,
        velocity: track.filter.currentVelocity,
        at: now,
        confidence: confidence,
        isFreshPose: false
      )
      let duplicateObservation = observedDetections.first(where: {
        duplicatePolicy.areDuplicates(
          $0.duplicateBodyCandidate,
          predictedDetection.duplicateBodyCandidate
        )
      })
      let duplicateDecision = SpatialBodyDuplicateTrackPolicy.decision(
        isStrongDuplicate: duplicateObservation != nil,
        hasFreshPoseConfirmation: duplicateObservation?.isFreshPose == true,
        previousFreshDuplicateConfirmationCount: track.duplicateFreshPoseConfirmationCount
      )
      track.duplicateFreshPoseConfirmationCount =
        duplicateDecision.freshDuplicateConfirmationCount

      switch duplicateDecision.disposition {
      case .keep:
        if observedDetections.contains(where: { $0.isFreshPose }) {
          track.duplicateFreshPoseConfirmationCount = 0
        }
        nextTracks[track.id] = track
        trackedDetections.append(predictedDetection)
      case .suppress:
        lastDuplicateTrackSuppressionCount += 1
        nextTracks[track.id] = track
      case .retire:
        lastDuplicateTrackSuppressionCount += 1
        lastDuplicateTrackRetirementCount += 1
      }
    }

    tracks = nextTracks
    return trackedDetections.sorted { $0.id < $1.id }
  }

  private static func trackedDetection(
    _ detection: SpatialBodyDetection,
    id: String,
    prediction: TrackPrediction,
    velocity: CGVector,
    at time: CFTimeInterval,
    confidence: Float,
    isFreshPose: Bool
  ) -> SpatialBodyDetection {
    let resizedDetection = detection.transformed(
      from: detection.boundingBox,
      to: prediction.boundingBox,
      confidence: confidence
    )
    return resizedDetection.withTracking(
      id: id,
      point: prediction.point,
      velocity: velocity,
      hasMotionEstimate: true,
      at: time,
      isFreshPose: isFreshPose
    )
  }

  private static func matchCost(
    track: Track,
    detection: SpatialBodyDetection,
    now: CFTimeInterval
  ) -> Double {
    var filter = track.filter
    let prediction = filter.predict(at: now)
    let bodyScale = max(track.lastDetection.bodyScale, 60)
    let pointDistance = distance(prediction.point, detection.trackingPoint)
    let centerDistance = distance(
      prediction.boundingBox.center,
      detection.boundingBox.center
    )
    let scaleRatio = max(
      0.01,
      Double(max(detection.boundingBox.width, detection.boundingBox.height))
        / Double(max(
          prediction.boundingBox.width,
          prediction.boundingBox.height,
          1
        ))
    )
    let scaleChange = max(scaleRatio, 1 / scaleRatio)
    let iou = intersectionOverUnion(
      prediction.boundingBox,
      detection.boundingBox
    )

    guard
      pointDistance <= Double(
        bodyScale * SpatialVisionTuning.bodyTrackMaximumCenterDisplacement
      ),
      scaleChange <= Double(SpatialVisionTuning.bodyTrackMaximumScaleRatio),
      !(iou < SpatialVisionTuning.bodyTrackMinimumFarIoU
        && pointDistance > Double(bodyScale * 0.55))
    else {
      return Self.maximumMatchCost
    }

    let overlapPenalty = (1 - iou) * 60
    let scalePenalty = abs(log(scaleRatio)) * 48
    let confidencePenalty = Double(max(0, 0.45 - detection.confidence)) * 40
    return pointDistance * 0.5
      + centerDistance * 0.18
      + overlapPenalty
      + scalePenalty
      + confidencePenalty
  }

  private static func intersectionOverUnion(
    _ first: CGRect,
    _ second: CGRect
  ) -> Double {
    let intersection = first.intersection(second)
    guard !intersection.isNull, !intersection.isEmpty else {
      return 0
    }

    let intersectionArea = intersection.width * intersection.height
    let unionArea = first.width * first.height
      + second.width * second.height
      - intersectionArea
    guard unionArea > 0 else {
      return 0
    }

    return Double(intersectionArea / unionArea)
  }
}
