import RoadSignMathAPI
import SwiftUI

/// The boards' Me: you, your signs and where they took you, your newest
/// badges, then your signs as Home's timeline or as photos. A tap opens a
/// sign; the gear opens settings (your name and email, sign out, Delete
/// my account, and the build).
struct MeView: View {
  /// Where You goes: a sign, your badges' shelves, or a finder's page.
  enum Route: Hashable {
    case sign(String)
    case badges
    case player(String)
  }

  enum Load: Equatable {
    case loading, loaded
    case failed(String)
  }

  @Environment(Account.self) private var account
  @Environment(CaptureFlow.self) private var flow
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var look = ProfileSigns.Look.timeline
  @Namespace private var zoom
  @State private var signs: [Sign] = []
  @State private var load = Load.loading
  @State private var showingSettings = Script.flag("RSMSettings")
  @State private var path: [Route] = Script.flag("RSMBadges") || Script.value("RSMBadge") != nil ? [.badges] : []
  /// A badge in the row tapped: its own sheet.
  @State private var badge: EarnedBadge?
  /// A held or hidden sign tapped: only you see it, so it has no page yet.
  @State private var onlyYours: Sign?
  /// Your avatar tapped: the profile photo's choices.
  @State private var photo: PhotoStart?
  /// Badges earned while you were away (not seen on this phone yet), on a
  /// card at the top that flips them in once You has read you afresh.
  @State private var arrived: [EarnedBadge] = []
  @State private var flipped = false
  /// On screen: a reload that ends after You closed reveals nothing.
  @State private var showing = false
  /// Deleting a sign only you see didn't work.
  @State private var problem: String?
  /// How far "On your signs" had been looked at when You opened: what's
  /// after it shows as new for this visit, though it counts as seen.
  @State private var lookedUpTo: Date?
  @State private var looked = false
  @Environment(\.accessibilityReduceMotion) private var still

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
        case .player(let handle):
          PlayerView(handle: handle)
        }
      }
      .sheet(isPresented: $showingSettings) { SettingsView() }
      .profilePhoto($photo)
      .sheet(item: $badge) { badge in
        BadgeSheet(slot: BadgeSlot(badge)) { id in
          self.badge = nil
          path.append(.sign(id))
        }
      }
      .alert(
        "Only you can see this one", isPresented: Binding(get: { onlyYours != nil }, set: { if !$0 { onlyYours = nil } }),
        presenting: onlyYours
      ) { sign in
        Button("OK", role: .cancel) {}
        Button("Delete this sign", role: .destructive) { delete(sign) }
      } message: { sign in
        Text((sign.moderationNote ?? "It isn’t on the feed or the map.") + "\n\nYou can delete it. That can’t be undone.")
      }
      .alert("That didn’t work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } }), presenting: problem) { _ in
        Button("OK", role: .cancel) {}
      } message: { problem in
        Text(problem)
      }
    }
    .findsAnotherWay()
    .environment(\.opener, Opener(sign: { path.append(.sign($0)) }, player: { path.append(.player($0)) }))
    .tint(.greenInk)
    .onAppear { showing = true }
    .onDisappear { showing = false }
    .countsView(ViewPath.you)
    .task {
      // Opened while signed out (the token ended a moment ago): nothing to show.
      guard account.signedIn else { return dismiss() }
      await reload()
    }
    .onChange(of: account.signedIn) { _, now in if !now { dismiss() } }
    // A sign's mini-map moves to the Map tab underneath; get out of its way.
    .onChange(of: store.tab) { dismiss() }
    .sensoryFeedback(.selection, trigger: look)
    .sensoryFeedback(.impact(weight: .heavy), trigger: flipped) { _, now in now }
  }

  private func reload() async {
    // Side by side as a Task of its own: no async let or task groups here.
    let fresh = Task { await account.refresh() }
    do {
      let mine = try await account.mySigns()
      withAnimation(.smooth) {
        signs = ProfileSigns.newestFirst(mine)
        load = .loaded
      }
    } catch {
      if account.signedIn, signs.isEmpty { load = .failed(Account.say(error)) }
    }
    await fresh.value
    #if DEBUG
      if Script.value("RSMLook") == "photos" { look = .photos }
    #endif
    seeActivity()
    await welcomeBack()
  }

  /// "On your signs" is looked at: the dot goes, and what came since the
  /// last look stays marked new until You closes.
  private func seeActivity() {
    guard showing, let activity = account.activity else { return }
    if !looked {
      lookedUpTo = account.activitySeen
      looked = true
    }
    account.seeActivity(upTo: activity.newest)
  }

  /// A row tapped: the sign's page, or for one only you see, why.
  private func open(_ ref: ActivityItem.SignRef) {
    if let mine = signs.first(where: { $0.id == ref.id }) { open(mine) } else { path.append(.sign(ref.id)) }
  }

  /// Badges earned since you last looked (a way someone found on your
  /// sign, a badge the server grew, a post that went up while you were
  /// away) flip in, as on "Posted!", then count as seen. Once a visit.
  /// Gone before they flipped (You closed mid-way), they stay unseen
  /// for next time.
  private func welcomeBack() async {
    guard showing, !Task.isCancelled, !flipped else { return }
    if arrived.isEmpty {
      let new = account.newBadges
      guard !new.isEmpty else { return }
      withAnimation(.smooth) { arrived = Badges.newest(new) }
    }
    do { try await Task.sleep(for: .milliseconds(still ? 300 : 650)) } catch { return }
    guard showing else { return }
    flipped = true
    account.seeBadges(arrived)
    do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
    guard showing else { return }
    AccessibilityNotification.Announcement(NewBadgesCard.words(arrived)).post()
  }

  // MARK: The page

  private func page(_ me: Me) -> some View {
    ScrollView {
      VStack(spacing: 20) {
        header(me)
        if !arrived.isEmpty {
          NewBadgesCard(badges: arrived, flipped: flipped)
            .padding(.horizontal, 16)
        }
        if let activity = account.activity {
          let rows = ActivityRow.rows(activity.items, seen: looked ? lookedUpTo : account.activitySeen)
          if !rows.isEmpty { OnYourSigns(rows: rows, days: activity.days, open: open) }
        }
        // Shown with none earned too, so the shelves say how to earn the
        // first; a server before 1.6.0 sends no badges at all.
        if let badges = me.badges { badgesRow(badges) }
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
            ProfileSigns(signs: signs, look: $look, zoom: zoom, whose: "your", open: open)
          }
        }
      }
      .padding(.top, 8)
      .padding(.bottom, 32)
    }
    .refreshable { await reload() }
  }

  private func header(_ me: Me) -> some View {
    ProfileHeader(name: me.shownName, unnamed: me.name.isEmpty, avatarColor: me.avatarColor,
                  avatarUrl: me.avatarUrl, changePhoto: { photo = .menu },
                  page: me.name.isEmpty ? nil : me.url, pageWords: "Your page", bio: me.bio,
                  signCount: me.signCount, states: me.states, firstYear: me.firstYear)
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
      if badges.isEmpty {
        Text("None yet. See all shows how each one is earned.")
          .face(.body)
          .foregroundStyle(Color.ink3)
          .padding(.horizontal, 16)
      } else {
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
  }

  /// How many of your newest badges the row shows.
  static let newestBadges = 6

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

  /// A held or hidden sign has no page, so its alert deletes it.
  private func delete(_ sign: Sign) {
    Task {
      do {
        try await account.deleteSign(sign.id)
        store.signGone(sign.id)
      } catch {
        problem = Account.say(error)
      }
    }
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

/// Me's settings: your profile photo, your name and email, the players
/// you blocked, sign out, Delete my account, and the build this is.
private struct SettingsView: View {
  @Environment(Account.self) private var account
  @Environment(\.dismiss) private var dismiss
  @State private var renaming = false
  @State private var editingBio = Script.flag("RSMBio")
  @State private var blockedCount: Int?
  @State private var confirmSignOut = false
  @State private var confirmDelete = false
  @State private var deleting = false
  @State private var problem: String?
  @State private var photo: PhotoStart?
  @State private var page: SettingsPage? = SettingsPage.scripted

  var body: some View {
    NavigationStack {
      Group {
        if let me = account.me { list(me) } else { ProgressView() }
      }
      .navigationDestination(item: $page) { page in
        switch page {
        case .blocked: BlockedPlayersView()
        case .howToPlay: HowToPlayView()
        case .feedback: FeedbackView()
        case .licenses: LicensesView()
        }
      }
      .profilePhoto($photo)
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
      .sheet(isPresented: $editingBio) {
        BioView(current: account.me?.bio ?? "")
          .presentationDetents([.medium, .large])
      }
    }
    .tint(.greenInk)
    .onChange(of: account.signedIn) { _, now in if !now { dismiss() } }
    // How many you've blocked, read again when you come back from the list.
    .task(id: page == nil) { if page == nil { blockedCount = try? await account.blockedPlayers().count } }
  }

  private func list(_ me: Me) -> some View {
    List {
      Section {
        HStack(spacing: 14) {
          Avatar(name: me.name, color: Color(hex: me.avatarColor) ?? .signGreen, size: 56, photo: me.avatarThumbUrl)
          VStack(alignment: .leading, spacing: 2) {
            Text("Profile photo").face(.bodyBold).foregroundStyle(Color.ink)
            Text(me.avatarUrl == nil ? "Your first letter shows until you add one." : "Everyone sees it beside your signs.")
              .face(.meta)
              .foregroundStyle(Color.ink2)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        Button { photo = .library } label: {
          Label("Choose a photo", systemImage: "photo.on.rectangle").face(.bodyBold)
        }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
          Button { photo = .camera } label: {
            Label("Take a photo", systemImage: "camera").face(.bodyBold)
          }
        }
        if me.avatarUrl != nil {
          Button(role: .destructive) { photo = .remove } label: {
            Label("Remove photo", systemImage: "trash").face(.bodyBold).foregroundStyle(Color.warn)
          }
        }
      }
      Section {
        Button {
          renaming = true
        } label: {
          row("Name", me.name.isEmpty ? "Add your name" : me.name, chevron: true, nudge: me.name.isEmpty)
        }
        Button {
          editingBio = true
        } label: {
          row("Bio", me.bio.flatMap { $0.isEmpty ? nil : $0 } ?? "Add a line about you", chevron: true, nudge: (me.bio ?? "").isEmpty)
        }
        row("Email", me.email)
          .accessibilityHint("Only you see this")
      } footer: {
        Text("Your bio shows on your page. Your email is only for signing in; nobody else sees it.").face(.meta)
      }
      Section {
        Button {
          page = .blocked
        } label: {
          row("Blocked players", blockedCount.map { $0 == 0 ? "" : "\($0)" } ?? "", chevron: true)
        }
      } footer: {
        Text("Their signs and ways stay out of your app until you unblock them.").face(.meta)
      }
      Section {
        Button {
          page = .howToPlay
        } label: {
          row("How to play", "", chevron: true)
        }
        Button {
          page = .feedback
        } label: {
          row("Send feedback", "", chevron: true)
        }
      } header: {
        Text("Help").face(.metaBold)
      } footer: {
        Text("A problem, an idea or a hello. It reaches Jamie.").face(.meta)
      }
      Section {
        Link(destination: SitePage.privacy) { row("Privacy", "", link: true) }
        Link(destination: SitePage.about) { row("About Road Sign Math", "", link: true) }
        Button {
          page = .licenses
        } label: {
          row("Licenses", "", chevron: true)
        }
      } header: {
        Text("About").face(.metaBold)
      } footer: {
        Text("Overpass, Latin Modern, SwiftMath, CC BY 4.0").face(.meta)
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

  private func row(_ label: String, _ value: String, chevron: Bool = false, nudge: Bool = false, link: Bool = false) -> some View {
    HStack(spacing: 10) {
      Text(label).face(.bodyBold).foregroundStyle(Color.ink)
      Spacer(minLength: 8)
      Text(value)
        .face(.body)
        .foregroundStyle(nudge ? Color.greenInk : Color.ink2)
        .lineLimit(1)
        .truncationMode(.middle)
      if chevron || link {
        Image(systemName: link ? "arrow.up.right" : "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.ink3)
          .accessibilityHidden(true)
      }
    }
    .frame(minHeight: 32)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(link ? .isLink : [])
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

/// The screens Settings pushes.
private enum SettingsPage: Hashable {
  case blocked, howToPlay, feedback, licenses

  /// `-RSMBlocked YES`, or `-RSMHelp play|feedback|licenses`, with
  /// `-RSMMe YES -RSMSettings YES`.
  static var scripted: SettingsPage? {
    if Script.flag("RSMBlocked") { return .blocked }
    switch Script.value("RSMHelp") {
    case "play": return .howToPlay
    case "feedback": return .feedback
    case "licenses": return .licenses
    default: return nil
    }
  }
}

/// Your bio: one line about you, on your page under your name.
private struct BioView: View {
  let current: String

  @Environment(Account.self) private var account
  @Environment(\.dismiss) private var dismiss
  @State private var bio = ""
  @State private var saving = false
  @State private var problem: String?
  @FocusState private var typing: Bool

  private var trimmed: String { bio.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var left: Int { APIClient.bioMax - bio.count }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 10) {
        TextField("Add a line about you", text: $bio, axis: .vertical)
          .face(.field)
          .lineLimit(2...4)
          .submitLabel(.done)
          .focused($typing)
          .padding(12)
          .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(typing ? Color.greenInk : Color.ruleStrong, lineWidth: typing ? 2 : 1.5)
          }
          .onChange(of: bio) { _, now in
            // One line: Return is Done, not a new line.
            if now.contains(where: \.isNewline) {
              bio = String(now.filter { !$0.isNewline }.prefix(APIClient.bioMax))
              typing = false
            } else if now.count > APIClient.bioMax {
              bio = String(now.prefix(APIClient.bioMax))
            }
          }
          .accessibilityLabel("Bio")
        HStack(alignment: .firstTextBaseline) {
          Text(trimmed.isEmpty && !current.isEmpty ? "Save it empty to take your bio away." : "It shows on your page, under your name, for everyone.")
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 12)
          Text("\(left) left").foregroundStyle(left < 20 ? Color.warn : Color.ink3)
        }
        .face(.meta)
        .foregroundStyle(Color.ink2)
        if let problem { ProblemLine(text: problem) }
        Spacer()
      }
      .padding(20)
      .background(Color.ground)
      .navigationTitle(current.isEmpty ? "Your bio" : "Change your bio")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button("Save", action: save).disabled(trimmed == current)
          }
        }
      }
    }
    .interactiveDismissDisabled(saving)
    .onAppear {
      bio = current
      if let scripted = Script.text("RSMBioText") { bio = scripted }
      typing = true
      if Script.flag("RSMBioSave") { save() }
    }
  }

  private func save() {
    guard !saving, trimmed != current else { return }
    saving = true
    problem = nil
    Task {
      do {
        try await account.setBio(trimmed)
        dismiss()
      } catch {
        problem = Account.say(error)
      }
      saving = false
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
            Text("Your page will be at \(Text(ProfileHeader.address(me.url.deletingLastPathComponent().appending(path: handle))).bold()), and that address stays for good.")
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
