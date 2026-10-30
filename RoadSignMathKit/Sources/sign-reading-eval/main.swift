// sign-reading-eval: how well Vision and the number rules read the numbers a
// player used on a sign. See docs/SPIKE.md.
//
//   swift run --package-path RoadSignMathKit sign-reading-eval \
//     --archive <rsm-mediawiki> --microblog <rsm-microblog> --out <folder>
//
// Writes results.json, report.md and gallery.html into --out.

import CoreGraphics
import Foundation
import ImageIO
import SignReading
import SignReadingEval

#if os(macOS)

struct Arguments {
  var archive: URL?
  var microblog: URL?
  var out: URL
  var limit: Int?

  static func parse(_ arguments: [String]) -> Arguments? {
    var values: [String: String] = [:]
    var index = 0
    while index < arguments.count {
      let key = arguments[index]
      guard key.hasPrefix("--"), index + 1 < arguments.count else { return nil }
      values[String(key.dropFirst(2))] = arguments[index + 1]
      index += 2
    }
    guard let out = values["out"], values["archive"] != nil || values["microblog"] != nil else { return nil }
    func folder(_ path: String) -> URL { URL(filePath: path, directoryHint: .isDirectory) }
    return Arguments(
      archive: values["archive"].map(folder), microblog: values["microblog"].map(folder), out: folder(out),
      limit: values["limit"].flatMap(Int.init))
  }
}

guard let arguments = Arguments.parse(Array(CommandLine.arguments.dropFirst())) else {
  FileHandle.standardError.write(
    Data(
      """
      usage: sign-reading-eval [--archive <dir>] [--microblog <dir>] --out <dir> [--limit <n>]
        --archive    the archive: signs/*.md and images/
        --microblog  the micro.blog export: feed.json and uploads/
        --out        where results.json, report.md and gallery.html go
        --limit      read only the first n archive signs (a quick check)

      """.utf8))
  exit(2)
}

func log(_ line: String) {
  FileHandle.standardError.write(Data((line + "\n").utf8))
}

// MARK: - Ground truth

var signs: [EvalSign] = []
var roots: [EvalSign.Era: URL] = [:]
do {
  if let microblog = arguments.microblog {
    let loaded = try MicroblogSigns.load(from: microblog)
    signs += loaded
    roots[.newEra] = microblog
    print("New-era signs: \(loaded.count). Expected numbers, from each post's equation:")
    for sign in loaded {
      let numbers = sign.expected.map { "\($0)" }.joined(separator: ", ")
      print("  \(sign.id) (\(sign.photos.count) photo\(sign.photos.count == 1 ? "" : "s")): [\(numbers)]")
    }
  }
  if let archive = arguments.archive {
    var loaded = try ArchiveSigns.load(from: archive)
    if let limit = arguments.limit { loaded = Array(loaded.prefix(limit)) }
    signs += loaded
    roots[.archive] = archive
    print("Archive signs with numbers and a photo: \(loaded.count)")
  }
} catch {
  log("Couldn't read the ground truth: \(error)")
  exit(1)
}

