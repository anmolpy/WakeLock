import Foundation
import WakeLockCore
import XCTest

final class WakePlanTests: XCTestCase {
  func testMakesSessionWithPlanConfiguration() throws {
    let alarmID = UUID()
    let sessionID = UUID()
    let plan = try makePlan(alarmID: alarmID)

    let session = plan.makeSession(id: sessionID)

    XCTAssertEqual(session.id, sessionID)
    XCTAssertEqual(session.alarmID, alarmID)
    XCTAssertEqual(session.target.payload, plan.qrTarget.payload)
    XCTAssertEqual(session.state, .waitingForAlarm)
  }

  func testCompletedSessionAdvancesWakeTime() throws {
    var plan = try makePlan()
    var session = plan.makeSession()
    session.alarmDidFire()
    XCTAssertEqual(session.submitScan(plan.qrTarget.payload), .completed)

    XCTAssertEqual(
      plan.recordCompletion(of: session),
      .recorded(nextWakeTime: try WakeTime(hour: 7, minute: 15))
    )
    XCTAssertEqual(plan.currentWakeTime, try WakeTime(hour: 7, minute: 15))
  }

  func testIncompleteSessionDoesNotAdvanceWakeTime() throws {
    var plan = try makePlan()
    let session = plan.makeSession()

    XCTAssertEqual(plan.recordCompletion(of: session), .incompleteSession)
    XCTAssertEqual(plan.currentWakeTime, try WakeTime(hour: 7, minute: 30))
    XCTAssertTrue(plan.completedSessionIDs.isEmpty)
  }

  func testSessionForDifferentAlarmDoesNotAdvanceWakeTime() throws {
    var plan = try makePlan()
    let target = try QRCodeTarget(payload: "wakelock:bathroom")
    var session = WakeSession(alarmID: UUID(), target: target)
    session.alarmDidFire()
    XCTAssertEqual(session.submitScan(target.payload), .completed)

    XCTAssertEqual(plan.recordCompletion(of: session), .differentAlarm)
    XCTAssertEqual(plan.currentWakeTime, try WakeTime(hour: 7, minute: 30))
  }

  func testDuplicateCompletionCannotAdvanceTwice() throws {
    var plan = try makePlan()
    var session = plan.makeSession()
    session.alarmDidFire()
    XCTAssertEqual(session.submitScan(plan.qrTarget.payload), .completed)

    XCTAssertEqual(
      plan.recordCompletion(of: session),
      .recorded(nextWakeTime: try WakeTime(hour: 7, minute: 15))
    )
    XCTAssertEqual(plan.recordCompletion(of: session), .alreadyRecorded)
    XCTAssertEqual(plan.currentWakeTime, try WakeTime(hour: 7, minute: 15))
    XCTAssertEqual(plan.completedSessionIDs, [session.id])
  }

  func testSeparateCompletedSessionsReachAndRemainAtTarget() throws {
    var plan = try makePlan(step: 20)

    for expectedTime in [(7, 10), (6, 50), (6, 40), (6, 40)] {
      var session = plan.makeSession()
      session.alarmDidFire()
      XCTAssertEqual(session.submitScan(plan.qrTarget.payload), .completed)

      XCTAssertEqual(
        plan.recordCompletion(of: session),
        .recorded(
          nextWakeTime: try WakeTime(
            hour: expectedTime.0,
            minute: expectedTime.1
          )
        )
      )
    }
  }

  private func makePlan(alarmID: UUID = UUID(), step: Int = 15) throws -> WakePlan {
    try WakePlan(
      alarmID: alarmID,
      qrTarget: QRCodeTarget(payload: "wakelock:bathroom"),
      progression: WakeProgression(
        startTime: WakeTime(hour: 7, minute: 30),
        targetTime: WakeTime(hour: 6, minute: 40),
        stepMinutes: step
      )
    )
  }
}
