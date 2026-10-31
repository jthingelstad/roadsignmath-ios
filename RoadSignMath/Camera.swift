@preconcurrency import AVFoundation
import Observation
import Synchronization
import SwiftUI

/// The camera behind Capture. The session lives on its own queue, as
/// AVFoundation asks; this is what the screen sees of it.
@MainActor @Observable
final class Camera {
  enum State: Equatable {
    case idle, starting, running
    /// The camera is turned off for Road Sign Math in Settings.
    case denied
    /// No camera at all: the simulator.
    case none
    case failed
  }

  private(set) var state = State.idle
  /// The zoom as the Camera app counts it: 1 is the main camera.
  private(set) var zoom: Double = 1
  /// The zooms worth a button: 1, and the telephoto's when there is one.
  private(set) var stops: [Double] = [1]

  let session = CameraSession()
  /// The preview, which knows how the phone is turned.
  weak var preview: PreviewView?

  func start() async {
    guard state == .idle || state == .failed || state == .denied else { return }
    // No camera (the simulator): say so without asking for one.
    guard AVCaptureDevice.default(for: .video) != nil else {
      state = .none
      return
    }
    guard await CameraSession.access() else {
      state = .denied
      return
    }
    state = .starting
    do {
      let lens = try await session.start()
      stops = lens.stops
      // The device keeps its zoom across stops; start it back at 1 so the
      // view and the button agree.
      zoom = 1
      session.setZoom(1)
      state = .running
      preview?.attach(session.session, device: lens.device)
    } catch CameraSession.Problem.noCamera {
      state = .none
    } catch {
      state = .failed
    }
  }

  func stop() {
    session.stop()
    if state == .running || state == .starting { state = .idle }
  }

  /// Takes a photo, turned the way the phone is held.
  func shoot() async throws -> Data {
    let angle = preview?.captureAngle ?? 90
    return try await session.capture(angle: angle)
  }

  /// Zooms to `factor` as the Camera app counts it, within what the lens can do.
  func zoom(to factor: Double) {
    let clamped = min(max(factor, 1), session.maxZoom)
    zoom = clamped
    session.setZoom(clamped)
  }
}

/// The capture session, on its own queue. Its state is touched only there,
/// and the photo continuations behind a lock, so it's safe to share.
final class CameraSession: NSObject, @unchecked Sendable {
  enum Problem: Error { case noCamera, failed }

  /// The lens in use and its zoom stops.
  struct Lens: @unchecked Sendable {
    let device: AVCaptureDevice
    let stops: [Double]
  }

  let session = AVCaptureSession()
  private let output = AVCapturePhotoOutput()
  private let queue = DispatchQueue(label: "xyz.roadsignmath.camera")
  private var device: AVCaptureDevice?
  private let limit = Mutex<Double>(1)
  /// The device's zoom factor for the main camera, the Camera app's 1x. A
  /// triple camera counts from its ultra wide, so its 1x is about 2.
  private let base = Mutex<Double>(1)
  private let waiting = Mutex<[Int64: CheckedContinuation<Data, any Error>]>([:])

  /// Whether the camera may be used, asking the first time.
  static func access() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: true
    case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
    default: false
    }
  }

  var maxZoom: Double { limit.withLock { $0 } }

  func start() async throws -> Lens {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          let lens = try self.configure()
          if !self.session.isRunning { self.session.startRunning() }
          continuation.resume(returning: lens)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func stop() {
    queue.async {
      if self.session.isRunning { self.session.stopRunning() }
    }
  }

  func setZoom(_ factor: Double) {
    queue.async {
      guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
      // The factor is the Camera app's; the device counts from its widest lens.
      let wanted = factor * self.base.withLock { $0 }
      device.videoZoomFactor = min(max(wanted, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
      device.unlockForConfiguration()
    }
  }

  func capture(angle: CGFloat) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        guard self.session.isRunning else { return continuation.resume(throwing: Problem.failed) }
        let settings =
          self.output.availablePhotoCodecTypes.contains(.jpeg)
          ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]) : AVCapturePhotoSettings()
        // Fast over fine: the sign is going by.
        settings.photoQualityPrioritization = .balanced
        if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) {
          connection.videoRotationAngle = angle
        }
        self.waiting.withLock { $0[settings.uniqueID] = continuation }
        self.output.capturePhoto(with: settings, delegate: self)
      }
    }
  }

  /// The back camera, with its telephoto when the phone has one (three
  /// cameras or two), so a far-off sign can be brought close.
  private func configure() throws -> Lens {
    if let device { return Lens(device: device, stops: stops(of: device)) }
    let found = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera], mediaType: .video,
      position: .back
    ).devices.first
    guard let found else { throw Problem.noCamera }
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .photo
    guard let input = try? AVCaptureDeviceInput(device: found), session.canAddInput(input), session.canAddOutput(output)
    else { throw Problem.failed }
    session.addInput(input)
    session.addOutput(output)
    output.maxPhotoQualityPrioritization = .balanced
    if output.isResponsiveCaptureSupported { output.isResponsiveCaptureEnabled = true }
    if output.isFastCapturePrioritizationSupported { output.isFastCapturePrioritizationEnabled = true }
    device = found
    let main = Double(1 / found.displayVideoZoomFactorMultiplier)
    base.withLock { $0 = main }
    limit.withLock { $0 = min(found.maxAvailableVideoZoomFactor / main, 10) }
    return Lens(device: found, stops: stops(of: found))
  }

  private func stops(of device: AVCaptureDevice) -> [Double] {
    // In the Camera app's terms: the main camera, then the first lens past it.
    let main = base.withLock { $0 }
    let switches = device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue / main }
    return [1] + switches.filter { $0 > 1.01 }.prefix(1)
  }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
    let continuation = waiting.withLock { $0.removeValue(forKey: photo.resolvedSettings.uniqueID) }
    if let error {
      continuation?.resume(throwing: error)
    } else if let data = photo.fileDataRepresentation() {
      continuation?.resume(returning: data)
    } else {
      continuation?.resume(throwing: Problem.failed)
    }
  }
}

/// The live view, filling the screen. It turns with the phone, through the
/// device's rotation coordinator, and knows which way to turn a photo.
final class PreviewView: UIView {
  override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
  private var coordinator: AVCaptureDevice.RotationCoordinator?

  func attach(_ session: AVCaptureSession, device: AVCaptureDevice) {
    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
    coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
    turn()
  }

  /// The angle a photo is turned by, so it stands as the phone was held.
  var captureAngle: CGFloat? { coordinator?.videoRotationAngleForHorizonLevelCapture }

  override func layoutSubviews() {
    super.layoutSubviews()
    turn()
  }

  private func turn() {
    guard let angle = coordinator?.videoRotationAngleForHorizonLevelPreview,
      let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle)
    else { return }
    connection.videoRotationAngle = angle
  }
}

struct CameraPreview: UIViewRepresentable {
  let camera: Camera

  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.backgroundColor = .black
    camera.preview = view
    return view
  }

  func updateUIView(_ view: PreviewView, context: Context) {}
}
