import RoadSignMathAPI
import SwiftUI

/// Everyone's signs, newest first, or nearest first.
struct HomeView: View {
  enum Which: Hashable { case latest, near }

  @Environment(Store.self) private var store
  @State private var which = Which.latest
  @State private var top = ScrollPosition(edge: .top)
  @Namespace private var zoom

  var body: some View {
    @Bindable var store = store
    NavigationStack(path: $store.homePath) {
      ScrollView {
        LazyVStack(spacing: 10, pinnedViews: .sectionHeaders) {
          Section {
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
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(Color.card, for: .navigationBar)
      .navigationDestination(for: String.self) { id in
        SignView(id: id)
          .navigationTransition(.zoom(sourceID: id, in: zoom))
      }
    }
    .task { if store.latestLoad == .idle { await store.loadLatest() } }
    .sensoryFeedback(.selection, trigger: which)
    .onChange(of: which) { _, now in
      if now == .near, store.nearLoad == .idle { Task { await store.loadNear() } }
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
