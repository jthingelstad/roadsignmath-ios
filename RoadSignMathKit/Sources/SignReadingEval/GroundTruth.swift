import Foundation

/// A sign the spike scores: its photos and the numbers a player used.
public struct EvalSign: Sendable, Hashable, Codable {
  public enum Era: String, Sendable, Hashable, Codable {
    /// The 2005-2014 archive.
    case archive
    /// The micro.blog signs, 2021-2025.
    case newEra
  }

  public var id: String
  public var era: Era
  public var title: String
  /// The numbers the player used, a multiset.
  public var expected: [Decimal]
  public var photos: [URL]

  public init(id: String, era: Era, title: String, expected: [Decimal], photos: [URL]) {
    self.id = id
    self.era = era
    self.title = title
    self.expected = expected
    self.photos = photos
  }
}

/// The archive's signs: `signs/*.md` with YAML front matter, photos in
/// `images/`. Only the few fields the spike needs are read.
public enum ArchiveSigns {
  public static func load(from archive: URL) throws -> [EvalSign] {
    let signsFolder = archive.appending(path: "signs", directoryHint: .isDirectory)
    let imagesFolder = archive.appending(path: "images", directoryHint: .isDirectory)
    let names = try FileManager.default.contentsOfDirectory(atPath: signsFolder.path(percentEncoded: false))
      .filter { $0.hasSuffix(".md") }
      .sorted()
    return try names.compactMap { name in
      let text = try String(contentsOf: signsFolder.appending(path: name), encoding: .utf8)
      let fields = frontMatter(of: text)
      let expected = numbers(from: fields)
      let photos = images(from: fields).map { imagesFolder.appending(path: $0) }.filter {
        FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
      }
      guard !expected.isEmpty, !photos.isEmpty else { return nil }
      return EvalSign(
        id: String(name.dropLast(3)), era: .archive, title: title(from: fields) ?? String(name.dropLast(3)),
        expected: expected, photos: photos)
    }
  }

  /// The lines between the opening `---` and the next.
  static func frontMatter(of text: String) -> [Substring] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }
    var result: [Substring] = []
    for line in lines.dropFirst() {
      if line.trimmingCharacters(in: .whitespaces) == "---" { break }
      result.append(line)
    }
    return result
  }

  static func title(from lines: [Substring]) -> String? {
    guard let line = lines.first(where: { $0.hasPrefix("title:") }) else { return nil }
    return unquote(line.dropFirst("title:".count))
  }

  /// `numbers: [1, 35, 36]`, or a block list of `- 1` lines. A quoted item
  /// may hold several numbers (`"12 144"`).
  static func numbers(from lines: [Substring]) -> [Decimal] {
    guard let start = lines.firstIndex(where: { $0.hasPrefix("numbers:") }) else { return [] }
    let rest = lines[start].dropFirst("numbers:".count).trimmingCharacters(in: .whitespaces)
    var items: [String] = []
    if rest.hasPrefix("[") {
      items = rest.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map(String.init)
    } else if rest.isEmpty {
      for line in lines[(start + 1)...] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("- ") else { break }
        items.append(String(trimmed.dropFirst(2)))
      }
    } else {
      items = [rest]
    }
    return items.flatMap { item in
      unquote(Substring(item)).split(whereSeparator: { $0 == " " || $0 == "," }).compactMap {
        Decimal(string: String($0), locale: Locale(identifier: "en_US_POSIX"))
      }
    }
  }

  /// The `image:` of each entry under `photos:`.
  static func images(from lines: [Substring]) -> [String] {
    guard let start = lines.firstIndex(where: { $0.hasPrefix("photos:") }) else { return [] }
    var result: [String] = []
    for line in lines[(start + 1)...] {
      guard line.first == " " else { break }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let field = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
      if field.hasPrefix("image:") {
        result.append(unquote(Substring(field.dropFirst("image:".count))))
      }
    }
    return result
  }

  static func unquote(_ value: Substring) -> String {
    var text = value.trimmingCharacters(in: .whitespaces)
    if text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" {
      text = String(text.dropFirst().dropLast())
    }
    return text
  }
}

/// The new-era signs: a micro.blog JSON Feed, each post one `$$...$$`
/// equation and its photos in `uploads/`.
public enum MicroblogSigns {
  struct Feed: Decodable {
    struct Item: Decodable {
      var id: String
      var title: String?
      var url: String?
      var content_text: String?
    }
    var items: [Item]
  }

  public static func load(from microblog: URL) throws -> [EvalSign] {
    let data = try Data(contentsOf: microblog.appending(path: "feed.json"))
    let feed = try JSONDecoder().decode(Feed.self, from: data)
    return feed.items.compactMap { item in
      let text = item.content_text ?? ""
      guard let equation = LatexNumbers.equation(in: text) else { return nil }
      let photos = imageSources(in: text).map { microblog.appending(path: $0) }.filter {
        FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
      }
      guard !photos.isEmpty else { return nil }
      let slug = slug(of: item.url ?? item.id)
      return EvalSign(
        id: slug, era: .newEra, title: item.title ?? untitled(slug),
        expected: LatexNumbers.numbers(in: equation), photos: photos)
    }
  }

  /// `2023/10/21/genesis` from the post's URL.
  static func slug(of url: String) -> String {
    var path = url
    if let range = path.range(of: "://") {
      path = String(path[range.upperBound...])
      if let slash = path.firstIndex(of: "/") { path = String(path[slash...]) }
    }
    if path.hasSuffix(".html") { path = String(path.dropLast(5)) }
    return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  /// A name for a post with no title: "Post of 2025-09-01".
  static func untitled(_ slug: String) -> String {
    let parts = slug.split(separator: "/").prefix(3)
    guard parts.count == 3 else { return slug }
    return "Post of " + parts.joined(separator: "-")
  }

  /// The `src` of each `<img>`, in order.
  static func imageSources(in text: String) -> [String] {
    let regex = try! NSRegularExpression(pattern: #"<img[^>]*\ssrc="([^"]+)""#)
    let string = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: string.length)).map {
      string.substring(with: $0.range(at: 1))
    }
  }
}

/// The numbers in a LaTeX equation, as a player wrote it.
public enum LatexNumbers {
  /// The first `$$...$$` in the text.
  public static func equation(in text: String) -> String? {
    guard let open = text.range(of: "$$"),
      let close = text.range(of: "$$", range: open.upperBound..<text.endIndex)
    else { return nil }
    return String(text[open.upperBound..<close.lowerBound])
  }

  /// The number literals, as a multiset. Commands (`\sqrt`, `\frac`,
  /// `\times`) are dropped, and so are subscripts: `\underbrace{...}_0`
  /// labels a part as 0, which is not a number on the sign.
  public static func numbers(in latex: String) -> [Decimal] {
    var text = latex
    for pattern in [#"_\s*\{[^{}]*\}"#, #"_\s*[0-9A-Za-z]"#, #"\\[A-Za-z]+"#] {
      text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
    }
    let regex = try! NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#)
    let string = text as NSString
    return regex.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap {
      Decimal(string: string.substring(with: $0.range), locale: Locale(identifier: "en_US_POSIX"))
    }
  }
}
