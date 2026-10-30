import SwiftUI

/// Home and Map side by side, each keeping its place, under the boards' tab
/// bar: Home, the raised green Capture button, Map.
struct RootView: View {
  @Environment(Store.self) private var store
  @State private var capturing = false

  var body: some View {
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
      TabBar(capture: { capturing = true })
        .zIndex(1)
    }
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .background(Color.ground)
    .sheet(isPresented: $capturing) {
      CaptureSoon()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
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

/// What the Capture button shows until capturing arrives.
private struct CaptureSoon: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "camera.viewfinder")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(Color.greenInk)
        .symbolEffect(.bounce, options: .nonRepeating)
        .padding(.top, 28)
      Text("Capture is on its way").face(.title).foregroundStyle(Color.ink)
      Text("Soon you’ll point the camera at a sign from the passenger seat, check the numbers it reads, and solve it right here.")
        .face(.body)
        .foregroundStyle(Color.ink2)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      SignPlate(text: "Driving + Math = Fun", tex: "\\text{Driving} + \\text{Math} = \\text{Fun}", size: 22)
        .padding(.top, 6)
        .accessibilityHidden(true)
      Spacer(minLength: 0)
      Button {
        dismiss()
      } label: {
        Text("Keep looking around")
          .face(.action)
          .frame(maxWidth: .infinity, minHeight: 50)
      }
      .buttonStyle(.borderedProminent)
      .tint(.signGreen)
      .buttonBorderShape(.roundedRectangle(radius: 14))
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 12)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.card)
  }
}
