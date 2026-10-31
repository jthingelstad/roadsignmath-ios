import SignCapture
import SignReading
import SwiftUI

/// Fixes a number the reading got wrong, or adds one it missed: the spot on
/// the photo, close up, and the number as the sign shows it.
struct NumberSheet: View {
  let edit: NumberEdit
  @Environment(CaptureFlow.self) private var flow
  @Environment(\.dismiss) private var dismiss
  @State private var typed = ""
  @State private var problem: String?
  @FocusState private var typing: Bool

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let closeUp {
            Image(uiImage: closeUp)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxWidth: .infinity, maxHeight: 150)
              .background(Color.photoGround)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              .accessibilityLabel("This part of your photo, close up")
          }
          if let said { Text(said).face(.body).foregroundStyle(Color.ink2) }

          VStack(alignment: .leading, spacing: 6) {
            Text("The number, as the sign shows it").face(.label).foregroundStyle(Color.ink)
            TextField("Number", text: $typed)
              .font(Face.digit.font(size: 26))
              .keyboardType(.numbersAndPunctuation)
              .textInputAutocapitalization(.characters)
              .autocorrectionDisabled()
              .submitLabel(.done)
              .focused($typing)
              .onSubmit(save)
              .onChange(of: typed) { problem = nil }
              .padding(.horizontal, 14)
              .frame(minHeight: 56)
              .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                  .strokeBorder(problem == nil ? Color.ruleStrong : Color.warn, lineWidth: 1.5)
              }
            Text(problem ?? "Letters next to it are fine: 7B counts as 7.")
              .face(problem == nil ? .meta : .metaBold)
              .foregroundStyle(problem == nil ? Color.ink3 : Color.warn)
              .fixedSize(horizontal: false, vertical: true)
          }

          Button(action: save) {
            Text(adding ? "Add it" : "Save")
              .face(.button)
              .frame(maxWidth: .infinity, minHeight: 50)
          }
          .buttonStyle(.borderedProminent)
          .tint(.signGreen)
          .buttonBorderShape(.roundedRectangle(radius: 14))

          if case .fix(let id) = edit, let number = flow.numbers[id] {
            if number.isFixed, let reading = number.reading {
              Button {
                flow.numbers.restore(id)
                dismiss()
              } label: {
                Text("Put back \(reading.text)")
                  .face(.action)
                  .foregroundStyle(Color.greenInk)
                  .frame(maxWidth: .infinity, minHeight: 44)
              }
              .buttonStyle(.plain)
            }
            Button(role: .destructive) {
              withAnimation(.snappy) { flow.numbers.remove(id) }
              dismiss()
            } label: {
              Text("Remove it, it isn’t a number on the sign")
                .face(.action)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.warn)
          }
        }
        .padding(20)
      }
      .background(Color.ground)
      .navigationTitle(adding ? "Add a number" : "Fix this number")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .onAppear {
      switch edit {
      case .fix(let id): typed = flow.numbers[id]?.text ?? ""
      case .add(_, let suggestion): typed = suggestion ?? ""
      }
      typing = true
    }
  }

  private var adding: Bool {
    if case .add = edit { true } else { false }
  }

  private var box: NormalizedBox? {
    switch edit {
    case .fix(let id): flow.numbers[id]?.box
    case .add(let box, _): box
    }
  }

  private var closeUp: UIImage? { box.flatMap { flow.closeUp($0) } }

  /// What we read there, in a sentence.
  private var said: String? {
    switch edit {
    case .fix(let id):
      guard let number = flow.numbers[id] else { return nil }
      guard let reading = number.reading else { return "You added this one." }
      return "We read \(reading.text) in “\(reading.sourceText)”."
    case .add(_, let suggestion?):
      return "Looking closer, we think this says \(suggestion)."
    case .add(let box?, nil) where box.width < 0.1:
      return "We couldn’t make out a number there. Type it as you see it."
    case .add:
      return nil
    }
  }

  private func save() {
    do throws(NumberEntry.Problem) {
      switch edit {
      case .fix(let id): _ = try flow.numbers.fix(id, to: typed)
      case .add(let box, _): _ = try flow.numbers.add(typed, at: box)
      }
      dismiss()
    } catch {
      problem = error.message
    }
  }
}
