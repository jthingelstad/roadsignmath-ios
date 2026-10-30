import MapKit
import RoadSignMathAPI
import SwiftUI
import UIKit

/// MapKit's map with the signs as pins that gather into clusters, which
/// SwiftUI's Map can't do yet. Choosing a pin sets `selected`; choosing a
/// cluster zooms into it, or, when its signs share one spot, lists them in
/// `together`.
struct SignMap: UIViewRepresentable {
  let pins: [Pin]
  @Binding var selected: String?
  @Binding var together: [String]
  @Binding var focus: MapFocus?

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIView(context: Context) -> MKMapView {
    let map = LaidOutMap()
    map.laidOut = { [weak map, coordinator = context.coordinator] in
      if let map { coordinator.frameWhenReady(map) }
    }
    let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
    configuration.pointOfInterestFilter = .excludingAll
    map.preferredConfiguration = configuration
    map.delegate = context.coordinator
    map.showsCompass = false
    map.showsScale = false
    map.register(SignPinView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
    map.register(SignClusterView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
    // The lower 48 until the pins arrive.
    map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 39.5, longitude: -96),
                                     span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 34)), animated: false)
    return map
  }

  func updateUIView(_ map: MKMapView, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    coordinator.sync(map, pins: pins)
    if let focus, focus != coordinator.lastFocus {
      coordinator.lastFocus = focus
      coordinator.fly(map, to: focus.id)
    }
    coordinator.syncSelection(map, selected: selected)
  }

  @MainActor
  final class Coordinator: NSObject, MKMapViewDelegate {
    var parent: SignMap
    var lastFocus: MapFocus?
    private var shown: [String: SignAnnotation] = [:]
    private var framed = false
    private var reframe: Task<Void, Never>?
    /// Whether the map shows what `frameAll` framed, at the size it was.
    private var fitted = false
    private var fittedSize = CGSize.zero

    init(_ parent: SignMap) { self.parent = parent }

    func sync(_ map: MKMapView, pins: [Pin]) {
      let wanted = Dictionary(pins.compactMap { pin in pin.location.map { _ in (pin.id, pin) } }, uniquingKeysWith: { a, _ in a })
      let gone = shown.keys.filter { wanted[$0] == nil }
      map.removeAnnotations(gone.compactMap { shown.removeValue(forKey: $0) })
      let added = wanted.values.filter { shown[$0.id] == nil }.map(SignAnnotation.init)
      for annotation in added { shown[annotation.id] = annotation }
      map.addAnnotations(added)
      if framed, !shown.isEmpty, !gone.isEmpty || !added.isEmpty {
        // A search or a year chose other signs: show them, once typing
        // pauses and the card below has taken its new height.
        frameSoon(map)
      }
      frameWhenReady(map)
    }

    /// Frames every pin once, as soon as there are pins and the map has a
    /// size; afterwards, while the map still shows all its pins, keeps them
    /// in view when the card below changes the map's height.
    func frameWhenReady(_ map: MKMapView) {
      if framed {
        if fitted, map.bounds.size != fittedSize { frameSoon(map) }
        return
      }
      guard !shown.isEmpty, map.bounds.width > 0 else { return }
      framed = true
      frameAll(map, animated: false)
    }

    /// Frames the pins once typing pauses and the card below has taken its
    /// new height.
    private func frameSoon(_ map: MKMapView) {
      reframe?.cancel()
      reframe = Task { @MainActor [weak map] in
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, let map else { return }
        self.frameAll(map, animated: true)
      }
    }

    func mapView(_ map: MKMapView, regionWillChangeAnimated animated: Bool) {
      // A finger on the map: it's the player's view now, not the framing.
      let touched = map.subviews.first?.gestureRecognizers?.contains { $0.state == .began || $0.state == .changed } ?? false
      if touched {
        fitted = false
        reframe?.cancel()
      }
    }

    func syncSelection(_ map: MKMapView, selected: String?) {
      let current = map.selectedAnnotations.compactMap { $0 as? SignAnnotation }.first?.id
      guard current != selected else { return }
      if let selected, let annotation = shown[selected] {
        map.selectAnnotation(annotation, animated: true)
      } else if selected == nil {
        for annotation in map.selectedAnnotations { map.deselectAnnotation(annotation, animated: true) }
      }
    }

    /// Every pin in view, with room for the search bar and the card.
    func frameAll(_ map: MKMapView, animated: Bool) {
      var rect = shown.values.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: MKMapPoint($1.coordinate), size: MKMapSize(width: 1, height: 1))) }
      // One sign, or a few in one town, shows the town around it rather
      // than the street.
      let least = 30_000 * MKMapPointsPerMeterAtLatitude(rect.origin.coordinate.latitude)
      if rect.width < least && rect.height < least {
        rect = rect.insetBy(dx: -(least - rect.width) / 2, dy: -(least - rect.height) / 2)
      }
      map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 150, left: 36, bottom: 40, right: 36), animated: animated)
      fitted = true
      fittedSize = map.bounds.size
    }

    /// Close enough to a pin that it stands on its own, then choose it.
    func fly(_ map: MKMapView, to id: String) {
      guard let annotation = shown[id] else { return }
      let region = MKCoordinateRegion(center: annotation.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
      fitted = false
      reframe?.cancel()
      map.setRegion(region, animated: true)
      parent.selected = id
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(450))
        map.selectAnnotation(annotation, animated: true)
      }
    }

    func mapView(_ map: MKMapView, didSelect annotation: any MKAnnotation) {
      if let cluster = annotation as? MKClusterAnnotation {
        map.deselectAnnotation(cluster, animated: false)
        let members = cluster.memberAnnotations.compactMap { $0 as? SignAnnotation }
        if spread(members) < 500 {
          // The same town: zooming won't part them, so list them.
          parent.selected = nil
          parent.together = members.map(\.id)
        } else {
          fitted = false
          reframe?.cancel()
          map.showAnnotations(members, animated: true)
        }
      } else if let pin = annotation as? SignAnnotation, parent.selected != pin.id {
        parent.selected = pin.id
      }
    }

    func mapView(_ map: MKMapView, didDeselect annotation: any MKAnnotation) {
      guard let pin = annotation as? SignAnnotation, parent.selected == pin.id else { return }
      // A tap on the map lets go; choosing another pin sets it again at once.
      Task { @MainActor in
        if map.selectedAnnotations.isEmpty, self.parent.selected == pin.id { self.parent.selected = nil }
      }
    }

    /// The widest distance between any member and the first, in meters.
    private func spread(_ members: [SignAnnotation]) -> CLLocationDistance {
      guard let first = members.first else { return 0 }
      let origin = MKMapPoint(first.coordinate)
      return members.map { MKMapPoint($0.coordinate).distance(to: origin) }.max() ?? 0
    }
  }
}

