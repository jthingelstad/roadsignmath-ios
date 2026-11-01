import Foundation

// The server counts a text's length as JavaScript does, in UTF-16 code
// units: a letter is 1, most emoji 2, a flag 4, a family emoji 8 or more.
// The app counts and clips the same way, so text it lets through is never
// refused for its length after it has left the phone.

extension String {
  /// This text's length as the server counts it.
  public var serverLength: Int { utf16.count }

  /// As much of this text as fits in `max` of the server's units, cut
  /// between characters, never through one.
  public func clipped(to max: Int) -> String {
    var used = 0
    var end = startIndex
    for index in indices {
      let size = self[index].utf16.count
      if used + size > max { break }
      used += size
      end = self.index(after: index)
    }
    return String(self[..<end])
  }
}

extension APIClient {
  /// The longest name `PATCH /me` takes.
  public static let nameMax = 40
}
