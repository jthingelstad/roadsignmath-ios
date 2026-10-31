import RoadSignMathAPI
import SwiftUI

/// The boards' Me: you, your signs and where they took you, your newest
/// badges, then your signs as Home's timeline or as photos. A tap opens a
/// sign; the gear opens settings (your name and email, sign out, Delete
/// my account, and the build).
struct MeView: View {
  enum Look: Hashable { case timeline, photos }

  /// Where You goes: a sign, or your badges' shelves.
  enum Route: Hashable {
    case sign(String)
    case badges
  }

  enum Load: Equatable {
    case loading, loaded
    case failed(String)
  }

  @Environment(Account.self) private var account
  @Environment(CaptureFlow.self) private var flow
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var look = Look.timeline
  @Namespace private var zoom
  @State private var signs: [Sign] = []
  @State private var load = Load.loading
  @State private var showingSettings = Script.flag("RSMSettings")
  @State private var path: [Route] = Script.flag("RSMBadges") || Script.value("RSMBadge") != nil ? [.badges] : []
  /// A badge in the row tapped: its own sheet.
  @State private var badge: EarnedBadge?
  /// A held or hidden sign tapped: only you see it, so it has no page yet.
  @State private var onlyYours: Sign?

  var body: some View {
    NavigationStack(path: $path) {
      Group {
        if let me = account.me {
          page(me)
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(Color.ground)
      .navigationTitle("You")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color.ground, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            showingSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
          .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.face(.action)
        }
      }
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .sign(let id):
          SignView(id: id).navigationTransition(.zoom(sourceID: id, in: zoom))
        case .badges:
          BadgesView(earned: account.me?.badges ?? []) { path.append(.sign($0)) }
        }
      }
      .sheet(isPresented: $showingSettings) { SettingsView() }
      .sheet(item: $badge) { badge in
        BadgeSheet(slot: BadgeSlot(badge)) { id in
          self.badge = nil
          path.append(.sign(id))
        }
      }
      .alert(
        "Only you can see this one", isPresented: Binding(get: { onlyYours != nil }, set: { if !$0 { onlyYours = nil } }),
        presenting: onlyYours
      ) { _ in
        Button("OK", role: .cancel) {}
      } message: { sign in
        Text(sign.moderationNote ?? "It isn’t on the feed or the map.")
      }
    }
    .tint(.greenInk)
    .task {
      // Opened while signed out (the token ended a moment ago): nothing to show.
      guard account.signedIn else { return dismiss() }
      await reload()
    }
    .onChange(of: account.signedIn) { _, now in if !now { dismiss() } }
    // A sign's mini-map moves to the Map tab underneath; get out of its way.
    .onChange(of: store.tab) { dismiss() }
    .sensoryFeedback(.selection, trigger: look)
  }

  private func reload() async {
    // Side by side as a Task of its own: no async let or task groups here.
    let fresh = Task { await account.refresh() }
    do {
      let mine = try await account.mySigns()
      withAnimation(.smooth) {
        // Newest posted first, as Home lists everyone's (Jamie, 2026-10-30).
        signs = mine.sorted { ($0.postedAt, $0.id) > ($1.postedAt, $1.id) }
        load = .loaded
      }
    } catch {
      if account.signedIn, signs.isEmpty { load = .failed(Account.say(error)) }
    }
    await fresh.value
    #if DEBUG
      if Script.value("RSMLook") == "photos" { look = .photos }
    #endif
  }

  // MARK: The page

  private func page(_ me: Me) -> some View {
    ScrollView {
      VStack(spacing: 20) {
        header(me)
        if let badges = me.badges, !badges.isEmpty { badgesRow(badges) }
        switch load {
        case .loading where signs.isEmpty:
          placeholder
        case .failed(let why):
          Notice(symbol: "wifi.exclamationmark", title: "Your signs didn’t load", message: why,
                 action: ("Try again", { load = .loading; Task { await reload() } }))
        default:
          if signs.isEmpty {
            firstSign
          } else {
            looks
            switch look {
            case .timeline: timeline
            case .photos: grid
            }
          }
        }
      }
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .refreshable { await reload() }
  }

  private func header(_ me: Me) -> some View {
    VStack(spacing: 14) {
      VStack(spacing: 8) {
        Avatar(name: me.name, color: Color(hex: me.avatarColor) ?? .signGreen, size: 84)
        Text(me.shownName)
          .face(.title)
          .foregroundStyle(me.name.isEmpty ? Color.ink3 : Color.ink)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
        if !me.name.isEmpty {
          Text(Self.address(me.url))
            .face(.meta)
            .foregroundStyle(Color.ink3)
            .accessibilityLabel("Your page: \(Self.address(me.url))")
        }
      }
      HStack(spacing: 10) {
        Stat(value: "\(me.signCount)", label: me.signCount == 1 ? "sign" : "signs")
        Stat(value: "\(me.states.count)", label: me.states.count == 1 ? "state" : "states")
        Stat(value: me.firstYear.map(String.init) ?? "–", label: "first sign")
          .accessibilityLabel(me.firstYear.map { "First sign in \($0)" } ?? "No first sign yet")
      }
      .padding(.horizontal, 16)
      if !me.states.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(me.states, id: \.self) { state in
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
        .accessibilityLabel("States: " + me.states.joined(separator: ", "))
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// Your newest few badges, a dot on any not seen yet, and "See all" for
  /// the shelves.
  private func badgesRow(_ badges: [EarnedBadge]) -> some View {
    let fresh = Set(account.newBadges.map(SeenBadges.key))
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("Badges")
          .face(.section)
          .foregroundStyle(Color.ink)
          .accessibilityLabel(fresh.isEmpty ? "Badges" : "Badges, \(fresh.count) new")
          .accessibilityAddTraits(.isHeader)
        if !fresh.isEmpty { NewDot() }
        Spacer()
        Button {
          path.append(.badges)
        } label: {
          Text("See all").face(.name).foregroundStyle(Color.greenInk).frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("See all your badges")
      }
      .padding(.horizontal, 16)
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 10) {
          ForEach(Badges.newest(badges).prefix(MeView.newestBadges), id: \.self) { earned in
            Button {
              badge = earned
            } label: {
              BadgeTile(badge: earned, new: fresh.contains(SeenBadges.key(earned)))
            }
            .buttonStyle(CardPress())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel((fresh.contains(SeenBadges.key(earned)) ? "New: " : "") + earned.spoken)
            .accessibilityAddTraits(.isButton)
          }
        }
        .padding(.horizontal, 16)
      }
      .scrollIndicators(.hidden)
    }
  }

  /// How many of your newest badges the row shows.
  static let newestBadges = 6

  /// Your signs as Home's timeline, or as a grid of photos.
  private var looks: some View {
    HStack(spacing: 8) {
      Pill(label: "Signs", chosen: look == .timeline) { withAnimation(.snappy) { look = .timeline } }
      Pill(label: "Photos", chosen: look == .photos) { withAnimation(.snappy) { look = .photos } }
      Spacer()
    }
    .padding(.horizontal, 16)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Show your signs as")
  }

  private var grid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
      ForEach(signs) { sign in
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

  /// Home's timeline, only your signs: the same cards, the math on each.
  private var timeline: some View {
    LazyVStack(spacing: 10) {
      ForEach(signs) { sign in
        SignCard(sign: sign, zoom: zoom) { open(sign) }
          .overlay(alignment: .topTrailing) { OnlyYou(sign: sign) }
      }
    }
    .transition(.opacity)
  }

  /// No signs yet: where the first one comes from.
  private var firstSign: some View {
    VStack(spacing: 14) {
      SignPlate(text: "you + a sign = ?", tex: nil, size: 22, large: true)
        .frame(maxWidth: 260)
        .rotationEffect(.degrees(-2))
        .accessibilityHidden(true)
      Text("Your first sign is out there")
        .face(.section)
        .foregroundStyle(Color.ink)
        .accessibilityAddTraits(.isHeader)
      Text("Next time you’re the passenger, watch for a sign whose numbers can make a true equation. Snap it, and it lands here.")
        .face(.body)
        .foregroundStyle(Color.ink2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        dismiss()
        Task {
          // Let the sheet go before Capture covers the screen.
          try? await Task.sleep(for: .milliseconds(450))
          flow.begin()
        }
      } label: {
        Label("Open the camera", systemImage: "camera.fill")
          .face(.button)
          .foregroundStyle(.white)
          .padding(.horizontal, 22)
          .frame(minHeight: 50)
          .background(Color.signGreen, in: Capsule())
      }
      .buttonStyle(CardPress())
      .padding(.top, 4)
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
    .padding(.horizontal, 16)
  }

  private var placeholder: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
      ForEach(0..<6, id: \.self) { _ in Color.photoGround.aspectRatio(1, contentMode: .fit) }
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding(.horizontal, 16)
    .modifier(Shimmer())
    .accessibilityLabel("Loading your signs")
  }

  private func open(_ sign: Sign) {
    if sign.visibility == .shown { path.append(.sign(sign.id)) } else { onlyYours = sign }
  }

  static func spoken(_ sign: Sign) -> String {
    var words = sign.title + ", " + sign.place.label
    if sign.visibility != .shown { words += ". Only you can see it" }
    return words
  }

  /// "roadsignmath.xyz/players/jamie"
  static func address(_ url: URL) -> String {
    (url.host() ?? "") + (url.port.map { ":\($0)" } ?? "") + url.path()
  }

  /// What deleting takes with it, in this player's numbers.
  static func deleteWords(_ me: Me) -> String {
    let signs: String
    switch me.signCount {
    case 0: signs = "the ways you found"
    case 1: signs = "the sign you posted (with every way found on it), the ways you found on other signs"
    default: signs = "the \(me.signCount) signs you posted (with every way found on them), the ways you found on other signs"
    }
    return "This deletes your account and everything it made: \(signs), your name on signs other people posted, and your email. It can’t be undone."
  }
}

/// One of the three numbers under your name.
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
  var inline = false

  var body: some View {
    if sign.visibility != .shown {
      Image(systemName: "eye.slash.fill")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(inline ? Color.ink3 : .white)
        .padding(inline ? 0 : 6)
        .background(inline ? .clear : .black.opacity(0.6), in: Circle())
        .padding(inline ? 0 : 6)
        .accessibilityHidden(true)
    }
  }
}

