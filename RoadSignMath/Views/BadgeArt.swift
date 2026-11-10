import RoadSignMathAPI
import SwiftUI

/// A badge drawn as a small road sign of its shelf's family, as the
/// website draws it (`src/web/badges.tsx`, a 64-point square): white
/// plates for the firsts, green guide signs, an interstate shield for
/// States and a mile post for Mile Markers, yellow diamonds for the math,
/// brown for the seasons, blue service signs for the secret ones and the
/// 66 route shield, orange plates for the years. Real signs keep their
/// colors in the dark, so these do too.
struct BadgeArt: View {
  enum Look { case earned, faded, blank }

  let shelf: BadgeShelf
  let id: String
  /// What the sign shows: a word, a symbol or a step.
  let mark: String
  var look = Look.earned
  var size: CGFloat = 56

  var body: some View {
    Canvas { context, canvas in
      let s = canvas.width / 64
      BadgeArt.draw(shelf: shelf, id: id, mark: look == .blank ? "" : mark, in: &context, scale: s)
    }
    .frame(width: size, height: size)
    .saturation(look == .earned ? 1 : 0)
    .opacity(look == .earned ? 1 : 0.32)
    .shadow(color: .black.opacity(look == .earned ? 0.18 : 0), radius: 1, y: 1)
    .accessibilityHidden(true)
  }

  // MARK: Drawing

  private static let ink = Color(light: 0x1D1D1B, dark: 0x1D1D1B)
  private static let green = Color(light: 0x00704A, dark: 0x00704A)
  private static let shieldBlue = Color(light: 0x0B4EA2, dark: 0x0B4EA2)
  private static let shieldRed = Color(light: 0xC8102E, dark: 0xC8102E)
  private static let yellow = Color(light: 0xFFC20E, dark: 0xFFC20E)
  private static let brown = Color(light: 0x6B3E1E, dark: 0x6B3E1E)
  private static let blue = Color(light: 0x00539B, dark: 0x00539B)
  private static let white = Color(light: 0xFFFFFF, dark: 0xFFFFFF)
  private static let orange = Color(light: 0xF28C28, dark: 0xF28C28)

  /// The mark's size, so a word fits where a symbol would.
  static func markSize(_ mark: String) -> CGFloat {
    switch mark.count {
    case ...2: 24
    case 3: 16
    case 4: 13
    default: 11
    }
  }

  private static func draw(shelf: BadgeShelf, id: String, mark: String, in context: inout GraphicsContext, scale s: CGFloat) {
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
      Path(roundedRect: CGRect(x: x * s, y: y * s, width: w * s, height: h * s), cornerRadius: r * s)
    }
    func poly(_ points: [(CGFloat, CGFloat)]) -> Path {
      var path = Path()
      path.addLines(points.map { CGPoint(x: $0.0 * s, y: $0.1 * s) })
      path.closeSubpath()
      return path
    }
    func text(_ mark: String, _ color: Color, y: CGFloat = 33, size: CGFloat? = nil) {
      guard !mark.isEmpty else { return }
      let font = Face(size: 16, weight: 800, style: .body).font(size: (size ?? markSize(mark)) * s)
      context.draw(Text(mark).font(font).foregroundStyle(color), at: CGPoint(x: 32 * s, y: y * s), anchor: .center)
    }
    /// A rectangular sign with the inset border real signs have.
    func plate(_ fill: Color, edge: Color, ink: Color, tall: Bool = false) {
      let (x, y, w, h): (CGFloat, CGFloat, CGFloat, CGFloat) = tall ? (18, 2, 28, 60) : (4, 12, 56, 40)
      context.fill(rect(x, y, w, h, 6), with: .color(fill))
      context.stroke(rect(x + 3, y + 3, w - 6, h - 6, 4), with: .color(edge), lineWidth: 1.5 * s)
      if tall {
        text("MILE", ink, y: 18, size: 8)
        text(mark, ink, y: 38, size: mark.count > 1 ? 15 : 20)
      } else {
        text(mark, ink)
      }
    }

