import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SignCapture
import SignReading

@Suite struct PhotoFactsTests {
  func blank(width: Int = 40, height: Int = 30) throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
  }

  @Test func readsTheDayAndThePlace() throws {
    let photo = try #require(SampleSign.photo())
    #expect(photo.facts.width == 1600)
    #expect(photo.facts.height == 1000)
    #expect(photo.facts.takenOn == "2025-09-01")
    #expect(photo.facts.takenAt == Date(timeIntervalSince1970: 1_756_766_520))
    #expect(photo.facts.latitude == 44.857)
    #expect(photo.facts.longitude == -93.29)
    #expect(photo.facts.hasPlace)
  }

  @Test func aPhotoWithoutFactsHasNone() throws {
    let data = try #require(PhotoFile.jpeg(try blank()))
    let photo = try #require(PhotoFile(data: data))
    #expect(photo.facts == PhotoFacts(width: 40, height: 30))
    #expect(!photo.facts.hasPlace)
  }

  @Test func aTurnedPhotoStandsUpright() throws {
    // Stored 40 wide, 30 high, and marked to be turned a quarter (6), as a
    // phone held upright writes it.
    let data = try #require(PhotoFile.jpeg(try blank(), properties: [kCGImagePropertyOrientation: 6]))
    let photo = try #require(PhotoFile(data: data))
    #expect(photo.facts.width == 30)
    #expect(photo.facts.height == 40)
    let image = try #require(photo.image())
    #expect(image.width == 30 && image.height == 40)
    let small = try #require(photo.image(maxPixels: 20))
    #expect(max(small.width, small.height) == 20)
  }

  @Test func halfAPlaceIsNoPlace() {
    let facts = PhotoFacts(properties: [
      kCGImagePropertyPixelWidth: 10, kCGImagePropertyPixelHeight: 10,
      kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 44.0] as [CFString: Any],
    ])
    #expect(facts.latitude == nil && facts.longitude == nil)
  }

  @Test func noOffsetReadsInThisPhonesZone() {
    #expect(PhotoFacts.day("2023:10:22 09:15:00") == "2023-10-22")
    #expect(PhotoFacts.day("0000:00:00 00:00:00") == nil)
    #expect(PhotoFacts.date("2023:10:22 09:15:00", offset: nil) != nil)
    #expect(PhotoFacts.date("2023:10:22 09:15:00", offset: "+00:00") == Date(timeIntervalSince1970: 1_697_966_100))
  }

  @Test func notAPhotoIsNil() {
    #expect(PhotoFile(data: Data("not a photo".utf8)) == nil)
  }
}

/// The sample sign read with Vision, end to end: the boxes land where the
/// numbers were drawn, so the photo's tiles sit on them.
@Suite struct SampleSignReadingTests {
  @Test func readsEveryNumberWhereItIs() async throws {
    let image = try #require(SampleSign.image())
    let read = try await SignReader.photo.numbers(in: image)
    let list = NumberList(read: read)
    #expect(list.numbers.map(\.text) == SampleSign.numbers)
    let seven = try #require(list.numbers.first { $0.text == "7" })
    #expect(seven.why == "Read as 7")
    // EXIT 7B is drawn at 69% across, 20% down.
    let box = try #require(seven.box)
    #expect(box.x > 0.69 && box.maxX < 0.85)
    #expect(box.y > 0.17 && box.maxY < 0.3)
  }

  @Test func aTapReadsTheSpotAgain() async throws {
    let image = try #require(SampleSign.image())
    // The tap lands on 90th St; everything else is already on the list.
    let others = [NormalizedBox(x: 0.12, y: 0.34, width: 0.2, height: 0.08)]
    let found = try await SpotReading.number(near: 0.6, 0.38, in: image, excluding: others)
    #expect(found?.text == "90")
    #expect(found?.why == "Letters dropped")
  }
}
