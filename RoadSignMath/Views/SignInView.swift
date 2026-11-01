import RoadSignMathAPI
import SwiftUI

/// Signing in, from the boards' Sign in and Check your email screens: an
/// email, then the 6-digit code from it (or the link, tapped on this
/// iPhone), a name the first time, and the moment you're in.
struct SignInView: View {
  /// Shown as the app's first screen, before anyone has looked around.
  var firstRun = false
  var lookAround: () -> Void

  @Environment(Account.self) private var account

  var body: some View {
    ZStack {
      switch account.step {
      case .email:
        EmailStep(firstRun: firstRun, close: lookAround)
          .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading)).combined(with: .opacity))
      case .code:
        CodeStep()
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .name:
        NameStep()
          .transition(.move(edge: .trailing).combined(with: .opacity))
      case .welcome:
        WelcomeStep()
          .transition(.opacity)
      }
    }
    .animation(.smooth(duration: 0.35), value: account.step)
    .background(Color.card)
    .interactiveDismissDisabled(account.step == .name || account.step == .welcome)
  }
}

// MARK: Email

private struct EmailStep: View {
  let firstRun: Bool
  let close: () -> Void

  @Environment(Account.self) private var account
  @State private var email = ""
  @State private var sending = false
  @State private var problem: String?
  @FocusState private var typing: Bool

  private var plausible: Bool {
    email.trimmingCharacters(in: .whitespaces).wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        hero
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 8) {
            Text("Email").face(.label).foregroundStyle(Color.ink)
            TextField("name@example.com", text: $email)
              .face(.field)
              .textContentType(.emailAddress)
              .keyboardType(.emailAddress)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .submitLabel(.send)
              .focused($typing)
              .onSubmit(send)
              .padding(.horizontal, 16)
              .frame(minHeight: 52)
              .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .strokeBorder(typing ? Color.greenInk : Color.ruleStrong, lineWidth: typing ? 2 : 1.5)
              }
              .accessibilityLabel("Email")
          }
          if let problem = problem ?? account.linkProblem {
            ProblemLine(text: problem)
          }
          BigButton(label: "Email me a sign-in code", symbol: "envelope", busy: sending, enabled: plausible, action: send)
          Text("No password. We email you a 6-digit code to type here, and a link that signs you in when you tap it on this iPhone.")
            .face(.body)
            .foregroundStyle(Color.ink2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 24)
          Button(action: close) {
            Text(firstRun ? "Look around first" : "Not now")
              .face(.nameLarge)
              .foregroundStyle(Color.ink)
              .frame(maxWidth: .infinity, minHeight: 48)
              .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ruleStrong, lineWidth: 1.5)
              }
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          Text("Signing in puts your name on the signs you find. Your email is only for signing in; nobody else sees it.")
            .face(.meta)
            .foregroundStyle(Color.ink3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 22) {
            Link("Privacy", destination: SitePage.privacy)
            Link("About", destination: SitePage.about)
          }
          .face(.metaBold)
          .foregroundStyle(Color.greenInk)
          .frame(maxWidth: .infinity, minHeight: 32)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .onAppear {
      if email.isEmpty, let last = account.pending?.email { email = last }
      if let scripted = Script.value("RSMSignIn"), email.isEmpty {
        email = scripted
        send()
      }
    }
  }

  private var hero: some View {
    VStack(spacing: 22) {
      GuideSign()
      VStack(spacing: 6) {
        Text("Road Sign Math")
          .face(.hero)
          .foregroundStyle(Color.ink)
          .accessibilityAddTraits(.isHeader)
        Text("3 × 33 = 99. Find the next one.")
          .face(.lead)
          .foregroundStyle(Color.ink2)
      }
      .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 24)
    .padding(.top, 36)
    .padding(.bottom, 32)
    .frame(maxWidth: .infinity)
    // Up under the status bar, and above it when the page is pulled down.
    .background { Color.ground.padding(.top, -600).ignoresSafeArea(edges: .top) }
  }

  private func send() {
    guard plausible, !sending else { return }
    sending = true
    problem = nil
    account.linkProblem = nil
    Task {
      do {
        try await account.start(email: email)
        typing = false
      } catch {
        problem = Account.say(error)
      }
      sending = false
    }
  }
}

