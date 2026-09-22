/// A local wall-clock time used to configure a daily alarm.
public struct WakeTime: Equatable, Hashable, Comparable, Sendable {
  public enum ValidationError: Error, Equatable {
    case invalidHour
    case invalidMinute
  }

  public let hour: Int
  public let minute: Int

  public init(hour: Int, minute: Int) throws {
    guard (0...23).contains(hour) else {
      throw ValidationError.invalidHour
    }
    guard (0...59).contains(minute) else {
      throw ValidationError.invalidMinute
    }

    self.hour = hour
    self.minute = minute
  }

  public static func < (lhs: WakeTime, rhs: WakeTime) -> Bool {
    lhs.minutesAfterMidnight < rhs.minutesAfterMidnight
  }

  var minutesAfterMidnight: Int {
    (hour * 60) + minute
  }

  init(minutesAfterMidnight: Int) {
    precondition((0..<(24 * 60)).contains(minutesAfterMidnight))
    hour = minutesAfterMidnight / 60
    minute = minutesAfterMidnight % 60
  }
}
