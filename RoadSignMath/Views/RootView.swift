import SignCapture
import SwiftUI

/// Home and Map side by side, each keeping its place, under the boards' tab
/// bar: Home, the raised green Capture button, Map.
struct RootView: View {
  @Environment(Store.self) private var store
  @Environment(Account.self) private var account
  @Environment(Outbox.self) private var outbox
  @State private var flow = CaptureFlow()
  /// Someone chose "Look around first" (or "Not now"): sign-in waits until
  /// they ask for it.
  @AppStorage("lookedAround") private var lookedAround = false
  @State private var firstRun = false

  var body: some View {
    @Bindable var account = account
    VStack(spacing: 0) {
      ZStack {
      HomeView()
        .opacity(store.tab == .home ? 1 : 0)
        .allowsHitTesting(store.tab == .home)
        .accessibilityHidden(store.tab != .home)
      MapScreen()
        .opacity(store.tab == .map ? 1 : 0)
        .allowsHitTesting(store.tab == .map)
        .accessibilityHidden(store.tab != .map)
      }
      // Below the screens, not over them, so nothing hides behind it; the
      // raised Capture button still rises over their bottom edge.
      TabBar(capture: { flow.begin() })
        .zIndex(1)
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .background(Color.ground)
    // Me's "Open the camera" starts Capture from its sheet.
    .environment(flow)
    .fullScreenCover(isPresented: $flow.open) {
      CaptureScreen()
        .environment(flow)
        .overlay(alignment: .top) { NoticeToast() }
    }
    .fullScreenCover(isPresented: $account.signingIn) {
      SignInView(firstRun: firstRun) {
        lookedAround = true
        firstRun = false
        account.finishSignIn()
      }
      .overlay(alignment: .top) { NoticeToast() }
    }
    .overlay(alignment: .top) { NoticeToast() }
    .onAppear(perform: welcome)
    // A post waiting for its poster goes once they're signed in, and a
    // post that went up shows on Home and the Map.
    .onChange(of: account.me?.handle) { outbox.signedInChanged() }
    .onChange(of: outbox.postedCount) {
      Task {
        await store.loadLatest()
        await store.loadMap()
      }
      // A post can earn a badge; reading you again puts its dot on Home.
      Task { await account.refresh() }
    }
  }

  /// The first time, the app opens on sign-in, with "Look around first"
  /// for anyone who'd rather see the signs. A sign-in left waiting for its
  /// code (the app closed while you were in Mail) picks up where it was.
  private func welcome() {
    flow.script()
    #if DEBUG
      if let ids = Script.value("RSMUnlocked") {
        Task {
          let picture = SampleSign.photo().flatMap { UIImage(data: $0.data) }
          let id = await outbox.scriptPosted(unlocked: ids.split(separator: ",").map(String.init), picture: picture)
          flow.begin()
          flow.path = [.posted(id)]
        }
      }
    #endif
    guard !account.signedIn else { return account.resumeNaming() }
    if Script.value("RSMSignIn") != nil {
      account.useAnotherEmail()
      account.beginSignIn()
    } else if !Script.scripted, !lookedAround || account.pending != nil {
      firstRun = !lookedAround
      account.beginSignIn()
    }
  }
}

/// A word that floats down from the top for a few seconds: signed out by
/// the server, the account deleted, already signed in.
private struct NoticeToast: View {
  @Environment(Account.self) private var account

  var body: some View {
    ZStack {
      if let notice = account.notice {
        Text(notice)
          .face(.name)
          .foregroundStyle(Color.card)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 18)
          .padding(.vertical, 12)
          .background(Color.ink, in: Capsule())
          .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
          .padding(.horizontal, 24)
          .padding(.top, 8)
          .transition(.move(edge: .top).combined(with: .opacity))
          .onTapGesture { account.notice = nil }
          .task(id: notice) {
            AccessibilityNotification.Announcement(notice).post()
            try? await Task.sleep(for: .seconds(4))
            withAnimation { account.notice = nil }
          }
          .accessibilityAddTraits(.isStaticText)
      }
    }
    .animation(.spring(duration: 0.4), value: account.notice)
  }
}

/// The boards' tab bar: two tabs either side of a raised Capture button.
private struct TabBar: View {
  let capture: () -> Void
  @Environment(Store.self) private var store

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      item(.home, "Home", symbol: "house", chosen: "house.fill")
      Button(action: capture) {
        Image(systemName: "camera")
          .font(.system(size: 24, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 72, height: 56)
          .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          .shadow(color: Color.signGreen.opacity(0.4), radius: 8, y: 6)
          .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
      .buttonStyle(CardPress())
      .offset(y: -18)
      .frame(maxWidth: .infinity)
      .accessibilityLabel("Capture a sign")
      .sensoryFeedback(.impact(weight: .medium), trigger: store.tab)
      item(.map, "Map", symbol: "map", chosen: "map.fill")
    }
    .padding(.top, 6)
    .frame(height: 52, alignment: .top)
    .frame(maxWidth: .infinity)
    .background {
      Color.card
        .ignoresSafeArea(edges: .bottom)
        .overlay(alignment: .top) { Color.rule.frame(height: 1) }
    }
  }

  private func item(_ tab: Store.Tab, _ label: String, symbol: String, chosen: String) -> some View {
    let on = store.tab == tab
    return Button {
      withAnimation(.snappy(duration: 0.2)) { store.choose(tab) }
    } label: {
      VStack(spacing: 2) {
        Image(systemName: on ? chosen : symbol)
          .font(.system(size: 22, weight: on ? .semibold : .regular))
          .frame(height: 28)
          .contentTransition(.symbolEffect(.replace))
        Text(label).face(on ? .tabOn : .tab)
      }
      .foregroundStyle(on ? Color.greenInk : Color.ink3)
      .frame(width: 80, height: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .accessibilityAddTraits(on ? .isSelected : [])
    .sensoryFeedback(.selection, trigger: on)
  }
}

