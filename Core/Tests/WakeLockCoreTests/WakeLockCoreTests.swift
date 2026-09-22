import Foundation
import WakeLockCore
import XCTest

final class QRCodeTargetTests: XCTestCase {
  func testRejectsEmptyPayload() {
    assertEmptyPayloadRejected("")
  }

  func testRejectsWhitespaceOnlyPayloads() {
    for payload in [" ", "\t\n\r", "\u{00A0}\u{2003}"] {
      assertEmptyPayloadRejected(payload)
    }
  }

  func testPreservesAcceptedPayloadIncludingWhitespace() throws {
    let payload = "  WakeLock:kitchen\n"

    let target = try QRCodeTarget(payload: payload)

    XCTAssertEqual(target.payload, payload)
    XCTAssertTrue(target.matches(payload))
  }

  func testMatchesIdenticalPayload() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")

    XCTAssertTrue(target.matches("WakeLock:kitchen"))
  }

  func testMatchingIsCaseSensitive() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")

    XCTAssertFalse(target.matches("wakelock:kitchen"))
  }

  func testMatchingDoesNotAddOrRemoveWhitespace() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    let paddedTarget = try QRCodeTarget(payload: " WakeLock:kitchen ")

    XCTAssertFalse(target.matches(" WakeLock:kitchen"))
    XCTAssertFalse(target.matches("WakeLock:kitchen\n"))
    XCTAssertFalse(paddedTarget.matches("WakeLock:kitchen"))
  }

  func testMatchingRequiresIdenticalUTF8DespiteUnicodeEquivalence() throws {
    let composed = "caf\u{00E9}"
    let decomposed = "cafe\u{0301}"
    let target = try QRCodeTarget(payload: composed)

    // Swift String equality accepts these two Unicode spellings. QR
    // verification intentionally requires the original UTF-8 bytes.
    XCTAssertEqual(composed, decomposed)
    XCTAssertFalse(target.matches(decomposed))
    XCTAssertTrue(target.matches(composed))
  }

  private func assertEmptyPayloadRejected(
    _ payload: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertThrowsError(
      try QRCodeTarget(payload: payload),
      file: file,
      line: line
    ) { error in
      guard let validationError = error as? QRCodeTarget.ValidationError else {
        XCTFail("Expected QRCodeTarget.ValidationError, got \(error)", file: file, line: line)
        return
      }

      switch validationError {
      case .emptyPayload:
        break
      }
    }
  }
}

final class WakeSessionTests: XCTestCase {
  func testNewSessionWaitsForAlarmAndCapturesConfiguration() throws {
    let alarmID = UUID()
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")

    let session = WakeSession(alarmID: alarmID, target: target)

    XCTAssertEqual(session.alarmID, alarmID)
    XCTAssertEqual(session.target.payload, target.payload)
    XCTAssertEqual(session.state, .waitingForAlarm)
  }

  func testCorrectScanBeforeAlarmCannotCompleteSession() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    var session = WakeSession(alarmID: UUID(), target: target)

    XCTAssertEqual(session.submitScan(target.payload), .notReady)
    XCTAssertEqual(session.state, .waitingForAlarm)
  }

  func testAlarmFiringEnablesScanning() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    var session = WakeSession(alarmID: UUID(), target: target)

    session.alarmDidFire()

    XCTAssertEqual(session.state, .awaitingScan)
  }

  func testWrongScanLeavesSessionReadyForCorrectScan() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    var session = WakeSession(alarmID: UUID(), target: target)
    session.alarmDidFire()

    XCTAssertEqual(session.submitScan("WakeLock:bedroom"), .wrongCode)
    XCTAssertEqual(session.state, .awaitingScan)
    XCTAssertEqual(session.submitScan(target.payload), .completed)
    XCTAssertEqual(session.state, .completed)
  }

  func testEmptyScanCannotCompleteSession() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    var session = WakeSession(alarmID: UUID(), target: target)
    session.alarmDidFire()

    XCTAssertEqual(session.submitScan(""), .wrongCode)
    XCTAssertEqual(session.state, .awaitingScan)
  }

  func testDuplicateAlarmEventLeavesSessionAwaitingScan() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    var session = WakeSession(alarmID: UUID(), target: target)
    session.alarmDidFire()

    session.alarmDidFire()

    XCTAssertEqual(session.state, .awaitingScan)
    XCTAssertEqual(session.submitScan(target.payload), .completed)
  }

  func testCompletedSessionRemainsCompletedAfterFurtherEvents() throws {
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    var session = WakeSession(alarmID: UUID(), target: target)
    session.alarmDidFire()
    XCTAssertEqual(session.submitScan(target.payload), .completed)

    session.alarmDidFire()

    XCTAssertEqual(session.state, .completed)
    XCTAssertEqual(session.submitScan(target.payload), .alreadyCompleted)
    XCTAssertEqual(session.submitScan("wrong code"), .alreadyCompleted)
    XCTAssertEqual(session.state, .completed)
  }

  func testTwoSessionsForSameAlarmProgressIndependently() throws {
    let alarmID = UUID()
    let target = try QRCodeTarget(payload: "WakeLock:kitchen")
    var firstSession = WakeSession(alarmID: alarmID, target: target)
    var secondSession = WakeSession(alarmID: alarmID, target: target)
    firstSession.alarmDidFire()

    XCTAssertEqual(firstSession.submitScan(target.payload), .completed)
    XCTAssertEqual(secondSession.state, .waitingForAlarm)
    XCTAssertEqual(secondSession.submitScan(target.payload), .notReady)

    secondSession.alarmDidFire()

    XCTAssertEqual(secondSession.state, .awaitingScan)
    XCTAssertEqual(firstSession.state, .completed)
  }

  func testChangingConfiguredTargetDoesNotChangeExistingSession() throws {
    var configuredTarget = try QRCodeTarget(payload: "WakeLock:kitchen")
    var session = WakeSession(alarmID: UUID(), target: configuredTarget)
    configuredTarget = try QRCodeTarget(payload: "WakeLock:hallway")
    session.alarmDidFire()

    XCTAssertEqual(session.target.payload, "WakeLock:kitchen")
    XCTAssertEqual(session.submitScan(configuredTarget.payload), .wrongCode)
    XCTAssertEqual(session.submitScan("WakeLock:kitchen"), .completed)
  }
}
