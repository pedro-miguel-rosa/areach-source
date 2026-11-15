import Foundation
import QuartzCore
import simd

struct SpatialOneEuroFilter {
  private var filteredValue: Float?
  private var filteredDerivative: Float = 0
  private var lastRawValue: Float?
  private var lastUpdatedAt: CFTimeInterval?

  mutating func reset() {
    filteredValue = nil
    filteredDerivative = 0
    lastRawValue = nil
    lastUpdatedAt = nil
  }

  mutating func filter(
    _ value: Float,
    at time: CFTimeInterval,
    minimumCutoff: Float = SpatialMeasurementTuning.worldPositionMinimumCutoff,
    beta: Float = SpatialMeasurementTuning.worldPositionBeta,
    derivativeCutoff: Float = SpatialMeasurementTuning.worldPositionDerivativeCutoff
  ) -> Float {
    guard
      value.isFinite,
      time.isFinite
    else {
      return filteredValue ?? value
    }

    guard
      let filteredValue,
      let lastRawValue,
      let lastUpdatedAt
    else {
      self.filteredValue = value
      self.lastRawValue = value
      self.lastUpdatedAt = time
      return value
    }

    let elapsed = time - lastUpdatedAt
    guard elapsed > 0 else {
      return filteredValue
    }

    if elapsed > SpatialMeasurementTuning.worldPositionMaximumMeasurementGap {
      self.filteredValue = value
      self.filteredDerivative = 0
      self.lastRawValue = value
      self.lastUpdatedAt = time
      return value
    }

    let derivative = (value - lastRawValue) / Float(elapsed)
    let derivativeAlpha = Self.alpha(
      cutoff: derivativeCutoff,
      elapsed: elapsed
    )
    filteredDerivative += derivativeAlpha * (derivative - filteredDerivative)

    let cutoff = minimumCutoff + beta * abs(filteredDerivative)
    let valueAlpha = Self.alpha(cutoff: cutoff, elapsed: elapsed)
    let nextValue = filteredValue + valueAlpha * (value - filteredValue)

    self.filteredValue = nextValue
    self.lastRawValue = value
    self.lastUpdatedAt = time
    return nextValue
  }

  private static func alpha(
    cutoff: Float,
    elapsed: CFTimeInterval
  ) -> Float {
    let safeCutoff = max(0.01, cutoff)
    let timeConstant = 1 / (2 * Float.pi * safeCutoff)
    return 1 / (1 + timeConstant / Float(max(elapsed, 1 / 120)))
  }
}

struct SpatialWorldPositionFilter {
  private var x = SpatialOneEuroFilter()
  private var y = SpatialOneEuroFilter()
  private var z = SpatialOneEuroFilter()
  private var lastRawPosition: SIMD3<Float>?
  private var lastRawAt: CFTimeInterval?
  private var velocity = SIMD3<Float>.zero

  mutating func reset() {
    x.reset()
    y.reset()
    z.reset()
    lastRawPosition = nil
    lastRawAt = nil
    velocity = .zero
  }

