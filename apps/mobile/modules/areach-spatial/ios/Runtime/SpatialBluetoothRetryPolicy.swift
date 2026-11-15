import Foundation
import QuartzCore

/// Pure retry timing semantics used by the CoreBluetooth coordinator and its
/// deterministic harness. A missing attempt timestamp is a first attempt,
/// never an epoch timestamp that accidentally consumes the backoff window.
enum SpatialBluetoothRetryPolicy {
  static func nextRetryAt(
    lastAttemptAt: CFTimeInterval?,
    delay: CFTimeInterval
  ) -> CFTimeInterval? {
    lastAttemptAt.map { $0 + max(0, delay) }
  }

  static func isEligible(
    now: CFTimeInterval,
    lastAttemptAt: CFTimeInterval?,
    delay: CFTimeInterval
  ) -> Bool {
    guard let nextRetryAt = nextRetryAt(
      lastAttemptAt: lastAttemptAt,
      delay: delay
    ) else {
      return true
    }

    return now >= nextRetryAt
  }

  static func advertisementExpiry(
    lastAdvertisementAt: CFTimeInterval?,
    staleAfter: CFTimeInterval
  ) -> CFTimeInterval? {
    lastAdvertisementAt.map { $0 + max(0, staleAfter) }
  }
}
