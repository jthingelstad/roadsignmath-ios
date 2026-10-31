import PhotosUI
import RoadSignMathAPI
import SwiftUI
import UIKit

/// Setting your profile photo: choose one from your photos or take one,
/// square it up in a round preview, and send it. The server crops it square
/// again, strips its metadata (and so where it was taken) and has the
/// moderator look; a refusal says why, and you can try another.
///
/// You's settings start at a choice (`.library`, `.camera`, `.remove`); a tap on your
/// avatar on You starts at the menu of all three.
enum PhotoStart: Hashable {
  case menu, library, camera, remove
}

/// A photo picked or taken, ready to square up.
struct PickedPhoto: Identifiable {
  let id = UUID()
  let image: UIImage
}

extension View {
  /// The profile photo flow, started by setting `start`.
  func profilePhoto(_ start: Binding<PhotoStart?>) -> some View {
    modifier(ProfilePhotoFlow(start: start))
  }
}

private struct ProfilePhotoFlow: ViewModifier {
  @Binding var start: PhotoStart?

  @Environment(Account.self) private var account
  @Environment(Store.self) private var store
  @State private var picked: PhotosPickerItem?
  @State private var cropping: PickedPhoto?
  @State private var confirmRemove = false
  @State private var problem: String?

  private var hasPhoto: Bool { account.me?.avatarUrl != nil }

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        hasPhoto ? "Your profile photo" : "Add a profile photo",
        isPresented: binding(.menu), titleVisibility: .visible
      ) {
        Button("Choose a photo") { after { start = .library } }
        if ProfilePhotoFlow.canTakePhotos { Button("Take a photo") { after { start = .camera } } }
        if hasPhoto { Button("Remove photo", role: .destructive) { confirmRemove = true } }
      } message: {
        Text("Everyone sees it beside your signs and on your page, in place of your first letter.")
      }
      .photosPicker(isPresented: binding(.library), selection: $picked, matching: .images, photoLibrary: .shared())
      .fullScreenCover(isPresented: binding(.camera)) {
        CameraPicker { image in
          start = nil
          if let image { after { cropping = PickedPhoto(image: image) } }
        }
        .ignoresSafeArea()
      }
      .sheet(item: $cropping) { photo in
        PhotoCropView(image: photo.image)
      }
      .alert("Remove your profile photo?", isPresented: $confirmRemove) {
        Button("Remove photo", role: .destructive, action: remove)
        Button("Keep it", role: .cancel) {}
      } message: {
        Text("Your first letter shows again in its place.")
      }
      .alert("Your photo wasn’t removed", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(problem ?? "")
      }
      .onChange(of: start) { _, now in
        guard now == .remove else { return }
        start = nil
        confirmRemove = true
      }
      .onChange(of: picked) { _, item in
        guard let item else { return }
        picked = nil
        Task {
          if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
            cropping = PickedPhoto(image: image)
          } else {
            problem = "That photo couldn’t be opened. Try another one."
          }
        }
      }
      .task {
        #if DEBUG
          // `-RSMPhoto menu` opens the choices; `-RSMPhoto <file>` squares up a
          // file on this Mac as if it had been picked. Nothing is sent until
          // "Use photo" is tapped (or `-RSMPhotoSave YES`).
          if let script = Script.text("RSMPhoto") {
            try? await Task.sleep(for: .milliseconds(600))
            if script == "menu" {
              start = .menu
            } else if let image = UIImage(contentsOfFile: script) {
              cropping = PickedPhoto(image: image)
            }
          }
        #endif
      }
  }

  /// Presented only while `start` is that step.
  private func binding(_ step: PhotoStart) -> Binding<Bool> {
    Binding(get: { start == step }, set: { if !$0, start == step { start = nil } })
  }

  /// The next step, once the one showing has gone away.
  private func after(_ next: @escaping @MainActor () -> Void) {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(350))
      next()
    }
  }

  private func remove() {
    Task {
      do {
        try await account.removePhoto()
        if let me = account.me { store.showPhoto(of: me) }
      } catch {
        if account.signedIn { problem = Account.say(error) }
      }
    }
  }

  static var canTakePhotos: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }
}

/// The camera, as UIKit's picker: front-facing first, since a profile
/// photo is most often of you.
private struct CameraPicker: UIViewControllerRepresentable {
  let done: (UIImage?) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    if UIImagePickerController.isCameraDeviceAvailable(.front) { picker.cameraDevice = .front }
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(done: done) }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let done: (UIImage?) -> Void
    init(done: @escaping (UIImage?) -> Void) { self.done = done }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      done(info[.originalImage] as? UIImage)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
  }
}

/// Squaring up a photo: drag and pinch it inside the square, seen through
/// the circle it will show in, then send it.
struct PhotoCropView: View {
  let image: UIImage

  @Environment(Account.self) private var account
  @Environment(Store.self) private var store
  @Environment(\.dismiss) private var dismiss
  /// How far in, 1 being the photo just filling the square.
  @State private var zoom: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var zoomAtStart: CGFloat?
  @State private var offsetAtStart: CGSize?
  @State private var saving = false
  @State private var problem: String?
  /// The on-screen square's side, which the zoom and offset are measured against.
  @State private var shownSide: CGFloat = 0

