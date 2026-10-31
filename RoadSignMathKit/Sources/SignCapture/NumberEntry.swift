import Foundation
import SignReading

/// A number the player types on "Check the numbers", to fix one the photo
/// was misread as or to add one it missed. It goes through the same number
/// rules as the photo, so `7B` is 7, `82nd` is 82, `12,000` is 12000 and
/// `1/2` is a half, and anything else is said plainly.
public enum NumberEntry {
  /// The longest entry taken: no sign number is longer.
  public static let maxLength = 16

  public enum Problem: Error, Sendable, Hashable {
    case empty
    case notANumber
    case moreThanOne
    case tooLong

    /// Said under the field.
    public var message: String {
      switch self {
      case .empty: "Type the number as the sign shows it."
      case .notANumber: "That isn’t a number we can read."
      case .moreThanOne: "That’s more than one number. Add them one at a time."
      case .tooLong: "That’s longer than any number on a sign."
      }
    }
  }

  public struct Entry: Sendable, Hashable {
    public var value: Decimal
    /// The number as it will show: `7`, `1/2`, `12,000`.
    public var text: String
  }

  public static func parse(_ typed: String) throws(Problem) -> Entry {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw .empty }
    guard trimmed.count <= maxLength else { throw .tooLong }
    let found = NumberExtractor().numbers(inText: trimmed)
    guard let first = found.first else { throw .notANumber }
    guard found.count == 1 else { throw .moreThanOne }
    return Entry(value: first.value, text: first.text)
  }
}
