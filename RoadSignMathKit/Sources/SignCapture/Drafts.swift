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
  /// The day it was taken where it was taken, `2025-08-14`: a library
  /// photo's own day, the one posting uses, which the phone's time zone
  /// can't move. Nil for drafts saved before it was kept.
  public var takenOn: String?
  /// The numbers as checked. Nil when it was saved before its reading
  /// finished, so opening it reads the photo again.
  public var numbers: NumberList?
  /// The math as far as it got on Solve.
  public var way: WayDraft?
  /// The town at the photo's own GPS spot, `Twin Lakes, MN`, looked up
  /// once it was saved. Nil when the photo doesn't say where (the app's
  /// own camera never does) or it couldn't be looked up yet. Drafts saved
  /// before it was kept read as nil.
  public var place: String?

  public init(
    id: UUID = UUID(), savedAt: Date = .now, source: Source, takenAt: Date?, takenOn: String? = nil, numbers: NumberList?,
    way: WayDraft?, place: String? = nil
  ) {
    self.id = id
    self.savedAt = savedAt
    self.source = source
    self.takenAt = takenAt
    self.takenOn = takenOn
    self.numbers = numbers
    self.way = way.flatMap { $0.isEmpty ? nil : $0 }
    self.place = place
  }

  /// What the list calls it: where it was taken, else where it came from.
  public var heading: String {
    if let place, !place.isEmpty { return place }
    switch source {
    case .library: return "From your photos"
    case .camera: return "From the camera"
    case .sample: return "The sample sign"
    }
  }

  /// The line under it: when it was taken (or saved, when the photo
  /// doesn't say) and its numbers, "Taken Saturday ∙ 2, 5 and 1". A photo
  /// from the library with no place says so instead of numbers not read.
  public func details(now: Date = .now, calendar: Calendar = .current) -> String {
    let taken = takenOn.flatMap { Self.noon(of: $0, calendar: calendar) } ?? takenAt
    var parts = [taken.map { "Taken " + Self.day($0, now: now, calendar: calendar) }
      ?? "Saved " + Self.day(savedAt, now: now, calendar: calendar)]
    if let numbers, !numbers.kept.isEmpty {
      parts.append(numbersText)
    } else if place == nil, source == .library {
      parts.append("no place in the photo")
    }
    return parts.joined(separator: " \u{2219} ")
  }

  /// Midday of `2025-08-14` in `calendar`, so the day reads as itself
  /// wherever the phone is.
  static func noon(of day: String, calendar: Calendar) -> Date? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
  }

  /// "today", "yesterday", the weekday within the week ("Saturday"), the
  /// day this year ("Aug 14") and the day with its year before that.
  public static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
    let start = calendar.startOfDay(for: now)
    let then = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: then, to: start).day ?? 0
    var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: calendar.locale ?? .current, calendar: calendar,
                                 timeZone: calendar.timeZone)
    switch days {
    case 0: return "today"
    case 1: return "yesterday"
    case 2...6:
      style = style.weekday(.wide)
    default:
      style = style.month(.abbreviated).day()
      if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
    }
    return date.formatted(style)
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
