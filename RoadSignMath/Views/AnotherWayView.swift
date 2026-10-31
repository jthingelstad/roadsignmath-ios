import RoadSignMathAPI
import SignCapture
import SwiftUI

/// "Find another way": Solve's editor on a posted sign's numbers, under
/// the sign's photo and the ways found so far. A new true way goes on the
/// sign, and any badge it earned flips in, as on Posted!. Anyone can write
/// one; posting it asks you to sign in.
struct AnotherWayView: View {
  let sign: Sign

  @Environment(Store.self) private var store
  @Environment(Account.self) private var account
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var still
  @State private var detail: SignDetail?
  @State private var failed: String?
  @State private var draft = WayDraft(tiles: [])
  @State private var taps = 0
  @State private var name = ""
  @State private var sending = false
  @State private var problem: String?
  @State private var askSignIn = false
  /// The way went on: the sign as the server answered.
  @State private var added: SignDetail?
  @State private var flipped = false
  @FocusState private var naming: Bool

  private var ways: [Way] { detail?.ways ?? [] }
  private var taken: Set<String> { Set(ways.map(\.text)) }
  private var fresh: Bool { WayEditor.isNew(draft.status, taken: taken) }
  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var needsName: Bool { account.signedIn && account.me?.needsName == true }

  private var editor: WayEditor {
    WayEditor(draft: $draft, taps: $taps, still: still, hint: "Tap a used number to take it back out.", taken: taken)
  }

  var body: some View {
    NavigationStack {
      Group {
        if let added {
          done(added)
        } else if detail != nil {
          writing
        } else if let failed {
          Notice(symbol: "signpost.right", title: "Can’t open this sign", message: failed,
                 action: ("Try again", { Task { await load(fresh: true) } }))
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(Color.ground)
      .navigationTitle(added == nil ? "Find another way" : "")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color.ground, for: .navigationBar)
      .toolbar {
        if added == nil {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
          }
        }
      }
    }
    .tint(.greenInk)
    .interactiveDismissDisabled(!draft.isEmpty && added == nil)
    .sensoryFeedback(.selection, trigger: taps)
    .sensoryFeedback(.success, trigger: fresh) { _, now in now }
    .onChange(of: fresh) { _, now in
      if now { AccessibilityNotification.Announcement("It works").post() }
    }
    .onChange(of: draft) { problem = nil }
    .signInToPost($askSignIn, waiting: "Your math waits right here while you do.") { post() }
    .task { await load(fresh: true) }
  }

  private func load(fresh: Bool) async {
    do {
      let read = try await store.detail(sign.id, fresh: fresh)
      let start = detail == nil
      detail = read
      failed = nil
      if start { begin(read) }
    } catch {
      if !Store.cancelled(error), detail == nil { failed = Store.say(error) }
    }
  }

  /// The tiles are the sign's numbers, as it was posted with them.
  private func begin(_ read: SignDetail) {
    let tiles = WayDraft.tiles(onSign: (read.sign.numbers ?? []).map(\.value))
    draft = WayDraft(tiles: tiles)
    #if DEBUG
      if let scripted = Script.text("RSMWay") { draft = WayDraft(tiles: tiles, text: scripted) }
      if let ids = Script.value("RSMWayAdded"), case .works(let solved) = draft.status {
        Task { await scriptAdded(read, way: solved.canonical, unlocked: ids.split(separator: ",").map(String.init)) }
      }
    #endif
  }

