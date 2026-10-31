import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Posting
import RoadSignMathAPI
import SignCapture
import SignReading

/// A post's parts from what Capture kept: the photo to send, the numbers,
/// the state, a title and the finders.
@Suite struct PostPartsTests {
  @Test func thePhotoGoesWithoutItsPlace() throws {
    // The sample sign carries a made-up GPS spot and day, as a phone's
    // photo would.
    let sample = try #require(SampleSign.photo())
    #expect(sample.facts.hasPlace)
    let data = try #require(PostParts.photo(sample))
    #expect(data.count <= APIClient.photoBytes)
    let sent = try #require(PhotoFile(data: data))
    #expect(!sent.facts.hasPlace)
    #expect(sent.facts.takenOn == nil)
    #expect(sent.facts.width == 1600 && sent.facts.height == 1000)
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    #expect(properties[kCGImagePropertyTIFFDictionary] == nil)
  }

  @Test func aBigPhotoIsMadeSmaller() throws {
    let big = try #require(SampleSign.image(width: 4000, height: 3000))
    let jpeg = try #require(PhotoFile.jpeg(big))
    let file = try #require(PhotoFile(data: jpeg))
    let data = try #require(PostParts.photo(file))
    let sent = try #require(PhotoFile(data: data))
    #expect(max(sent.facts.width, sent.facts.height) == 2048)
  }

  @Test func numbersSayWhereTheyCameFrom() throws {
    let exit = ReadNumber(
      value: 7, text: "7", sourceText: "EXIT 7B", reason: .lettersDropped,
      box: NormalizedBox(x: 0.7, y: 0.18, width: 0.08, height: 0.05))
    let plain = ReadNumber(
      value: 82, text: "82", sourceText: "82", reason: .readFromPhoto, box: NormalizedBox(x: 0.97, y: 0.98, width: 0.06, height: 0.05))
    var list = NumberList(read: [exit, plain])
    _ = try list.add("1/2")
    let numbers = PostParts.numbers(list.kept)
    #expect(numbers.count == 3)
    let byValue = Dictionary(uniqueKeysWithValues: numbers.map { ($0.value, $0) })
    #expect(byValue["7"] == PostNumber(value: "7", text: "EXIT 7B", why: "Letters dropped", box: [0.7, 0.18, 0.08, 0.05]))
    // A box that runs off the edge is kept inside it, as the server checks.
    let edge = try #require(byValue["82"])
    #expect(edge.text == nil && edge.why == nil)
    let box = try #require(edge.box)
    #expect(box[0] + box[2] <= 1 && box[1] + box[3] <= 1)
    // A typed fraction keeps its form, with its value as the number.
    #expect(byValue["0.5"] == PostNumber(value: "0.5", text: "1/2", why: nil, box: nil))
  }

  @Test func unkeptNumbersStayOff() throws {
    var list = NumberList(read: [ReadNumber(value: 8, text: "8", sourceText: "8", reason: .readFromPhoto)])
    _ = try list.add("9")
    list.setKept(false, for: list.numbers[0].id)
    #expect(PostParts.numbers(list.kept).map(\.value) == ["9"])
  }

  @Test func theStateIsTheLabelsLastPart() {
    #expect(PostParts.state(in: "Bloomington, MN") == "MN")
    #expect(PostParts.state(in: "Phoenix, AZ") == "AZ")
    #expect(PostParts.state(in: "Toronto, Ontario") == nil)
    #expect(PostParts.state(in: "Paris") == nil)
    #expect(PostParts.state(in: "Ames, ia") == nil)
  }

  @Test func aTitleFromTheTown() {
    #expect(PostParts.title(near: "Bloomington, MN") == "Bloomington Math")
    #expect(PostParts.title(near: nil) == nil)
    #expect(PostParts.title(near: " ") == nil)
  }

  @Test func aloneThePosterFoundIt() {
    #expect(PostParts.finders(poster: "zoe", spotters: [], players: []) == nil)
    #expect(PostParts.finders(poster: "zoe", spotters: ["  ", ""], players: []) == nil)
  }

  @Test func withOthersThePosterTookThePhoto() {
    let finders = PostParts.finders(poster: "zoe", spotters: ["Tyler", "@Jamie", "@nobody", "tyler", "@zoe"], players: ["jamie", "zoe"])
    #expect(
      finders == [
        .player("zoe", .tookPhoto), .named("Tyler", .spotted), .player("jamie", .spotted), .named("@nobody", .spotted),
      ])
  }

  @Test func findersStopAtSix() {
    let finders = PostParts.finders(poster: "zoe", spotters: (1...9).map { "Friend \($0)" }, players: [])
    #expect(finders?.count == APIClient.findersMax)
  }
}
