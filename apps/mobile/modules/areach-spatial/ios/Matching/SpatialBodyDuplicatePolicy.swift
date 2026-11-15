import Foundation

struct SpatialBodyDuplicatePoint: Equatable {
  let x: Double
  let y: Double
}

struct SpatialBodyDuplicateBounds: Equatable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double

  var area: Double {
    max(0, width) * max(0, height)
  }
}

struct SpatialBodyDuplicateJoint: Equatable {
  let name: String
  let confidence: Double
  let point: SpatialBodyDuplicatePoint
}

struct SpatialBodyDuplicateCandidate {
  let bounds: SpatialBodyDuplicateBounds
  let confidence: Double
  let bodyScale: Double
  let joints: [SpatialBodyDuplicateJoint]
  let trackingPoint: SpatialBodyDuplicatePoint
}

struct SpatialBodyDuplicateResult: Equatable {
  let retainedIndices: [Int]
  let suppressedIndices: [Int]
}

/// A deliberately strict same-person check. Box overlap is only a prerequisite;
/// corroborating root, torso, scale, and corresponding core-joint geometry is
/// required before one observation can suppress another.
struct SpatialBodyDuplicatePolicy {
  // Matches the detector's minimum confidence for valid body-bound joints.
  static let minimumReliableJointConfidence = 0.2
  // Require substantial overlap, allowing partial observations only when one
  // box is almost contained by the other. Neither measure can suppress alone.
  static let minimumBoundingBoxIoU = 0.45
  static let minimumSmallerBoxCoverage = 0.82
  // This rejects different apparent body extents before comparing normalized
  // root/torso geometry; the distance gates below allow only small pose jitter.
  static let maximumBodyScaleRatio = 1.25
  static let maximumNormalizedRootDistance = 0.12
  static let maximumNormalizedTorsoDistance = 0.14
  static let minimumSharedCoreJointCount = 3
  static let maximumMeanNormalizedCoreJointDistance = 0.11
  static let maximumNormalizedCoreJointDistance = 0.21

  func suppressDuplicates(
    in candidates: [SpatialBodyDuplicateCandidate]
  ) -> SpatialBodyDuplicateResult {
    let priorityOrder = candidates.indices.sorted { firstIndex, secondIndex in
      outranks(
        candidates[firstIndex],
        at: firstIndex,
        candidates[secondIndex],
        at: secondIndex
      )
    }

    var retained: [Int] = []
    var suppressed: [Int] = []
    for candidateIndex in priorityOrder {
      let isDuplicate = retained.contains { retainedIndex in
        areDuplicates(candidates[retainedIndex], candidates[candidateIndex])
      }
      if isDuplicate {
        suppressed.append(candidateIndex)
      } else {
        retained.append(candidateIndex)
      }
    }

    return SpatialBodyDuplicateResult(
      retainedIndices: retained.sorted(),
      suppressedIndices: suppressed.sorted()
    )
  }

  func areDuplicates(
    _ first: SpatialBodyDuplicateCandidate,
    _ second: SpatialBodyDuplicateCandidate
  ) -> Bool {
    let firstArea = first.bounds.area
    let secondArea = second.bounds.area
    let firstScale = max(60, first.bodyScale)
    let secondScale = max(60, second.bodyScale)
    guard
      firstArea > 0,
      secondArea > 0,
      first.bodyScale.isFinite,
      second.bodyScale.isFinite,
      firstScale > 0,
      secondScale > 0
    else {
      return false
    }

    let scaleRatio = max(firstScale, secondScale) / min(firstScale, secondScale)
    guard scaleRatio <= Self.maximumBodyScaleRatio else {
      return false
    }

    let overlap = overlapMetrics(first.bounds, second.bounds)
    guard
      overlap.iou >= Self.minimumBoundingBoxIoU
        || overlap.smallerBoxCoverage >= Self.minimumSmallerBoxCoverage
    else {
      return false
    }

    let referenceScale = min(firstScale, secondScale)
    guard normalizedDistance(
      first.trackingPoint,
      second.trackingPoint,
      scale: referenceScale
    ) <= Self.maximumNormalizedRootDistance else {
      return false
    }

    let firstCoreJoints = coreJoints(in: first)
    let secondCoreJoints = coreJoints(in: second)
    let firstTorsoAnchors = torsoAnchors(in: firstCoreJoints)
    let secondTorsoAnchors = torsoAnchors(in: secondCoreJoints)
    let sharedTorsoDistances = firstTorsoAnchors.compactMap { name, point in
      secondTorsoAnchors[name].map {
        normalizedDistance(point, $0, scale: referenceScale)
      }
    }
    guard
      !sharedTorsoDistances.isEmpty,
      (sharedTorsoDistances.max() ?? .infinity)
        <= Self.maximumNormalizedTorsoDistance
    else {
      return false
    }

    let sharedJointDistances = firstCoreJoints.compactMap { name, firstJoint in
      secondCoreJoints[name].map { secondJoint in
        normalizedDistance(
          firstJoint.point,
          secondJoint.point,
          scale: referenceScale
        )
      }
    }
    guard sharedJointDistances.count >= Self.minimumSharedCoreJointCount else {
      return false
    }

    let meanJointDistance = sharedJointDistances.reduce(0, +)
      / Double(sharedJointDistances.count)
    return meanJointDistance <= Self.maximumMeanNormalizedCoreJointDistance
      && (sharedJointDistances.max() ?? .infinity)
        <= Self.maximumNormalizedCoreJointDistance
  }

