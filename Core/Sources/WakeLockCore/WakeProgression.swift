/// A deterministic policy for moving a daily wake time toward an earlier goal.
///
/// The app supplies the number of QR-verified wake sessions. Failed or skipped
/// sessions do not move the alarm earlier because they do not increase that
/// count.
public struct WakeProgression: Equatable, Sendable {
  public enum ValidationError: Error, Equatable {
    case targetMustNotBeLaterThanStart
    case stepMustBePositive
    case negativeCompletedSessionCount
  }

  public let startTime: WakeTime
  public let targetTime: WakeTime
  public let stepMinutes: Int

  public init(
    startTime: WakeTime,
    targetTime: WakeTime,
    stepMinutes: Int
  ) throws {
    guard targetTime <= startTime else {
      throw ValidationError.targetMustNotBeLaterThanStart
    }
    guard stepMinutes > 0 else {
      throw ValidationError.stepMustBePositive
    }

    self.startTime = startTime
    self.targetTime = targetTime
    self.stepMinutes = stepMinutes
  }

  /// Returns the scheduled time after a number of successful wake sessions.
  /// The final step is shortened when necessary so the goal is never passed.
  public func wakeTime(afterCompletedSessions count: Int) throws -> WakeTime {
    guard count >= 0 else {
      throw ValidationError.negativeCompletedSessionCount
    }

    return wakeTime(forValidatedCompletedSessionCount: count)
  }

  func wakeTime(forValidatedCompletedSessionCount count: Int) -> WakeTime {
    precondition(count >= 0)

    let distance = startTime.minutesAfterMidnight - targetTime.minutesAfterMidnight
    guard distance > 0, count > 0 else { return startTime }

    // Check the clamp before multiplying. This also avoids overflow if a
    // corrupt persisted count is unexpectedly very large.
    let stepsToTarget = (distance + stepMinutes - 1) / stepMinutes
    guard count < stepsToTarget else { return targetTime }

    return WakeTime(
      minutesAfterMidnight: startTime.minutesAfterMidnight - (count * stepMinutes)
    )
  }

  public func successfulSessionsRemaining(afterCompletedSessions count: Int) throws -> Int {
    let currentTime = try wakeTime(afterCompletedSessions: count)
    let remainingMinutes = currentTime.minutesAfterMidnight - targetTime.minutesAfterMidnight
    guard remainingMinutes > 0 else { return 0 }
    return (remainingMinutes + stepMinutes - 1) / stepMinutes
  }
}
