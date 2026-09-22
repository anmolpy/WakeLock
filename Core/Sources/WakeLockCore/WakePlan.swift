import Foundation

/// Connects QR-verified alarm occurrences to a gradual wake-time progression.
public struct WakePlan: Sendable {
  public enum CompletionResult: Equatable, Sendable {
    case recorded(nextWakeTime: WakeTime)
    case incompleteSession
    case differentAlarm
    case alreadyRecorded
  }

  public let alarmID: UUID
  public let qrTarget: QRCodeTarget
  public let progression: WakeProgression
  public private(set) var completedSessionIDs: Set<UUID>

  public init(
    alarmID: UUID,
    qrTarget: QRCodeTarget,
    progression: WakeProgression,
    completedSessionIDs: Set<UUID> = []
  ) {
    self.alarmID = alarmID
    self.qrTarget = qrTarget
    self.progression = progression
    self.completedSessionIDs = completedSessionIDs
  }

  public var currentWakeTime: WakeTime {
    progression.wakeTime(
      forValidatedCompletedSessionCount: completedSessionIDs.count
    )
  }

  public func makeSession(id: UUID = UUID()) -> WakeSession {
    WakeSession(id: id, alarmID: alarmID, target: qrTarget)
  }

  /// Records a verified occurrence exactly once and returns the newly derived
  /// wake time. Persist the plan after `.recorded` before rescheduling AlarmKit.
  public mutating func recordCompletion(of session: WakeSession) -> CompletionResult {
    guard session.alarmID == alarmID else { return .differentAlarm }
    guard session.state == .completed else { return .incompleteSession }
    guard completedSessionIDs.insert(session.id).inserted else {
      return .alreadyRecorded
    }

    return .recorded(nextWakeTime: currentWakeTime)
  }
}