  private func outranks(
    _ first: SpatialBodyDuplicateCandidate,
    at firstIndex: Int,
    _ second: SpatialBodyDuplicateCandidate,
    at secondIndex: Int
  ) -> Bool {
    let firstCoreCount = coreJoints(in: first).count
    let secondCoreCount = coreJoints(in: second).count
    if firstCoreCount != secondCoreCount {
      return firstCoreCount > secondCoreCount
    }

    let firstReliableJointCount = first.joints.filter {
      $0.confidence >= Self.minimumReliableJointConfidence
    }.count
    let secondReliableJointCount = second.joints.filter {
      $0.confidence >= Self.minimumReliableJointConfidence
    }.count
    if firstReliableJointCount != secondReliableJointCount {
      return firstReliableJointCount > secondReliableJointCount
    }

    if first.confidence != second.confidence {
      return first.confidence > second.confidence
    }
    return firstIndex < secondIndex
  }

  private func coreJoints(
    in candidate: SpatialBodyDuplicateCandidate
  ) -> [String: SpatialBodyDuplicateJoint] {
    var result: [String: SpatialBodyDuplicateJoint] = [:]
    for joint in candidate.joints
    where joint.confidence >= Self.minimumReliableJointConfidence {
      guard let name = canonicalCoreJointName(joint.name) else {
        continue
      }
      if let previous = result[name], previous.confidence >= joint.confidence {
        continue
      }
      result[name] = joint
    }
    return result
  }

  private func torsoAnchors(
    in joints: [String: SpatialBodyDuplicateJoint]
  ) -> [String: SpatialBodyDuplicatePoint] {
    var anchors: [String: SpatialBodyDuplicatePoint] = [:]
    let shoulderCenter = midpoint(
      joints["leftshoulder"]?.point,
      joints["rightshoulder"]?.point
    ) ?? joints["leftshoulder"]?.point ?? joints["rightshoulder"]?.point
    let hipCenter = midpoint(
      joints["lefthip"]?.point,
      joints["righthip"]?.point
    ) ?? joints["lefthip"]?.point ?? joints["righthip"]?.point

    if let shoulderCenter {
      anchors["shoulders"] = shoulderCenter
    }
    if let hipCenter {
      anchors["hips"] = hipCenter
    }
    return anchors
  }

  private func canonicalCoreJointName(_ name: String) -> String? {
    let normalizedName = name.lowercased().filter(\.isLetter)
    if normalizedName.contains("leftshoulder") { return "leftshoulder" }
    if normalizedName.contains("rightshoulder") { return "rightshoulder" }
    if normalizedName.contains("lefthip") { return "lefthip" }
    if normalizedName.contains("righthip") { return "righthip" }
    if normalizedName.contains("neck") { return "neck" }
    if normalizedName == "root" || normalizedName.hasSuffix("root") {
      return "root"
    }
    return nil
  }

  private func overlapMetrics(
    _ first: SpatialBodyDuplicateBounds,
    _ second: SpatialBodyDuplicateBounds
  ) -> (iou: Double, smallerBoxCoverage: Double) {
    let intersectionWidth = max(
      0,
      min(first.x + first.width, second.x + second.width)
        - max(first.x, second.x)
    )
    let intersectionHeight = max(
      0,
      min(first.y + first.height, second.y + second.height)
        - max(first.y, second.y)
    )
    let intersectionArea = intersectionWidth * intersectionHeight
    let unionArea = first.area + second.area - intersectionArea
    guard unionArea > 0 else {
      return (0, 0)
    }

    return (
      intersectionArea / unionArea,
      intersectionArea / min(first.area, second.area)
    )
  }

