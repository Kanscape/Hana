import Foundation
import Security

enum HanaCredentialStoreError: Error, Equatable {
  case unexpectedStatus(OSStatus)
  case invalidResult
}

protocol HanaCredentialStore {
  func data(for account: String) throws -> Data?
  func set(_ data: Data, for account: String) throws
  func removeData(for account: String) throws
}

struct HanaKeychainCredentialStore: HanaCredentialStore {
  static let defaultService = "sh.celia.hana.site-session.cookies"

  let service: String

  init(service: String = Self.defaultService) {
    self.service = service
  }

  func data(for account: String) throws -> Data? {
    var query = baseQuery(for: account)
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw HanaCredentialStoreError.unexpectedStatus(status)
    }
    guard let data = result as? Data else {
      throw HanaCredentialStoreError.invalidResult
    }
    return data
  }

  func set(_ data: Data, for account: String) throws {
    var attributes = baseQuery(for: account)
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemAdd(attributes as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updates = [kSecValueData as String: data]
      let updateStatus = SecItemUpdate(
        baseQuery(for: account) as CFDictionary,
        updates as CFDictionary
      )
      guard updateStatus == errSecSuccess else {
        throw HanaCredentialStoreError.unexpectedStatus(updateStatus)
      }
      return
    }
    guard status == errSecSuccess else {
      throw HanaCredentialStoreError.unexpectedStatus(status)
    }
  }

  func removeData(for account: String) throws {
    let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw HanaCredentialStoreError.unexpectedStatus(status)
    }
  }

  private func baseQuery(for account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }
}

final class HanaSessionCookieStore {
  static let legacyCookieHeaderKey = "Hana.SiteWebSession.cookieHeader"

  private let credentialStore: any HanaCredentialStore
  private let defaults: UserDefaults

  init(
    credentialStore: any HanaCredentialStore = HanaKeychainCredentialStore(),
    defaults: UserDefaults = .standard
  ) {
    self.credentialStore = credentialStore
    self.defaults = defaults
  }

  func cookieHeader(for baseURL: URL) -> String? {
    guard let account = Self.account(for: baseURL) else { return nil }

    if defaults.bool(forKey: Self.tombstoneKey(for: baseURL)) {
      do {
        try credentialStore.removeData(for: account)
        defaults.removeObject(forKey: Self.tombstoneKey(for: baseURL))
      } catch {
        return nil
      }
    }

    if let fallback = scopedFallbackCookieHeader(for: baseURL) {
      migrateFallback(fallback, account: account, baseURL: baseURL)
      return fallback
    }

    do {
      if let data = try credentialStore.data(for: account) {
        if let header = String(data: data, encoding: .utf8), !header.isEmpty {
          removeFallbackValues(for: baseURL)
          return header
        }
        try? credentialStore.removeData(for: account)
      }
    } catch {
      // Keychain read failures use the local fallback below.
    }

    guard let fallback = legacyFallbackCookieHeader(for: baseURL) else { return nil }
    migrateFallback(fallback, account: account, baseURL: baseURL)
    return fallback
  }

  func saveCookieHeader(_ header: String, for baseURL: URL) {
    guard !header.isEmpty, let account = Self.account(for: baseURL) else {
      removeCookieHeader(for: baseURL)
      return
    }

    do {
      try credentialStore.set(Data(header.utf8), for: account)
      removeFallbackValues(for: baseURL)
      defaults.removeObject(forKey: Self.tombstoneKey(for: baseURL))
    } catch {
      defaults.set(header, forKey: Self.fallbackKey(for: baseURL))
      removeLegacyFallbackValue(for: baseURL)
      defaults.removeObject(forKey: Self.tombstoneKey(for: baseURL))
    }
  }

  func removeCookieHeader(for baseURL: URL) {
    removeFallbackValues(for: baseURL)
    guard let account = Self.account(for: baseURL) else { return }

    do {
      try credentialStore.removeData(for: account)
      defaults.removeObject(forKey: Self.tombstoneKey(for: baseURL))
    } catch {
      defaults.set(true, forKey: Self.tombstoneKey(for: baseURL))
    }
  }

  static func account(for baseURL: URL) -> String? {
    baseURL.host()?.lowercased()
  }

  static func fallbackKey(for baseURL: URL) -> String {
    scopedKey("cookieHeader", suffix: keySuffix(for: baseURL))
  }

  static func tombstoneKey(for baseURL: URL) -> String {
    scopedKey("cookieHeaderInvalidated", suffix: keySuffix(for: baseURL))
  }

  private func scopedFallbackCookieHeader(for baseURL: URL) -> String? {
    guard let fallback = defaults.string(forKey: Self.fallbackKey(for: baseURL)),
      !fallback.isEmpty
    else {
      return nil
    }
    return fallback
  }

  private func legacyFallbackCookieHeader(for baseURL: URL) -> String? {
    if Self.canReadLegacyValue(for: baseURL),
      let legacy = defaults.string(forKey: Self.legacyCookieHeaderKey),
      !legacy.isEmpty
    {
      return legacy
    }
    return nil
  }

  private func migrateFallback(_ fallback: String, account: String, baseURL: URL) {
    do {
      try credentialStore.set(Data(fallback.utf8), for: account)
      removeFallbackValues(for: baseURL)
    } catch {
      // Retain the fallback and retry migration on a later read.
    }
  }

  private func removeFallbackValues(for baseURL: URL) {
    defaults.removeObject(forKey: Self.fallbackKey(for: baseURL))
    removeLegacyFallbackValue(for: baseURL)
  }

  private func removeLegacyFallbackValue(for baseURL: URL) {
    if Self.canReadLegacyValue(for: baseURL) {
      defaults.removeObject(forKey: Self.legacyCookieHeaderKey)
    }
  }

  private static func canReadLegacyValue(for baseURL: URL) -> Bool {
    account(for: baseURL) == URL(string: HanaSiteBaseURL.defaultValue)?.host()?.lowercased()
  }

  private static func keySuffix(for baseURL: URL) -> String {
    account(for: baseURL)?.replacingOccurrences(of: ".", with: "_") ?? "default"
  }

  private static func scopedKey(_ name: String, suffix: String) -> String {
    "Hana.SiteWebSession.\(suffix).\(name)"
  }
}
