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
}
