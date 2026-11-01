import RoadSignMathAPI
import SwiftUI

/// Everyone's signs, newest first, nearest first, the most hearted first,
/// or the most complex math first.
struct HomeView: View {
  enum Which: Hashable { case latest, near, popular, complex }

  @Environment(Store.self) private var store
  @Environment(Account.self) private var account
  @Environment(CaptureFlow.self) private var flow
  @State private var which = HomeView.scripted()
  /// How to play has been closed, or its camera opened: a new player's
  /// card shows until then, or until they've posted a sign.
  @AppStorage("howToPlayDone") private var howToPlayDone = false
  /// `-RSMHowToPlay YES` shows the card anyway, for screenshots.
  @State private var howToPlayScripted = Script.flag("RSMHowToPlay")
  @State private var showingMe = Script.flag("RSMMe") || Script.flag("RSMBadges") || Script.value("RSMBadge") != nil
  @State private var top = ScrollPosition(edge: .top)
  @Namespace private var zoom

  var body: some View {
    @Bindable var store = store
    NavigationStack(path: $store.homePath) {
      ScrollView {
        LazyVStack(spacing: 10, pinnedViews: .sectionHeaders) {
          Section {
            OutboxNotes()
            if which == .latest, let trouble = store.latestTrouble {
              NoSignalBar(trouble: trouble, asOf: store.latestReadAt)
            }
            if showsHowToPlay {
              HowToPlayCard(name: account.me?.name, done: closeHowToPlay) {
                closeHowToPlay()
                flow.begin()
              }
              .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            content
          } header: {
            tabs
          }
        }
        .padding(.bottom, 24)
      }
      .scrollPosition($top)
      .onChange(of: store.homeToTop) { withAnimation(.smooth) { top.scrollTo(edge: .top) } }
      .background(Color.ground)
      .refreshable {
        switch which {
        case .latest: await store.loadLatest()
        case .near: await store.loadNear()
        case .popular: await store.loadPopular()
        case .complex: await store.loadComplex()
        }
      }
      .toolbar {
        ToolbarItem(placement: .principal) { Brand() }
        ToolbarItem(placement: .topBarTrailing) { you }
          .sharedBackgroundVisibility(.hidden)
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color.card, for: .navigationBar)
      .navigationDestination(for: String.self) { id in
        if let handle = PlayerPath.handle(id) {
          PlayerView(handle: handle)
        } else {
          SignView(id: id)
            .navigationTransition(.zoom(sourceID: id, in: zoom))
        }
      }
    }
    .findsAnotherWay()
    .environment(\.opener, Opener(sign: { store.homePath.append($0) }, player: { store.homePath.append(PlayerPath.of($0)) }))
    .task { if store.latestLoad == .idle { await store.loadLatest() } }
    .sheet(isPresented: $showingMe) { MeView() }
    .sensoryFeedback(.selection, trigger: which)
    .onChange(of: which) { _, now in
      if now == .near, store.nearLoad == .idle { Task { await store.loadNear() } }
      if now == .popular, store.popularLoad == .idle { Task { await store.loadPopular() } }
      if now == .complex, store.complexLoad == .idle { Task { await store.loadComplex() } }
    }
    .task {
      if which == .popular, store.popularLoad == .idle { await store.loadPopular() }
      if which == .complex, store.complexLoad == .idle { await store.loadComplex() }
    }
    // A player with a sign posted knows how to play.
    .onChange(of: account.me?.signCount ?? 0, initial: true) { _, now in
      if now > 0, !howToPlayScripted { howToPlayDone = true }
    }
  }

  private var showsHowToPlay: Bool {
    howToPlayScripted || (!howToPlayDone && (account.me?.signCount ?? 0) == 0)
  }

  private func closeHowToPlay() {
    withAnimation(.snappy) {
      howToPlayDone = true
      howToPlayScripted = false
    }
  }

  /// The tab Home opens on: Latest, or `-RSMFeed popular|complexity` in
  /// a Debug build's screenshots.
  private static func scripted() -> Which {
    switch Script.value("RSMFeed") {
    case "popular": .popular
    case "complexity": .complex
    default: .latest
    }
  }

  /// Your avatar, which opens Me, or a way to sign in.
  @ViewBuilder private var you: some View {
    if let me = account.me, account.signedIn {
      Button {
        showingMe = true
      } label: {
        Avatar(name: me.name, color: Color(hex: me.avatarColor) ?? .signGreen, size: 34, photo: me.avatarThumbUrl)
          // A badge not seen yet.
          .overlay(alignment: .topTrailing) { if !account.newBadges.isEmpty { NewDot().offset(x: 2, y: -2) } }
          .frame(width: 44, height: 44)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel((me.name.isEmpty ? "You" : "You: \(me.name)") + (account.newBadges.isEmpty ? "" : ", a new badge"))
    } else if account.signedIn {
      Button { showingMe = true } label: {
        Image(systemName: "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(Color.greenInk)
          .frame(width: 44, height: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("You")
    } else {
      Button { account.beginSignIn() } label: {
        // The words when they fit beside the title, else the symbol.
        ViewThatFits(in: .horizontal) {
          Text("Sign in").face(.action).lineLimit(1).fixedSize()
          Image(systemName: "person.crop.circle").font(.system(size: 26))
        }
        .foregroundStyle(Color.greenInk)
        .frame(minWidth: 44, minHeight: 44)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Sign in")
    }
  }

  private var tabs: some View {
    // Four don't fit across a phone, so they slide sideways.
    ScrollView(.horizontal) {
      HStack(spacing: 6) {
        Pill(label: "Latest", chosen: which == .latest) { withAnimation(.snappy) { which = .latest } }
        Pill(label: "Near you", chosen: which == .near) { withAnimation(.snappy) { which = .near } }
        Pill(label: "Popular", chosen: which == .popular) { withAnimation(.snappy) { which = .popular } }
        Pill(label: "Complexity", chosen: which == .complex) { withAnimation(.snappy) { which = .complex } }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
    }
    .scrollIndicators(.hidden)
    .background(Color.card)
    .overlay(alignment: .bottom) { Color.rule.frame(height: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Which signs")
  }

  @ViewBuilder private var content: some View {
    switch which {
    case .latest: latest
    case .near: near
    case .popular: popular
    case .complex: complexity
    }
  }

  @ViewBuilder private var latest: some View {
    switch store.latestLoad {
    // The signs kept from last time show while the server is read.
    case .idle where store.latest.isEmpty, .loading where store.latest.isEmpty:
      ForEach(0..<3, id: \.self) { _ in CardSkeleton() }
    case .failed(let why):
      Notice(symbol: "wifi.exclamationmark", title: "Can’t reach the signs", message: why,
             action: ("Try again", { Task { await store.loadLatest() } }))
        .padding(.top, 60)
    default:
      if store.latest.isEmpty {
        Notice(symbol: "signpost.right", title: "No signs yet", message: "When someone finds a sign whose numbers make true math, it shows up here.")
          .padding(.top, 60)
      } else {
        cards(store.latest, miles: false)
        if store.hasMore {
          if store.latestTrouble == nil {
            ProgressView()
              .padding(24)
              .task { await store.loadMore() }
          }
        } else if store.latest.count > 3, !store.latestKept {
          Text("That’s every sign so far.")
            .face(.meta)
            .foregroundStyle(Color.ink3)
            .padding(24)
        }
      }
    }
  }

  @ViewBuilder private var near: some View {
    if store.locationDenied {
      Notice(symbol: "location.slash", title: "Where are you?",
             message: "Near you needs your location, only while you’re looking. You can allow it in Settings.",
             action: ("Open Settings", { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }))
        .padding(.top, 60)
    } else {
      switch store.nearLoad {
      case .idle, .loading:
        if store.near.isEmpty {
          ForEach(0..<3, id: \.self) { _ in CardSkeleton() }
        } else {
          cards(store.near, miles: true)
        }
      case .failed(let why):
        Notice(symbol: "location.magnifyingglass", title: "Can’t find signs near you", message: why,
               action: ("Try again", { Task { await store.loadNear() } }))
          .padding(.top, 60)
      case .loaded:
        if store.near.isEmpty {
          Notice(symbol: "signpost.right", title: "Nothing near you yet", message: "Be the first to find one around here.")
            .padding(.top, 60)
        } else {
          cards(store.near, miles: true)
        }
      }
    }
  }

  /// The most hearted first (Jamie, 2026-10-31: all-time hearts, newest
  /// breaks ties, unhearted signs last), in the order the server gives.
  @ViewBuilder private var popular: some View {
    switch store.popularLoad {
    case .idle, .loading where store.popular.isEmpty:
      ForEach(0..<3, id: \.self) { _ in CardSkeleton() }
    case .failed(let why):
      Notice(symbol: "wifi.exclamationmark", title: "Can’t reach the signs", message: why,
             action: ("Try again", { Task { await store.loadPopular() } }))
        .padding(.top, 60)
    default:
      if store.popular.isEmpty {
        Notice(symbol: "heart", title: "No signs yet", message: "Heart the signs you love and the favorites rise to the top here.")
          .padding(.top, 60)
      } else {
        cards(store.popular, miles: false)
      }
    }
  }

  /// The most complex math first, as the server scores it (the operators in
  /// a sign's hardest way: roots, powers and factorials count most). The
  /// score orders the list and is never shown.
  @ViewBuilder private var complexity: some View {
    switch store.complexLoad {
    case .idle, .loading where store.complex.isEmpty:
      ForEach(0..<3, id: \.self) { _ in CardSkeleton() }
    case .failed(let why):
      Notice(symbol: "wifi.exclamationmark", title: "Can’t reach the signs", message: why,
             action: ("Try again", { Task { await store.loadComplex() } }))
        .padding(.top, 60)
    default:
      if store.complex.isEmpty {
        Notice(symbol: "x.squareroot", title: "No signs yet", message: "Roots, powers and factorials put a sign near the top here.")
          .padding(.top, 60)
      } else {
        cards(store.complex, miles: false)
      }
    }
  }

  private func cards(_ signs: [Sign], miles: Bool) -> some View {
    ForEach(signs) { sign in
      SignCard(sign: sign, showMiles: miles, zoom: zoom) { store.homePath.append(sign.id) }
    }
  }
}

/// Over Latest's signs when the last read failed, for want of a signal
/// or an answer: when the signs shown were read, and how to try again.
/// It goes by itself once a read works, which happens as soon as the
/// signal is back.
struct NoSignalBar: View {
  let trouble: Store.Trouble
  let asOf: Date?

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: trouble == .noSignal ? "wifi.slash" : "exclamationmark.icloud")
        .font(.system(size: 20, weight: .semibold))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(trouble == .noSignal ? "No signal" : "Can’t reach the signs").face(.bodyBold)
        Text(words).face(.meta).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .foregroundStyle(Color.yellowInk)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color.signYellow, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .padding(.horizontal, 16)
    .padding(.top, 2)
    .accessibilityElement(children: .combine)
  }

  private var words: String {
    let read = asOf.map { "These are the signs as of \(Self.when($0)). " } ?? ""
    return trouble == .noSignal
      ? read + "Pull down to try again."
      : "Road Sign Math isn’t answering just now. " + read + "Pull down to try again."
  }

  /// "2:14 PM" today, "yesterday at 2:14 PM", or "Oct 30 at 2:14 PM".
  static func when(_ date: Date, now: Date = .now) -> String {
    let time = date.formatted(date: .omitted, time: .shortened)
    let calendar = Calendar.current
    if calendar.isDate(date, inSameDayAs: now) { return time }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
      return "yesterday at \(time)"
    }
    return date.formatted(.dateTime.month(.abbreviated).day()) + " at " + time
  }
}

/// The app's name in the bar, with its sign.
struct Brand: View {
  var body: some View {
    HStack(spacing: 8) {
      Image("Logo")
        .resizable()
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      Text("Road Sign Math").face(.brand).foregroundStyle(Color.ink)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Road Sign Math")
    .accessibilityAddTraits(.isHeader)
  }
}

/// A card's shape while the signs are on their way.
struct CardSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Circle().fill(Color.rule).frame(width: 34, height: 34)
        VStack(alignment: .leading, spacing: 6) {
          Capsule().fill(Color.rule).frame(width: 80, height: 10)
          Capsule().fill(Color.rule).frame(width: 160, height: 8)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      Color.photoGround.frame(height: 270)
      RoundedRectangle(cornerRadius: 12).fill(Color.signGreen.opacity(0.35))
        .frame(height: 52)
        .padding(.horizontal, 16)
        .padding(.top, 10)
      Capsule().fill(Color.rule).frame(width: 200, height: 10).padding(16)
    }
    .background(Color.card)
    .modifier(Shimmer())
    .accessibilityHidden(true)
  }
}
