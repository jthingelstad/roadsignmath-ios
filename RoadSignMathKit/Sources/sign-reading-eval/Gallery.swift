import CoreGraphics
import Foundation
import ImageIO
import SignReading
import SignReadingEval
import UniformTypeIdentifiers

/// gallery.html: every photo with a box on each number read, green where the
/// player used it, yellow where they didn't. One self-contained page.
enum Gallery {
  static let maxWidth = 800
  static let byteBudget = 11_500_000

  static func html(
    for variant: VariantResult, signs: [EvalSign], images: [URL: CGImage]
  ) -> String {
    // New-era signs in feed order, then the archive, worst recall first.
    let order = variant.signs.indices.sorted { lhs, rhs in
      let a = variant.signs[lhs]
      let b = variant.signs[rhs]
      if a.era != b.era { return a.era == .newEra }
      if a.era == .newEra { return lhs < rhs }
      if a.recall != b.recall { return a.recall < b.recall }
      return a.id < b.id
    }
    var page = ""
    for quality in [0.72, 0.6, 0.5, 0.4] {
      page = render(variant: variant, signs: signs, order: order, images: images, quality: quality)
      if page.utf8.count <= byteBudget { break }
    }
    return page
  }

  static func render(
    variant: VariantResult, signs: [EvalSign], order: [Int], images: [URL: CGImage], quality: Double
  ) -> String {
    var cards = ""
    var lastEra: EvalSign.Era?
    for index in order {
      let result = variant.signs[index]
      let sign = signs[index]
      if result.era != lastEra {
        cards += result.era == .newEra
          ? "<h2>New-era signs (2021-2025)</h2>\n"
          : "<h2>Archive signs (2005-2014), worst recall first</h2>\n<p class=note>The archive lists only the numbers the old rules allowed, so yellow boxes here are often real numbers on the sign.</p>\n"
        lastEra = result.era
      }
      cards += card(result: result, sign: sign, images: images, quality: quality)
    }
    let summary = "\(variant.newEra.fullHits) of \(variant.newEra.signs) new-era signs and "
      + "\(variant.archive.fullHits) of \(variant.archive.signs) archive signs had every number read."
    return """
      <!doctype html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Sign Reading Gallery</title>
      <style>
      :root { --bg: #fbfaf7; --fg: #1d1d1b; --muted: #6b6a66; --card: #ffffff; --line: #e4e1da;
        --hit: #1f9d55; --extra: #e0a800; --miss: #c8372d; }
      @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #161615; --fg: #ecebe6;
        --muted: #a3a29c; --card: #20201e; --line: #34332f; } }
      :root[data-theme="dark"] { --bg: #161615; --fg: #ecebe6; --muted: #a3a29c; --card: #20201e; --line: #34332f; }
      * { box-sizing: border-box; }
      body { margin: 0; padding: 16px; background: var(--bg); color: var(--fg);
        font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      main { max-width: 860px; margin: 0 auto; }
      h1 { font-size: 1.5rem; margin: 0 0 .25rem; }
      h2 { font-size: 1.15rem; margin: 2rem 0 .5rem; }
      p { margin: .25rem 0 .75rem; }
      .note, .meta { color: var(--muted); font-size: .9rem; }
      .card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 12px;
        margin: 0 0 16px; }
      .card h3 { font-size: 1rem; margin: 0 0 .25rem; }
      .row { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; margin: .35rem 0; }
      .row b { font-weight: 600; min-width: 4.5rem; font-size: .85rem; color: var(--muted); }
      .chip { border-radius: 999px; padding: 1px 9px; font-size: .85rem; border: 1.5px solid var(--line); }
      .chip.hit { border-color: var(--hit); }
      .chip.extra { border-color: var(--extra); }
      .chip.miss { border-color: var(--miss); color: var(--miss); text-decoration: line-through; }
      .photo { position: relative; margin: 8px 0 0; max-width: 100%; }
      .photo img { display: block; width: 100%; height: auto; border-radius: 6px; }
      .photo svg { position: absolute; inset: 0; width: 100%; height: 100%; }
      .photo rect { fill: none; stroke-width: 3; vector-effect: non-scaling-stroke; }
      .photo rect.hit { stroke: var(--hit); }
      .photo rect.extra { stroke: var(--extra); }
      .legend span { display: inline-block; width: .8em; height: .8em; border: 2px solid; margin: 0 .3em 0 .8em;
        vertical-align: -1px; }
      </style>
      </head>
      <body>
      <main>
      <h1>Sign reading gallery</h1>
      <p>\(escape(variant.label)). \(summary)</p>
      <p class="legend note"><span style="border-color: var(--hit)"></span>read, and the player used it
      <span style="border-color: var(--extra)"></span>read, not used
      <span style="border-color: var(--miss)"></span>used, not read (struck through)</p>
      \(cards)
      </main>
      </body>
      </html>

      """
  }

  static func card(result: SignResult, sign: EvalSign, images: [URL: CGImage], quality: Double) -> String {
    var expectedLeft = Multiset(result.read)
    let expectedChips = result.expected.map { value in
      let hit = expectedLeft.remove(value)
      return "<span class=\"chip \(hit ? "hit" : "miss")\">\(value)</span>"
    }.joined(separator: " ")

    var photos = ""
    var readChips: [String] = []
    for (photo, photoResult) in zip(sign.photos, result.photos) {
      var left = Multiset(result.expected)
      var rects = ""
      guard let image = images[photo], let encoded = jpeg(image, quality: quality) else { continue }
      for number in photoResult.numbers {
        let kind = left.remove(number.value) ? "hit" : "extra"
        let box = number.box
        let w = Double(encoded.width)
        let h = Double(encoded.height)
        rects += String(
          format: "<rect class=\"%@\" x=\"%.1f\" y=\"%.1f\" width=\"%.1f\" height=\"%.1f\"><title>%@</title></rect>",
          kind, box.x * w, box.y * h, box.width * w, box.height * h,
          escape("\(number.text): \(number.why) (\(number.sourceText))"))
        readChips.append(
          "<span class=\"chip \(kind)\" title=\"\(escape(number.why + ", from " + number.sourceText))\">"
            + "\(escape(number.text))</span>")
      }
      photos += """
        <figure class="photo"><img alt="Photo of the \(escape(result.title)) sign" width="\(encoded.width)" \
        height="\(encoded.height)" src="data:image/jpeg;base64,\(encoded.data.base64EncodedString())">\
        <svg viewBox="0 0 \(encoded.width) \(encoded.height)" preserveAspectRatio="none" aria-hidden="true">\(rects)</svg></figure>

        """
    }
    let recall = "\(result.hits) of \(result.expected.count) read"
    return """
      <section class="card"><h3>\(escape(result.title))</h3>
      <p class="meta">\(escape(result.id)) · \(recall)\(result.extras > 0 ? " · \(result.extras) extra" : "")</p>
      <div class="row"><b>Used</b> \(expectedChips)</div>
      <div class="row"><b>Read</b> \(readChips.isEmpty ? "<span class=note>nothing</span>" : readChips.joined(separator: " "))</div>
      \(photos)</section>

      """
  }

  struct Encoded {
    var data: Data
    var width: Int
    var height: Int
  }

  /// The photo as a JPEG at most `maxWidth` wide.
  static func jpeg(_ image: CGImage, quality: Double) -> Encoded? {
    var output = image
    if image.width > maxWidth {
      let height = Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded())
      guard let smaller = ImageScaling.resized(image, width: maxWidth, height: height) else { return nil }
      output = smaller
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(
      destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return Encoded(data: data as Data, width: output.width, height: output.height)
  }

  static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
