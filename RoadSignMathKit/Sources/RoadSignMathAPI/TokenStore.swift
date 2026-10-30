import Foundation
import Security
import Synchronization

/// Where the app keeps its sign-in token between launches.
public protocol TokenStore: Sendable {
  func read() throws -> String?
  func save(_ token: String) throws
  func clear() throws
}

/// The token in the Keychain, as a generic password: on this device only,
/// readable once the phone has been unlocked after a restart (so a refresh
/// in the background can still use it), and never in a backup.
///
/// `account` tells servers apart, so a token for `npm run dev` is never
/// sent to the live server or the other way round.
public struct KeychainTokenStore: TokenStore {
  public var service: String
  public var account: String

  public init(service: String = "xyz.roadsignmath.app.token", account: String) {
    self.service = service
    self.account = account
  }

  /// One token per server, named by its address.
  public init(server: URL) {
    self.init(account: server.absoluteString)
  }

  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }

  public func read() throws -> String? {
    var ask = query
    ask[kSecReturnData as String] = true
    ask[kSecMatchLimit as String] = kSecMatchLimitOne
    var found: CFTypeRef?
    let status = SecItemCopyMatching(ask as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    return (found as? Data).flatMap { String(data: $0, encoding: .utf8) }
  }

  public func save(_ token: String) throws {
    let data = Data(token.utf8)
    let update: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(update) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  public func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
  }
}

public struct KeychainError: Error, Sendable, Hashable, CustomStringConvertible {
  public var status: OSStatus
  public var description: String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
  }
}

/// A token kept in memory only: for tests and previews.
public final class MemoryTokenStore: TokenStore {
  private let token: Mutex<String?>

  public init(_ token: String? = nil) {
    self.token = Mutex(token)
  }

  public func read() throws -> String? { token.withLock { $0 } }
  public func save(_ token: String) throws { self.token.withLock { $0 = token } }
  public func clear() throws { token.withLock { $0 = nil } }
}
