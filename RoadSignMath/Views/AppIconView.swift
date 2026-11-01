import SwiftUI

/// Settings' App icon: the five icons from the identity collection, the
/// one on the Home Screen ticked. A tap asks the system to change it (it
/// says so in its own alert); if it can't, the tick stays where the icon
/// really is and a line says it didn't change.
struct AppIconView: View {
  @State private var current = HomeScreenIcon.current
  @State private var changing: HomeScreenIcon?
  @State private var problem: String?
  private let changeable = HomeScreenIcon.changeable

  var body: some View {
    List {
      Section {
        ForEach(HomeScreenIcon.allCases) { icon in
          Button {
            choose(icon)
          } label: {
            row(icon)
          }
          .disabled(!changeable || changing != nil)
        }
      } footer: {
        VStack(alignment: .leading, spacing: 12) {
          if let problem {
            ProblemLine(text: problem)
          }
          Text(
            changeable
              ? "Changes the icon on your Home Screen. Inside the app, Road Sign Math stays Highway green."
              : "This iPhone can’t change the app’s icon."
          )
          .face(.meta)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Color.ground)
    .navigationTitle("App icon")
    .navigationBarTitleDisplayMode(.inline)
    .sensoryFeedback(.selection, trigger: current)
    .onAppear { current = .current }
    .task {
      // `-RSMAppIconPick <id>` (with `-RSMAppIcon YES`) taps one, for screenshots.
      guard let id = Script.value("RSMAppIconPick"), let icon = HomeScreenIcon(rawValue: id) else { return }
      try? await Task.sleep(for: .seconds(1))
      choose(icon)
    }
  }

  private func row(_ icon: HomeScreenIcon) -> some View {
    HStack(spacing: 14) {
      Image(icon.picture)
        .resizable()
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 13.5, style: .continuous))
      VStack(alignment: .leading, spacing: 2) {
        Text(icon.name).face(.bodyBold).foregroundStyle(Color.ink)
        Text(icon == .highway ? icon.about + " The default." : icon.about)
          .face(.meta)
          .foregroundStyle(Color.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      if changing == icon {
        ProgressView()
      } else if current == icon {
        Image(systemName: "checkmark")
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(Color.greenInk)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(icon.name + (icon == .highway ? ", the default" : ""))
    .accessibilityValue(icon.looks)
    .accessibilityAddTraits(current == icon ? .isSelected : [])
  }

  private func choose(_ icon: HomeScreenIcon) {
    guard changeable, changing == nil, icon != current else { return }
    changing = icon
    problem = nil
    Task {
      do {
        try await icon.choose()
      } catch {
        problem = "The icon didn’t change. Try again in a moment."
      }
      // Whatever the system did, show what's really there.
      current = .current
      changing = nil
    }
  }
}

#Preview {
  NavigationStack { AppIconView() }
}
