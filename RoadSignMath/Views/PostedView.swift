import Posting
import RoadSignMathAPI
import SwiftUI

/// After Post it: the post on its way, then the moment it's up ("Posted!",
/// with the sign's numbers bursting out), or what's keeping it: no
/// connection (it posts on its own), held for a look, or the server's no.
struct PostedView: View {
  let id: UUID

  @Environment(Outbox.self) private var outbox
  @Environment(Store.self) private var store
  @Environment(CaptureFlow.self) private var flow
  @Environment(\.accessibilityReduceMotion) private var still
  /// The post as last seen, kept once the outbox lets it go.
  @State private var last: OutboxItem?
  @State private var burst = false

  private var item: OutboxItem? { outbox.item(id) ?? last }

  enum Moment: Equatable { case sending, waiting(String), signIn, posted, held(String?), refused(String) }

  private var moment: Moment {
    guard let item else { return .sending }
    switch item.state {
    case .waiting(let problem): return outbox.sending == id || problem == nil ? .sending : .waiting(problem!)
    case .needsSignIn: return .signIn
    case .posted: return .posted
    case .held(_, let note): return .held(note)
    case .refused(let message): return .refused(message)
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 22) {
        badge
          .padding(.top, 28)
        words
        card
        buttons
      }
      .padding(20)
      .frame(maxWidth: 560)
      .frame(maxWidth: .infinity)
    }
    .background(Color.ground)
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(true)
    .toolbarBackground(Color.ground, for: .navigationBar)
    .onAppear { last = outbox.item(id) }
    .onChange(of: outbox.item(id)) { _, now in if let now { last = now } }
    .onChange(of: moment) { _, now in
      if now == .posted { celebrate() }
      AccessibilityNotification.Announcement(headline).post()
    }
    .onAppear { if moment == .posted { celebrate() } }
    .sensoryFeedback(trigger: moment) { _, now in
      switch now {
      case .posted, .held: .success
      case .refused: .error
      case .waiting: .warning
      default: nil
      }
    }
  }

  // MARK: The moment

  @ViewBuilder private var badge: some View {
    ZStack {
      if moment == .posted, !still { NumberBurst(numbers: numbers, out: burst) }
      Circle()
        .fill(badgeColor)
        .frame(width: 112, height: 112)
        .overlay { Circle().strokeBorder(.white, lineWidth: 4).padding(5) }
        .shadow(color: badgeColor.opacity(0.35), radius: 14, y: 8)
      Group {
        if moment == .sending {
          ProgressView().controlSize(.large).tint(.white)
        } else {
          Image(systemName: symbol)
            .font(.system(size: 46, weight: .bold))
            .foregroundStyle(badgeInk)
            .contentTransition(.symbolEffect(.replace))
        }
      }
    }
    .frame(height: 180)
    .scaleEffect(moment == .posted && !still ? (burst ? 1 : 0.6) : 1)
    .animation(still ? nil : .spring(response: 0.45, dampingFraction: 0.55), value: burst)
    .animation(.snappy, value: moment)
    .accessibilityHidden(true)
  }

  private var symbol: String {
    switch moment {
    case .sending: "paperplane.fill"
    case .waiting: "wifi.slash"
    case .signIn: "person.crop.circle.badge.exclamationmark"
    case .posted: "checkmark"
    case .held: "eye"
    case .refused: "exclamationmark"
    }
  }

  private var badgeColor: Color {
    switch moment {
    case .sending, .posted: .signGreen
    case .waiting, .held, .signIn: .signYellow
    case .refused: .warn
    }
  }

  /// Ink on caution yellow, as the boards say; white on green and red.
  private var badgeInk: Color {
    switch moment {
    case .waiting, .held, .signIn: Color(light: 0x18201C, dark: 0x18201C)
    default: .white
    }
  }

  private var headline: String {
    switch moment {
    case .sending: "Posting…"
    case .waiting: "Waiting to post"
    case .signIn: "Sign in to post it"
    case .posted: "Posted!"
    case .held: "Posted, and held for a look"
    case .refused: "It didn’t post"
    }
  }

  private var words: some View {
    VStack(spacing: 10) {
      Text(headline)
        .face(moment == .posted ? .hero : .display)
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      Group {
        switch moment {
        case .sending:
          Text("Sending your photo and your sign.")
        case .waiting(let problem):
          Text(problem + " You can close this: it’s kept on your phone until it goes.")
        case .signIn:
          Text("You were signed out. It waits on your phone, and goes once you’re signed in again.")
        case .posted:
          Text("\u{201C}\(item?.post.title ?? "Your sign")\u{201D} is on the map and the website now.")
        case .held(let note):
          Text([note, "Only you can see it until then."].compactMap { $0 }.joined(separator: " "))
        case .refused(let message):
          Text(message)
        }
      }
      .face(.lead)
      .foregroundStyle(Color.ink2)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// The post: its photo, name, place, and the math (or unsolved).
  @ViewBuilder private var card: some View {
    if let item {
      VStack(alignment: .leading, spacing: 0) {
        if let picture = outbox.picture(id) ?? flow.shot?.picture {
          Image(uiImage: picture)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(height: 170)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityLabel("Your photo of the sign")
        }
        VStack(alignment: .leading, spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(item.post.title).face(.title).foregroundStyle(Color.ink)
            Text(item.post.place.label).face(.meta).foregroundStyle(Color.ink3)
          }
          if let way = item.post.way {
            SignPlate(text: way, tex: nil, size: 20)
          } else {
            Text("Unsolved: anyone can find the math.").face(.meta).foregroundStyle(Color.ink3)
          }
        }
        .padding(14)
      }
      .background(Color.card)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
      .accessibilityElement(children: .combine)
    }
  }

  @ViewBuilder private var buttons: some View {
    VStack(spacing: 10) {
      switch moment {
      case .posted:
        if let sign = item?.posted {
          BigButton(label: "See your sign", symbol: "signpost.right.fill", busy: false, enabled: true) { see(sign) }
        }
        plain("Find another", symbol: "camera") { another() }
      case .held:
        BigButton(label: "Find another", symbol: "camera", busy: false, enabled: true) { another() }
        plain("Done", symbol: "checkmark") { done() }
      case .waiting:
        BigButton(label: "Done", symbol: "checkmark", busy: false, enabled: true) { done() }
        plain("Try now", symbol: "arrow.clockwise") { outbox.retry(id) }
      case .signIn, .sending:
        BigButton(label: "Done", symbol: "checkmark", busy: false, enabled: true) { done() }
      case .refused:
        BigButton(label: "Fix the post", symbol: "pencil", busy: false, enabled: true) { fix() }
        plain("Try again", symbol: "arrow.clockwise") { outbox.retry(id) }
      }
    }
  }

  private func plain(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(label, systemImage: symbol)
        .face(.button)
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ruleStrong, lineWidth: 1.5) }
    }
    .buttonStyle(CardPress())
  }

  private var numbers: [String] { item.map { Array($0.post.numbers.prefix(10).map(\.value)) } ?? [] }

  private func celebrate() {
    guard !burst else { return }
    burst = true
  }

  // MARK: Leaving

  /// Closes Capture; the post, if it's still going, goes on in the outbox.
  private func done() {
    outbox.acknowledge(id)
    flow.close()
    flow.finishPosting()
  }

  private func see(_ sign: PostedSign) {
    store.tab = .home
    store.homePath = [sign.slug]
    done()
  }

  /// Straight back to the camera for the next sign.
  private func another() {
    outbox.acknowledge(id)
    flow.finishPosting()
    flow.begin()
  }

  /// Back to the form to change what the server said no to; this try is
  /// forgotten, and the form posts afresh.
  private func fix() {
    outbox.remove(id)
    flow.path.removeLast()
  }
}

/// The sign's numbers flying out from the badge, once.
private struct NumberBurst: View {
  let numbers: [String]
  let out: Bool

  var body: some View {
    ZStack {
      ForEach(Array(numbers.enumerated()), id: \.offset) { index, number in
        let angle = Angle.degrees(Double(index) / Double(max(numbers.count, 1)) * 360 - 90)
        let reach: CGFloat = 118 + CGFloat(index % 2) * 26
        Text(number)
          .font(Face.number.font(size: 17))
          .foregroundStyle(Color.greenInk)
          .padding(.horizontal, 10)
          .frame(minHeight: 34)
          .background(Color.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
          .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.signGreen, lineWidth: 1.5) }
          .offset(x: out ? cos(angle.radians) * reach : 0, y: out ? sin(angle.radians) * reach * 0.62 : 0)
          .scaleEffect(out ? 1 : 0.3)
          .opacity(out ? 1 : 0)
          .animation(.spring(response: 0.6, dampingFraction: 0.62).delay(0.05 * Double(index)), value: out)
      }
    }
  }
}
