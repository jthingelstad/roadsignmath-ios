import MapKit
import Posting
import RoadSignMathAPI
import SignCapture
import SwiftUI

/// The boards' Post it: name the sign, where it is (the town at the
/// photo's own spot, or a town the player picks: never the phone's live
/// location), the day it was found, who found it, whether it's been posted
/// already, then Post it. Posting puts it in the outbox, which sends it
/// now or as soon as it can.
struct PostView: View {
  enum Where: Equatable {
    /// Naming the photo's spot.
    case finding
    case photo(PostPlace)
    /// A town the player picked.
    case picked(PostPlace)
    /// No place yet: the photo has none, or its spot couldn't be named.
    case none(photoHadOne: Bool)

    var place: PostPlace? {
      switch self {
      case .photo(let place), .picked(let place): place
      default: nil
      }
    }
  }

  enum Similar: Equatable {
    case waiting, checking, none, failed
    case found([Sign])
  }

  @Environment(CaptureFlow.self) private var flow
  @Environment(Account.self) private var account
  @Environment(Store.self) private var store
  @Environment(Outbox.self) private var outbox
  @Environment(\.verticalSizeClass) private var height
  @State private var title = ""
  @State private var place = Where.finding
  @State private var foundOn = Date.now
  @State private var spotters: [String] = []
  @State private var spotter = ""
  @State private var similar = Similar.waiting
  @State private var name = ""
  @State private var sayingWhere = false
  @State private var posting = false
  @State private var problem: String?
  @State private var started = false
  @State private var autoPosted = false
  @State private var scroll = ScrollPosition(edge: .top)
  @FocusState private var field: Field?

