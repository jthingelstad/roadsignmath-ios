import Equation
import Foundation
import SignReading

/// One number on "Check the numbers": read off the photo (and maybe fixed by
/// the player), or added by the player.
public struct CheckedNumber: Identifiable, Sendable, Hashable, Codable {
  public let id: Int
  /// The number's value. A fraction is kept as its decimal value; `text`
  /// keeps the form the sign shows.
  public var value: Decimal
  /// The number as a player sees it: `7`, `1/2`, `12,000`.
  public var text: String
  /// Where it is on the photo. Nil for a number typed in without a spot.
  public var box: NormalizedBox?
  /// Ticked: one of the sign's numbers. Unticked numbers stay in the list,
  /// so a change of mind is one tap, but leave the sign.
  public var kept: Bool
  /// What the photo was read as. Nil for a number the player added.
  public let reading: ReadNumber?

  /// A number read off the photo.
  public var isRead: Bool { reading != nil }
  /// Read off the photo, then changed by the player.
  public var isFixed: Bool { reading.map { $0.value != value || $0.text != text } ?? false }
  /// Added by the player.
  public var isAdded: Bool { reading == nil }

  /// The text on the sign it came from, `EXIT 7B`, when it was read.
  public var sourceText: String? { reading?.sourceText }

  /// The short "why" "Check the numbers" shows under each number.
  public var why: String {
    guard let reading else { return "Added by you" }
    if isFixed { return "You fixed it (we read \(reading.text))" }
    return reading.why
  }

  /// The value as the API and the equation checker write it: `7`, `0.5`,
  /// `12000`.
  public var valueText: String { EquationChecker.normalizeNumber("\(value)") }
}

/// The sign's numbers as the player checks them: what the photo was read
/// as, in reading order, every one ticked to start, then fixed, unticked,
/// removed or added to. The kept numbers, in order, are the sign's checked
/// list: the numbers its math may use.
public struct NumberList: Sendable, Hashable, Codable {
  /// The most numbers a sign can keep (the API's `numbersMax`).
  public static let limit = 30

  /// Why the list can't go on to Solve or a post yet.
  public enum Problem: Sendable, Hashable {
    case nothingKept
    case tooMany(Int)

    public var message: String {
      switch self {
      case .nothingKept: "Keep at least one number."
      case .tooMany(let count): "A sign keeps up to \(NumberList.limit) numbers. Untick \(count - NumberList.limit) to go on."
      }
    }
  }

  public private(set) var numbers: [CheckedNumber]
  private var nextID: Int

  /// The numbers a photo was read as, all kept, in reading order.
  public init(read: [ReadNumber] = []) {
    let ordered = Self.inReadingOrder(read, box: \.box)
    numbers = ordered.enumerated().map { index, reading in
      CheckedNumber(id: index, value: reading.value, text: reading.text, box: reading.box, kept: true, reading: reading)
    }
    nextID = ordered.count
  }

  public subscript(id: CheckedNumber.ID) -> CheckedNumber? {
    numbers.first { $0.id == id }
  }

  public var isEmpty: Bool { numbers.isEmpty }

  /// The ticked numbers, in order: the sign's checked list.
  public var kept: [CheckedNumber] { numbers.filter(\.kept) }

  /// The kept numbers' values as the equation checker compares them.
  public var values: [String] { kept.map(\.valueText) }

  public var problem: Problem? {
    let count = kept.count
    if count == 0 { return .nothingKept }
    if count > Self.limit { return .tooMany(count) }
    return nil
  }

  public mutating func setKept(_ kept: Bool, for id: CheckedNumber.ID) {
    guard let index = index(of: id) else { return }
    numbers[index].kept = kept
  }

  public mutating func toggle(_ id: CheckedNumber.ID) {
    guard let index = index(of: id) else { return }
    numbers[index].kept.toggle()
  }

  /// Changes a number to what the player typed. Typing what was read puts
  /// it back as read. A fixed number is kept.
  @discardableResult
  public mutating func fix(_ id: CheckedNumber.ID, to typed: String) throws(NumberEntry.Problem) -> CheckedNumber? {
    guard let index = index(of: id) else { return nil }
    let entry = try NumberEntry.parse(typed)
    numbers[index].value = entry.value
    numbers[index].text = entry.text
    numbers[index].kept = true
    return numbers[index]
  }

  /// Puts a fixed number back to what the photo was read as.
  public mutating func restore(_ id: CheckedNumber.ID) {
    guard let index = index(of: id), let reading = numbers[index].reading else { return }
    numbers[index].value = reading.value
    numbers[index].text = reading.text
  }

  /// A number the reading missed, typed in, at a spot on the photo or none.
  /// It takes its place in reading order when it has a spot, else goes last.
  @discardableResult
  public mutating func add(_ typed: String, at box: NormalizedBox? = nil) throws(NumberEntry.Problem) -> CheckedNumber {
    let entry = try NumberEntry.parse(typed)
    let number = CheckedNumber(id: nextID, value: entry.value, text: entry.text, box: box, kept: true, reading: nil)
    nextID += 1
    numbers.append(number)
    reorder()
    return number
  }

  /// Takes a number off the list altogether.
  public mutating func remove(_ id: CheckedNumber.ID) {
    numbers.removeAll { $0.id == id }
  }

  /// The number whose box holds a spot on the photo, the smallest box when
  /// boxes overlap, so a tap on the photo picks the number under it.
  public func number(at x: Double, _ y: Double, slop: Double = 0.01) -> CheckedNumber? {
    numbers
      .filter { number in
        guard let box = number.box?.padded(dx: slop, dy: slop) else { return false }
        return x >= box.x && x <= box.maxX && y >= box.y && y <= box.maxY
      }
      .min { ($0.box?.area ?? 1) < ($1.box?.area ?? 1) }
  }

  private func index(of id: CheckedNumber.ID) -> Int? {
    numbers.firstIndex { $0.id == id }
  }

  /// Numbers with a spot in reading order, then those without in the order
  /// they came.
  private mutating func reorder() {
    let placed = numbers.filter { $0.box != nil }
    let loose = numbers.filter { $0.box == nil }
    numbers = Self.inReadingOrder(placed) { $0.box ?? .fullImage } + loose
  }

  /// Reading order: rows from the top, each read left to right. A number
  /// joins a row when its middle lies within the height of the row's first
  /// number, so numbers side by side on one sign line read across even when
  /// Vision's boxes sit a little higher or lower.
  static func inReadingOrder<Item>(_ items: [Item], box: (Item) -> NormalizedBox) -> [Item] {
    let byTop = items.enumerated().sorted { a, b in
      let (boxA, boxB) = (box(a.element), box(b.element))
      return boxA.y == boxB.y ? a.offset < b.offset : boxA.y < boxB.y
    }
    var rows: [[(offset: Int, element: Item)]] = []
    var rowBand: (top: Double, bottom: Double)?
    for item in byTop {
      let itemBox = box(item.element)
      let middle = itemBox.y + itemBox.height / 2
      if let band = rowBand, middle >= band.top, middle <= band.bottom {
        rows[rows.count - 1].append(item)
      } else {
        rows.append([item])
        rowBand = (itemBox.y, itemBox.maxY)
      }
    }
    return rows.flatMap { row in
      row.sorted { a, b in
        let (boxA, boxB) = (box(a.element), box(b.element))
        return boxA.x == boxB.x ? a.offset < b.offset : boxA.x < boxB.x
      }.map(\.element)
    }
  }
}
