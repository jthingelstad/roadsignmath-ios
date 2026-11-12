import Foundation

/// The last part of a sign's or a player's page on the website, from a
/// link the app is opened with: `/signs/<key>`, `/players/<key>`. Pages go
/// by slug and handle. On 2026-11-12 the site gave out id links for a day
/// (an uppercase ULID as stored), and it now redirects them, but a
/// universal link reaches the app without the redirect. The API takes
/// either: `GET /signs/{id}` an id or slug, and `GET /players/{handle}` a
/// handle or (API 1.14.0) an id, but an id only as stored, while the site
/// also takes one typed in another case.
public enum PageKey {
  /// The key to ask the API with: an id in another case made uppercase, as
  /// the site does; a slug or handle as it is.
  public static func normalized(_ key: String) -> String {
    let upper = key.uppercased()
    return key != upper && isID(upper) ? upper : key
  }

  /// A ULID as the server writes one: 26 characters of Crockford's base 32
  /// (no I, L, O or U), the first 0 to 7.
  public static func isID(_ key: String) -> Bool {
    key.wholeMatch(of: /[0-7][0-9A-HJKMNP-TV-Z]{25}/) != nil
  }
}
