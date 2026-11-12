import SignCapture
import SwiftUI

/// The boards' Solve: the math as it's written, on a sign of its own; the
/// sign's numbers as tiles that check off as they go in; a keypad of
/// operators; and a line that says how the math reads, ending in "It works".
/// The math uses every number kept on Check the numbers (Jamie,
/// 2026-11-12: "require every number in new ways"), so true math that
/// leaves one out says which and holds Post it.
struct SolveView: View {
  @Environment(CaptureFlow.self) private var flow
  @Environment(Account.self) private var account
  @Environment(\.accessibilityReduceMotion) private var still
  @State private var draft = WayDraft(tiles: [])
  @State private var askSignIn = false
  /// Bumped by every tile and key, for the tap's haptic.
  @State private var taps = 0
  /// The space above the keypad, and how tall the math and tiles are in it,
  /// so the photo can take what's left.
  @State private var room = CGSize.zero
  @State private var rest: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
      if geometry.size.width > geometry.size.height {
        HStack(alignment: .top, spacing: 16) {
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              ShotStrip(height: 96)
              editor.board
              editor.reading
            }
            // Room for the ring and the seal, which the scroll view would clip.
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
          }
          .scrollBounceBehavior(.basedOnSize)
          VStack(spacing: 12) {
            ScrollView { editor.tiles(hint: false).padding(.vertical, 12) }
              .scrollBounceBehavior(.basedOnSize)
            editor.keypad
            actions
          }
          .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
      } else {
        VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 14) {
              ShotStrip(height: stripHeight)
              VStack(alignment: .leading, spacing: 14) {
                editor.board
                editor.reading
                editor.tiles(hint: true)
              }
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rest = $0 }
            }
            .padding(16)
          }
          .scrollBounceBehavior(.basedOnSize)
          .onGeometryChange(for: CGSize.self) { $0.size } action: { room = $0 }
          VStack(spacing: 12) {
            editor.keypad
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
    .savesForLater()
    .sensoryFeedback(.selection, trigger: taps)
    .sensoryFeedback(.success, trigger: works) { _, now in now }
    .onAppear(perform: start)
    .onChange(of: draft) { _, now in flow.draft = now }
    .onChange(of: works) { _, now in
      if now { AccessibilityNotification.Announcement("It works").post() }
    }
    .signInToPost($askSignIn, waiting: "Your photo and your math wait right here while you do.") {
      flow.path.append(.post)
    }
  }

  /// The photo takes the room the math and tiles leave above the keypad:
  /// at least 110 points, and never less than its numbers need (ShotStrip
  /// sees to that). Past the whole photo's height it closes in on the
  /// numbers, up to half as big again.
  private var stripHeight: CGFloat {
    guard let size = flow.shot?.picture.size else { return 110 }
    let whole = ShotStrip.height(for: nil, of: size, width: room.width - 32)
    let free = room.height - 32 - 14 - rest
    // Closer in, but never so close that a number falls off the sides.
    let span = ShotStrip.numbers(flow.numbers.kept).map { $0.width + 0.08 } ?? 1
    return max(110, min(whole * min(1.5, 1 / span), free))
  }

  private var status: WayDraft.Status { draft.status }
  private var works: Bool { status.works }

  /// The math, how it reads, the tiles and the keypad.
  private var editor: WayEditor {
    WayEditor(draft: $draft, taps: $taps, still: still, hint: "Tap a used number to take it back out. Missing one? Go back and add it.",
              leftOutHelp: "Every number you kept goes in. One that isn’t part of the sign? Go back and untick it.")
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
      .accessibilityHint(works ? "" : status.isLeftOut ? "Use every number first." : "Write math that works first.")
    }
    .animation(.snappy, value: works)
  }

  private func post(_ way: String?) {
    flow.way = way
    if account.signedIn { flow.path.append(.post) } else { askSignIn = true }
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
