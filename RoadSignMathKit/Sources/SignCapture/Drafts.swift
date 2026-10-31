import Foundation

/// A sign saved for later: the photo of a sign that looked hopeful, and as
/// far as the player got with it (the numbers checked, the math begun), to
/// pick up and solve another day. Drafts stay on the phone.
public struct Draft: Codable, Sendable, Hashable, Identifiable {
  public enum Source: String, Codable, Sendable { case camera, library, sample }

  public let id: UUID
  public var savedAt: Date
  public var source: Source
  /// When the photo was taken: the shutter, or the library photo's clock.
  public var takenAt: Date?
  /// The numbers as checked. Nil when it was saved before its reading
  /// finished, so opening it reads the photo again.
  public var numbers: NumberList?
  /// The math as far as it got on Solve.
  public var way: WayDraft?

  public init(
    id: UUID = UUID(), savedAt: Date = .now, source: Source, takenAt: Date?, numbers: NumberList?, way: WayDraft?
  ) {
    self.id = id
    self.savedAt = savedAt
    self.source = source
    self.takenAt = takenAt
    self.numbers = numbers
    self.way = way.flatMap { $0.isEmpty ? nil : $0 }
  }

  /// The math works.
  public var solved: Bool { way?.status.works == true }

  /// The kept numbers in a few words: "8, 82 and 90", "8, 82, 90 and 3
  /// more", "No numbers yet", "Not read yet".
  public var numbersText: String {
    guard let numbers else { return "Not read yet" }
    let shown = numbers.kept.map(\.text)
    switch shown.count {
    case 0: return "No numbers yet"
    case 1: return shown[0]
    case 2...4: return shown.dropLast().joined(separator: ", ") + " and " + shown.last!
    default: return shown.prefix(3).joined(separator: ", ") + " and \(shown.count - 3) more"
    }
  }
}

/// The drafts on this phone, a folder each: `draft.json`, the photo as it
/// was taken (with its own day and place, for posting) and a small
/// `thumb.jpg` for the list. Kept in Application Support, so they go with
/// the phone's backup.
public struct DraftFolder: Sendable {
  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  /// `Application Support/Drafts`.
  public static var standard: DraftFolder {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return DraftFolder(folder: support.appending(path: "Drafts", directoryHint: .isDirectory))
  }

  /// Saves a draft. `photo` is the photo's file, given the first time;
  /// nil keeps the one already saved.
  public func save(_ draft: Draft, photo: Data?) throws {
    let place = folder(of: draft.id)
    try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true)
    if let photo {
      try photo.write(to: place.appending(path: "photo"), options: .atomic)
      if let file = PhotoFile(data: photo), let small = file.image(maxPixels: 360),
        let thumb = PhotoFile.jpeg(small, quality: 0.8)
      {
        try thumb.write(to: thumbnail(of: draft.id), options: .atomic)
      }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    try encoder.encode(draft).write(to: place.appending(path: "draft.json"), options: .atomic)
  }

  /// Every draft with its photo, last saved first.
  public func all() -> [Draft] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
    let decoder = JSONDecoder()
    return names.compactMap { name -> Draft? in
      let place = folder.appending(path: name, directoryHint: .isDirectory)
      guard FileManager.default.fileExists(atPath: place.appending(path: "photo").path(percentEncoded: false)),
        let data = try? Data(contentsOf: place.appending(path: "draft.json"))
      else { return nil }
      return try? decoder.decode(Draft.self, from: data)
    }
    .sorted { $0.savedAt > $1.savedAt }
  }

  public func photo(of id: UUID) -> Data? {
    try? Data(contentsOf: folder(of: id).appending(path: "photo"))
  }

  public func thumbnail(of id: UUID) -> URL {
    folder(of: id).appending(path: "thumb.jpg")
  }

  public func remove(_ id: UUID) {
    try? FileManager.default.removeItem(at: folder(of: id))
  }

  private func folder(of id: UUID) -> URL {
    folder.appending(path: id.uuidString, directoryHint: .isDirectory)
  }
}