/// The Genesis sign near Melrose, Minnesota, 3 × 33 = 99, as a guide sign:
/// the boards' sign-in picture.
struct GuideSign: View {
  private let rows = [("Melrose", "3"), ("St Cloud", "33"), ("Minneapolis", "99")]

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
      ForEach(rows, id: \.0) { row in
        GridRow {
          Text(row.0)
          Text(row.1).gridColumnAlignment(.trailing)
        }
      }
    }
    .face(.guideSign)
    .lineLimit(1)
    .minimumScaleFactor(0.6)
    // A picture of a sign, read whole by VoiceOver: it grows with the
    // text size, but not so far that the place names break.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .foregroundStyle(.white)
    .padding(.horizontal, 18)
    .padding(.top, 14)
    .padding(.bottom, 10)
    .frame(maxWidth: 300)
    .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(.white, lineWidth: 3) }
    .padding(6)
    .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .shadow(color: Color(red: 0, green: 0.24, blue: 0.16).opacity(0.25), radius: 14, y: 12)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("A road sign: Melrose 3, St Cloud 33, Minneapolis 99")
  }
}

// MARK: Code

private struct CodeStep: View {
  @Environment(Account.self) private var account
  @Environment(\.openURL) private var openURL
  @State private var code = ""
  @State private var checking = false
  @State private var problem: String?
  @State private var wrong = 0
  @State private var resent: String?
  @State private var resending = false
  @FocusState private var typing: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Button {
          account.useAnotherEmail()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to your email")
        .padding(.leading, -12)

        Image(systemName: "envelope.open")
          .font(.system(size: 40, weight: .medium))
          .foregroundStyle(Color.signGreen)
          .frame(width: 88, height: 88)
          .background(Color.wayGround, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
          .symbolEffect(.bounce, options: .nonRepeating, value: resent)
          .accessibilityHidden(true)
        Text("Check your email")
          .face(.display)
          .foregroundStyle(Color.ink)
          .accessibilityAddTraits(.isHeader)
        Text("We sent a code to \(Text(account.pending?.email ?? "your email").bold().foregroundStyle(Color.ink)). Type it here, or tap the link in the email on this iPhone. Both work for 15 minutes.")
          .face(.lead)
          .foregroundStyle(Color.ink2)
          .fixedSize(horizontal: false, vertical: true)

        CodeField(code: $code, wrong: wrong, checking: checking, typing: $typing)
          .onChange(of: code) { _, now in
            let digits = String(now.filter { $0.isASCII && $0.isNumber }.prefix(6))
            if digits != now { code = digits; return }
            if digits.count == 6 { check() } else if !digits.isEmpty { clearProblems() }
          }
        // A link from the email that didn't work lands here too, when an
        // email is waiting for its code.
        if let problem = problem ?? account.linkProblem {
          ProblemLine(text: problem)
        } else if let resent {
          Text(resent).face(.metaBold).foregroundStyle(Color.greenInk)
            .transition(.opacity)
        }

        Button {
          if let mail = URL(string: "message://") { openURL(mail) }
        } label: {
          Label("Open Mail", systemImage: "envelope")
            .face(.button)
            .foregroundStyle(Color.greenInk)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ruleStrong, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)

        VStack(spacing: 2) {
          Button(action: resend) {
            HStack(spacing: 8) {
              if resending { ProgressView().controlSize(.small) }
              Text("Send the email again")
            }
            .face(.nameLarge)
            .foregroundStyle(Color.greenInk)
            .frame(minHeight: 44)
          }
          .disabled(resending)
          Button("Use a different email") { account.useAnotherEmail() }
            .face(.nameLarge)
            .foregroundStyle(Color.ink2)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .onAppear {
      typing = true
      if let scripted = Script.value("RSMCode"), code.isEmpty { code = scripted }
    }
    .sensoryFeedback(.error, trigger: wrong)
    .sensoryFeedback(.error, trigger: account.linkProblem) { _, now in now != nil }
  }

  private func clearProblems() {
    problem = nil
    account.linkProblem = nil
  }

  private func check() {
    guard !checking else { return }
    clearProblems()
    checking = true
    typing = false
    Task {
      do {
        try await account.verify(code: code)
      } catch {
        problem = Account.say(error)
        withAnimation(.default) { wrong += 1 }
        code = ""
        typing = true
      }
      checking = false
    }
  }

  private func resend() {
    guard let email = account.pending?.email else { return account.useAnotherEmail() }
    resending = true
    clearProblems()
    Task {
      do {
        try await account.start(email: email, again: true)
        withAnimation { resent = "Sent again. A code from either email works." }
      } catch {
        problem = Account.say(error)
      }
      resending = false
    }
  }
}

/// Six boxes over one hidden field, so the keyboard's one-time-code
/// suggestion (from Mail or Messages) and pasting fill the whole code.
/// VoiceOver hears one field, "Sign-in code".
private struct CodeField: View {
  @Binding var code: String
  let wrong: Int
  let checking: Bool
  var typing: FocusState<Bool>.Binding

  var body: some View {
    ZStack {
      TextField("", text: $code)
        .textContentType(.oneTimeCode)
        .keyboardType(.numberPad)
        .focused(typing)
        .foregroundStyle(.clear)
        .tint(.clear)
        .frame(maxWidth: .infinity, minHeight: 60)
        .accessibilityLabel("Sign-in code")
        .accessibilityHint("Six digits, from the email")
      HStack(spacing: 8) {
        ForEach(0..<6, id: \.self) { index in box(index) }
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
      .modifier(Shake(times: CGFloat(wrong)))
    }
    .contentShape(Rectangle())
    .onTapGesture { typing.wrappedValue = true }
  }

  private func box(_ index: Int) -> some View {
    let digits = Array(code)
    let filled = index < digits.count
    let current = typing.wrappedValue && index == min(digits.count, 5) && !checking
    return Text(filled ? String(digits[index]) : "")
      .face(.digit)
      .foregroundStyle(Color.ink)
      .frame(maxWidth: 52)
      .frame(height: 60)
      .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(current ? Color.greenInk : filled ? Color.ink : Color.ruleStrong, lineWidth: current ? 2.5 : 1.5)
      }
      .opacity(checking ? 0.45 : 1)
      .animation(checking ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: checking)
      .animation(.snappy(duration: 0.15), value: filled)
  }
}

/// A wrong code's shake, side to side.
private struct Shake: GeometryEffect {
  var times: CGFloat
  var animatableData: CGFloat {
    get { times }
    set { times = newValue }
  }

  func effectValue(size: CGSize) -> ProjectionTransform {
    ProjectionTransform(CGAffineTransform(translationX: 8 * sin(times * .pi * 4), y: 0))
  }
}

// MARK: Name

private struct NameStep: View {
  @Environment(Account.self) private var account
  @State private var name = ""
  @State private var saving = false
  @State private var problem: String?
  @FocusState private var typing: Bool

  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Label("Welcome!", systemImage: "hand.wave.fill")
          .face(.label)
          .foregroundStyle(Color.greenInk)
          .symbolEffect(.wiggle, options: .nonRepeating)
          .padding(.top, 32)
        Text("What should we call you?")
          .face(.display)
          .foregroundStyle(Color.ink)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text("Your name goes on the signs you find, for everyone to see.")
          .face(.lead)
          .foregroundStyle(Color.ink2)
          .fixedSize(horizontal: false, vertical: true)
        TextField("Your name", text: $name)
          .face(.field)
          .textContentType(.givenName)
          .submitLabel(.done)
          .focused($typing)
          .onSubmit(save)
          .padding(.horizontal, 16)
          .frame(minHeight: 52)
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(typing ? Color.greenInk : Color.ruleStrong, lineWidth: typing ? 2 : 1.5)
          }
          .onChange(of: name) { _, now in if now.count > 40 { name = String(now.prefix(40)) } }
        address
        if let problem { ProblemLine(text: problem) }
        BigButton(label: "That’s me", symbol: "checkmark", busy: saving, enabled: !trimmed.isEmpty, action: save)
        Button("Not now") { account.nameLater() }
          .face(.nameLarge)
          .foregroundStyle(Color.ink2)
          .frame(maxWidth: .infinity, minHeight: 44)
          .buttonStyle(.plain)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
    }
    .scrollBounceBehavior(.basedOnSize)
    .onAppear {
      typing = true
      if let scripted = Script.value("RSMName"), name.isEmpty {
        name = scripted
        if Script.flag("RSMNameSave") { save() }
      }
    }
  }

  /// Where their page will be, said kindly: the address is for good.
  private var address: some View {
    let handle = Handle.preview(for: trimmed)
    let home = account.me.map { $0.url.deletingLastPathComponent() }
    let shown = home.map { ($0.host() ?? "roadsignmath.xyz") + ($0.port.map { ":\($0)" } ?? "") + $0.path() }
      ?? "roadsignmath.xyz/players/"
    return HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "signpost.right")
        .foregroundStyle(Color.greenInk)
        .accessibilityHidden(true)
      Group {
        if let handle {
          Text("Your page will be at \(Text(shown + handle).bold().foregroundStyle(Color.ink)). You can change your name later, but the address stays for good, so links to your page always work.")
        } else {
          Text("Your first name also makes the address of your page, and that address stays for good, so links to it always work. You can change your name later.")
        }
      }
      .face(.meta)
      .foregroundStyle(Color.ink2)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .animation(.snappy, value: handle)
  }

  private func save() {
    guard !trimmed.isEmpty, !saving else { return }
    saving = true
    problem = nil
    Task {
      do {
        try await account.setName(trimmed)
        typing = false
        account.step = .welcome
      } catch {
        problem = Account.say(error)
        if !account.signedIn { account.finishSignIn() }
      }
      saving = false
    }
  }
}

