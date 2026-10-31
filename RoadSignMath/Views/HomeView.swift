import RoadSignMathAPI
import SwiftUI

/// Everyone's signs, newest first, or nearest first.
struct HomeView: View {
  enum Which: Hashable { case latest, near }

  @Environment(Store.self) private var store
  @Environment(Account.self) private var account
  @State private var which = Which.latest
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
    }
  }

  /// Your avatar, which opens Me, or a way to sign in.
  @ViewBuilder private var you: some View {
    if let me = account.me, account.signedIn {
      Button {
        showingMe = true
      } label: {
        Avatar(name: me.name, color: Color(hex: me.avatarColor) ?? .signGreen, size: 34)
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
    HStack(spacing: 6) {
      Pill(label: "Latest", chosen: which == .latest) { withAnimation(.snappy) { which = .latest } }
      Pill(label: "Near you", chosen: which == .near) { withAnimation(.snappy) { which = .near } }
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.card)
    .overlay(alignment: .bottom) { Color.rule.frame(height: 1) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Which signs")
  }

  @ViewBuilder private var content: some View {
    switch which {
    case .latest: latest
    case .near: near
    }
  }

  @ViewBuilder private var latest: some View {
    switch store.latestLoad {
    case .idle, .loading where store.latest.isEmpty:
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
          ProgressView()
            .padding(24)
            .task { await store.loadMore() }
        } else if store.latest.count > 3 {
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

  private func cards(_ signs: [Sign], miles: Bool) -> some View {
    ForEach(signs) { sign in
      SignCard(sign: sign, showMiles: miles, zoom: zoom) { store.homePath.append(sign.id) }
    }
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
