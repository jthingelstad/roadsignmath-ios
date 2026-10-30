import RoadSignMathAPI
import SwiftUI

/// You, the beginnings of the boards' Me screen: your name and page, your
/// email (only you see it), sign out, and Delete my account. Your signs,
/// passenger mode and the rest come with the full Me screen.
struct MeView: View {
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
        if let me = account.me {
          list(me)
        } else {
          ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
      .background(Color.ground)
      .navigationTitle("You")
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
    .task {
      // Opened while signed out (the token ended a moment ago): nothing to show.
      guard account.signedIn else { return dismiss() }
      await account.refresh()
    }
    .onChange(of: account.signedIn) { _, now in if !now { dismiss() } }
  }

  private func list(_ me: Me) -> some View {
    List {
      Section {
        header(me)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())
      }
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
          Text(Self.deleteWords(me))
        }
      } footer: {
        if let problem {
          ProblemLine(text: problem)
        } else {
          Text("Deletes your account and everything you posted. It can’t be undone.").face(.meta)
        }
      }
    }
    .scrollContentBackground(.hidden)
    .tint(.greenInk)
  }

  private func header(_ me: Me) -> some View {
    VStack(spacing: 10) {
      Avatar(name: me.name, color: Color(hex: me.avatarColor) ?? .signGreen, size: 76)
      Text(me.shownName)
        .face(.title)
        .foregroundStyle(me.name.isEmpty ? Color.ink3 : Color.ink)
        .accessibilityAddTraits(.isHeader)
      if !me.name.isEmpty {
        Text(Self.address(me.url))
          .face(.meta)
          .foregroundStyle(Color.ink3)
          .accessibilityLabel("Your page: \(Self.address(me.url))")
      }
      HStack(spacing: 28) {
        stat("\(me.signCount)", me.signCount == 1 ? "sign" : "signs")
        stat("\(me.states.count)", me.states.count == 1 ? "state" : "states")
        stat(me.firstYear.map(String.init) ?? "–", "first sign")
          .accessibilityLabel(me.firstYear.map { "First sign in \($0)" } ?? "No first sign yet")
      }
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
  }

  private func stat(_ value: String, _ label: String) -> some View {
    VStack(spacing: 0) {
      Text(value).face(.number).foregroundStyle(Color.ink)
      Text(label).face(.meta).foregroundStyle(Color.ink3)
    }
    .accessibilityElement(children: .combine)
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