// MARK: You're in

private struct WelcomeStep: View {
  @Environment(Account.self) private var account
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
  @Environment(\.accessibilityReduceMotion) private var still
  @State private var shown = false

  private var name: String { account.me?.name ?? "" }

  var body: some View {
    VStack(spacing: 22) {
      Spacer()
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 56, weight: .semibold))
        .foregroundStyle(Color.greenInk)
        .symbolEffect(.bounce, options: .nonRepeating, value: shown)
        .accessibilityHidden(true)
      Text(name.isEmpty ? "You’re in." : "You’re in, \(name).")
        .face(.display)
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      SignPlate(text: "Driving + Math = Fun", tex: "\\text{Driving} + \\text{Math} = \\text{Fun}", size: 26, large: true)
        .frame(maxWidth: 340)
        .scaleEffect(shown || still ? 1 : 0.6)
        .rotationEffect(.degrees(shown || still ? 0 : -6))
        .opacity(shown ? 1 : 0)
        .accessibilityHidden(true)
      Text("Find a sign whose numbers make true math, and post it from the passenger seat.")
        .face(.lead)
        .foregroundStyle(Color.ink2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Spacer()
      BigButton(label: "Let’s go", symbol: "arrow.right", busy: false, enabled: true) { account.finishSignIn() }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 20)
    .sensoryFeedback(.success, trigger: shown)
    .onAppear {
      withAnimation(.spring(duration: 0.6, bounce: 0.45)) { shown = true }
    }
    .task {
      // A beat to enjoy it, then on to the signs. VoiceOver users go on
      // with the button, in their own time.
      guard !voiceOver else { return }
      try? await Task.sleep(for: .seconds(2.6))
      if account.step == .welcome { account.finishSignIn() }
    }
  }
}

// MARK: Bits

/// The boards' big green button, with a spinner while it works.
struct BigButton: View {
  let label: String
  let symbol: String
  let busy: Bool
  let enabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        if busy {
          ProgressView().tint(.white)
        } else {
          Image(systemName: symbol).font(.system(size: 17, weight: .bold)).accessibilityHidden(true)
        }
        Text(label).face(.button)
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 54)
      .background(Color.signGreen.opacity(enabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(CardPress())
    .disabled(!enabled || busy)
    .accessibilityValue(busy ? "Working" : "")
  }
}

/// What went wrong, in red, read out by VoiceOver as soon as it shows.
struct ProblemLine: View {
  let text: String

  var body: some View {
    Label {
      Text(text).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "exclamationmark.circle.fill")
    }
    .face(.metaBold)
    .foregroundStyle(Color.warn)
    .transition(.opacity)
    .onAppear { AccessibilityNotification.Announcement(text).post() }
    .onChange(of: text) { _, now in AccessibilityNotification.Announcement(now).post() }
  }
}
