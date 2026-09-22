import Foundation

/// The decoded text of the QR code chosen before an alarm fires.
public struct QRCodeTarget: Sendable {
  public enum ValidationError: Error, Equatable {
    case emptyPayload
  }

  public let payload: String

  public init(payload: String) throws {
    guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ValidationError.emptyPayload
    }

    // Trimming is only for validation. Preserve the chosen code exactly.
    self.payload = payload
  }

  /// Compares decoded text byte-for-byte, including case and whitespace.
  public func matches(_ scannedPayload: String) -> Bool {
    // String equality accepts equivalent Unicode spellings. A QR target
    // should instead require the exact UTF-8 representation we enrolled.
    payload.utf8.elementsEqual(scannedPayload.utf8)
  }
}
