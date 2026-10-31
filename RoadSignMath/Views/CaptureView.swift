import PhotosUI
import SignCapture
import SwiftUI

/// Capture, as a whole: the camera, then Check the numbers, then the step
/// after, over the app. It turns with the phone; the rest of the app stands
/// upright.
struct CaptureScreen: View {
  @Environment(CaptureFlow.self) private var flow

  var body: some View {
    @Bindable var flow = flow
    NavigationStack(path: $flow.path) {
      CameraView()
        .navigationTitle("Camera")
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: CaptureFlow.Stop.self) { stop in
          switch stop {
          case .check: CheckView()
          case .solve: SolveView()
          case .post: PostView()
          case .posted(let id): PostedView(id: id)
          }
        }
    }
    .tint(.greenInk)
    .onAppear {
      Orientation.allow(.allButUpsideDown)
      #if DEBUG
        if Script.flag("RSMLandscape") {
          Task {
            try? await Task.sleep(for: .milliseconds(600))
            Orientation.turnSideways()
          }
        }
      #endif
    }
    .onDisappear { Orientation.allow(.portrait) }
  }
}

/// The boards' Capture: the camera filling the screen, "Passenger mode" at
/// the top, the shutter on the side the phone's bottom is on. After a shot,
/// the photo with every number it reads boxed, and the way on to checking
/// them.
private struct CameraView: View {
  @Environment(CaptureFlow.self) private var flow
  @State private var camera = Camera()
  @State private var picked: PhotosPickerItem?
  @State private var aboutPassenger = false
  @AppStorage(Preferences.passengerMode) private var passengerMode = true
  @State private var shooting = false
  @State private var blink = false
  @State private var pinchFrom: Double?
  @Environment(\.openURL) private var openURL
  @Environment(\.scenePhase) private var phase

