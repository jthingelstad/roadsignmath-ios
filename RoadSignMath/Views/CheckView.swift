import SignCapture
import SignReading
import SwiftUI

/// What the number sheet is open for.
enum NumberEdit: Identifiable, Hashable {
  /// Fixing (or removing) a number on the list.
  case fix(CheckedNumber.ID)
  /// Adding one the reading missed: where on the photo, if a spot was
  /// tapped, and what a second, closer reading found there.
  case add(box: NormalizedBox?, suggestion: String?)

  var id: String {
    switch self {
    case .fix(let id): "fix-\(id)"
    case .add(let box, let suggestion): "add-\(String(describing: box))-\(suggestion ?? "")"
    }
  }
}

/// The boards' Check the numbers: the photo with every number boxed, and
/// the list under it. Untick a number to leave it out, tap one to fix it,
/// tap the photo where one was missed. The kept numbers are what Solve
/// (step 2.4) may use.
struct CheckView: View {
  @Environment(CaptureFlow.self) private var flow
  @Environment(Account.self) private var account
  @State private var editing: NumberEdit?
  @State private var focus: CheckedNumber.ID?
  @State private var spot: CGPoint?
  @State private var askSignIn = false
  @State private var signingIn = false
  @State private var nothingThere = false

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width > geometry.size.height
      Group {
        if wide {
          HStack(spacing: 0) {
            photo
              .frame(width: geometry.size.width * 0.52)
              .padding(.vertical, 8)
            ScrollView { list.padding(16) }
          }
        } else {
          ScrollView {
            VStack(spacing: 0) {
              photo
                .frame(height: min(geometry.size.width * 0.72, 320))
                .background(Color.photoGround)
              list.padding(16)
            }
          }
        }
      }
    }
    .background(Color.ground)
    .safeAreaInset(edge: .bottom, spacing: 0) { actions }
    .navigationTitle("Check the numbers")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(Color.ground, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if !flow.numbers.isEmpty {
          Text("\(flow.numbers.kept.count)/\(flow.numbers.numbers.count)")
            .font(Face.number.font(size: 16))
            .foregroundStyle(Color.greenInk)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy, value: flow.numbers.kept.count)
            .accessibilityLabel("\(flow.numbers.kept.count) of \(flow.numbers.numbers.count) numbers kept")
        }
      }
    }
    .sheet(item: $editing, onDismiss: { focus = nil }) { edit in
      NumberSheet(edit: edit)
    }
    .alert("Sign in to post", isPresented: $askSignIn) {
      Button("Sign in") {
        if account.prepareSignIn() { signingIn = true }
      }
      Button("Not now", role: .cancel) {}
    } message: {
      Text("Your photo and its numbers wait right here while you do.")
    }
    .fullScreenCover(isPresented: $signingIn) {
      // "Not now" on the email step comes back here; a finished sign-in
      // ends on its own (the welcome moment resets the step), seen below.
      SignInView { leaveSignIn() }
    }
    .onChange(of: account.step) { _, step in
      if signingIn, step == .email, account.signedIn { leaveSignIn() }
    }
    // Sign-in stands upright, as it does everywhere else.
    .onChange(of: signingIn) { _, now in Orientation.allow(now ? .portrait : .allButUpsideDown) }
    .onAppear(perform: script)
  }

  // MARK: The photo

  @ViewBuilder private var photo: some View {
    if let shot = flow.shot {
      BoxedPhoto(
        picture: shot.picture, numbers: flow.numbers.numbers, focus: focus,
        scanning: flow.reading == .reading, spot: spot
      ) { x, y in
        tapped(x, y)
      }
      .overlay(alignment: .bottom) {
        if nothingThere {
          Text("Nothing new there. Type it instead?")
            .face(.metaBold)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.7), in: Capsule())
            .padding(.bottom, 10)
            .transition(.opacity)
        }
      }
    }
  }

  /// A tap on a number opens it; a tap anywhere else reads that spot again,
  /// close up, for a number the first reading missed.
  private func tapped(_ x: Double, _ y: Double) {
    if let number = flow.numbers.number(at: x, y) {
      focus = number.id
      editing = .fix(number.id)
      return
    }
    guard spot == nil, flow.reading != .reading else { return }
    spot = CGPoint(x: x, y: y)
    Task {
      let found = await flow.readSpot(x, y)
      spot = nil
      if let found {
        editing = .add(box: found.box, suggestion: found.text)
      } else {
        editing = .add(box: SpotReading.marker(at: x, y), suggestion: nil)
      }
    }
  }

  // MARK: The list

  private var list: some View {
    VStack(alignment: .leading, spacing: 14) {
      switch flow.reading {
      case .reading, .idle:
        HStack(spacing: 10) {
          ProgressView()
          Text("Reading the numbers…").face(.body).foregroundStyle(Color.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
      case .failed(let why):
        Notice(symbol: "exclamationmark.magnifyingglass", title: "Couldn’t read this one", message: why)
        // The ones the player added themselves, to fix, untick or remove.
        if !flow.numbers.isEmpty { rows }
      case .read where flow.numbers.isEmpty:
        Notice(
          symbol: "number.square",
          title: "No numbers read",
          message: "Tap a number on the photo, or type the ones you see.")
      case .read:
        rows
        Text("Untick a number to leave it out. It’s your sign: keep the ones that make the math fun.")
          .face(.meta)
          .foregroundStyle(Color.ink3)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 4)
      }
      if flow.reading != .reading {
        Button {
          editing = .add(box: nil, suggestion: nil)
        } label: {
          Label("Add a number we missed", systemImage: "plus")
            .face(.action)
            .foregroundStyle(Color.greenInk)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.ruleStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
        .buttonStyle(CardPress())
        Text("Or tap the photo where it is.")
          .face(.meta)
          .foregroundStyle(Color.ink3)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var rows: some View {
    VStack(spacing: 0) {
      ForEach(Array(flow.numbers.numbers.enumerated()), id: \.element.id) { index, number in
        if index > 0 { Divider().overlay(Color.rule).padding(.leading, 16) }
        NumberRow(number: number) {
          withAnimation(.snappy) { flow.numbers.toggle(number.id) }
        } open: {
          focus = number.id
          editing = .fix(number.id)
        } remove: {
          withAnimation(.snappy) { flow.numbers.remove(number.id) }
        }
      }
    }
    .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.rule, lineWidth: 1) }
  }

  // MARK: The way on

  private var actions: some View {
    VStack(spacing: 8) {
      if flow.reading == .read || flow.reading.isFailed, let problem = flow.numbers.problem {
        Text(problem.message)
          .face(.metaBold)
          .foregroundStyle(Color.warn)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
      HStack(spacing: 10) {
        Button {
          if account.signedIn { flow.path.append(.post) } else { askSignIn = true }
        } label: {
          Text("Post unsolved")
            .face(.button)
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.ruleStrong, lineWidth: 1.5)
            }
        }
        .buttonStyle(CardPress())
        Button {
          flow.path.append(.solve)
        } label: {
          Text("Solve it")
            .face(.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.signGreen, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(CardPress())
      }
      .disabled(!ready)
      .opacity(ready ? 1 : 0.5)
    }
    .padding(.horizontal, 16)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(Color.ground.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
  }

  /// Closes sign-in and, once signed in, goes on to posting.
  private func leaveSignIn() {
    account.finishSignIn()
    signingIn = false
    if account.signedIn { flow.path.append(.post) }
  }

  private var ready: Bool {
    flow.reading != .reading && flow.numbers.problem == nil
  }

  private func script() {
    #if DEBUG
      if let nth = Script.value("RSMFix").flatMap(Int.init), flow.numbers.numbers.indices.contains(nth - 1) {
        let number = flow.numbers.numbers[nth - 1]
        focus = number.id
        editing = .fix(number.id)
      } else if Script.flag("RSMAdd") {
        editing = .add(box: nil, suggestion: nil)
      } else if let at = Script.value("RSMSpot")?.split(separator: ",").compactMap({ Double($0) }), at.count == 2 {
        tapped(at[0], at[1])
      }
    #endif
  }
}

extension CaptureFlow.Reading {
  var isFailed: Bool { if case .failed = self { true } else { false } }
}

/// One number on the list: the number, the words it was read from, why,
/// and its tick.
private struct NumberRow: View {
  let number: CheckedNumber
  let toggle: () -> Void
  let open: () -> Void
  let remove: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Button(action: open) {
        HStack(spacing: 14) {
          Text(number.text)
            .font(Face.number.font(size: 22))
            .foregroundStyle(number.kept ? Color.ink : Color.ink3)
            .strikethrough(!number.kept, color: Color.ink3)
            .frame(minWidth: 52, alignment: .leading)
          VStack(alignment: .leading, spacing: 2) {
            // The words it was read from, when there are more than the
            // number itself ("EXIT 7B", "82nd St").
            if let source {
              Text(source)
                .face(.name)
                .foregroundStyle(number.kept ? Color.ink : Color.ink3)
                .lineLimit(2)
            }
            Text(number.why)
              .face(source == nil ? .body : .meta)
              .foregroundStyle(source == nil ? Color.ink2 : Color.ink3)
              .lineLimit(2)
          }
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Button(action: toggle) {
        ZStack {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(number.kept ? Color.signGreen : Color.card)
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(number.kept ? Color.signGreen : Color(uiColor: UIColor(rgb: 0xB9C3BB)), lineWidth: 2)
          if number.kept {
            Image(systemName: "checkmark")
              .font(.system(size: 14, weight: .heavy))
              .foregroundStyle(.white)
              .transition(.scale.combined(with: .opacity))
          }
        }
        .frame(width: 26, height: 26)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .sensoryFeedback(.selection, trigger: number.kept)
    }
    .padding(.leading, 16)
    .padding(.trailing, 6)
    .padding(.vertical, 6)
    .frame(minHeight: 64)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(number.kept ? "Kept" : "Left out")
    .accessibilityHint("Double-tap to keep it or leave it out")
    .accessibilityAddTraits(.isToggle)
    .accessibilityAction(.default, toggle)
    .accessibilityAction(named: "Fix it", open)
    .accessibilityAction(named: "Remove it", remove)
    .contextMenu {
      Button("Fix it", systemImage: "pencil", action: open)
      Button(number.kept ? "Leave it out" : "Keep it", systemImage: number.kept ? "minus.circle" : "checkmark.circle", action: toggle)
      Button("Remove it", systemImage: "trash", role: .destructive, action: remove)
    }
  }

  private var source: String? {
    guard let source = number.sourceText?.trimmingCharacters(in: .whitespaces), source != number.text else {
      return nil
    }
    return source
  }

  private var label: String {
    var words = number.text
    if let source { words += ", from \(source)" }
    return words + ". " + number.why
  }
}