  /// The square sent: the server keeps 512 pixels, and a little more
  /// leaves it room to resize cleanly.
  static let side: CGFloat = 1024

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        GeometryReader { geometry in
          let side = min(geometry.size.width, geometry.size.height)
          frame(side: side)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .onAppear { shownSide = side }
            .onChange(of: side) { _, now in
              shownSide = now
              offset = clamp(offset, side: now)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        VStack(spacing: 10) {
          if let problem {
            ProblemLine(text: problem)
          } else {
            Text("Drag and pinch to fit it in the circle. Everyone sees it beside your signs and on your page.")
              .face(.meta)
              .foregroundStyle(Color.ink2)
              .multilineTextAlignment(.center)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.horizontal, 20)
        Spacer(minLength: 0)
      }
      .padding(.top, 12)
      .background(Color.ground)
      .navigationTitle("Your profile photo")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
        ToolbarItem(placement: .confirmationAction) {
          if saving {
            ProgressView()
          } else {
            Button(problem == nil ? "Use photo" : "Try again") { save() }.face(.action)
          }
        }
      }
    }
    .interactiveDismissDisabled(saving)
    .tint(.greenInk)
    .task {
      #if DEBUG
        // `-RSMPhotoSave YES` sends it as "Use photo" would, once it's showing.
        if Script.flag("RSMPhotoSave") {
          try? await Task.sleep(for: .seconds(2))
          save()
        }
      #endif
    }
  }

  /// The photo filling a square, the circle clear and the corners dimmed.
  private func frame(side: CGFloat) -> some View {
    let shown = shownSize(side: side)
    return Image(uiImage: image)
      .resizable()
      .frame(width: shown.width, height: shown.height)
      .offset(offset)
      .frame(width: side, height: side)
      .clipped()
      .overlay {
        Rectangle()
          .fill(Color.black.opacity(0.45))
          .mask {
            Rectangle().overlay { Circle().blendMode(.destinationOut) }.compositingGroup()
          }
          .allowsHitTesting(false)
      }
      .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 2).allowsHitTesting(false) }
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { drag in
            let from = offsetAtStart ?? offset
            offsetAtStart = from
            offset = clamp(CGSize(width: from.width + drag.translation.width, height: from.height + drag.translation.height),
                           side: side)
          }
          .onEnded { _ in offsetAtStart = nil }
          .simultaneously(with: MagnifyGesture()
            .onChanged { pinch in
              let from = zoomAtStart ?? zoom
              zoomAtStart = from
              zoom = min(max(from * pinch.magnification, 1), 5)
              offset = clamp(offset, side: side)
            }
            .onEnded { _ in zoomAtStart = nil })
      )
      .accessibilityElement()
      .accessibilityLabel("Your photo, as it will show")
      .accessibilityAddTraits(.isImage)
  }

  /// The photo's size on screen: filling the square at zoom 1.
  private func shownSize(side: CGFloat) -> CGSize {
    let fill = max(side / image.size.width, side / image.size.height) * zoom
    return CGSize(width: image.size.width * fill, height: image.size.height * fill)
  }

  /// Keeps the photo covering the square.
  private func clamp(_ offset: CGSize, side: CGFloat) -> CGSize {
    let shown = shownSize(side: side)
    let x = max(0, (shown.width - side) / 2)
    let y = max(0, (shown.height - side) / 2)
    return CGSize(width: min(max(offset.width, -x), x), height: min(max(offset.height, -y), y))
  }

  private func save() {
    saving = true
    problem = nil
    let jpeg = PhotoCropView.square(image, zoom: zoom, offset: offset, side: shownSide)
    Task {
      do {
        guard let jpeg else { throw CropProblem.unreadable }
        try await account.setPhoto(jpeg)
        if let me = account.me { store.showPhoto(of: me) }
        saving = false
        dismiss()
      } catch CropProblem.unreadable {
        problem = "That photo couldn’t be read. Try another one."
        saving = false
      } catch {
        problem = Account.say(error)
        saving = false
      }
    }
  }

  enum CropProblem: Error { case unreadable }

  /// The part of the photo inside the square, drawn as a square JPEG at
  /// most `side` pixels across.
  static func square(_ image: UIImage, zoom: CGFloat, offset: CGSize, side screen: CGFloat) -> Data? {
    let size = image.size
    guard size.width > 0, size.height > 0, screen > 0 else { return nil }
    // Points of the photo per point on screen.
    let fill = max(screen / size.width, screen / size.height) * zoom
    let cropSide = screen / fill
    let center = CGPoint(x: size.width / 2 - offset.width / fill, y: size.height / 2 - offset.height / fill)
    let crop = CGRect(x: center.x - cropSide / 2, y: center.y - cropSide / 2, width: cropSide, height: cropSide)
    let out = min(Self.side, cropSide * image.scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let scale = out / cropSide
    let drawn = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
      image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale, width: size.width * scale, height: size.height * scale))
    }
    return drawn.jpegData(compressionQuality: 0.85)
  }
}