/// A map that says when it has been laid out, so the first framing knows its size.
final class LaidOutMap: MKMapView {
  var laidOut: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    laidOut?()
  }
}

/// A sign on the map. It has no `title`: MapKit floats a chosen pin's title
/// over it, and the card below already says it.
final class SignAnnotation: NSObject, MKAnnotation {
  let id: String
  let coordinate: CLLocationCoordinate2D
  let name: String

  init(_ pin: Pin) {
    id = pin.id
    coordinate = CLLocationCoordinate2D(latitude: pin.lat ?? 0, longitude: pin.lng ?? 0)
    name = pin.title
  }
}

private let green = UIColor(rgb: 0x006348)
private let yellow = UIColor(rgb: 0xF2B300)

/// A sign's pin, as the boards draw it: the sign's green in a white ring,
/// growing a yellow ring when chosen.
final class SignPinView: MKAnnotationView {
  private let dot = UIView()

  override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    clusteringIdentifier = "signs"
    collisionMode = .circle
    displayPriority = .defaultHigh
    canShowCallout = false
    frame = CGRect(x: 0, y: 0, width: 44, height: 44)
    dot.frame = CGRect(x: 13, y: 13, width: 18, height: 18)
    dot.backgroundColor = green
    dot.layer.cornerRadius = 9
    dot.layer.borderWidth = 2.5
    dot.layer.borderColor = UIColor.white.cgColor
    dot.layer.shadowColor = UIColor.black.cgColor
    dot.layer.shadowOpacity = 0.35
    dot.layer.shadowRadius = 2
    dot.layer.shadowOffset = CGSize(width: 0, height: 1)
    dot.isUserInteractionEnabled = false
    addSubview(dot)
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not from a storyboard") }

  override var annotation: (any MKAnnotation)? {
    didSet {
      clusteringIdentifier = "signs"
      accessibilityLabel = (annotation as? SignAnnotation)?.name ?? "A sign"
    }
  }

  override func prepareForDisplay() {
    super.prepareForDisplay()
    clusteringIdentifier = "signs"
    accessibilityLabel = (annotation as? SignAnnotation)?.name ?? "A sign"
  }

  override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    let change = {
      self.dot.transform = selected ? CGAffineTransform(scaleX: 1.4, y: 1.4) : .identity
      self.dot.layer.borderColor = (selected ? yellow : UIColor.white).cgColor
      self.dot.layer.borderWidth = selected ? 3 : 2.5
    }
    zPriority = selected ? .max : .defaultUnselected
    if animated && !UIAccessibility.isReduceMotionEnabled {
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, animations: change)
    } else {
      change()
    }
    accessibilityTraits = selected ? [.button, .selected] : .button
  }
}

/// Signs gathered into one circle with how many.
final class SignClusterView: MKAnnotationView {
  private let circle = UILabel()

  override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
    super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
    collisionMode = .circle
    displayPriority = .defaultHigh
    circle.textAlignment = .center
    circle.textColor = .white
    circle.backgroundColor = green
    circle.font = UIFont(name: "OverpassRoman-Black", size: 15) ?? .systemFont(ofSize: 15, weight: .black)
    circle.layer.borderColor = UIColor.white.cgColor
    circle.layer.borderWidth = 2.5
    circle.layer.masksToBounds = true
    circle.isUserInteractionEnabled = false
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.35
    layer.shadowRadius = 3
    layer.shadowOffset = CGSize(width: 0, height: 1)
    addSubview(circle)
    isAccessibilityElement = true
    accessibilityTraits = .button
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not from a storyboard") }

  override func prepareForDisplay() {
    super.prepareForDisplay()
    let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0
    let side: CGFloat = count < 10 ? 34 : 40
    frame = CGRect(x: 0, y: 0, width: max(side, 44), height: max(side, 44))
    circle.frame = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
    circle.layer.cornerRadius = side / 2
    circle.text = String(count)
    accessibilityLabel = "\(count) signs here"
    accessibilityHint = "Zooms in"
  }
}
