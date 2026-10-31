import CoreGraphics
import Foundation
import ImageIO

/// What a photo says about itself: its size, the day it was taken and where.
/// Read from its metadata, for "place from the photo" when posting. A photo
/// taken in the app has none of this; one picked from the library usually
/// has the day, and the place when the camera kept it.
public struct PhotoFacts: Sendable, Hashable {
  /// The photo's size upright, in pixels.
  public var width: Int
  public var height: Int
  /// The day it was taken, `2025-09-01`, as the camera's clock had it where
  /// it was taken: the API's `found_on`.
  public var takenOn: String?
  /// When it was taken. Exact when the camera wrote its time zone, else
  /// read in this phone's.
  public var takenAt: Date?
  public var latitude: Double?
  public var longitude: Double?

  public init(
    width: Int, height: Int, takenOn: String? = nil, takenAt: Date? = nil, latitude: Double? = nil,
    longitude: Double? = nil
  ) {
    self.width = width
    self.height = height
    self.takenOn = takenOn
    self.takenAt = takenAt
    self.latitude = latitude
    self.longitude = longitude
  }

  /// The photo knows where it was taken.
  public var hasPlace: Bool { latitude != nil && longitude != nil }

  /// The facts in an image's properties, as ImageIO gives them.
  init(properties: [CFString: Any]) {
    let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
    let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    // Orientations 5 to 8 turn the photo a quarter, so it stands the other way.
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    let turned = (5...8).contains(orientation)
    width = turned ? pixelHeight : pixelWidth
    height = turned ? pixelWidth : pixelHeight

    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
    let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String
      ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String
      ?? tiff[kCGImagePropertyTIFFDateTime] as? String
    let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
      ?? exif[kCGImagePropertyExifOffsetTime] as? String
    takenOn = stamp.flatMap(Self.day)
    takenAt = stamp.flatMap { Self.date($0, offset: offset) }

    let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
    latitude = Self.coordinate(gps, kCGImagePropertyGPSLatitude, kCGImagePropertyGPSLatitudeRef, negative: "S", limit: 90)
    longitude = Self.coordinate(gps, kCGImagePropertyGPSLongitude, kCGImagePropertyGPSLongitudeRef, negative: "W", limit: 180)
    if latitude == nil || longitude == nil {
      latitude = nil
      longitude = nil
    }
  }

  /// "2025:09:01 14:22:10" as "2025-09-01".
  static func day(_ stamp: String) -> String? {
    guard let match = stamp.wholeMatch(of: /(\d{4}):(\d{2}):(\d{2})[ T].*/),
      let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
      year > 1900, (1...12).contains(month), (1...31).contains(day)
    else { return nil }
    return "\(match.1)-\(match.2)-\(match.3)"
  }

  /// "2025:09:01 14:22:10" with "-05:00", or in this phone's time zone.
  static func date(_ stamp: String, offset: String?) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    if let offset, offset.wholeMatch(of: /[+-]\d{2}:\d{2}/) != nil {
      formatter.dateFormat = "yyyy:MM:dd HH:mm:ssxxx"
      return formatter.date(from: String(stamp.prefix(19)) + offset)
    }
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter.date(from: String(stamp.prefix(19)))
  }

  static func coordinate(
    _ gps: [CFString: Any], _ key: CFString, _ refKey: CFString, negative: String, limit: Double
  ) -> Double? {
    guard let raw = (gps[key] as? NSNumber)?.doubleValue, raw.isFinite, abs(raw) <= limit else { return nil }
    let ref = (gps[refKey] as? String)?.uppercased()
    return ref == negative ? -abs(raw) : raw
  }
}

/// A photo as the player gave it: the file the camera made or the library
/// handed over, kept as it is (step 2.5 makes the sizes to post, without
/// the metadata), with its facts and an upright picture to read and show.
public struct PhotoFile: Sendable {
  public let data: Data
  public let facts: PhotoFacts

  /// Nil when ImageIO can't read it as an image.
  public init?(data: Data) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return nil }
    let facts = PhotoFacts(properties: properties)
    guard facts.width > 0, facts.height > 0 else { return nil }
    self.data = data
    self.facts = facts
  }

  /// The photo upright (its orientation applied), no larger than
  /// `maxPixels` on its long side; at full size without one.
  public func image(maxPixels: Int? = nil) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let longSide = max(facts.width, facts.height)
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: min(maxPixels ?? longSide, longSide),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  /// A picture as a JPEG file, with only the facts given: for the sample
  /// sign and for tests.
  public static func jpeg(_ image: CGImage, quality: Double = 0.9, properties: [CFString: Any] = [:]) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
      return nil
    }
    var all = properties
    all[kCGImageDestinationLossyCompressionQuality] = quality
    CGImageDestinationAddImage(destination, image, all as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
