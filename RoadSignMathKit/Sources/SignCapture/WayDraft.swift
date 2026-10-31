import Equation
import Foundation

/// The math being written on Solve: the sign's numbers, placed by tapping
/// their tiles, and the keypad's keys, in order. Each tile is one of the
/// sign's kept numbers and goes in at most once, so a number the sign shows
/// twice can be used twice and never a third time. The equation checker
/// reads `text`; nothing here decides what's true.
public struct WayDraft: Sendable, Hashable {
  /// The keypad. There are no digits: the math uses the sign's numbers, and
  /// a number the reading missed is added on Check the numbers.
  public enum Key: String, CaseIterable, Sendable, Hashable {
    case open = "("
    case close = ")"
    case root = "√"
    case power = "^"
    case factorial = "!"
    case add = "+"
    case subtract = "−"
    case multiply = "×"
    case divide = "÷"
    case equals = "="

    /// What VoiceOver says for the key.
    public var spoken: String {
      switch self {
      case .open: "Open bracket"
      case .close: "Close bracket"
      case .root: "Square root"
      case .power: "To the power of"
      case .factorial: "Factorial"
      case .add: "Plus"
      case .subtract: "Minus"
      case .multiply: "Times"
      case .divide: "Divided by"
      case .equals: "Equals"
      }
    }

    /// A key after which the math needs something more.
    var wantsMore: Bool {
      switch self {
      case .close, .factorial: false
      default: true
      }
    }
  }

  public enum Piece: Sendable, Hashable {
    /// A tile, by its number's id, with the value the checker reads.
    case number(CheckedNumber.ID, String)
    case key(Key)
  }

  /// How the math reads so far, for the line under it.
  public enum Status: Sendable, Hashable {
    /// Nothing written.
    case empty
    /// Unfinished: an operator or bracket waits for what comes next.
    case writing
    /// One side, and what it comes to so far (nil when it can't be worked
    /// out, as when something is divided by zero).
    case oneSide(String?)
    /// Two sides or more that aren't equal yet: each side's value.
    case notTrue([String])
    /// Something the checker can't take, in its words.
    case problem(String)
    /// True, using only the sign's numbers.
    case works(SolvedEquation)

    public var works: Bool { if case .works = self { true } else { false } }
  }

  /// The most pieces a way can have. 30 numbers and their operators fit
  /// easily, and the text stays far inside the checker's 400 characters.
  public static let limit = 120

  /// The kept numbers, in order: the tiles.
  public private(set) var tiles: [CheckedNumber]
  public private(set) var pieces: [Piece] = []

  public init(tiles: [CheckedNumber]) {
    self.tiles = tiles
  }

  /// A draft written from text, each number on the first unused tile of
  /// that value. Numbers no tile matches are skipped. For screenshots and
  /// tests.
  public init(tiles: [CheckedNumber], text: String) {
    self.tiles = tiles
    let keys = Dictionary(uniqueKeysWithValues: Key.allCases.map { ($0.rawValue, $0) })
    let ascii: [Character: Key] = ["-": .subtract, "*": .multiply, "x": .multiply, "/": .divide]
    var digits = ""
    func endNumber() {
      guard !digits.isEmpty else { return }
      let value = EquationChecker.normalizeNumber(digits)
      if let tile = tiles.first(where: { $0.valueText == value && !isUsed($0.id) }) { place(tile.id) }
      digits = ""
    }
    for c in text {
      if c.isNumber || c == "." {
        digits.append(c)
        continue
      }
      endNumber()
      if let key = keys[String(c)] ?? ascii[c] { press(key) }
    }
    endNumber()
  }

  public var isEmpty: Bool { pieces.isEmpty }

  public func isUsed(_ id: CheckedNumber.ID) -> Bool {
    pieces.contains { if case .number(id, _) = $0 { true } else { false } }
  }

  /// How many tiles are in the math.
  public var usedCount: Int {
    pieces.reduce(0) { count, piece in if case .number = piece { count + 1 } else { count } }
  }

  /// Every tile is in the math.
  public var usesEveryNumber: Bool { !tiles.isEmpty && usedCount == tiles.count }

  /// Puts a tile's number at the end. False when it's already in the math,
  /// isn't a tile, or the math is full.
  @discardableResult
  public mutating func place(_ id: CheckedNumber.ID) -> Bool {
    guard pieces.count < Self.limit, !isUsed(id), let tile = tiles.first(where: { $0.id == id }) else { return false }
    pieces.append(.number(id, tile.valueText))
    return true
  }

