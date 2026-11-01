import RoadSignMathAPI
import SwiftUI

/// The website's pages the app links to. Always the live site: a local
/// server has no pages of its own worth reading.
enum SitePage {
  static let privacy = URL(string: "https://roadsignmath.xyz/privacy")!
  static let about = URL(string: "https://roadsignmath.xyz/about")!
  static let ccBy = URL(string: "https://creativecommons.org/licenses/by/4.0/")!
}

// MARK: How to play

/// The game in three steps and an example: How to play in Settings, and
/// the card a new player sees on Home.
struct HowToPlaySteps: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HowToStep(number: 1, title: "Spot it", words: "Any road sign with numbers. Every number counts, even 7B and 82nd.")
      HowToStep(number: 2, title: "Snap it", words: "The passenger takes the photo, never the driver. The app boxes the numbers.")
      HowToStep(
        number: 3, title: "Solve it",
        words: "Write math with its numbers that’s true. Using every one is the fun part, not a requirement.")
      HowToExample()
      Text("Post it and it goes on the map. Anyone can find another way.")
        .face(.body)
        .foregroundStyle(Color.ink2)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct HowToStep: View {
  let number: Int
  let title: String
  let words: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(number)")
        .face(.metaBold)
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(Color.signGreen, in: Circle())
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).face(.section).foregroundStyle(Color.ink)
        Text(words)
          .face(.body)
          .foregroundStyle(Color.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// EXIT 2, COUNTY 5, 1 MILE, and the math it makes.
private struct HowToExample: View {
  var body: some View {
    HStack(spacing: 10) {
      VStack(spacing: 1) {
        Text("EXIT 2")
        Text("COUNTY 5")
        Text("1 MILE")
      }
      .face(.name)
      .foregroundStyle(.white)
      .lineLimit(1)
      .dynamicTypeSize(...DynamicTypeSize.xxLarge)
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .overlay { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white, lineWidth: 2) }
      .padding(3)
      .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      .fixedSize()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("A road sign: Exit 2, County 5, 1 mile")
      Image(systemName: "arrow.right")
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(Color.ink3)
        .accessibilityHidden(true)
      SignPlate(text: "√(5 − 1) = 2", tex: nil, size: 20)
    }
    .padding(.leading, 38)
  }
}

/// How to play on Home, for a new player: shown until it's closed (or its
/// camera opened) or they've posted a sign. After that it lives in
/// Settings, under Help.
struct HowToPlayCard: View {
  let name: String?
  let done: () -> Void
  let openCamera: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(welcome)
            .face(.metaBold)
            .textCase(.uppercase)
            .foregroundStyle(Color.greenInk)
          Text("How to play")
            .face(.title)
            .foregroundStyle(Color.ink)
            .accessibilityAddTraits(.isHeader)
        }
        Spacer(minLength: 0)
        Button(action: done) {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.ink2)
            .frame(width: 36, height: 36)
            .background(Color.ground, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, -4)
        .padding(.trailing, -4)
        .accessibilityLabel("Close How to play")
      }
      HowToPlaySteps()
      // Side by side, "Got it" as wide as its words; stacked at large text.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          gotIt.fixedSize(horizontal: true, vertical: false)
          camera
        }
        VStack(spacing: 10) {
          camera
          gotIt
        }
      }
      Text("You’ll find it again in Settings, under Help.")
        .face(.meta)
        .foregroundStyle(Color.ink3)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
    .padding(.horizontal, 16)
    .padding(.top, 18)
    .padding(.bottom, 14)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.rule) }
    .shadow(color: Color.signGreen.opacity(0.10), radius: 11, y: 8)
    .padding(.horizontal, 12)
    .padding(.top, 10)
    .padding(.bottom, 6)
  }

  private var welcome: String {
    guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "Welcome" }
    return "Welcome, \(name)"
  }

  private var gotIt: some View {
    Button(action: done) {
      Text("Got it")
        .face(.button)
        .foregroundStyle(Color.ink)
        .lineLimit(1)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ruleStrong) }
    }
    .buttonStyle(CardPress())
  }

  private var camera: some View {
    Button(action: openCamera) {
      Label("Open the camera", systemImage: "camera.fill")
        .face(.button)
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(CardPress())
  }
}

/// How to play, from Settings' Help.
struct HowToPlayView: View {
  var body: some View {
    ScrollView {
      HowToPlaySteps()
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color.ground)
    .navigationTitle("How to play")
    .navigationBarTitleDisplayMode(.inline)
  }
}

// MARK: Send feedback

/// A problem, an idea or a hello, emailed to Jamie with your name and
/// page and the build it came from. Your email goes along only when you
/// say Jamie can write back.
struct FeedbackView: View {
  @Environment(Account.self) private var account
  @Environment(\.dismiss) private var dismiss
  @State private var message = ""
  @State private var replyOK = true
  @State private var sending = false
  @State private var sent = false
  @State private var problem: String?
  @FocusState private var typing: Bool

