import Foundation
import WakeLockCore
import XCTest

final class WakeSessionPersistenceTests: XCTestCase {
  func testRoundTripsWaitingSession() throws {
    let session = try makeSession()

    let restored = try roundTrip(session)

    assertSameIdentity(restored, session)
    XCTAssertEqual(restored.state, .waitingForAlarm)
  }

  func testRoundTripsSessionAwaitingScan() throws {
    var session = try makeSession()
    session.alarmDidFire()

    let restored = try roundTrip(session)

    assertSameIdentity(restored, session)
    XCTAssertEqual(restored.state, .awaitingScan)
  }

  func testRoundTripsCompletedSession() throws {
    var session = try makeSession()
    session.alarmDidFire()
    XCTAssertEqual(session.submitScan(session.target.payload), .completed)

    var restored = try roundTrip(session)

    assertSameIdentity(restored, session)
    XCTAssertEqual(restored.state, .completed)
    XCTAssertEqual(restored.submitScan(session.target.payload), .alreadyCompleted)
  }

  func testDecodeRevalidatesQRPayload() throws {
    let session = try makeSession()
    let data = try replacingJSONValue(
      in: WakeSessionJSONCodec.encode(session),
      key: "qrPayload",
      value: "\n"
    )

    XCTAssertThrowsError(try WakeSessionJSONCodec.decode(data)) { error in
      XCTAssertEqual(error as? QRCodeTarget.ValidationError, .emptyPayload)
    }
  }

  func testDecodeRejectsUnsupportedVersion() throws {
    let session = try makeSession()
    let data = try replacingJSONValue(
      in: WakeSessionJSONCodec.encode(session),
      key: "version",
      value: 2
    )

    XCTAssertThrowsError(try WakeSessionJSONCodec.decode(data)) { error in
      XCTAssertEqual(
        error as? WakeSessionSnapshot.RestoreError,
        .unsupportedVersion(2)
      )
    }
  }

  func testFileStoreRoundTripsActiveSession() throws {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("WakeLockCoreTests")
      .appendingPathComponent(UUID().uuidString)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: rootURL)
    }
    let store = WakeSessionFileStore(
      fileURL: rootURL.appendingPathComponent("active-session.json")
    )
    var session = try makeSession()
    session.alarmDidFire()

    XCTAssertNil(try store.load())
    try store.save(session)

    let restored = try XCTUnwrap(store.load())
    assertSameIdentity(restored, session)
    XCTAssertEqual(restored.state, .awaitingScan)
  }

  private func makeSession() throws -> WakeSession {
    WakeSession(
      id: UUID(),
      alarmID: UUID(),
      target: try QRCodeTarget(payload: "wakelock:bathroom")
    )
  }

  private func roundTrip(_ session: WakeSession) throws -> WakeSession {
    try WakeSessionJSONCodec.decode(WakeSessionJSONCodec.encode(session))
  }

  private func assertSameIdentity(
    _ lhs: WakeSession,
    _ rhs: WakeSession,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(lhs.id, rhs.id, file: file, line: line)
    XCTAssertEqual(lhs.alarmID, rhs.alarmID, file: file, line: line)
    XCTAssertEqual(lhs.target.payload, rhs.target.payload, file: file, line: line)
  }

  private func replacingJSONValue(
    in data: Data,
    key: String,
    value: Any
  ) throws -> Data {
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    object[key] = value
    return try JSONSerialization.data(withJSONObject: object)
  }
}