    switch shelf {
    case .firsts, .other:
      context.fill(rect(10, 4, 44, 56, 5), with: .color(white))
      context.stroke(rect(10, 4, 44, 56, 5), with: .color(ink), lineWidth: 2.5 * s)
      context.stroke(rect(14, 8, 36, 48, 3), with: .color(ink), lineWidth: 1 * s)
      // An upright plate is narrow, so a long word gets smaller.
      text(mark, ink, size: mark.count >= 4 ? 10 : nil)
    case .places where id == "states":
      var shield = Path()
      shield.move(to: CGPoint(x: 6 * s, y: 12 * s))
      shield.addQuadCurve(to: CGPoint(x: 58 * s, y: 12 * s), control: CGPoint(x: 32 * s, y: 2 * s))
      shield.addLine(to: CGPoint(x: 58 * s, y: 32 * s))
      shield.addQuadCurve(to: CGPoint(x: 32 * s, y: 62 * s), control: CGPoint(x: 58 * s, y: 52 * s))
      shield.addQuadCurve(to: CGPoint(x: 6 * s, y: 32 * s), control: CGPoint(x: 6 * s, y: 52 * s))
      shield.closeSubpath()
      context.fill(shield, with: .color(shieldBlue))
      context.stroke(shield, with: .color(white), lineWidth: 2 * s)
      var band = Path()
      band.move(to: CGPoint(x: 7 * s, y: 12.5 * s))
      band.addQuadCurve(to: CGPoint(x: 57 * s, y: 12.5 * s), control: CGPoint(x: 32 * s, y: 3 * s))
      band.addLine(to: CGPoint(x: 57 * s, y: 22 * s))
      band.addLine(to: CGPoint(x: 7 * s, y: 22 * s))
      band.closeSubpath()
      context.fill(band, with: .color(shieldRed))
      text(mark, white, y: 39, size: 20)
    case .places where id == "mile-markers":
      plate(green, edge: white, ink: white, tall: true)
    case .places:
      plate(green, edge: white, ink: white)
    case .math:
      let diamond = poly([(32, 2), (62, 32), (32, 62), (2, 32)])
      context.fill(diamond, with: .color(yellow))
      context.stroke(diamond, with: .color(ink), lineWidth: 2.5 * s)
      context.stroke(poly([(32, 7), (57, 32), (32, 57), (7, 32)]), with: .color(ink), lineWidth: 1 * s)
      text(mark, ink)
    case .seasons:
      plate(brown, edge: white, ink: white)
    case .secret where id == "secret-2":
      var route = Path()
      route.move(to: CGPoint(x: 10 * s, y: 6 * s))
      route.addLine(to: CGPoint(x: 54 * s, y: 6 * s))
      route.addQuadCurve(to: CGPoint(x: 60 * s, y: 20 * s), control: CGPoint(x: 56 * s, y: 16 * s))
      route.addQuadCurve(to: CGPoint(x: 32 * s, y: 60 * s), control: CGPoint(x: 56 * s, y: 44 * s))
      route.addQuadCurve(to: CGPoint(x: 4 * s, y: 20 * s), control: CGPoint(x: 8 * s, y: 44 * s))
      route.addQuadCurve(to: CGPoint(x: 10 * s, y: 6 * s), control: CGPoint(x: 8 * s, y: 16 * s))
      route.closeSubpath()
      context.fill(route, with: .color(white))
      context.stroke(route, with: .color(ink), lineWidth: 2.5 * s)
      text(mark, ink, y: 34, size: 22)
    case .secret:
      plate(blue, edge: white, ink: white)
    case .years:
      // A wide orange plate, the year on it, as the website draws it.
      context.fill(rect(2, 14, 60, 36, 5), with: .color(orange))
      context.stroke(rect(5, 17, 54, 30, 3), with: .color(ink), lineWidth: 1.5 * s)
      text(mark, ink, y: 32.5, size: 19)
    }
  }
}

extension BadgeArt {
  /// An earned badge's sign.
  init(_ badge: EarnedBadge, size: CGFloat = 56) {
    self.init(shelf: badge.shelf, id: badge.id, mark: badge.mark, size: size)
  }

  /// A place on a shelf: earned in full color; not yet, faded, a stepped
  /// one showing the step to reach; a secret one blank.
  init(_ slot: BadgeSlot, size: CGFloat = 56) {
    if let earned = slot.earned {
      self.init(earned, size: size)
    } else {
      let mark = slot.nextStep.map(String.init) ?? slot.badge.mark ?? ""
      // A secret one not earned is a plain blank plate, so its shape
      // (the 66 shield) gives nothing away.
      self.init(shelf: slot.badge.shelf, id: slot.hidden ? "" : slot.id, mark: mark, look: slot.hidden ? .blank : .faded, size: size)
    }
  }
}

