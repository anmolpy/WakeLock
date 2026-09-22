import WakeLockCore
import XCTest

final class WakeTimeTests: XCTestCase {
  func testAcceptsBoundaryTimes() throws {
    XCTAssertEqual(try WakeTime(hour: 0, minute: 0), try WakeTime(hour: 0, minute: 0))
    XCTAssertEqual(try WakeTime(hour: 23, minute: 59), try WakeTime(hour: 23, minute: 59))
  }

  func testRejectsInvalidHours() {
    for hour in [-1, 24] {
      XCTAssertThrowsError(try WakeTime(hour: hour, minute: 0)) { error in
        XCTAssertEqual(error as? WakeTime.ValidationError, .invalidHour)
      }
    }
  }

  func testRejectsInvalidMinutes() {
    for minute in [-1, 60] {
      XCTAssertThrowsError(try WakeTime(hour: 6, minute: minute)) { error in
        XCTAssertEqual(error as? WakeTime.ValidationError, .invalidMinute)
      }
    }
  }

  func testOrdersTimesWithinADay() throws {
    XCTAssertLessThan(
      try WakeTime(hour: 5, minute: 59),
      try WakeTime(hour: 6, minute: 0)
    )
  }
}

final class WakeProgressionTests: XCTestCase {
  func testStartsAtConfiguredTimeWithNoCompletedSessions() throws {
    let progression = try makeProgression(start: (7, 30), target: (6, 30), step: 15)

    XCTAssertEqual(
      try progression.wakeTime(afterCompletedSessions: 0),
      try WakeTime(hour: 7, minute: 30)
    )
  }

  func testMovesEarlierForEachCompletedSession() throws {
    let progression = try makeProgression(start: (7, 30), target: (6, 30), step: 15)

    XCTAssertEqual(
      try progression.wakeTime(afterCompletedSessions: 1),
      try WakeTime(hour: 7, minute: 15)
    )
    XCTAssertEqual(
      try progression.wakeTime(afterCompletedSessions: 3),
      try WakeTime(hour: 6, minute: 45)
    )
  }

  func testShortensFinalStepToLandOnTarget() throws {
    let progression = try makeProgression(start: (7, 0), target: (6, 40), step: 15)

    XCTAssertEqual(
      try progression.wakeTime(afterCompletedSessions: 1),
      try WakeTime(hour: 6, minute: 45)
    )
    XCTAssertEqual(
      try progression.wakeTime(afterCompletedSessions: 2),
      try WakeTime(hour: 6, minute: 40)
    )
  }

  func testNeverMovesPastTarget() throws {
    let progression = try makeProgression(start: (7, 0), target: (6, 40), step: 15)
    let target = try WakeTime(hour: 6, minute: 40)

    XCTAssertEqual(try progression.wakeTime(afterCompletedSessions: 3), target)
    XCTAssertEqual(try progression.wakeTime(afterCompletedSessions: .max), target)
  }

  func testReportsSuccessfulSessionsRemaining() throws {
    let progression = try makeProgression(start: (7, 0), target: (6, 40), step: 15)

    XCTAssertEqual(try progression.successfulSessionsRemaining(afterCompletedSessions: 0), 2)
    XCTAssertEqual(try progression.successfulSessionsRemaining(afterCompletedSessions: 1), 1)
    XCTAssertEqual(try progression.successfulSessionsRemaining(afterCompletedSessions: 2), 0)
  }

  func testAllowsAlreadyReachedGoal() throws {
    let progression = try makeProgression(start: (6, 30), target: (6, 30), step: 10)

    XCTAssertEqual(
      try progression.wakeTime(afterCompletedSessions: 100),
      try WakeTime(hour: 6, minute: 30)
    )
  }

  func testRejectsLaterTarget() throws {
    XCTAssertThrowsError(
      try WakeProgression(
        startTime: WakeTime(hour: 6, minute: 30),
        targetTime: WakeTime(hour: 7, minute: 0),
        stepMinutes: 10
      )
    ) { error in
      XCTAssertEqual(
        error as? WakeProgression.ValidationError,
        .targetMustNotBeLaterThanStart
      )
    }
  }

  func testRejectsNonPositiveStep() throws {
    for step in [-1, 0] {
      XCTAssertThrowsError(
        try makeProgression(start: (7, 0), target: (6, 30), step: step)
      ) { error in
        XCTAssertEqual(error as? WakeProgression.ValidationError, .stepMustBePositive)
      }
    }
  }

  func testRejectsNegativeCompletedSessionCount() throws {
    let progression = try makeProgression(start: (7, 0), target: (6, 30), step: 10)

    XCTAssertThrowsError(try progression.wakeTime(afterCompletedSessions: -1)) { error in
      XCTAssertEqual(
        error as? WakeProgression.ValidationError,
        .negativeCompletedSessionCount
      )
    }
  }

  private func makeProgression(
    start: (hour: Int, minute: Int),
    target: (hour: Int, minute: Int),
    step: Int
  ) throws -> WakeProgression {
    try WakeProgression(
      startTime: WakeTime(hour: start.hour, minute: start.minute),
      targetTime: WakeTime(hour: target.hour, minute: target.minute),
      stepMinutes: step
    )
  }
}