  mutating func filter(
    _ transform: simd_float4x4,
    at time: CFTimeInterval
  ) -> simd_float4x4 {
    let rawPosition = SIMD3<Float>(
      transform.columns.3.x,
      transform.columns.3.y,
      transform.columns.3.z
    )
    guard
      time.isFinite,
      rawPosition.x.isFinite,
      rawPosition.y.isFinite,
      rawPosition.z.isFinite
    else {
      return transform
    }

    if let lastRawPosition, let lastRawAt {
      let elapsed = time - lastRawAt
      let displacement = simd_distance(rawPosition, lastRawPosition)
      if elapsed <= 0
        || elapsed > SpatialMeasurementTuning.worldPositionMaximumMeasurementGap
        || displacement >= SpatialMeasurementTuning.worldPositionDiscontinuityDistance
      {
        reset()
      } else {
        let rawVelocity = (rawPosition - lastRawPosition) / Float(elapsed)
        let velocityBlend: Float = 0.42
        velocity += velocityBlend * (rawVelocity - velocity)
        let speed = simd_length(velocity)
        if speed > SpatialMeasurementTuning.worldPositionMaximumSpeed {
          velocity *= SpatialMeasurementTuning.worldPositionMaximumSpeed / speed
        }
      }
    }

    let filteredPosition = SIMD3<Float>(
      x.filter(rawPosition.x, at: time),
      y.filter(rawPosition.y, at: time),
      z.filter(rawPosition.z, at: time)
    )
    let speed = simd_length(velocity)
    let predictionHorizon = min(
      SpatialMeasurementTuning.worldPositionPredictionHorizon,
      max(0, time - (lastRawAt ?? time))
    )
    let prediction = velocity * Float(predictionHorizon)
    let boundedPrediction: SIMD3<Float>
    if simd_length(prediction)
      > SpatialMeasurementTuning.worldPositionMaximumPredictionDistance,
      simd_length(prediction) > 0
    {
      boundedPrediction = prediction
        * (SpatialMeasurementTuning.worldPositionMaximumPredictionDistance
          / simd_length(prediction))
    } else {
      boundedPrediction = speed.isFinite ? prediction : .zero
    }

    lastRawPosition = rawPosition
    lastRawAt = time

    var displayTransform = transform
    let displayPosition = filteredPosition + boundedPrediction
    displayTransform.columns.3 = SIMD4<Float>(
      displayPosition.x,
      displayPosition.y,
      displayPosition.z,
      transform.columns.3.w
    )
    return displayTransform
  }
}

struct SpatialDistanceDisplayFilter {
  private var samples: [Float] = []
  private var filteredDistance: Float?
  private var lastRawDistance: Float?
  private var lastUpdatedAt: CFTimeInterval?

  mutating func reset() {
    samples.removeAll(keepingCapacity: true)
    filteredDistance = nil
    lastRawDistance = nil
    lastUpdatedAt = nil
  }

  mutating func update(
    _ rawDistance: Float,
    at time: CFTimeInterval
  ) -> (distance: Float, uncertainty: Float, sampleCount: Int) {
    guard rawDistance.isFinite, rawDistance > 0, time.isFinite else {
      return (
        filteredDistance ?? rawDistance,
        1.2,
        samples.count
      )
    }

    if let lastUpdatedAt,
      time - lastUpdatedAt > SpatialMeasurementTuning.distanceMaximumMeasurementGap
    {
      reset()
    }

    samples.append(rawDistance)
    if samples.count > SpatialMeasurementTuning.distanceMedianWindow {
      samples.removeFirst(
        samples.count - SpatialMeasurementTuning.distanceMedianWindow
      )
    }

    let sortedSamples = samples.sorted()
    let median = sortedSamples[sortedSamples.count / 2]
    let deviations = samples.map { abs($0 - median) }.sorted()
    let medianAbsoluteDeviation = deviations[deviations.count / 2]
    let robustDistance = abs(rawDistance - median)
      > max(
        SpatialMeasurementTuning.distanceOutlierFloor,
        medianAbsoluteDeviation * 3
      ) && samples.count > 2
      ? median
      : rawDistance

    let elapsed = lastUpdatedAt.map { max(1 / 120, time - $0) } ?? 0
    let derivative = elapsed > 0
      ? abs(robustDistance - (lastRawDistance ?? robustDistance))
        / Float(elapsed)
      : 0
    let movement = min(1, derivative / 1.5)
    let alpha = SpatialMeasurementTuning.distanceEMAAlpha
      + (SpatialMeasurementTuning.distanceMovingEMAAlpha
        - SpatialMeasurementTuning.distanceEMAAlpha) * movement
    let displayDistance = filteredDistance.map {
      $0 + alpha * (robustDistance - $0)
    } ?? robustDistance

    filteredDistance = displayDistance
    lastRawDistance = rawDistance
    lastUpdatedAt = time

    return (
      displayDistance,
      min(
        1.2,
        max(
          0.12,
          medianAbsoluteDeviation * 1.4826
            + 0.03 / sqrt(Float(max(samples.count, 1)))
        )
      ),
      samples.count
    )
  }
}