/// Me's settings: your name and email, sign out, Delete my
/// account, and the build this is.
private struct SettingsView: View {
  @Environment(Account.self) private var account
  @Environment(\.dismiss) private var dismiss
  @State private var renaming = false
  @State private var confirmSignOut = false
  @State private var confirmDelete = false
  @State private var deleting = false
  @State private var problem: String?

  var body: some View {
    NavigationStack {
      Group {
        if let me = account.me { list(me) } else { ProgressView() }
      }
      .background(Color.ground)
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.face(.action)
        }
      }
      .sheet(isPresented: $renaming) {
        RenameView(current: account.me?.name ?? "")
          .presentationDetents([.medium, .large])
      }
    }
    .tint(.greenInk)
    .onChange(of: account.signedIn) { _, now in if !now { dismiss() } }
  }

  private func list(_ me: Me) -> some View {
    List {
      Section {
        Button {
          renaming = true
        } label: {
          row("Name", me.name.isEmpty ? "Add your name" : me.name, chevron: true, nudge: me.name.isEmpty)
        }
        row("Email", me.email)
          .accessibilityHint("Only you see this")
      } footer: {
        Text("Your email is only for signing in. Nobody else sees it.").face(.meta)
      }
      Section {
        Button {
          confirmSignOut = true
        } label: {
          Text("Sign out").face(.bodyBold).foregroundStyle(Color.warn)
        }
        .confirmationDialog("Sign out of Road Sign Math on this iPhone?", isPresented: $confirmSignOut, titleVisibility: .visible) {
          Button("Sign out", role: .destructive) { Task { await account.signOut() } }
        } message: {
          Text("Your signs stay put. Sign in again with your email whenever you like.")
        }
      }
      Section {
        Button {
          confirmDelete = true
        } label: {
          HStack {
            Text("Delete my account").face(.bodyBold).foregroundStyle(Color.warn)
            Spacer()
            if deleting { ProgressView() }
          }
        }
        .disabled(deleting)
        .alert("Delete your account?", isPresented: $confirmDelete) {
          Button("Delete my account", role: .destructive, action: delete)
          Button("Keep it", role: .cancel) {}
        } message: {
          Text(MeView.deleteWords(me))
        }
      } footer: {
        VStack(alignment: .leading, spacing: 18) {
          if let problem {
            ProblemLine(text: problem)
          } else {
            Text("Deletes your account and everything you posted. It can’t be undone.").face(.meta)
          }
          // The build, for a tester to name when something's off.
          Text(BuildInfo.line)
            .face(.meta)
            .foregroundStyle(Color.ink3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Version \(BuildInfo.version), build \(BuildInfo.build)")
        }
      }
    }
    .scrollContentBackground(.hidden)
  }

  private func row(_ label: String, _ value: String, chevron: Bool = false, nudge: Bool = false) -> some View {
    HStack(spacing: 10) {
      Text(label).face(.bodyBold).foregroundStyle(Color.ink)
      Spacer(minLength: 8)
      Text(value)
        .face(.body)
        .foregroundStyle(nudge ? Color.greenInk : Color.ink2)
        .lineLimit(1)
        .truncationMode(.middle)
      if chevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.ink3)
          .accessibilityHidden(true)
      }
    }
    .frame(minHeight: 32)
    .accessibilityElement(children: .combine)
  }

  private func delete() {
    deleting = true
    problem = nil
    Task {
      do {
        try await account.deleteAccount()
      } catch {
        if account.signedIn { problem = Account.say(error) }
      }
      deleting = false
    }
  }
}

