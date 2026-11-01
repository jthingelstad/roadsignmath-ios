import Foundation
import Testing

@testable import SignCapture

@Suite struct DraftTests {
  let drafts = DraftFolder(folder: FileManager.default.temporaryDirectory.appending(path: "drafts-\(UUID().uuidString)"))

  var sample: NumberList {
    var list = NumberList()
    for n in SampleSign.numbers { try! list.add(n) }
    return list
  }

  @Test func keepsThePhotoTheNumbersAndTheMath() throws {
    defer { try? FileManager.default.removeItem(at: drafts.folder) }
    let photo = try #require(SampleSign.photo())
    let numbers = sample
    let way = WayDraft(tiles: numbers.kept, text: "90 − 82 = 8")
    let draft = Draft(source: .sample, takenAt: Date(timeIntervalSince1970: 1_700_000_000), numbers: numbers, way: way)
    try drafts.save(draft, photo: photo.data)

    let back = try #require(drafts.all().first)
    #expect(back == draft)
    #expect(back.solved)
    #expect(back.way?.text == way.text)
    #expect(drafts.photo(of: draft.id) == photo.data)
    #expect(FileManager.default.fileExists(atPath: drafts.thumbnail(of: draft.id).path(percentEncoded: false)))
  }

  @Test func savingAgainKeepsThePhoto() throws {
    defer { try? FileManager.default.removeItem(at: drafts.folder) }
    let photo = try #require(SampleSign.photo())
    var draft = Draft(source: .camera, takenAt: nil, numbers: nil, way: nil)
    try drafts.save(draft, photo: photo.data)
    draft.numbers = sample
    draft.savedAt = .now
    try drafts.save(draft, photo: nil)
    #expect(drafts.all() == [draft])
    #expect(drafts.photo(of: draft.id) == photo.data)
  }

  @Test func newestFirstAndRemoved() throws {
    defer { try? FileManager.default.removeItem(at: drafts.folder) }
    let photo = try #require(SampleSign.photo())
    let older = Draft(savedAt: Date(timeIntervalSince1970: 100), source: .library, takenAt: nil, numbers: nil, way: nil)
    let newer = Draft(savedAt: Date(timeIntervalSince1970: 200), source: .library, takenAt: nil, numbers: nil, way: nil)
    try drafts.save(older, photo: photo.data)
    try drafts.save(newer, photo: photo.data)
    #expect(drafts.all().map(\.id) == [newer.id, older.id])
    drafts.remove(newer.id)
    #expect(drafts.all().map(\.id) == [older.id])
  }

  @Test func aFolderWithNoPhotoOrBrokenJSONIsSkipped() throws {
    defer { try? FileManager.default.removeItem(at: drafts.folder) }
    let broken = drafts.folder.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("{".utf8).write(to: broken.appending(path: "draft.json"))
    try Data([1]).write(to: broken.appending(path: "photo"))
    try drafts.save(Draft(source: .camera, takenAt: nil, numbers: nil, way: nil), photo: nil)
    #expect(drafts.all().isEmpty)
  }

  @Test func anEmptyWayIsNoWay() {
    let draft = Draft(source: .camera, takenAt: nil, numbers: sample, way: WayDraft(tiles: sample.kept))
    #expect(draft.way == nil)
    #expect(!draft.solved)
  }

  @Test func numbersInAFewWords() {
    func text(_ values: [String]) -> String {
      var list = NumberList()
      for n in values { try! list.add(n) }
      return Draft(source: .camera, takenAt: nil, numbers: list, way: nil).numbersText
    }
    #expect(Draft(source: .camera, takenAt: nil, numbers: nil, way: nil).numbersText == "Not read yet")
    #expect(text([]) == "No numbers yet")
    #expect(text(["7"]) == "7")
    #expect(text(["8", "82"]) == "8 and 82")
    #expect(text(["8", "7", "82", "90"]) == "8, 7, 82 and 90")
    #expect(text(SampleSign.numbers) == "8, 7, 82 and 2 more")
  }

  /// Central time, US English, Gregorian: the list's days don't move with
  /// the Mac running the tests.
  var central: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Chicago")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
  }

  /// Friday 2025-10-31, 8 PM Central.
  let now = Date(timeIntervalSince1970: 1_761_958_800)

  func daysBefore(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86_400) }

  @Test func daysInWords() {
    #expect(Draft.day(now, now: now, calendar: central) == "today")
    #expect(Draft.day(daysBefore(1), now: now, calendar: central) == "yesterday")
    #expect(Draft.day(daysBefore(6), now: now, calendar: central) == "Saturday")
    #expect(Draft.day(daysBefore(7), now: now, calendar: central) == "Oct 24")
    #expect(Draft.day(Date(timeIntervalSince1970: 1_755_180_000), now: now, calendar: central) == "Aug 14")
    #expect(Draft.day(Date(timeIntervalSince1970: 1_723_640_400), now: now, calendar: central) == "Aug 14, 2024")
  }

  @Test func aDraftIsKnownByWhereItWasTaken() {
    var draft = Draft(source: .library, takenAt: daysBefore(6), numbers: nil, way: nil, place: "Twin Lakes, MN")
    #expect(draft.heading == "Twin Lakes, MN")
    var list = NumberList()
    for n in ["2", "5", "1"] { try! list.add(n) }
    draft.numbers = list
    #expect(draft.details(now: now, calendar: central) == "Taken Saturday \u{2219} 2, 5 and 1")
  }

  @Test func noPlaceSaysWhereItCameFrom() {
    let photos = Draft(savedAt: daysBefore(1), source: .library, takenAt: nil, numbers: nil, way: nil)
    #expect(photos.heading == "From your photos")
    #expect(photos.details(now: now, calendar: central) == "Saved yesterday \u{2219} no place in the photo")
    // The app's camera never knows the place, so there's nothing to explain.
    let camera = Draft(source: .camera, takenAt: now, numbers: nil, way: nil)
    #expect(camera.heading == "From the camera")
    #expect(camera.details(now: now, calendar: central) == "Taken today")
    #expect(Draft(source: .sample, takenAt: nil, numbers: nil, way: nil).heading == "The sample sign")
  }

  @Test func aDraftSavedBeforePlacesStillReads() throws {
    let old = #"{"id":"8C7B0E35-6D0C-4B2E-9B8A-3F1D2C4E5A6B","savedAt":800000000,"source":"library"}"#
    let draft = try JSONDecoder().decode(Draft.self, from: Data(old.utf8))
    #expect(draft.place == nil)
    #expect(draft.takenOn == nil)
    #expect(draft.heading == "From your photos")
  }

  @Test func takenIsThePhotosOwnDay() {
    // Taken Aug 14 at 23:30 at −05:00, which is Aug 15 in UTC.
    var utc = central
    utc.timeZone = TimeZone(identifier: "UTC")!
    let takenAt = Date(timeIntervalSince1970: 1_755_232_200)
    let draft = Draft(source: .library, takenAt: takenAt, takenOn: "2025-08-14", numbers: nil, way: nil, place: "Ames, IA")
    #expect(draft.details(now: now, calendar: utc).hasPrefix("Taken Aug 14"))
    // Kept before the day was: the clock, in the phone's time zone.
    let older = Draft(source: .library, takenAt: takenAt, numbers: nil, way: nil, place: "Ames, IA")
    #expect(older.details(now: now, calendar: utc).hasPrefix("Taken Aug 15"))
  }
}
