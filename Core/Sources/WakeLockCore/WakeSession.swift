import Foundation

/// QR verification for one occurrence of an alarm, separate from its sound.
/// Create a new session for each occurrence of a repeating alarm.
public struct WakeSession: Sendable {
  public enum State: Equatable, Sendable {
    case waitingForAlarm
    case awaitingScan
    case completed
  }

  public enum ScanResult: Equatable, Sendable {
    case notReady
    case wrongCode
    case completed
    case alreadyCompleted
  }

  public let id: UUID
  public let alarmID: UUID
  public let target: QRCodeTarget
  public private(set) var state: State = .waitingForAlarm

  public init(id: UUID = UUID(), alarmID: UUID, target: QRCodeTarget) {
    self.id = id
    self.alarmID = alarmID
    self.target = target
  }

  /// Call when the app learns that this alarm occurrence has fired.
  /// Repeated notifications cannot reset an active or completed session.
  public mutating func alarmDidFire() {
    guard state == .waitingForAlarm else { return }
    state = .awaitingScan
  }

  /// Accepts decoded text from the scanner. This does not control AlarmKit
  /// audio or establish that a camera, rather than another caller, supplied it.
  public mutating func submitScan(_ payload: String) -> ScanResult {
    switch state {
    case .waitingForAlarm:
      return .notReady
    case .awaitingScan:
      guard target.matches(payload) else { return .wrongCode }
      state = .completed
      return .completed
    case .completed:
      return .alreadyCompleted
    }
  }
}
