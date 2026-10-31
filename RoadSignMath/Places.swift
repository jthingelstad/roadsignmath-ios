import CoreLocation
import MapKit
import Observation
import Posting
import RoadSignMathAPI

/// Where a sign is, for its post: the town at the photo's own GPS spot, or
/// a town the player picks. Never the phone's live location: Capture
/// doesn't ask for it.
@MainActor
enum Places {
  /// The town at a spot, `Bloomington, MN`, pinned at the spot itself.
  /// Nil when MapKit can't say (no connection, the middle of a lake).
  static func town(latitude: Double, longitude: Double) async -> PostPlace? {
    guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
      let item = try? await request.mapItems.first,
      let label = label(item)
    else { return nil }
    return PostPlace(label: label, state: state(item, label), lat: latitude, lng: longitude, approximate: false)
  }

  /// A town picked from the search, pinned at the town: approximate.
  static func town(_ completion: MKLocalSearchCompletion) async -> PostPlace? {
    let request = MKLocalSearch.Request(completion: completion)
    request.resultTypes = .address
    guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
    let coordinate = item.location.coordinate
    let label = label(item) ?? [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    guard !label.isEmpty else { return nil }
    return PostPlace(
      label: String(label.prefix(APIClient.placeMax)), state: state(item, label),
      lat: coordinate.latitude, lng: coordinate.longitude, approximate: true)
  }

  private static func label(_ item: MKMapItem) -> String? {
    let label = item.addressRepresentations?.cityWithContext(.short) ?? item.addressRepresentations?.cityName ?? item.name
    return label.map { String($0.prefix(APIClient.placeMax)) }
  }

  /// The two-letter state, for places in the US.
  private static func state(_ item: MKMapItem, _ label: String) -> String? {
    guard item.addressRepresentations?.region == .unitedStates else { return nil }
    return PostParts.state(in: label)
  }
}

/// The town search on "Where was it?": MapKit's completer, towns only.
@MainActor @Observable
final class TownSearch: NSObject, MKLocalSearchCompleterDelegate {
  private(set) var results: [MKLocalSearchCompletion] = []
  private(set) var failed = false
  @ObservationIgnored private let completer = MKLocalSearchCompleter()

  override init() {
    super.init()
    completer.resultTypes = .address
    completer.addressFilter = MKAddressFilter(including: [.locality])
    completer.delegate = self
  }

  var query: String = "" {
    didSet {
      failed = false
      if query.trimmingCharacters(in: .whitespaces).isEmpty {
        completer.cancel()
        results = []
      } else {
        completer.queryFragment = query
      }
    }
  }

  nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    MainActor.assumeIsolated { results = self.completer.results }
  }

  nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
    MainActor.assumeIsolated { failed = true }
  }
}
