import Foundation
import WakeLockCore
import XCTest

final class WakePlanPersistenceTests: XCTestCase {
  func testRoundTripPreservesPlanAndProgress() throws {
    let alarmID = UUID()
    var plan = try makePlan(alarmID: alarmID)
    try completeOneSession(in: &plan)
    try completeOneSession(in: &plan)

    let data = try WakePlanJSONCodec.encode(plan)
    let restored = try WakePlanJSONCodec.decode(data)

    XCTAssertEqual(restored.alarmID, alarmID)
    XCTAssertEqual(restored.qrTarget.payload, "wakelock:bathroom")
    XCTAssertEqual(restored.progression.startTime, try WakeTime(hour: 7, minute: 30))
    XCTAssertEqual(restored.progression.targetTime, try WakeTime(hour: 6, minute: 30))
    XCTAssertEqual(restored.progression.stepMinutes, 15)
    XCTAssertEqual(restored.completedSessionIDs, plan.completedSessionIDs)
    XCTAssertEqual(restored.currentWakeTime, try WakeTime(hour: 7, minute: 0))
  }

  func testEncodingIsStableForSamePlan() throws {
    var plan = try makePlan()
    try completeOneSession(in: &plan)
    try completeOneSession(in: &plan)

    XCTAssertEqual(
      try WakePlanJSONCodec.encode(plan),
      try WakePlanJSONCodec.encode(plan)
    )
  }

  func testDecodeRejectsUnsupportedVersion() throws {
    let data = try replacingJSONValue(
      in: WakePlanJSONCodec.encode(try makePlan()),
      key: "version",
      value: 99
    )

    XCTAssertThrowsError(try WakePlanJSONCodec.decode(data)) { error in
      XCTAssertEqual(
        error as? WakePlanSnapshot.RestoreError,
        .unsupportedVersion(99)
      )
    }
  }

  func testDecodeRevalidatesWakeTime() throws {
    let data = try replacingJSONValue(
      in: WakePlanJSONCodec.encode(try makePlan()),
      key: "startHour",
      value: 24
    )

    XCTAssertThrowsError(try WakePlanJSONCodec.decode(data)) { error in
      XCTAssertEqual(error as? WakeTime.ValidationError, .invalidHour)
    }
  }

  func testDecodeRevalidatesQRPayload() throws {
    let data = try replacingJSONValue(
      in: WakePlanJSONCodec.encode(try makePlan()),
      key: "qrPayload",
      value: "   "
    )

    XCTAssertThrowsError(try WakePlanJSONCodec.decode(data)) { error in
      XCTAssertEqual(error as? QRCodeTarget.ValidationError, .emptyPayload)
    }
  }

  func testDecodeRevalidatesProgression() throws {
    let data = try replacingJSONValue(
      in: WakePlanJSONCodec.encode(try makePlan()),
      key: "stepMinutes",
      value: 0
    )

    XCTAssertThrowsError(try WakePlanJSONCodec.decode(data)) { error in
      XCTAssertEqual(error as? WakeProgression.ValidationError, .stepMustBePositive)
    }
  }

  func testFileStoreReturnsNilWhenNoPlanExists() throws {
    let store = try makeFileStore()

    XCTAssertNil(try store.load())
  }

  func testFileStoreCreatesDirectoryAndRoundTripsPlan() throws {
    let store = try makeFileStore(nested: true)
    var plan = try makePlan()
    try completeOneSession(in: &plan)

    try store.save(plan)
    let restored = try XCTUnwrap(store.load())

    XCTAssertEqual(restored.alarmID, plan.alarmID)
    XCTAssertEqual(restored.completedSessionIDs, plan.completedSessionIDs)
    XCTAssertEqual(restored.currentWakeTime, plan.currentWakeTime)
  }

  func testFileStoreOverwritesPreviousSnapshot() throws {
    let store = try makeFileStore()
    var plan = try makePlan()
    try store.save(plan)

    try completeOneSession(in: &plan)
    try store.save(plan)

    let restored = try XCTUnwrap(store.load())
    XCTAssertEqual(restored.completedSessionIDs.count, 1)
    XCTAssertEqual(restored.currentWakeTime, try WakeTime(hour: 7, minute: 15))
  }

  private func makePlan(alarmID: UUID = UUID()) throws -> WakePlan {
    try WakePlan(
      alarmID: alarmID,
      qrTarget: QRCodeTarget(payload: "wakelock:bathroom"),
      progression: WakeProgression(
        startTime: WakeTime(hour: 7, minute: 30),
        targetTime: WakeTime(hour: 6, minute: 30),
        stepMinutes: 15
      )
    )
  }

  private func completeOneSession(in plan: inout WakePlan) throws {
    var session = plan.makeSession()
    session.alarmDidFire()
    XCTAssertEqual(session.submitScan(plan.qrTarget.payload), .completed)

    guard case .recorded = plan.recordCompletion(of: session) else {
      return XCTFail("Expected completion to be recorded")
    }
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

  private func makeFileStore(nested: Bool = false) throws -> WakePlanFileStore {
    let rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("WakeLockCoreTests")
      .appendingPathComponent(UUID().uuidString)
    addTeardownBlock {
      try? FileManager.default.removeItem(at: rootURL)
    }

    let directoryURL =
      nested
      ? rootURL.appendingPathComponent("nested", isDirectory: true)
      : rootURL
    return WakePlanFileStore(
      fileURL: directoryURL.appendingPathComponent("wake-plan.json")
    )
  }
}
