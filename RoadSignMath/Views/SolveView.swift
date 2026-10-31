import SignCapture
import SwiftUI

/// The boards' Solve: the math as it's written, on a sign of its own; the
/// sign's numbers as tiles that check off as they go in; a keypad of
/// operators; and a line that says how the math reads, ending in "It works".
/// Using every number is the fun part, never a requirement.
struct SolveView: View {
  @Environment(CaptureFlow.self) private var flow
  @Environment(Account.self) private var account
  @Environment(\.accessibilityReduceMotion) private var still
  @State private var draft = WayDraft(tiles: [])
  @State private var askSignIn = false
  @State private var signingIn = false
  /// Bumped by every tile and key, for the tap's haptic.
  @State private var taps = 0

  var body: some View {
    GeometryReader { geometry in
      if geometry.size.width > geometry.size.height {
        HStack(alignment: .top, spacing: 16) {
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              ShotStrip(height: 96)
              board
              reading
            }
            // Room for the ring and the seal, which the scroll view would clip.
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
          }
          .scrollBounceBehavior(.basedOnSize)
          VStack(spacing: 12) {
            ScrollView { tiles(hint: false).padding(.vertical, 12) }
              .scrollBounceBehavior(.basedOnSize)
            keypad
            actions
          }
          .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
      } else {
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              ShotStrip(height: 110)
              board
              reading
              tiles(hint: true)
            }
            .padding(16)
          }
          .scrollBounceBehavior(.basedOnSize)
          VStack(spacing: 12) {
            keypad
            actions
          }
          .padding(.horizontal, 16)
          .padding(.top, 12)
          .padding(.bottom, 8)
          .background(Color.ground.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
        }
      }
    }
    .background(Color.ground)
    .navigationTitle("Solve it")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Color.ground, for: .navigationBar)
    .sensoryFeedback(.selection, trigger: taps)
    .sensoryFeedback(.success, trigger: works) { _, now in now }
    .onAppear(perform: start)
    .onChange(of: draft) { _, now in flow.draft = now }
    .onChange(of: works) { _, now in
      if now { AccessibilityNotification.Announcement("It works").post() }
    }
    .alert("Sign in to post", isPresented: $askSignIn) {
      Button("Sign in") {
        if account.prepareSignIn() { signingIn = true }
      }
      Button("Not now", role: .cancel) {}
    } message: {
      Text("Your photo and your math wait right here while you do.")
    }
    .fullScreenCover(isPresented: $signingIn) {
      SignInView { leaveSignIn() }
    }
    .onChange(of: account.step) { _, step in
      if signingIn, step == .email, account.signedIn { leaveSignIn() }
    }
    .onChange(of: signingIn) { _, now in Orientation.allow(now ? .portrait : .allButUpsideDown) }
  }

  private var status: WayDraft.Status { draft.status }
  private var works: Bool { status.works }

  // MARK: The math

  /// The math on a green sign, white on green, as it will be posted.
  private var board: some View {
    ZStack {
      if draft.isEmpty {
        Text("Your math goes here")
          .face(.plateText)
          .foregroundStyle(.white.opacity(0.7))
          .frame(maxWidth: .infinity, minHeight: 44)
          .accessibilityHidden(true)
      } else {
        MathLine(text: draft.shownText, tex: draft.tex, size: 30, relativeTo: .title)
          .frame(minHeight: 44)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 22)
    .frame(maxWidth: .infinity)
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white, lineWidth: 2.5)
    }
    .padding(5)
    .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 15, style: .continuous)
        .strokeBorder(Color.signYellow, lineWidth: works ? 4 : 0)
        .padding(-6)
    }
    .overlay(alignment: .topTrailing) {
      if works {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 34, weight: .bold))
          .symbolRenderingMode(.palette)
          .foregroundStyle(Color.signGreen, Color.signYellow)
          .background(Circle().fill(.white).padding(4))
          .offset(x: 12, y: -14)
          .symbolEffect(.bounce, options: .nonRepeating, value: works)
          .transition(still ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
          .accessibilityHidden(true)
      }
    }
    .scaleEffect(works && !still ? 1.01 : 1)
    .animation(still ? .default : .spring(response: 0.35, dampingFraction: 0.55), value: works)
    .padding(.top, 6)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(draft.isEmpty ? "Your math, empty" : "Your math")
  }

  /// How the math reads, in a few gentle words.
  private var reading: some View {
    let (symbol, words, tint) = readingLine
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: symbol)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(words.0).face(works ? .bodyBold : .body).foregroundStyle(works ? Color.greenInk : Color.ink)
        if let more = words.1 {
          Text(more).face(.meta).foregroundStyle(Color.ink3)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .animation(.snappy, value: status)
    .accessibilityElement(children: .combine)
  }

  private var readingLine: (String, (String, String?), Color) {
    let left = draft.tiles.count - draft.usedCount
    switch status {
    case .empty:
      return ("hand.tap", ("Tap a number to start.", "It just has to be true. Using every number is the fun part, not a requirement."), .ink3)
    case .writing:
      return ("ellipsis", ("Keep going…", nil), .ink3)
    case .oneSide(let value):
      let so = value.map { "So far that’s \($0)." } ?? "So far, so good."
      return ("equal", (so, "Add an = and make the other side match."), .ink3)
    case .notTrue(let values):
      return ("arrow.left.arrow.right", ("Not true yet: \(values.formatted(.list(type: .and))).", "Try another operator, or move a bracket."), .ink3)
    case .problem(let message):
      return ("exclamationmark.circle", (message, nil), .warn)
    case .works(let solved):
      if draft.usesEveryNumber {
        return ("sparkles", ("It works! Both sides make \(solved.value).", "Every number on the sign. Beautiful."), .greenInk)
      }
      let rest = left == 1 ? "One number sits this one out" : "\(left) numbers sit this one out"
      return ("checkmark.circle.fill", ("It works! Both sides make \(solved.value).", "\(rest): fit them in for fun, or post it as it is."), .greenInk)
    }
  }

  // MARK: The numbers

  /// The tiles, and in portrait a word on how they work. Landscape keeps
  /// its height for the keypad.
  private func tiles(hint: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Your numbers").face(.section).foregroundStyle(Color.ink)
      FlowLayout(spacing: 8) {
        ForEach(draft.tiles) { number in
          Tile(number: number, used: draft.isUsed(number.id)) {
            if draft.isUsed(number.id) { draft.takeOut(number.id) } else { draft.place(number.id) }
            taps += 1
          }
        }
      }
      if hint {
        Text("Tap a used number to take it back out. Missing one? Go back and add it.")
          .face(.meta)
          .foregroundStyle(Color.ink3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: The keypad

  private var keypad: some View {
    HStack(spacing: 6) {
      Grid(horizontalSpacing: 6, verticalSpacing: 6) {
        GridRow {
          ForEach([WayDraft.Key.open, .close, .root, .power, .factorial], id: \.self) { key($0) }
        }
        GridRow {
          ForEach([WayDraft.Key.add, .subtract, .multiply, .divide, .equals], id: \.self) { key($0) }
        }
      }
      Button {
        draft.deleteLast()
        taps += 1
      } label: {
        Image(systemName: "delete.left")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(Color.ink)
          .frame(width: 56)
          .frame(maxHeight: .infinity)
          .background(Color.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
      }
      .buttonStyle(CardPress())
      .disabled(draft.isEmpty)
      .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in
        guard !draft.isEmpty else { return }
        draft.clear()
        taps += 1
      })
      .accessibilityLabel("Delete")
      .accessibilityHint("Touch and hold to clear the math.")
      .accessibilityAction(named: "Clear the math") { draft.clear() }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func key(_ key: WayDraft.Key) -> some View {
    Button {
      draft.press(key)
      taps += 1
    } label: {
      Group {
        if key == .power {
          // xʸ, as a calculator writes it.
          (Text("x") + Text("y").font(Face.number.font(size: 12)).baselineOffset(8))
        } else if key == .factorial {
          Text("n!")
        } else {
          Text(key.rawValue)
        }
      }
      .font(.system(size: 22, weight: .semibold, design: .serif))
      .foregroundStyle(key == .equals ? Color.white : Color.ink)
      .frame(maxWidth: .infinity, minHeight: 46)
      .background(key == .equals ? Color.signGreen : Color.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        if key != .equals {
          RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.rule, lineWidth: 1)
        }
      }
    }
    .buttonStyle(CardPress())
    .accessibilityLabel(key.spoken)
  }

  // MARK: The way on

  private var actions: some View {
    HStack(spacing: 10) {
      if !works {
        Button {
          post(nil)
        } label: {
          Text("Post unsolved")
            .face(.button)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ruleStrong, lineWidth: 1.5)
            }
        }
        .buttonStyle(CardPress())
        .transition(.opacity)
      }
      Button {
        if case .works(let solved) = status { post(solved.canonical) }
      } label: {
        Label("Post it", systemImage: works ? "paperplane.fill" : "paperplane")
          .face(.button)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity, minHeight: 52)
          .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(CardPress())
      .disabled(!works)
      .opacity(works ? 1 : 0.45)
      .accessibilityHint(works ? "" : "Write math that works first.")
    }
    .animation(.snappy, value: works)
  }

  private func post(_ way: String?) {
    flow.way = way
    if account.signedIn { flow.path.append(.post) } else { askSignIn = true }
  }

  /// Closes sign-in and, once signed in, goes on to posting.
  private func leaveSignIn() {
    account.finishSignIn()
    signingIn = false
    if account.signedIn { flow.path.append(.post) }
  }

  /// Picks up the math where it was left, following any change to the
  /// numbers since.
  private func start() {
    var kept = flow.draft ?? WayDraft(tiles: flow.numbers.kept)
    kept.retile(flow.numbers.kept)
    #if DEBUG
      if kept.isEmpty, let scripted = Script.text("RSMWay") {
        kept = WayDraft(tiles: flow.numbers.kept, text: scripted)
      }
    #endif
    draft = kept
  }
}

/// One of the sign's numbers: white with a green edge until it's in the
/// math, then green with a tick.
private struct Tile: View {
  let number: CheckedNumber
  let used: Bool
  let tap: () -> Void

  var body: some View {
    Button(action: tap) {
      HStack(spacing: 6) {
        Text(number.text).font(Face.number.font(size: 19))
        if used {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .heavy))
            .transition(.scale.combined(with: .opacity))
        }
      }
      .foregroundStyle(used ? Color.white : Color.greenInk)
      .padding(.horizontal, 14)
      .frame(minWidth: 52, minHeight: 46)
      .background(used ? Color.signGreen : Color.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.signGreen, lineWidth: 1.5)
      }
      .animation(.snappy(duration: 0.2), value: used)
    }
    .buttonStyle(CardPress())
    .accessibilityLabel(number.text)
    .accessibilityValue(used ? "In the math" : "")
    .accessibilityHint(used ? "Takes it back out." : "Puts it in the math.")
  }
}