  var body: some View {
    GeometryReader { geometry in
      let wide = geometry.size.width > geometry.size.height
      ZStack {
        Color.black.ignoresSafeArea()
        viewfinder
          .ignoresSafeArea()
        if blink { Color.white.ignoresSafeArea().transition(.opacity) }
        chrome(wide: wide)
      }
    }
    .statusBarHidden()
    .persistentSystemOverlays(.hidden)
    .task {
      #if DEBUG
        // A screenshot of a photo needs no camera, nor its question.
        if let what = Script.value("RSMCapture"), what != "camera" { return }
      #endif
      await camera.start()
    }
    .onDisappear { camera.stop() }
    .onChange(of: phase) { _, now in
      // Back from Settings with the camera turned on: ask again.
      if now == .active, camera.state == .denied { Task { await camera.start() } }
    }
    .onChange(of: picked) { _, item in
      guard let item else { return }
      picked = nil
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          flow.take(data, from: .library)
        } else {
          flow.problem = "That photo couldn’t be opened. Try another one."
        }
      }
    }
    .sensoryFeedback(.success, trigger: flow.reading) { _, now in now == .read }
  }

  // MARK: The picture

  @ViewBuilder private var viewfinder: some View {
    ZStack {
      CameraPreview(camera: camera)
        .opacity(camera.state == .running ? 1 : 0)
        .gesture(pinch)
      if camera.state != .running && camera.state != .starting && camera.state != .idle {
        cameraProblem
      }
      if flow.reviewing, let shot = flow.shot {
        Color.black
        BoxedPhoto(
          picture: shot.picture, numbers: flow.reading == .read ? flow.numbers.numbers : [],
          scanning: flow.reading == .reading
        ) { _, _ in
          if flow.reading == .read { flow.path.append(.check) }
        }
        .transition(.opacity)
      }
      if flow.opening {
        ProgressView().tint(.white).controlSize(.large)
      }
    }
    .animation(.easeOut(duration: 0.25), value: flow.reviewing)
  }

  private var pinch: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let from = pinchFrom ?? camera.zoom
        pinchFrom = from
        camera.zoom(to: from * value.magnification)
      }
      .onEnded { _ in pinchFrom = nil }
  }

  /// No camera, or no permission: say so kindly, and offer the photo library.
  private var cameraProblem: some View {
    VStack(spacing: 12) {
      Image(systemName: camera.state == .denied ? "camera.badge.ellipsis" : "camera.metering.unknown")
        .font(.system(size: 40, weight: .semibold))
        .foregroundStyle(Color.signYellow)
      Text(problemTitle).face(.section).foregroundStyle(.white)
      Text(problemText)
        .face(.body)
        .foregroundStyle(.white.opacity(0.8))
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      VStack(spacing: 10) {
        if camera.state == .denied {
          Button {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          } label: {
            Text("Open Settings").face(.action).frame(minWidth: 200, minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .tint(.signGreen)
        } else if camera.state == .failed {
          Button {
            Task { await camera.start() }
          } label: {
            Text("Try again").face(.action).frame(minWidth: 200, minHeight: 44)
          }
          .buttonStyle(.borderedProminent)
          .tint(.signGreen)
        }
        // The picker's label is built off the main actor, so the face goes on
        // the picker.
        PhotosPicker("Choose a photo you took", selection: $picked, matching: .images, photoLibrary: .shared())
          .face(.action)
          .controlSize(.large)
          .buttonStyle(.bordered)
          .tint(.white)
        #if DEBUG
          Button {
            if let sample = SampleSign.photo() { flow.take(sample.data, from: .sample) }
          } label: {
            Text("Shoot the sample sign").face(.action).frame(minWidth: 200, minHeight: 44)
          }
          .buttonStyle(.bordered)
          .tint(Color.signYellow)
        #endif
      }
      .padding(.top, 6)
    }
    .padding(28)
    .frame(maxWidth: 420)
  }

  private var problemTitle: String {
    switch camera.state {
    case .denied: "The camera is off for Road Sign Math"
    case .none: "No camera here"
    default: "The camera didn’t start"
    }
  }

  private var problemText: String {
    switch camera.state {
    case .denied: "Turn it on in Settings to photograph signs, or use a photo you took earlier."
    case .none: "This iPhone has no camera to use. A photo you took earlier works just as well."
    default: "Something kept the camera from starting. Try again, or use a photo you took earlier."
    }
  }

  // MARK: Around the picture

  private func chrome(wide: Bool) -> some View {
    ZStack {
      // Close, at the top left; Passenger mode, at the top in the middle.
      VStack {
        ZStack(alignment: .top) {
          HStack {
            RoundButton(symbol: "xmark", label: "Close the camera") { flow.close() }
            Spacer()
          }
          if passengerMode { PassengerLabel(open: $aboutPassenger) }
        }
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 8)

      if wide {
        HStack(spacing: 0) {
          ZStack {
            hint(wide: true)
            card
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
              .padding(16)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          controls(wide: true)
        }
      } else {
        VStack(spacing: 0) {
          Spacer()
          ZStack(alignment: .bottom) {
            hint(wide: false)
            card
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 14)
          controls(wide: false)
        }
      }
    }
  }

  /// Under the live view: what to do, or what went wrong with a photo.
  @ViewBuilder private func hint(wide: Bool) -> some View {
    if !flow.reviewing, camera.state == .running || flow.problem != nil {
      VStack(alignment: .leading, spacing: 2) {
        Text(flow.problem == nil ? "Frame the sign’s numbers" : "That one didn’t open").face(.name)
        Text(flow.problem ?? "Every number on it counts, even 7B and 82nd.")
          .face(.meta)
          .foregroundStyle(Color(uiColor: UIColor(rgb: 0xDDE3DD)))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      .padding(wide ? 16 : 0)
      .allowsHitTesting(false)
    }
  }

  /// After a shot: "Got it. 8 numbers." and the way on.
  @ViewBuilder private var card: some View {
    if flow.reviewing, flow.shot != nil {
      Button {
        flow.path.append(.check)
      } label: {
        HStack(spacing: 12) {
          if flow.reading == .reading {
            ProgressView().tint(Color.greenInk)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(flow.headline).face(.nameLarge).foregroundStyle(Color.ink)
            Text(cardText)
              .face(.meta)
              .foregroundStyle(Color.ink2)
          }
          Image(systemName: "chevron.right")
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(Color.greenInk)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
      }
      .buttonStyle(CardPress())
      .disabled(flow.reading == .reading)
      .accessibilityHint(flow.reading == .reading ? "" : "Opens Check the numbers")
      .transition(.move(edge: .bottom).combined(with: .opacity))
    }
  }

  private var cardText: String {
    switch flow.reading {
    case .idle, .reading: "Every number gets a box"
    case .failed: "Add its numbers yourself"
    case .read: flow.numbers.isEmpty ? "Tap them on the photo, or type them" : "Check them before you solve"
    }
  }

  /// The shutter between the photo library and the last shot: down the
  /// side held sideways, along the bottom upright.
  private func controls(wide: Bool) -> some View {
    let layout = wide ? AnyLayout(VStackLayout(spacing: 26)) : AnyLayout(HStackLayout(spacing: 0))
    return layout {
      PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
        Image(systemName: "photo.on.rectangle")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 48, height: 48)
          .background(.white.opacity(0.14), in: Circle())
      }
      .accessibilityLabel("Choose a photo you took")
      .frame(maxWidth: wide ? nil : .infinity)

      shutter
        // The zoom sits beside the shutter, toward the picture, as in the
        // Camera app.
        .overlay(alignment: wide ? .leading : .top) {
          if camera.state == .running, camera.stops.count > 1, !flow.reviewing {
            zoomButton.offset(x: wide ? -54 : 0, y: wide ? 0 : -54)
          }
        }
        .frame(maxWidth: wide ? nil : .infinity)

      Group {
        if let shot = flow.shot, !flow.reviewing {
          Button {
            flow.reviewing = true
          } label: {
            Image(uiImage: shot.picture)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 48, height: 48)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white, lineWidth: 2) }
          }
          .accessibilityLabel("Last photo: check its numbers")
        } else {
          Color.clear.frame(width: 48, height: 48)
        }
      }
      .frame(maxWidth: wide ? nil : .infinity)
    }
    .padding(wide ? .vertical : .horizontal, 20)
    .frame(width: wide ? 120 : nil, height: wide ? nil : 120)
    .frame(maxWidth: wide ? nil : .infinity, maxHeight: wide ? .infinity : nil)
    .background(.black.opacity(0.42))
  }

  /// The zoom: 1x, or the telephoto's 2x or 3x, for a sign far off.
  private var zoomButton: some View {
    let tele = camera.stops.last ?? 1
    let on = camera.zoom >= tele - 0.01
    return Button {
      camera.zoom(to: on ? 1 : tele)
    } label: {
      Text(zoomText)
        .font(Face.number.font(size: 13))
        .foregroundStyle(on ? Color.signYellow : .white)
        .frame(width: 40, height: 40)
        .background(.black.opacity(0.5), in: Circle())
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
    .accessibilityLabel("Zoom")
    .accessibilityValue(zoomText)
    .sensoryFeedback(.selection, trigger: on)
  }

  private var zoomText: String {
    let value = (camera.zoom * 10).rounded() / 10
    return (value == value.rounded() ? String(Int(value)) : String(value)) + "×"
  }

  @ViewBuilder private var shutter: some View {
    let canShoot = camera.state == .running && !shooting
    Button {
      if flow.reviewing {
        flow.retake()
      } else {
        shoot()
      }
    } label: {
      ZStack {
        Circle().strokeBorder(.white, lineWidth: 4)
        if flow.reviewing {
          Image(systemName: "arrow.counterclockwise")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
        } else {
          Circle().fill(.white).padding(8).opacity(canShoot ? 1 : 0.4)
        }
      }
      .frame(width: 72, height: 72)
      .contentShape(Circle())
    }
    .buttonStyle(CardPress())
    .disabled(!flow.reviewing && !canShoot)
    .accessibilityLabel(flow.reviewing ? "Take another photo" : "Take the photo")
    .sensoryFeedback(.impact(weight: .medium), trigger: shooting) { _, now in now }
  }

  private func shoot() {
    shooting = true
    withAnimation(.easeOut(duration: 0.08)) { blink = true }
    Task {
      try? await Task.sleep(for: .milliseconds(90))
      withAnimation(.easeIn(duration: 0.2)) { blink = false }
    }
    Task {
      defer { shooting = false }
      do {
        let data = try await camera.shoot()
        flow.take(data, from: .camera, at: .now)
      } catch {
        flow.problem = "The camera missed that one. Try again."
      }
    }
  }
}

/// "Passenger mode": a reminder, not a lock, as the boards draw it. A tap
/// says what it means.
private struct PassengerLabel: View {
  @Binding var open: Bool

  var body: some View {
    VStack(spacing: 8) {
      Button {
        withAnimation(.snappy) { open.toggle() }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "steeringwheel")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.signYellow)
          Text("Passenger mode").face(.name)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(.black.opacity(0.6), in: Capsule())
        .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .frame(minHeight: 44)
      .accessibilityHint("What passenger mode means")

      if open {
        Text("Road Sign Math is for the passenger seat. Driving? Keep your eyes on the road and let someone else take the shot.")
          .face(.meta)
          .foregroundStyle(Color.ink)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
          .frame(maxWidth: 300)
          .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
          .onTapGesture { withAnimation(.snappy) { open = false } }
          .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
          .task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation(.snappy) { open = false }
          }
      }
    }
  }
}

/// A round, dark button on the camera.
private struct RoundButton: View {
  let symbol: String
  let label: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 44, height: 44)
        .background(.black.opacity(0.55), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}