  enum Field: Hashable { case title, spotter, name }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        top
        nameIt
        whereIs
        when
        who
        if account.me?.needsName == true { yourName }
        posted
      }
      .padding(16)
      .frame(maxWidth: 640)
      .frame(maxWidth: .infinity)
    }
    .scrollPosition($scroll)
    .scrollDismissesKeyboard(.interactively)
    .background(Color.ground)
    .safeAreaInset(edge: .bottom, spacing: 0) { actions }
    .navigationTitle(flow.way == nil ? "Post unsolved" : "Post it")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Color.ground, for: .navigationBar)
    .sheet(isPresented: $sayingWhere) {
      SayWhere { picked in place = .picked(picked) }
    }
    .task { await start() }
    .task(id: place.place) { await checkSimilar() }
    #if DEBUG
      .onChange(of: missing == nil) { _, ready in
        if ready, Script.flag("RSMPostIt"), !autoPosted {
          autoPosted = true
          Task { await post() }
        }
      }
    #endif
  }

  // MARK: The sign

  private var top: some View {
    VStack(alignment: .leading, spacing: 12) {
      ShotStrip(height: height == .compact ? 130 : 170, whole: height == .compact)
      if let way = flow.way {
        SignPlate(text: way, tex: nil, size: 22, large: true)
          .accessibilityLabel("The math: \(way)")
      } else {
        Label("Posted unsolved, so anyone can find the math.", systemImage: "questionmark.square.dashed")
          .face(.body)
          .foregroundStyle(Color.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var nameIt: some View {
    Part(title: "Name it") {
      VStack(alignment: .leading, spacing: 8) {
        TextField("A name for the sign", text: $title)
          .face(.field)
          .foregroundStyle(Color.ink)
          .focused($field, equals: .title)
          .submitLabel(.done)
          .textInputAutocapitalization(.words)
          .padding(.horizontal, 14)
          .frame(minHeight: 50)
          .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(field == .title ? Color.signGreen : Color.ruleStrong, lineWidth: 1.5)
          }
          .onChange(of: title) { _, now in
            if now.count > APIClient.titleMax { title = String(now.prefix(APIClient.titleMax)) }
          }
        if let suggestion, title.trimmingCharacters(in: .whitespaces).isEmpty {
          Button {
            title = suggestion
          } label: {
            Label("Call it \u{201C}\(suggestion)\u{201D}", systemImage: "wand.and.sparkles")
              .face(.metaBold)
              .foregroundStyle(Color.greenInk)
              .padding(.horizontal, 12)
              .frame(minHeight: 36)
              .background(Color.wayGround, in: Capsule())
          }
          .buttonStyle(.plain)
        } else if title.count > APIClient.titleMax - 10 {
          Text("\(APIClient.titleMax - title.count) letters left")
            .face(.meta)
            .foregroundStyle(Color.ink3)
        }
      }
    }
  }

  private var suggestion: String? { PostParts.title(near: place.place?.label) }

  // MARK: Where

  private var whereIs: some View {
    Part(title: "Where") {
      switch place {
      case .finding:
        HStack(spacing: 10) {
          ProgressView()
          Text("Finding the town from your photo…").face(.body).foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
      case .photo(let found):
        PlaceCard(place: found, from: "From your photo", change: { sayingWhere = true })
      case .picked(let picked):
        PlaceCard(place: picked, from: "The town you picked", change: { sayingWhere = true })
      case .none(let photoHadOne):
        VStack(alignment: .leading, spacing: 10) {
          Text(
            photoHadOne
              ? "We couldn’t name the spot your photo was taken. Pick the town it’s in."
              : "Your photo doesn’t say where it was taken. Pick the town it’s in."
          )
          .face(.body)
          .foregroundStyle(Color.ink2)
          .fixedSize(horizontal: false, vertical: true)
          Button {
            sayingWhere = true
          } label: {
            Label("Where was it?", systemImage: "magnifyingglass")
              .face(.action)
              .foregroundStyle(Color.greenInk)
              .frame(maxWidth: .infinity, minHeight: 48)
              .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.signGreen, lineWidth: 1.5)
              }
          }
          .buttonStyle(CardPress())
        }
      }
    }
  }

  // MARK: When

  private var when: some View {
    Part(title: "Found") {
      DatePicker(selection: $foundOn, in: PostView.firstDay...Date.now, displayedComponents: .date) {
        Label(foundNote, systemImage: "calendar")
          .face(.body)
          .foregroundStyle(Color.ink)
      }
      .tint(.greenInk)
      .padding(.horizontal, 14)
      .frame(minHeight: 52)
      .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
    }
  }

  private var foundNote: String {
    guard let shot = flow.shot else { return "The day" }
    if shot.source == .camera {
      // A draft taken on another day says so.
      return Calendar.current.isDateInToday(shot.takenAt ?? .now) ? "Today" : "When you took it"
    }
    return shot.file.facts.takenOn == nil ? "The day" : "From your photo"
  }

  static let firstDay = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2000, month: 1, day: 1))!

  // MARK: Who

  private var who: some View {
    Part(title: "Who found it") {
      VStack(alignment: .leading, spacing: 10) {
        if let me = account.me {
          // Before you've a name, the one you're typing below.
          let yours = me.needsName ? trimmedName : me.name
          FinderRow(
            avatar: Avatar(name: yours.isEmpty ? "?" : yours, color: Color(hex: me.avatarColor) ?? .signGreen, size: 32, photo: me.avatarThumbUrl),
            name: yours.isEmpty ? "You" : "\(yours) (you)",
            role: spotters.isEmpty ? "Found it" : "Took the photo")
        }
        ForEach(Array(spotters.enumerated()), id: \.offset) { index, spotter in
          FinderRow(
            avatar: Avatar(name: spotter.hasPrefix("@") ? String(spotter.dropFirst()) : spotter, color: store.color(for: handle(spotter)), size: 32, photo: store.photo(for: handle(spotter))),
            name: spotter, role: "Spotted it",
            remove: { withAnimation(.snappy) { _ = spotters.remove(at: index) } })
        }
        if spotters.count < APIClient.findersMax - 1 {
          HStack(spacing: 8) {
            TextField("Someone who spotted it", text: $spotter)
              .face(.field)
              .focused($field, equals: .spotter)
              .textInputAutocapitalization(.words)
              .autocorrectionDisabled()
              .submitLabel(.done)
              .onSubmit(addSpotter)
              .padding(.horizontal, 14)
              .frame(minHeight: 48)
              .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .strokeBorder(field == .spotter ? Color.signGreen : Color.ruleStrong, lineWidth: 1.5)
              }
            Button(action: addSpotter) {
              Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.signGreen.opacity(spotterText.isEmpty ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(CardPress())
            .disabled(spotterText.isEmpty)
            .accessibilityLabel("Add who spotted it")
          }
          Text("Somebody in the car saw it first? Add them. A player’s @handle links to their page.")
            .face(.meta)
            .foregroundStyle(Color.ink3)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private var spotterText: String { spotter.trimmingCharacters(in: .whitespacesAndNewlines) }

  private func addSpotter() {
    guard !spotterText.isEmpty else { return }
    withAnimation(.snappy) { spotters.append(String(spotterText.prefix(APIClient.finderNameMax))) }
    spotter = ""
  }

  /// A spotter's handle, when they wrote one that's a player's.
  private func handle(_ spotter: String) -> String? {
    guard spotter.hasPrefix("@") else { return nil }
    let handle = String(spotter.dropFirst()).lowercased()
    return store.players[handle] == nil ? nil : handle
  }

  // MARK: Your name

  private var yourName: some View {
    Part(title: "Your name") {
      VStack(alignment: .leading, spacing: 8) {
        TextField("Your name", text: $name)
          .face(.field)
          .focused($field, equals: .name)
          .textContentType(.name)
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .padding(.horizontal, 14)
          .frame(minHeight: 50)
          .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .strokeBorder(field == .name ? Color.signGreen : Color.ruleStrong, lineWidth: 1.5)
          }
        Text("It goes on your signs. Your first name also makes your page’s address, for good.")
          .face(.meta)
          .foregroundStyle(Color.ink3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: Posted already?

  @ViewBuilder private var posted: some View {
    Part(title: "Posted already?") {
      switch similar {
      case .waiting:
        Text("Once it has a place, we’ll look for it among the signs nearby.")
          .face(.body).foregroundStyle(Color.ink3).fixedSize(horizontal: false, vertical: true)
      case .checking:
        HStack(spacing: 10) {
          ProgressView()
          Text("Looking at the signs nearby…").face(.body).foregroundStyle(Color.ink2)
        }
      case .none:
        Label {
          Text("Nobody has posted this sign yet").face(.bodyBold).foregroundStyle(Color.ink)
        } icon: {
          Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.greenInk)
        }
        .accessibilityElement(children: .combine)
      case .failed:
        Text("We couldn’t look at the signs nearby just now. You can post it anyway.")
          .face(.body).foregroundStyle(Color.ink3).fixedSize(horizontal: false, vertical: true)
      case .found(let signs):
        VStack(alignment: .leading, spacing: 10) {
          Text(signs.count == 1 ? "This sign nearby has the same numbers:" : "These signs nearby have the same numbers:")
            .face(.body).foregroundStyle(Color.ink2).fixedSize(horizontal: false, vertical: true)
          ForEach(signs.prefix(3)) { sign in SimilarRow(sign: sign) }
          Text("If it’s the same sign, you can still post yours. Finding another way to a posted sign comes soon.")
            .face(.meta).foregroundStyle(Color.ink3).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  // MARK: Post it

  private var actions: some View {
    VStack(spacing: 8) {
      if let problem {
        ProblemLine(text: problem).frame(maxWidth: .infinity, alignment: .leading)
      } else if let missing {
        Text(missing)
          .face(.metaBold)
          .foregroundStyle(Color.ink3)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
      BigButton(
        label: flow.way == nil ? "Post unsolved" : "Post it", symbol: "paperplane.fill", busy: posting,
        enabled: missing == nil
      ) {
        Task { await post() }
      }
      .frame(maxWidth: 640)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(Color.ground.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
  }

  private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// What's still needed before it can go, said under the button.
  private var missing: String? {
    if trimmedTitle.isEmpty { return "Give it a name to post it." }
    if place == .finding { return "Finding the town…" }
    if place.place == nil { return "Say where it was to post it." }
    if account.me?.needsName == true, trimmedName.isEmpty { return "Give your name to post it." }
    return nil
  }

  private func post() async {
    guard let shot = flow.shot, let where_ = place.place, !posting else { return }
    field = nil
    posting = true
    problem = nil
    defer { posting = false }
    do {
      if account.me?.needsName == true { try await account.setName(trimmedName) }
      guard let handle = account.me?.handle, account.signedIn else {
        problem = "You’ve been signed out. Sign in again to post it."
        return
      }
      let file = shot.file
      guard let photo = await Task.detached(priority: .userInitiated, operation: { PostParts.photo(file) }).value else {
        problem = "That photo couldn’t be made ready to post."
        return
      }
      let post = SignPost(
        title: trimmedTitle, numbers: PostParts.numbers(flow.numbers.kept), place: where_, foundOn: day(foundOn),
        finders: PostParts.finders(poster: handle, spotters: spotters, players: Set(store.players.keys)),
        way: flow.way)
      guard let id = try? outbox.add(post, photo: photo, picture: shot.picture, handle: handle) else {
        problem = "Your phone couldn’t keep this post to send. Free up some space, then try again."
        return
      }
      flow.posted()
      flow.path.append(.posted(id))
    } catch {
      problem = Account.say(error)
    }
  }

  /// The day as the server takes it, `2025-09-01`, on the phone's calendar
  /// day in its own time zone.
  private func day(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
  }

  // MARK: Starting

  private func start() async {
    guard !started, let shot = flow.shot else { return }
    started = true
    if let day = shot.foundOn, let date = PostView.date(day) { foundOn = min(date, .now) }
    if store.players.isEmpty { Task { await store.loadPlayers() } }
    script()
    if let lat = shot.file.facts.latitude, let lng = shot.file.facts.longitude {
      if let town = await Places.town(latitude: lat, longitude: lng) {
        if place == .finding { place = .photo(town) }
      } else if place == .finding {
        // Still pinned at the photo's spot, once the player names the town.
        place = .none(photoHadOne: true)
      }
    } else {
      place = .none(photoHadOne: false)
    }
  }

  /// `2025-09-01` at noon, so no time zone moves it a day.
  static func date(_ day: String) -> Date? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
  }

  private func checkSimilar() async {
    guard let spot = place.place, let lat = spot.lat, let lng = spot.lng else {
      similar = .waiting
      return
    }
    let numbers = flow.numbers.values
    guard !numbers.isEmpty else { return similar = .none }
    similar = .checking
    do {
      let signs = try await store.client.similarSigns(latitude: lat, longitude: lng, numbers: numbers)
      similar = signs.isEmpty ? .none : .found(signs)
    } catch {
      if !Store.cancelled(error) { similar = .failed }
    }
    #if DEBUG
      if Script.flag("RSMScrollEnd") {
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation { scroll.scrollTo(edge: .bottom) }
      }
    #endif
  }

  /// Debug builds' launch arguments for screenshots: `-RSMTitle <name>`,
  /// `-RSMSpotted <a,b>`, `-RSMSayWhere YES` (opens the town search, with
  /// `-RSMTown <words>` typed), `-RSMPostName <name>` and `-RSMPostIt YES`
  /// (posts once the form is ready; `-RSMTownPick YES` picks the town
  /// search's first answer), and `-RSMScrollEnd YES` scrolls to the
  /// bottom once "Posted already?" has its answer.
  private func script() {
    #if DEBUG
      if let text = Script.text("RSMTitle") { title = text }
      if let list = Script.text("RSMSpotted") {
        spotters = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      }
      if let text = Script.text("RSMPostName") { name = text }
      if Script.flag("RSMSayWhere") { sayingWhere = true }
    #endif
  }
}

// MARK: Bits

/// A part of the form: its heading, then what it holds.
private struct Part<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).face(.section).foregroundStyle(Color.ink).accessibilityAddTraits(.isHeader)
      content
    }
  }
}

/// The place, with a small map of it and a way to change it.
private struct PlaceCard: View {
  let place: PostPlace
  let from: String
  let change: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      if let lat = place.lat, let lng = place.lng {
        let spot = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        Map(initialPosition: .region(MKCoordinateRegion(center: spot, latitudinalMeters: place.approximate ? 9000 : 1800, longitudinalMeters: place.approximate ? 9000 : 1800)), interactionModes: []) {
          if place.approximate {
            MapCircle(center: spot, radius: 2500).foregroundStyle(Color.signGreen.opacity(0.18)).stroke(Color.signGreen, lineWidth: 1.5)
          } else {
            Marker(place.label, systemImage: "signpost.right.fill", coordinate: spot).tint(Color.signGreen)
          }
        }
        .id(place)
        .frame(height: 120)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      HStack(spacing: 12) {
        Image(systemName: place.approximate ? "mappin.circle" : "mappin.and.ellipse")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(Color.greenInk)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(place.label).face(.nameLarge).foregroundStyle(Color.ink)
          Text(from).face(.meta).foregroundStyle(Color.ink3)
        }
        Spacer(minLength: 8)
        Button("Change", action: change)
          .face(.action)
          .foregroundStyle(Color.greenInk)
          .frame(minHeight: 44)
          .accessibilityLabel("Change the place")
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
    .background(Color.card)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
    .accessibilityElement(children: .combine)
  }
}

/// Someone who found it, and how.
private struct FinderRow: View {
  let avatar: Avatar
  let name: String
  let role: String
  var remove: (() -> Void)?

  var body: some View {
    HStack(spacing: 12) {
      avatar.accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(name).face(.name).foregroundStyle(Color.ink)
        Text(role).face(.meta).foregroundStyle(Color.ink3)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 8)
      if let remove {
        Button(action: remove) {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(Color.ink3)
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(name)")
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 52)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

/// A sign nearby with the same numbers: its photo, name and how far.
private struct SimilarRow: View {
  let sign: Sign

  var body: some View {
    HStack(spacing: 12) {
      if let photo = sign.photos.first {
        PhotoView(url: photo.thumbUrl, alt: photo.alt, pixels: 160)
          .frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(sign.title).face(.name).foregroundStyle(Color.ink).lineLimit(2)
        Text(Self.nearby(sign))
          .face(.meta).foregroundStyle(Color.ink3).lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(10)
    .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.signYellow, lineWidth: 1.5) }
    .accessibilityElement(children: .combine)
  }

  /// "Right here, found by Tyler", "0.4 mi away, found by Jamie".
  static func nearby(_ sign: Sign) -> String {
    let found = "found by \(sign.finderNames)"
    guard let miles = sign.miles else { return "Found by \(sign.finderNames)" }
    if miles < 0.1 { return "Right here, \(found)" }
    return "\(sign.milesText ?? "") away, \(found)"
  }
}

/// "Where was it?": a town search, towns only, from MapKit.
struct SayWhere: View {
  let picked: (PostPlace) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var search = TownSearch()
  @State private var resolving: String?
  @State private var problem: String?
  @FocusState private var focused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass").foregroundStyle(Color.ink3).accessibilityHidden(true)
          TextField("A town or city", text: $search.query)
            .face(.search)
            .focused($focused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .submitLabel(.search)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.signGreen, lineWidth: 1.5) }
        .padding(16)
        if let problem {
          ProblemLine(text: problem).padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
        }
        List {
          ForEach(Array(search.results.enumerated()), id: \.offset) { index, result in
            Button {
              Task { await choose(index) }
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(result.title).face(.nameLarge).foregroundStyle(Color.ink)
                  if !result.subtitle.isEmpty {
                    Text(result.subtitle).face(.meta).foregroundStyle(Color.ink3)
                  }
                }
                Spacer()
                if resolving == result.title + result.subtitle { ProgressView() }
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.card)
          }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
          if search.results.isEmpty {
            Text(search.failed ? "We couldn’t search just now. Check your connection." : "Type the town nearest the sign. It’s pinned at the town, not the spot.")
              .face(.body)
              .foregroundStyle(Color.ink3)
              .multilineTextAlignment(.center)
              .padding(32)
              .frame(maxHeight: .infinity, alignment: .top)
          }
        }
      }
      .background(Color.ground)
      .navigationTitle("Where was it?")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
    }
    .onAppear {
      focused = true
      #if DEBUG
        if let words = Script.text("RSMTown") { search.query = words }
      #endif
    }
    #if DEBUG
      .onChange(of: search.results) { _, now in
        if Script.flag("RSMTownPick"), !now.isEmpty { Task { await choose(0) } }
      }
    #endif
  }

  private func choose(_ index: Int) async {
    guard resolving == nil, search.results.indices.contains(index) else { return }
    let result = search.results[index]
    resolving = result.title + result.subtitle
    problem = nil
    defer { resolving = nil }
    if let place = await Places.town(result) {
      picked(place)
      dismiss()
    } else {
      problem = "We couldn’t find that town on the map. Try another."
    }
  }
}
