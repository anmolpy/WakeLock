import Foundation

/// Versioned JSON representation of the durable parts of a wake plan.
/// Runtime-only values, such as an in-progress camera scan, are not included.
public struct WakePlanSnapshot: Codable, Equatable, Sendable {
  public enum RestoreError: Error, Equatable {
    case unsupportedVersion(Int)
  }

  public static let currentVersion = 1

  public let version: Int
  public let alarmID: UUID
  public let qrPayload: String
  public let startHour: Int
  public let startMinute: Int
  public let targetHour: Int
  public let targetMinute: Int
  public let stepMinutes: Int
  public let completedSessionIDs: [UUID]

  public init(plan: WakePlan) {
    version = Self.currentVersion
    alarmID = plan.alarmID
    qrPayload = plan.qrTarget.payload
    startHour = plan.progression.startTime.hour
    startMinute = plan.progression.startTime.minute
    targetHour = plan.progression.targetTime.hour
    targetMinute = plan.progression.targetTime.minute
    stepMinutes = plan.progression.stepMinutes
    completedSessionIDs = plan.completedSessionIDs.sorted {
      $0.uuidString < $1.uuidString
    }
  }

  public func restorePlan() throws -> WakePlan {
    guard version == Self.currentVersion else {
      throw RestoreError.unsupportedVersion(version)
    }

    return try WakePlan(
      alarmID: alarmID,
      qrTarget: QRCodeTarget(payload: qrPayload),
      progression: WakeProgression(
        startTime: WakeTime(hour: startHour, minute: startMinute),
        targetTime: WakeTime(hour: targetHour, minute: targetMinute),
        stepMinutes: stepMinutes
      ),
      completedSessionIDs: Set(completedSessionIDs)
    )
  }
}

public enum WakePlanJSONCodec {
  public static func encode(_ plan: WakePlan) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(WakePlanSnapshot(plan: plan))
  }

  public static func decode(_ data: Data) throws -> WakePlan {
    let snapshot = try JSONDecoder().decode(WakePlanSnapshot.self, from: data)
    return try snapshot.restorePlan()
  }
}

/// A small file-backed store suitable for an app-support directory supplied by
/// the iOS app. Writes are atomic so an interrupted save does not leave partial
/// JSON at the destination.
public struct WakePlanFileStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> WakePlan? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }

    return try WakePlanJSONCodec.decode(Data(contentsOf: fileURL))
  }

  public func save(_ plan: WakePlan) throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try WakePlanJSONCodec.encode(plan).write(to: fileURL, options: .atomic)
  }
}

/// Versioned representation of one alarm occurrence's verification state.
public struct WakeSessionSnapshot: Codable, Equatable, Sendable {
  public enum PersistedState: String, Codable, Sendable {
    case waitingForAlarm
    case awaitingScan
    case completed
  }

  public enum RestoreError: Error, Equatable {
    case unsupportedVersion(Int)
  }

  public static let currentVersion = 1

  public let version: Int
  public let id: UUID
  public let alarmID: UUID
  public let qrPayload: String
  public let state: PersistedState

  public init(session: WakeSession) {
    version = Self.currentVersion
    id = session.id
    alarmID = session.alarmID
    qrPayload = session.target.payload
    state =
      switch session.state {
      case .waitingForAlarm: .waitingForAlarm
      case .awaitingScan: .awaitingScan
      case .completed: .completed
      }
  }

  public func restoreSession() throws -> WakeSession {
    guard version == Self.currentVersion else {
      throw RestoreError.unsupportedVersion(version)
    }

    let target = try QRCodeTarget(payload: qrPayload)
    var session = WakeSession(id: id, alarmID: alarmID, target: target)

    switch state {
    case .waitingForAlarm:
      break
    case .awaitingScan:
      session.alarmDidFire()
    case .completed:
      session.alarmDidFire()
      _ = session.submitScan(target.payload)
    }

    return session
  }
}

public enum WakeSessionJSONCodec {
  public static func encode(_ session: WakeSession) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(WakeSessionSnapshot(session: session))
  }

  public static func decode(_ data: Data) throws -> WakeSession {
    let snapshot = try JSONDecoder().decode(WakeSessionSnapshot.self, from: data)
    return try snapshot.restoreSession()
  }
}

public struct WakeSessionFileStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() throws -> WakeSession? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return nil
    }

    return try WakeSessionJSONCodec.decode(Data(contentsOf: fileURL))
  }

  public func save(_ session: WakeSession) throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    try WakeSessionJSONCodec.encode(session).write(to: fileURL, options: .atomic)
  }
}