  #if DEBUG
    /// `-RSMWayAdded <id,id>` with `-RSMWay <math>`: the done screen as if
    /// that way had gone on and earned these badges. Shown, never sent.
    private func scriptAdded(_ read: SignDetail, way: String, unlocked ids: [String]) async {
      let catalog = (try? await store.client.badges()) ?? []
      let badgeSign = BadgeSign(id: read.sign.id, slug: read.sign.slug, title: read.sign.title, url: read.sign.url)
      let badges = ids.map { id in
        let known = catalog.first { $0.id == id }
        let step = known?.steps?.first
        return EarnedBadge(
          id: id, shelf: known?.shelf ?? .math, name: known?.name ?? id, how: known?.how ?? "",
          mark: step.map(String.init) ?? known?.mark ?? "?", step: step, earnedOn: "2026-10-31", sign: badgeSign)
      }
      // Ways have no public init; go through JSON as the server would answer.
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase
      encoder.dateEncodingStrategy = .iso8601
      var answer = read
      answer.unlocked = badges
      guard let data = try? encoder.encode(answer),
            var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var ways = object["ways"] as? [[String: Any]] else { return }
      let me = account.me.map { ["handle": $0.handle, "name": $0.name] } ?? ["handle": "you", "name": "You"]
      ways.append(["id": "01scripted", "text": way, "value": "", "numbers": [String](), "by": me,
                   "created_at": Date.now.formatted(.iso8601)])
      object["ways"] = ways
      guard let json = try? JSONSerialization.data(withJSONObject: object),
            let shown = try? APIClient.decoder.decode(SignDetail.self, from: json) else { return }
      added = shown
      celebrate(shown.unlocked)
    }
  #endif

  // MARK: Writing

