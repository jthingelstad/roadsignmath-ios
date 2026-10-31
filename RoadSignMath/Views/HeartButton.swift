import RoadSignMathAPI
import SwiftUI

/// A sign's heart and its count, the website's and the app's together.
/// A tap gives your heart with a burst of little hearts and a firm tap
/// under your thumb, as the website's button does; another takes it back.
/// Signed out, it asks you to sign in first.
struct HeartButton: View {
  /// The sign as it is now (`Store.current`), so a heart just given shows.
  let sign: Sign
  var large = false

  @Environment(Store.self) private var store
  @Environment(Account.self) private var account
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var bursts = 0
  @State private var takenBack = 0
  @State private var pop = false
  @State private var askSignIn = false

  /// Read through the store, so a tap sees a heart given a moment ago.
  private var hearted: Bool { account.signedIn && store.current(sign).hearted == true }

  var body: some View {
    Button(action: tap) {
      HStack(spacing: 5) {
        Image(systemName: hearted ? "heart.fill" : "heart")
          .font(.system(size: large ? 20 : 19, weight: .medium))
          .foregroundStyle(hearted ? Color.heart : Color.ink2)
          .scaleEffect(pop ? 1.32 : 1)
          .overlay { if !reduceMotion { HeartBurst(trigger: bursts) } }
        if let count = sign.hearts, count > 0 {
          Text(count.formatted())
            .face(.metaBold)
            .monospacedDigit()
            .foregroundStyle(hearted ? Color.heart : Color.ink2)
            .contentTransition(.numericText(value: Double(count)))
        }
      }
      .padding(.horizontal, large ? 12 : 10)
      .frame(minWidth: 44, minHeight: large ? 40 : 44)
      .background {
        if large {
          Capsule().fill(hearted ? Color.heartSoft : .clear)
          Capsule().strokeBorder(hearted ? Color.heart : Color.ruleStrong, lineWidth: 1.5)
        }
      }
      .contentShape(Rectangle())
      .animation(.snappy, value: sign.hearts)
      .animation(.snappy, value: hearted)
    }
    .buttonStyle(.plain)
    .zIndex(1)
    .sensoryFeedback(.impact(weight: .medium, intensity: 1), trigger: bursts)
    .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: takenBack)
    .accessibilityLabel(hearted ? "Take back your heart" : "Heart this sign")
    .accessibilityValue(countWords)
    #if DEBUG
      // `-RSMHeart YES` with `-RSMOpen /signs/<slug>`: taps the sign page's
      // heart a moment after it opens (`-RSMHeart twice` takes it back after).
      .task {
        guard large, let say = Script.value("RSMHeart") else { return }
        try? await Task.sleep(for: .seconds(2))
        tap()
        if say == "twice" {
          try? await Task.sleep(for: .seconds(2.5))
          tap()
        }
      }
    #endif
    .signInFirst($askSignIn, title: "Sign in to heart it",
                 waiting: "Hearts come from players. Sign in, and your heart goes on this sign.") {
      give(true)
    }
  }

  private var countWords: String {
    guard let count = sign.hearts else { return "" }
    return count == 1 ? "1 heart" : "\(count) hearts"
  }

  private func tap() {
    guard account.signedIn else { return askSignIn = true }
    give(!hearted)
  }

  private func give(_ on: Bool) {
    if on {
      bursts += 1
      withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { pop = true }
      Task {
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { pop = false }
      }
    } else {
      takenBack += 1
    }
    let sign = store.current(self.sign)
    Task {
      do {
        try await store.heart(sign, on)
      } catch {
        withAnimation { account.notice = Self.say(error, on: on) }
      }
    }
  }

  static func say(_ error: any Error, on: Bool) -> String {
    if let error = error as? APIError, error.status != 503 { return error.message }
    if error is APIError || error is URLError {
      return on ? "Your heart didn’t go on just now. Try again in a minute." : "Your heart couldn’t be taken back just now. Try again in a minute."
    }
    return Store.say(error)
  }
}

/// A burst of little hearts from the middle of a heart that was just
/// given: thrown up and out, turning, falling back and fading.
struct HeartBurst: View {
  let trigger: Int
  var count = 12

  var body: some View {
    ZStack {
      ForEach(0..<count, id: \.self) { index in
        Flyer(index: index, of: count, trigger: trigger)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private struct Motion {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var scale: CGFloat = 0.3
    var opacity: Double = 0
    var angle: Double = 0
  }

  private struct Flyer: View {
    let index: Int
    let of: Int
    let trigger: Int

    var body: some View {
      // Each burst throws its hearts a little differently.
      var random = Wobble(seed: UInt64(index &* 7919 &+ trigger &* 104_729 &+ 1))
      let spread = Double.pi * 1.25
      let angle = -Double.pi / 2 - spread / 2 + spread * (Double(index) + random.next(0.15, 0.85)) / Double(of)
      let reach = random.next(34, 64)
      let dx = CGFloat(cos(angle) * reach)
      let rise = CGFloat(sin(angle) * reach)
      let fall = CGFloat(random.next(18, 34))
      let spin = random.next(-50, 50)
      let size = random.next(8, 14)
      let tint = [Color.heart, Color.heart.opacity(0.8), Color(light: 0xE0566B, dark: 0xF28C9C)][index % 3]

      return Image(systemName: "heart.fill")
        .font(.system(size: size))
        .foregroundStyle(tint)
        .keyframeAnimator(initialValue: Motion(), trigger: trigger) { content, m in
          content
            .scaleEffect(m.scale)
            .rotationEffect(.degrees(m.angle))
            .offset(x: m.x, y: m.y)
            .opacity(m.opacity)
        } keyframes: { _ in
          KeyframeTrack(\.x) {
            CubicKeyframe(dx, duration: 0.95)
          }
          KeyframeTrack(\.y) {
            CubicKeyframe(rise, duration: 0.38)
            CubicKeyframe(rise + fall, duration: 0.57)
          }
          KeyframeTrack(\.scale) {
            SpringKeyframe(1, duration: 0.25, spring: .bouncy)
            LinearKeyframe(1, duration: 0.45)
            LinearKeyframe(0.5, duration: 0.25)
          }
          KeyframeTrack(\.opacity) {
            LinearKeyframe(1, duration: 0.06)
            LinearKeyframe(1, duration: 0.57)
            LinearKeyframe(0, duration: 0.32)
          }
          KeyframeTrack(\.angle) {
            LinearKeyframe(spin, duration: 0.95)
          }
        }
    }
  }
}

/// A small steady random number source (SplitMix64), so a burst can be
/// drawn the same way each time SwiftUI asks for it.
private struct Wobble {
  var state: UInt64
  init(seed: UInt64) { state = seed }

  mutating func next(_ low: Double, _ high: Double) -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    return low + (high - low) * Double(z >> 11) / Double(1 << 53)
  }
}