/// Changing your name. The handle, and so your page's address, stays.
private struct RenameView: View {
  let current: String

  @Environment(Account.self) private var account
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var saving = false
  @State private var problem: String?
  @FocusState private var typing: Bool

  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var first: Bool { account.me?.needsName ?? current.isEmpty }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 14) {
        TextField("Your name", text: $name)
          .face(.field)
          .textContentType(.givenName)
          .submitLabel(.done)
          .focused($typing)
          .onSubmit(save)
          .padding(.horizontal, 16)
          .frame(minHeight: 52)
          .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(typing ? Color.greenInk : Color.ruleStrong, lineWidth: typing ? 2 : 1.5)
          }
          .onChange(of: name) { _, now in if now.count > 40 { name = String(now.prefix(40)) } }
        Group {
          if first, let handle = Handle.preview(for: trimmed), let me = account.me {
            Text("Your page will be at \(Text(MeView.address(me.url.deletingLastPathComponent().appending(path: handle))).bold()), and that address stays for good.")
          } else if first {
            Text("Your first name also makes your page’s address, which stays for good.")
          } else {
            Text("Your page’s address stays the same, so links to it keep working.")
          }
        }
        .face(.meta)
        .foregroundStyle(Color.ink2)
        .fixedSize(horizontal: false, vertical: true)
        if let problem { ProblemLine(text: problem) }
        Spacer()
      }
      .padding(20)
      .background(Color.ground)
      .navigationTitle(first ? "Your name" : "Change your name")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button("Save", action: save).disabled(trimmed.isEmpty || trimmed == current)
          }
        }
      }
    }
    .onAppear {
      name = current
      typing = true
    }
  }

  private func save() {
    guard !trimmed.isEmpty, trimmed != current, !saving else { return }
    saving = true
    problem = nil
    Task {
      do {
        try await account.setName(trimmed)
        dismiss()
      } catch {
        problem = Account.say(error)
      }
      saving = false
    }
  }
}