  private var writing: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          header
          editor.board
          editor.reading
          if draft.tiles.isEmpty {
            Text("This sign was posted without its numbers, so there’s nothing to make math from.")
              .face(.body)
              .foregroundStyle(Color.ink2)
          } else {
            editor.tiles(hint: true)
          }
          if needsName { yourName }
        }
        .padding(16)
      }
      .scrollBounceBehavior(.basedOnSize)
      .scrollDismissesKeyboard(.interactively)
      VStack(spacing: 12) {
        if !naming { editor.keypad }
        if let problem {
          Text(problem)
            .face(.meta)
            .foregroundStyle(Color.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        postButton
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)
      .padding(.bottom, 8)
      .background(Color.ground.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
    }
  }

  /// The sign: its photo, its name and place, and the ways already on it,
  /// so a new one is new.
  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Color.photoGround
          .frame(width: 96, height: 72)
          .overlay {
            if let photo = sign.photos.first { PhotoView(url: photo.thumbUrl, alt: photo.alt, pixels: 300) }
          }
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(sign.title).face(.nameLarge).foregroundStyle(Color.ink).lineLimit(2)
          Text("\(sign.finderNames)\(String.dot)\(sign.place.label)")
            .face(.meta)
            .foregroundStyle(Color.ink3)
            .lineLimit(2)
        }
        Spacer(minLength: 0)
      }
      .accessibilityElement(children: .combine)
      if !ways.isEmpty {
        Text(ways.count == 1 ? "The way so far" : "\(ways.count) ways so far")
          .face(.metaBold)
          .foregroundStyle(Color.ink2)
          .padding(.top, 2)
        ForEach(ways) { way in
          HStack(spacing: 10) {
            MathLine(text: way.text, tex: way.tex, size: 16, light: 0x1F3A2E, dark: 0xCDE8DA, fallback: .bodyBold, leading: true)
              .frame(maxWidth: .infinity, alignment: .leading)
            if let by = way.by { Text(by.name).face(.meta).foregroundStyle(Color.ink2) }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(Color.wayGround, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
          .accessibilityElement(children: .combine)
        }
      }
    }
  }

  private var yourName: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Your name").face(.section).foregroundStyle(Color.ink)
      TextField("Your name", text: $name)
        .face(.field)
        .focused($naming)
        .textContentType(.name)
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(naming ? Color.signGreen : Color.ruleStrong, lineWidth: 1.5)
        }
      Text("It goes beside your way. Your first name also makes your page’s address, for good.")
        .face(.meta)
        .foregroundStyle(Color.ink3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, 6)
  }

  private var ready: Bool { fresh && !sending && (!needsName || !trimmedName.isEmpty) }

  private var postButton: some View {
    Button(action: post) {
      HStack(spacing: 8) {
        if sending {
          ProgressView().tint(.white)
        } else {
          Image(systemName: fresh ? "paperplane.fill" : "paperplane")
        }
        Text(sending ? "Adding your way…" : "Add this way")
      }
      .face(.button)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(CardPress())
    .disabled(!ready)
    .opacity(ready || sending ? 1 : 0.45)
    .accessibilityHint(fresh ? "" : needsName && trimmedName.isEmpty ? "Give your name first." : "Write a new way that works first.")
  }

  private func post() {
    guard fresh, case .works(let solved) = draft.status else { return }
    guard account.signedIn else { return askSignIn = true }
    // Just signed in with no name yet: the name field shows; post once it's filled in.
    if needsName, trimmedName.isEmpty { return naming = true }
    sending = true
    problem = nil
    Task {
      defer { sending = false }
      do {
        if needsName { try await account.setName(trimmedName) }
        let answer = try await account.addWay(solved.canonical, to: sign.id)
        store.wayAdded(answer)
        withAnimation(.smooth) { added = answer }
        celebrate(answer.unlocked)
      } catch let error as APIError where error.code == "conflict" {
        // Found by someone else meanwhile: read the ways again, so the editor says so.
        problem = error.message + "."
        await load(fresh: true)
      } catch {
        problem = Account.say(error)
      }
    }
  }

  // MARK: Done

  private func done(_ answer: SignDetail) -> some View {
    let mine = answer.ways.last { $0.by?.handle == account.me?.handle } ?? answer.ways.last
    return ScrollView {
      VStack(spacing: 20) {
        Image(systemName: "checkmark.seal.fill")
          .font(.system(size: 54, weight: .bold))
          .symbolRenderingMode(.palette)
          .foregroundStyle(Color.signGreen, Color.signYellow)
          .symbolEffect(.bounce, options: .nonRepeating, value: added != nil)
          .padding(.top, 28)
          .accessibilityHidden(true)
        VStack(spacing: 6) {
          Text("Another way!")
            .face(.title)
            .foregroundStyle(Color.ink)
            .accessibilityAddTraits(.isHeader)
          Text(answer.ways.count == 2 ? "\(answer.sign.title) has two ways now." : "\(answer.sign.title) has \(answer.ways.count) ways now.")
            .face(.body)
            .foregroundStyle(Color.ink2)
            .multilineTextAlignment(.center)
        }
        if let mine {
          SignPlate(text: mine.text, tex: mine.tex, size: 24, large: true)
        }
        if !answer.unlocked.isEmpty {
          NewBadgesCard(badges: answer.unlocked, flipped: flipped)
        }
        Button { dismiss() } label: {
          Text("Done")
            .face(.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CardPress())
      }
      .padding(20)
    }
  }

  /// The badges the way earned flip in, then count as seen.
  private func celebrate(_ badges: [EarnedBadge]) {
    AccessibilityNotification.Announcement("Another way!").post()
    guard !badges.isEmpty else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(still ? 300 : 650))
      flipped = true
      account.seeBadges(badges)
      try? await Task.sleep(for: .milliseconds(600))
      AccessibilityNotification.Announcement(NewBadgesCard.words(badges)).post()
    }
  }
}

/// Opens "Find another way" on a sign, over whichever tab asked.
struct FindWay {
  let open: (Sign) -> Void
}

extension EnvironmentValues {
  @Entry var findWay: FindWay?
}

extension View {
  /// Lets the screens inside open "Find another way" on a sign, as a sheet
  /// over this one.
  func findsAnotherWay() -> some View { modifier(AnotherWayHost()) }
}

private struct AnotherWayHost: ViewModifier {
  @State private var sign: Sign?

  func body(content: Content) -> some View {
    content
      .environment(\.findWay, FindWay { sign = $0 })
      .sheet(item: $sign) { AnotherWayView(sign: $0) }
  }
}