/// A photo's name relative to its source folder, so no local path is written.
@MainActor func relativeName(_ photo: URL, era: EvalSign.Era) -> String {
  let path = photo.path(percentEncoded: false)
  guard let root = roots[era]?.path(percentEncoded: false), path.hasPrefix(root) else {
    return photo.lastPathComponent
  }
  return String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

// MARK: - Variants

/// One reading of every photo with some Vision options, keeping each pass's
/// lines and time apart so variants with fewer passes come from the same run.
struct ReadingRun: Sendable {
  var key: String
  var options: RecognitionOptions
  var passes: SignReader.Passes
}

let runs: [ReadingRun] = [
  ReadingRun(key: "accurate", options: .photo, passes: .textRegionAndQuarters),
  ReadingRun(key: "accurate-lc", options: RecognitionOptions(usesLanguageCorrection: true), passes: .textRegion),
  ReadingRun(key: "accurate-noup", options: RecognitionOptions(upscalesBelowWidth: nil), passes: .textRegion),
  ReadingRun(key: "fast", options: RecognitionOptions(level: .fast), passes: .textRegion),
]

struct Variant: Sendable {
  var key: String
  var label: String
  var run: ReadingRun
  var passes: SignReader.Passes
  var rules: NumberExtractor.Rules
}

func passCount(_ passes: SignReader.Passes) -> Int {
  switch passes {
  case .whole: 1
  case .textRegion: 2
  case .textRegionAndQuarters: 2 + SignReader.quarters.count
  }
}

let variants: [Variant] = {
  let readings: [(ReadingRun, SignReader.Passes, String)] = [
    (runs[0], .textRegionAndQuarters, "Accurate, text region and quarters"),
    (runs[0], .textRegion, "Accurate, text region"),
    (runs[0], .whole, "Accurate, one pass"),
    (runs[1], .textRegion, "Accurate, text region, language correction on"),
    (runs[1], .whole, "Accurate, one pass, language correction on"),
    (runs[2], .textRegion, "Accurate, text region, no upscaling"),
    (runs[2], .whole, "Accurate, one pass, no upscaling"),
    (runs[3], .whole, "Fast, one pass"),
    (runs[3], .textRegion, "Fast, text region"),
  ]
  return readings.flatMap { run, passes, label in
    NumberExtractor.Rules.allCases.map { rules in
      Variant(
        key: "\(run.key)/\(passes.rawValue)/\(rules.rawValue)",
        label: label + (rules == .signRules ? ", sign rules" : ", digits only"),
        run: run, passes: passes, rules: rules)
    }
  }
}()

// MARK: - Reading

/// A photo upright (its EXIF orientation applied), at full size or at most
/// `maxPixelSize` on its longer side.
func loadImage(_ url: URL, maxPixelSize: Int? = nil) -> CGImage? {
  guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int,
    let height = properties[kCGImagePropertyPixelHeight] as? Int
  else { return nil }
  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize ?? Int.max, max(width, height)),
  ]
  return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

struct PhotoReading: Codable {
  var photo: String
  var width: Int
  var height: Int
  /// Each pass's lines, boxes on the whole photo.
  var passes: [[RecognizedLine]]
  /// Each pass's time.
  var seconds: [Double]
}

var images: [URL: CGImage] = [:]
for sign in signs {
  for photo in sign.photos where images[photo] == nil {
    if let image = loadImage(photo) { images[photo] = image } else { log("Couldn't open \(photo.lastPathComponent)") }
  }
}
let photoCount = images.count
print("Photos: \(photoCount)")

let clock = ContinuousClock()
func seconds(since start: ContinuousClock.Instant) -> Double {
  let elapsed = clock.now - start
  return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
}

/// Lines read per run, per photo.
var readings: [String: [URL: PhotoReading]] = [:]
for run in runs {
  let recognizer = TextRecognizer(options: run.options)
  // Vision loads its models on the first request; keep that out of the times.
  if let first = signs.first?.photos.first, let image = images[first] {
    _ = try? await recognizer.lines(in: image)
  }
  var done: [URL: PhotoReading] = [:]
  for sign in signs {
    for photo in sign.photos where done[photo] == nil {
      guard let image = images[photo] else { continue }
      var regions: [NormalizedBox?] = [nil]
      var passes: [[RecognizedLine]] = []
      var times: [Double] = []
      var index = 0
      while index < regions.count {
        if let region = regions[index], region.area == 0 {
          passes.append([])
          times.append(0)
          index += 1
          continue
        }
        let start = clock.now
        do {
          passes.append(try await recognizer.lines(in: image, region: regions[index]))
        } catch {
          log("\(run.key): couldn't read \(photo.lastPathComponent): \(error)")
          passes.append([])
        }
        times.append(seconds(since: start))
        if index == 0, run.passes != .whole {
          // As SignReader does: the text region, then the quarters.
          // No text found leaves no region: an empty pass stands in.
          regions.append(SignReader.textRegion(of: passes[0]) ?? NormalizedBox(x: 0, y: 0, width: 0, height: 0))
          if run.passes == .textRegionAndQuarters { regions += SignReader.quarters.map { Optional($0) } }
        }
        index += 1
      }
      done[photo] = PhotoReading(
        photo: relativeName(photo, era: sign.era), width: image.width, height: image.height, passes: passes,
        seconds: times)
      if done.count % 25 == 0 { log("\(run.key): \(done.count)/\(photoCount)") }
    }
  }
  readings[run.key] = done
  log("\(run.key): done")
}