  @discardableResult
  public mutating func press(_ key: Key) -> Bool {
    guard pieces.count < Self.limit else { return false }
    pieces.append(.key(key))
    return true
  }

  /// Takes a tile's number back out of the math, wherever it is.
  public mutating func takeOut(_ id: CheckedNumber.ID) {
    pieces.removeAll { if case .number(id, _) = $0 { true } else { false } }
  }

  public mutating func deleteLast() {
    _ = pieces.popLast()
  }

  public mutating func clear() {
    pieces = []
  }

  /// After "Check the numbers" changes: tiles that left take their numbers
  /// out of the math, and a fixed number's new value goes in its place.
  public mutating func retile(_ kept: [CheckedNumber]) {
    tiles = kept
    let values = Dictionary(uniqueKeysWithValues: kept.map { ($0.id, $0.valueText) })
    pieces = pieces.compactMap { piece in
      guard case .number(let id, _) = piece else { return piece }
      return values[id].map { .number(id, $0) }
    }
  }

  /// The math as the checker reads it.
  public var text: String {
    pieces.map(\.text).joined(separator: " ")
  }

  /// The math as written, for when it can't be drawn: no spaces inside
  /// brackets or around ^, √ and !.
  public var shownText: String {
    var out = ""
    for (index, piece) in pieces.enumerated() {
      let previous = index > 0 ? pieces[index - 1] : nil
      if previous != nil, piece.spaced, previous?.spacedAfter ?? false { out += " " }
      out += piece.text
    }
    return out
  }

  /// The math to draw while it's written: a box where the next piece goes,
  /// and open brackets closed, so "(90 − 82) ÷" draws as a fraction waiting
  /// for its bottom. Nil when even that doesn't parse (draw `shownText`).
  public var tex: String? {
    guard !pieces.isEmpty else { return nil }
    let (completed, hole) = completedText
    guard var tex = EquationChecker.tex(of: completed) else { return nil }
    if let hole { tex = tex.replacingOccurrences(of: hole, with: "\\square") }
    return tex
  }

  public var status: Status {
    guard !pieces.isEmpty else { return .empty }
    let (completed, hole) = completedText
    if hole != nil || completed != text {
      // Unfinished. If finishing it can't make it parse, say why now.
      if case .failed(let failure) = EquationChecker.check(completed), failure.error == .parse {
        return .problem(failure.message)
      }
      return .writing
    }
    switch EquationChecker.check(text) {
    case .solved(let solved):
      let off = EquationChecker.numbersNotOnSign(used: solved.numbers, onSign: tiles.map(\.valueText))
      if !off.isEmpty { return .problem("\(off.joined(separator: ", ")) isn’t one of the sign’s numbers") }
      return .works(solved)
    case .failed(let failure):
      switch failure.error {
      case .noEquals: return .oneSide(Self.value(of: text))
      case .notTrue: return .notTrue(failure.values ?? [])
      default: return .problem(failure.message)
      }
    }
  }

  /// What one side comes to, as the checker writes values.
  static func value(of side: String) -> String? {
    if case .solved(let solved) = EquationChecker.check("\(side) = \(side)") { return solved.value }
    return nil
  }

  /// The text with a stand-in number where the next piece goes and every
  /// open bracket closed, and the stand-in (nil when none was needed).
  private var completedText: (String, String?) {
    var parts = pieces.map(\.text)
    var hole: String?
    if case .key(let key) = pieces.last, key.wantsMore {
      let used = Set(tiles.map(\.valueText))
      var stand = "987654321"
      while used.contains(stand) { stand += "0" }
      hole = stand
      parts.append(stand)
    }
    var depth = 0
    for piece in pieces {
      if piece == .key(.open) { depth += 1 }
      if piece == .key(.close), depth > 0 { depth -= 1 }
    }
    parts += Array(repeating: ")", count: depth)
    return (parts.joined(separator: " "), hole)
  }
}

extension WayDraft.Piece {
  var text: String {
    switch self {
    case .number(_, let value): value
    case .key(let key): key.rawValue
    }
  }

  /// Takes a space before it.
  fileprivate var spaced: Bool {
    switch self {
    case .number: true
    case .key(let key): [.add, .subtract, .multiply, .divide, .equals, .open, .root].contains(key)
    }
  }

  /// Takes a space after it.
  fileprivate var spacedAfter: Bool {
    switch self {
    case .number: true
    case .key(let key): [.add, .subtract, .multiply, .divide, .equals, .close, .factorial].contains(key)
    }
  }
}
