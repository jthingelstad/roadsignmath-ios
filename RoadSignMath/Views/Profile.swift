import RoadSignMathAPI
import SwiftUI

/// What You and a player's page share, as the boards draw them: the
/// avatar, name and page, the three numbers, the states, and the signs as
/// Home's timeline or a grid of photos.

/// Who someone is: the avatar, the name, their page, the bio, then their
/// signs, states and the year of their first sign.
struct ProfileHeader: View {
  /// The name as shown, "Add your name" when there isn't one yet.
  let name: String
  /// No name yet: the shown words are a nudge, not a name.
  var unnamed = false
  let avatarColor: String
  /// Their profile photo, if they have one.
  var avatarUrl: URL?
  /// Your own page: a tap on the avatar sets your photo.
  var changePhoto: (() -> Void)?
  /// Their page on the website, as `roadsignmath.xyz/players/jamie`.
  var page: URL?
  /// Opens the page in the browser, or only says where it is.
  var linked = false
  /// What VoiceOver says before the page's address.
  var pageWords = "Page"
  let bio: String?
  let signCount: Int
  let states: [String]
  let firstYear: Int?

  var body: some View {
    VStack(spacing: 14) {
      VStack(spacing: 8) {
        avatar
        Text(name)
          .face(.title)
          .foregroundStyle(unnamed ? Color.ink3 : Color.ink)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
        if let page { address(page) }
        if let bio, !bio.isEmpty {
          Text(bio)
            .face(.body)
            .foregroundStyle(Color.ink2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
        }
      }
      HStack(spacing: 10) {
        Stat(value: "\(signCount)", label: signCount == 1 ? "sign" : "signs")
        Stat(value: "\(states.count)", label: states.count == 1 ? "state" : "states")
        Stat(value: firstYear.map(String.init) ?? "–", label: "first sign")
          .accessibilityLabel(firstYear.map { "First sign in \($0)" } ?? "No first sign yet")
      }
      .padding(.horizontal, 16)
      if !states.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(states, id: \.self) { state in
            Text(state)
              .face(.pill)
              .foregroundStyle(Color.greenInk)
              .padding(.horizontal, 10)
              .frame(minHeight: 28)
              .background(Color.wayGround, in: Capsule())
          }
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("States: " + states.joined(separator: ", "))
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder private var avatar: some View {
    let drawn = Avatar(name: unnamed ? "" : name, color: Color(hex: avatarColor) ?? .signGreen, size: 84, photo: avatarUrl)
    if let changePhoto {
      Button(action: changePhoto) {
        drawn.overlay(alignment: .bottomTrailing) {
          Image(systemName: "camera.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.greenInk)
            .frame(width: 28, height: 28)
            .background(Color.card, in: Circle())
            .overlay(Circle().stroke(Color.ruleStrong, lineWidth: 1))
            .offset(x: 2, y: 2)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(avatarUrl == nil ? "Add a profile photo" : "Change your profile photo")
    } else {
      drawn
    }
  }

  @ViewBuilder private func address(_ page: URL) -> some View {
    let words = ProfileHeader.address(page)
    if linked {
      Link(destination: page) {
        Label(words, systemImage: "safari")
          .face(.meta)
          .foregroundStyle(Color.greenInk)
          .frame(minHeight: 44)
      }
      .accessibilityLabel("\(pageWords) on the website: \(words)")
      .padding(.vertical, -10)
    } else {
      Text(words)
        .face(.meta)
        .foregroundStyle(Color.ink3)
        .accessibilityLabel("\(pageWords): \(words)")
    }
  }

  /// "roadsignmath.xyz/players/jamie"
  static func address(_ url: URL) -> String {
    (url.host() ?? "") + (url.port.map { ":\($0)" } ?? "") + url.path()
  }
}

/// Someone's signs as Home's timeline (the same cards, the math on each)
/// or as a grid of photos, with the pills that switch between them.
struct ProfileSigns: View {
  enum Look: Hashable { case timeline, photos }

  let signs: [Sign]
  @Binding var look: Look
  let zoom: Namespace.ID
  /// "your", "Jamie’s": for VoiceOver's "Show your signs as".
  let whose: String
  let open: (Sign) -> Void
  @Environment(Store.self) private var store

  /// Leaves out a sign deleted or taken down since the list was read.
  private var shown: [Sign] { signs.filter { !store.gone.contains($0.id) } }

  var body: some View {
    looks
    switch look {
    case .timeline: timeline
    case .photos: grid
    }
  }

  private var looks: some View {
    HStack(spacing: 8) {
      Pill(label: "Signs", chosen: look == .timeline) { withAnimation(.snappy) { look = .timeline } }
      Pill(label: "Photos", chosen: look == .photos) { withAnimation(.snappy) { look = .photos } }
      Spacer()
    }
    .padding(.horizontal, 16)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Show \(whose) signs as")
  }

  private var grid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
      ForEach(shown) { sign in
        Button { open(sign) } label: {
          Color.photoGround
            .aspectRatio(1, contentMode: .fit)
            .overlay {
              if let photo = sign.photos.first {
                PhotoView(url: photo.thumbUrl, alt: photo.alt, pixels: 480)
              }
            }
            .clipped()
            .overlay(alignment: .topLeading) { OnlyYou(sign: sign) }
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPress())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(sign))
        .accessibilityAddTraits(.isButton)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding(.horizontal, 16)
    .transition(.opacity)
  }

  private var timeline: some View {
    LazyVStack(spacing: 10) {
      ForEach(shown) { sign in
        // A way added from here shows at once, though the list was read before.
        SignCard(sign: store.current(sign), zoom: zoom) { open(sign) }
          .overlay(alignment: .topTrailing) { OnlyYou(sign: sign) }
      }
    }
    .transition(.opacity)
  }

  static func spoken(_ sign: Sign) -> String {
    var words = sign.title + ", " + sign.place.label
    if sign.visibility != .shown { words += ". Only you can see it" }
    return words
  }

  /// Newest posted first, as Home lists everyone's (Jamie, 2026-10-30).
  static func newestFirst(_ signs: [Sign]) -> [Sign] {
    signs.sorted { ($0.postedAt, $0.id) > ($1.postedAt, $1.id) }
  }
}

/// One of the three numbers under a name.
private struct Stat: View {
  let value: String
  let label: String

  var body: some View {
    VStack(spacing: 2) {
      Text(value)
        .font(Face.number.font(size: 24))
        .foregroundStyle(Color.ink)
        .contentTransition(.numericText())
        .animation(.snappy, value: value)
      Text(label).face(.meta).foregroundStyle(Color.ink3)
    }
    .frame(maxWidth: .infinity, minHeight: 68)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
    .accessibilityElement(children: .combine)
  }
}

/// A held or hidden sign's mark: only you see it.
private struct OnlyYou: View {
  let sign: Sign

  var body: some View {
    if sign.visibility != .shown {
      Image(systemName: "eye.slash.fill")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white)
        .padding(6)
        .background(.black.opacity(0.6), in: Circle())
        .padding(6)
        .accessibilityHidden(true)
    }
  }
}

/// Where a sign or a player opens: each tab's stack says how to push them,
/// so a sign's finder opens their page in whichever tab you're in.
struct Opener {
  var sign: (String) -> Void
  var player: (String) -> Void
}

extension EnvironmentValues {
  @Entry var opener: Opener?
}

/// A player's page on a stack of sign ids: `@jamie`.
enum PlayerPath {
  static func of(_ handle: String) -> String { "@" + handle }
  static func handle(_ id: String) -> String? { id.hasPrefix("@") ? String(id.dropFirst()) : nil }
}
