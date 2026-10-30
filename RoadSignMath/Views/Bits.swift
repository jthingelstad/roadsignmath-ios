import RoadSignMathAPI
import SwiftUI

/// A player's initial on their colour.
struct Avatar: View {
  let name: String
  var color: Color = .signGreen
  var size: CGFloat = 34

  var body: some View {
    Group {
      if let first = name.first {
        // Sized to the circle, which doesn't grow with Dynamic Type.
        Text(String(first).uppercased()).font(Face.avatar.font(size: size * 0.44))
      } else {
        // No name yet: a person, not a letter.
        Image(systemName: "person.fill").font(.system(size: size * 0.48, weight: .semibold))
      }
    }
    .foregroundStyle(.white)
    .frame(width: size, height: size)
    .background(color, in: Circle())
    .accessibilityHidden(true)
  }
}

extension Store {
  /// A finder's colour, from their player page, else the sign's green.
  func color(for handle: String?) -> Color {
    handle.flatMap { players[$0] }.flatMap { Color(hex: $0.avatarColor) } ?? .signGreen
  }
}

extension Sign {
  /// "Tyler", "Jamie and Tyler", "Jamie, Tammy and Tyler".
  var finderNames: String {
    let names = foundBy.map(\.name)
    return names.isEmpty ? "Someone" : names.formatted(.list(type: .and))
  }

  var leadFinder: Finder? { foundBy.first }

  /// "Sep 1, 2025".
  var foundShort: String { foundDate?.formatted(.dateTime.month(.abbreviated).day().year()) ?? foundOn }
  /// "September 1, 2025".
  var foundLong: String { foundDate?.formatted(.dateTime.month(.wide).day().year()) ?? foundOn }
  /// "Sep 2025".
  var foundMonth: String { foundDate?.formatted(.dateTime.month(.abbreviated).year()) ?? foundOn }

  /// The day found, at noon in the phone's calendar, only for formatting.
  private var foundDate: Date? {
    guard var day = foundDay else { return nil }
    day.hour = 12
    return Calendar.current.date(from: day)
  }

  /// "One way so far", "3 ways so far".
  var waysSoFar: String { wayCount == 1 ? "One way so far" : "\(wayCount) ways so far" }

  var milesText: String? {
    guard let miles else { return nil }
    if miles < 0.1 { return "here" }
    if miles < 10 { return miles.formatted(.number.precision(.fractionLength(1))) + " mi" }
    return miles.formatted(.number.precision(.fractionLength(0))) + " mi"
  }
}

/// A rounded pill, black when chosen, as the boards' tabs and chips.
struct Pill: View {
  let label: String
  let chosen: Bool
  var floating = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label)
        .face(.pill)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .foregroundStyle(chosen ? Color.card : Color.ink)
        .background(chosen ? Color.ink : Color.card, in: Capsule())
        .overlay {
          if !chosen && !floating { Capsule().strokeBorder(Color.ruleStrong, lineWidth: 1.5) }
        }
        .shadow(color: .black.opacity(floating ? 0.12 : 0), radius: 3, y: 2)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(chosen ? .isSelected : [])
  }
}

/// A quiet message where a list would be: loading failed, nothing yet.
struct Notice: View {
  let symbol: String
  let title: String
  let message: String
  var action: (label: String, run: () -> Void)?

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(Color.greenInk)
        .padding(.bottom, 4)
      Text(title).face(.section).foregroundStyle(Color.ink)
      Text(message)
        .face(.body)
        .foregroundStyle(Color.ink3)
        .multilineTextAlignment(.center)
      if let action {
        Button(action.label, action: action.run)
          .face(.action)
          .buttonStyle(.borderedProminent)
          .tint(.signGreen)
          .padding(.top, 6)
      }
    }
    .padding(32)
    .frame(maxWidth: .infinity)
  }
}

/// A soft pulse for things still loading.
struct Shimmer: ViewModifier {
  @State private var on = false
  @Environment(\.accessibilityReduceMotion) private var still

  func body(content: Content) -> some View {
    content
      .opacity(on ? 0.55 : 1)
      .onAppear {
        guard !still else { return }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
      }
  }
}