extension EarnedBadge {
  /// "Square Root. Use √ in a way. Earned September 1, 2025 with Ames Math."
  var spoken: String { "\(title). \(how) Earned \(longDay) with \(sign.title)." }

  /// "September 1, 2025".
  var longDay: String {
    day.flatMap { Calendar(identifier: .gregorian).date(from: $0) }?
      .formatted(.dateTime.month(.wide).day().year()) ?? earnedOn
  }

  /// "Sep 1, 2025".
  var shortDay: String {
    day.flatMap { Calendar(identifier: .gregorian).date(from: $0) }?
      .formatted(.dateTime.month(.abbreviated).day().year()) ?? earnedOn
  }
}

extension BadgeShelf {
  var title: String {
    switch self {
    case .firsts: "Firsts"
    case .places: "Places"
    case .math: "Math"
    case .seasons: "Seasons"
    case .secret: "Secret"
    case .years: "Years"
    case .other: "More"
    }
  }
}

/// A player's earned badges in a row: each sign and its name, newest
/// first. Nothing about the ones not earned, and no count, as the
/// website shows another player's.
struct BadgeRow: View {
  let badges: [EarnedBadge]
  var open: ((EarnedBadge) -> Void)?

  var body: some View {
    ScrollView(.horizontal) {
      HStack(alignment: .top, spacing: 10) {
        ForEach(badges, id: \.self) { badge in
          Button {
            open?(badge)
          } label: {
            BadgeTile(badge: badge)
          }
          .buttonStyle(CardPress())
          .disabled(open == nil)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(badge.spoken)
          .accessibilityAddTraits(open == nil ? [] : .isButton)
        }
      }
      .padding(.horizontal, 16)
    }
    .scrollIndicators(.hidden)
  }
}

/// The years a player found a sign, oldest first: a row of orange plates,
/// each its own badge. A tap opens the badge.
struct YearRow: View {
  let years: [EarnedBadge]
  /// The ones not seen on this phone yet get a dot.
  var fresh: Set<String> = []
  var open: ((EarnedBadge) -> Void)?
  @ScaledMetric(relativeTo: .body) private var size: CGFloat = 68

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 6) {
        ForEach(years, id: \.self) { year in
          let new = fresh.contains(SeenBadges.key(year))
          Button {
            open?(year)
          } label: {
            BadgeArt(year, size: size)
              .overlay(alignment: .topTrailing) { if new { NewDot().offset(x: -2, y: 8) } }
          }
          .buttonStyle(CardPress())
          .disabled(open == nil)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel((new ? "New: " : "") + "\(year.name). First sign that year: \(year.sign.title), \(year.longDay).")
          .accessibilityAddTraits(open == nil ? [] : .isButton)
        }
      }
      .padding(.horizontal, 16)
    }
    .scrollIndicators(.hidden)
  }
}

/// A profile's Years section: a heading, a line and the plates.
struct YearsSection: View {
  let years: [EarnedBadge]
  /// "you" on your own page, else the player's name.
  let who: String
  var fresh: Set<String> = []
  var open: ((EarnedBadge) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Years")
          .face(.section)
          .foregroundStyle(Color.ink)
          .accessibilityAddTraits(.isHeader)
        if !fresh.isEmpty { NewDot() }
      }
      .padding(.horizontal, 16)
      Text("A badge for every year \(who) found a sign. They are not easy to find.")
        .face(.meta)
        .foregroundStyle(Color.ink3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
      YearRow(years: years, fresh: fresh, open: open)
    }
  }
}

/// One badge: its sign over its name.
struct BadgeTile: View {
  let badge: EarnedBadge
  var new = false
  @ScaledMetric(relativeTo: .caption) private var width: CGFloat = 84

  var body: some View {
    VStack(spacing: 4) {
      BadgeArt(badge)
        .overlay(alignment: .topTrailing) { if new { NewDot().offset(x: 4, y: -2) } }
      // One line, as wide as it needs: the rows scroll sideways, and a
      // stepped badge's count ("Mile Markers: 25") never wraps on its own.
      Text(badge.title)
        .face(.meta)
        .foregroundStyle(Color.ink2)
        .lineLimit(1)
        .fixedSize()
    }
    .frame(minWidth: width)
  }
}

/// The dot on something new.
struct NewDot: View {
  var body: some View {
    Circle()
      .fill(Color.warn)
      .frame(width: 10, height: 10)
      .overlay { Circle().strokeBorder(Color.card, lineWidth: 2) }
      .accessibilityHidden(true)
  }
}