  private func normalizedDistance(
    _ first: SpatialBodyDuplicatePoint,
    _ second: SpatialBodyDuplicatePoint,
    scale: Double
  ) -> Double {
    hypot(first.x - second.x, first.y - second.y) / scale
  }

  private func midpoint(
    _ first: SpatialBodyDuplicatePoint?,
    _ second: SpatialBodyDuplicatePoint?
  ) -> SpatialBodyDuplicatePoint? {
    guard let first, let second else {
      return nil
    }
    return SpatialBodyDuplicatePoint(
      x: (first.x + second.x) / 2,
      y: (first.y + second.y) / 2
    )
  }
}

enum SpatialBodyDuplicateTrackDisposition: Equatable {
  case keep
  case suppress
  case retire
}

struct SpatialBodyDuplicateTrackDecision: Equatable {
  let disposition: SpatialBodyDuplicateTrackDisposition
  let freshDuplicateConfirmationCount: Int
}

enum SpatialBodyDuplicateTrackPolicy {
  static let freshConfirmationsBeforeRetirement = 2

  static func decision(
    isStrongDuplicate: Bool,
    hasFreshPoseConfirmation: Bool,
    previousFreshDuplicateConfirmationCount: Int
  ) -> SpatialBodyDuplicateTrackDecision {
    guard isStrongDuplicate else {
      return SpatialBodyDuplicateTrackDecision(
        disposition: .keep,
        freshDuplicateConfirmationCount: hasFreshPoseConfirmation
          ? 0
          : max(0, previousFreshDuplicateConfirmationCount)
      )
    }

    let confirmationCount = hasFreshPoseConfirmation
      ? max(0, previousFreshDuplicateConfirmationCount) + 1
      : max(0, previousFreshDuplicateConfirmationCount)
    return SpatialBodyDuplicateTrackDecision(
      disposition: hasFreshPoseConfirmation
        && confirmationCount >= freshConfirmationsBeforeRetirement
        ? .retire
        : .suppress,
      freshDuplicateConfirmationCount: confirmationCount
    )
  }
}

struct SpatialBodyPipelineDiagnostics: Equatable {
  let rawVisionObservationCount: Int
  let uniqueVisionDetectionCount: Int
  let detectorTrackedBodyCount: Int
  let visionDuplicateSuppressionCount: Int
  let detectorTrackDuplicateSuppressionCount: Int
  let matcherTrackedBodyCount: Int
  let matcherDuplicateTrackSuppressionCount: Int
  let matcherDuplicateTrackRetirementCount: Int

  static let empty = SpatialBodyPipelineDiagnostics(
    rawVisionObservationCount: 0,
    uniqueVisionDetectionCount: 0,
    detectorTrackedBodyCount: 0,
    visionDuplicateSuppressionCount: 0,
    detectorTrackDuplicateSuppressionCount: 0,
    matcherTrackedBodyCount: 0,
    matcherDuplicateTrackSuppressionCount: 0,
    matcherDuplicateTrackRetirementCount: 0
  )

  var totalDuplicateSuppressionCount: Int {
    visionDuplicateSuppressionCount
      + detectorTrackDuplicateSuppressionCount
      + matcherDuplicateTrackSuppressionCount
  }

  func withMatcherOutput(
    trackedBodyCount: Int,
    duplicateTrackSuppressionCount: Int,
    duplicateTrackRetirementCount: Int
  ) -> SpatialBodyPipelineDiagnostics {
    SpatialBodyPipelineDiagnostics(
      rawVisionObservationCount: rawVisionObservationCount,
      uniqueVisionDetectionCount: uniqueVisionDetectionCount,
      detectorTrackedBodyCount: detectorTrackedBodyCount,
      visionDuplicateSuppressionCount: visionDuplicateSuppressionCount,
      detectorTrackDuplicateSuppressionCount: detectorTrackDuplicateSuppressionCount,
      matcherTrackedBodyCount: trackedBodyCount,
      matcherDuplicateTrackSuppressionCount: duplicateTrackSuppressionCount,
      matcherDuplicateTrackRetirementCount: duplicateTrackRetirementCount
    )
  }
}