// MARK: - Scoring

struct PhotoResult: Codable {
  var photo: String
  var numbers: [ReadNumber]
}

struct SignResult: Codable {
  var id: String
  var era: EvalSign.Era
  var title: String
  var expected: [Decimal]
  var read: [Decimal]
  var hits: Int
  var recall: Double
  var fullHit: Bool
  var extras: Int
  var photos: [PhotoResult]
}

struct VariantResult: Codable {
  var key: String
  var label: String
  var options: RecognitionOptions
  var passes: SignReader.Passes
  var rules: NumberExtractor.Rules
  /// What `SignReader.photo` does: the app's configuration.
  var isShipping: Bool
  var archive: ScoreSummary
  var newEra: ScoreSummary
  var signs: [SignResult]
}

var results: [VariantResult] = []
for variant in variants {
  let reader = SignReader(recognition: variant.run.options, passes: variant.passes, rules: variant.rules)
  let passes = passCount(variant.passes)
  guard let done = readings[variant.run.key] else { continue }
  var signResults: [SignResult] = []
  for sign in signs {
    let photos = sign.photos.compactMap { photo in
      done[photo].map {
        PhotoResult(photo: $0.photo, numbers: reader.numbers(fromPasses: Array($0.passes.prefix(passes))))
      }
    }
    let read = Multiset.union(photos.map { $0.numbers.map(\.value) })
    let score = SignScore(expected: sign.expected, read: read)
    signResults.append(
      SignResult(
        id: sign.id, era: sign.era, title: sign.title, expected: sign.expected, read: read, hits: score.hits,
        recall: score.recall, fullHit: score.isFullHit, extras: score.extras, photos: photos))
  }
  func summary(_ era: EvalSign.Era) -> ScoreSummary {
    let chosen = signs.indices.filter { signs[$0].era == era }
    let scores = chosen.map {
      SignScore(expected: signResults[$0].expected, read: signResults[$0].read)
    }
    let photos = Set(chosen.flatMap { signs[$0].photos })
    return ScoreSummary(scores: scores, seconds: photos.compactMap { done[$0].map { $0.seconds.prefix(passes).reduce(0, +) } })
  }
  results.append(
    VariantResult(
      key: variant.key, label: variant.label, options: variant.run.options, passes: variant.passes,
      rules: variant.rules,
      isShipping: variant.run.options == SignReader.photo.recognition && variant.passes == SignReader.photo.passes
        && variant.rules == SignReader.photo.rules,
      archive: summary(.archive), newEra: summary(.newEra), signs: signResults))
}

// The best variant: most new-era full hits, then new-era recall, then
// archive recall, then the sign rules over digits only (they read the same
// values but say why), then the quicker.
let best = results.max { lhs, rhs in
  func rank(_ result: VariantResult) -> (Int, Double, Double, Int, Double) {
    (
      result.newEra.fullHits, result.newEra.meanRecall, result.archive.meanRecall,
      result.rules == .signRules ? 1 : 0, -result.newEra.meanSecondsPerImage
    )
  }
  return rank(lhs) < rank(rhs)
}!

// MARK: - Output

try FileManager.default.createDirectory(at: arguments.out, withIntermediateDirectories: true)

struct ResultsFile: Codable {
  var generated: Date
  var best: String
  var readings: [String: [PhotoReading]]
  var variants: [VariantResult]
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let resultsFile = ResultsFile(
  generated: Date(), best: best.key,
  readings: readings.mapValues { $0.values.sorted { $0.photo < $1.photo } }, variants: results)
try encoder.encode(resultsFile).write(to: arguments.out.appending(path: "results.json"))

let report = Report.markdown(results: results, best: best, signs: signs)
try Data(report.utf8).write(to: arguments.out.appending(path: "report.md"))
print("")
print(report)

let gallery = Gallery.html(for: best, signs: signs, images: images)
try Data(gallery.utf8).write(to: arguments.out.appending(path: "gallery.html"))
print("Gallery: \(gallery.utf8.count / 1024) KB, variant \(best.key)")

#else
print("sign-reading-eval runs on macOS.")
#endif