  private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var left: Int { APIClient.feedbackMax - message.serverLength }
  private var email: String { account.me?.email ?? "your email" }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if sent { thanks } else { form }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(Color.ground)
    .navigationTitle("Send feedback")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(sending)
    .sensoryFeedback(.success, trigger: sent)
    #if DEBUG
      // `-RSMFeedbackText <words>` writes the message; `-RSMFeedbackReply NO`
      // turns off the reply; `-RSMFeedbackSend YES` sends it (only ever
      // against `npm run dev`, whose mail lands in `.data/mail/`).
      .task {
        if let words = Script.text("RSMFeedbackText") { message = words }
        if Script.value("RSMFeedbackReply") == "NO" { replyOK = false }
        if Script.flag("RSMFeedbackSend") { send() }
      }
    #endif
  }

  @ViewBuilder private var form: some View {
    Text("A problem, an idea or a hello. It reaches Jamie.")
      .face(.body)
      .foregroundStyle(Color.ink2)
      .fixedSize(horizontal: false, vertical: true)
    VStack(alignment: .trailing, spacing: 6) {
      TextField("What’s on your mind?", text: $message, axis: .vertical)
        .face(.field)
        .lineLimit(6...14)
        .focused($typing)
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(typing ? Color.greenInk : Color.ruleStrong, lineWidth: typing ? 2 : 1.5)
        }
        .onChange(of: message) { _, now in
          if now.serverLength > APIClient.feedbackMax { message = now.clipped(to: APIClient.feedbackMax) }
        }
        .accessibilityLabel("Your feedback")
      if left < 200 {
        Text("\(left) left").face(.meta).foregroundStyle(left < 20 ? Color.warn : Color.ink3)
      }
    }
    Toggle(isOn: $replyOK) {
      Text("Jamie can write back to \(email)")
        .face(.body)
        .foregroundStyle(Color.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .tint(.greenInk)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.rule) }
    Text("It goes with your name and page, the app’s version, and your iPhone’s model and iOS version. Your email goes along only when Jamie can write back.")
      .face(.meta)
      .foregroundStyle(Color.ink3)
      .fixedSize(horizontal: false, vertical: true)
    if let problem { ProblemLine(text: problem) }
    BigButton(label: "Send to Jamie", symbol: "paperplane", busy: sending, enabled: !trimmed.isEmpty && !sending, action: send)
      .padding(.top, 4)
  }

  @ViewBuilder private var thanks: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.system(size: 44, weight: .semibold))
      .foregroundStyle(Color.greenInk)
      .accessibilityHidden(true)
    Text("Thanks!")
      .face(.title)
      .foregroundStyle(Color.ink)
      .accessibilityAddTraits(.isHeader)
    Text(replyOK ? "It’s on its way to Jamie. A reply would come to \(email)." : "It’s on its way to Jamie.")
      .face(.body)
      .foregroundStyle(Color.ink2)
      .fixedSize(horizontal: false, vertical: true)
    Button("Done") { dismiss() }
      .face(.action)
      .foregroundStyle(Color.greenInk)
      .padding(.top, 4)
  }

  private func send() {
    guard !sending, !trimmed.isEmpty else { return }
    sending = true
    problem = nil
    typing = false
    Task {
      do {
        try await account.sendFeedback(trimmed, replyOK: replyOK)
        withAnimation(.smooth) { sent = true }
      } catch {
        problem = Account.say(error)
      }
      sending = false
    }
  }
}

// MARK: About

/// What the app is made with, each with its license.
struct LicensesView: View {
  var body: some View {
    List {
      Section {
        link("Overpass and Overpass Mono", "The type. Copyright 2021 The Overpass Project Authors. SIL Open Font License 1.1.",
             files: ["Overpass-OFL"])
        link("Latin Modern Math", "The type the math is drawn in, by GUST. GUST Font License.",
             files: ["LatinModern-GUST-FONT-LICENSE"])
        link("SwiftMath", "Draws the math. MIT License, copyright 2023 Computer Inspirations; from iosMath, copyright 2013 MathChat.",
             files: ["SwiftMath-LICENSE", "iosMath-LICENSE"])
      } header: {
        Text("Made with").face(.metaBold)
      }
      Section {
        Link(destination: SitePage.ccBy) {
          VStack(alignment: .leading, spacing: 3) {
            Label("CC BY 4.0", systemImage: "arrow.up.right").labelStyle(TrailingIcon())
              .face(.bodyBold)
              .foregroundStyle(Color.ink)
            Text("Every sign, photo and way players post is shared under it: anyone may use them if they credit the player.")
              .face(.meta)
              .foregroundStyle(Color.ink2)
              .fixedSize(horizontal: false, vertical: true)
          }
          .padding(.vertical, 3)
        }
      } header: {
        Text("Signs and photos").face(.metaBold)
      }
    }
    .scrollContentBackground(.hidden)
    .background(Color.ground)
    .navigationTitle("Licenses")
    .navigationBarTitleDisplayMode(.inline)
  }

  private func link(_ title: String, _ words: String, files: [String]) -> some View {
    NavigationLink {
      LicenseText(title: title, files: files)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).face(.bodyBold).foregroundStyle(Color.ink)
        Text(words).face(.meta).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
      }
      .padding(.vertical, 3)
    }
  }
}

/// A license's whole text, from the app's bundle.
private struct LicenseText: View {
  let title: String
  let files: [String]

  private var text: String {
    files.compactMap { name in
      Bundle.main.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
    .joined(separator: "\n\n\n")
  }

  var body: some View {
    ScrollView {
      Text(text)
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(Color.ink)
        .textSelection(.enabled)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Color.ground)
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// A label with its icon after the words: a link that leaves the app.
struct TrailingIcon: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.title
      configuration.icon.font(.system(size: 12, weight: .bold)).foregroundStyle(Color.ink3)
    }
  }
}
