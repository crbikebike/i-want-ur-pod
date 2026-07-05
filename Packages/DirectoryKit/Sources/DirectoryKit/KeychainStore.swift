// PodcastIndex credential store. Source model: docs/design/direction.md §12.2
// (PodcastIndex opt-in; inactive until the user supplies their own API key +
// secret). The UI only shows connection state, e.g. "key ending ••3F".
import Foundation
import Security

/// A `kSecClassGenericPassword` wrapper that persists the PodcastIndex
/// `apiKey` / `apiSecret` pair in the system Keychain.
///
/// PodcastIndex is the opt-in source of §12.2: it stays inactive until the
/// user supplies their own credentials. This store owns the save / load /
/// delete of those credentials and exposes only non-secret connection state
/// (``hasCredentials`` and ``redactedDisplay``) for the Settings UI.
///
/// The type is a value type over a Keychain service string, so it is
/// `Sendable` and cheap to copy; all state lives in the Keychain itself.
public struct KeychainStore: Sendable {

    /// A PodcastIndex credential pair.
    public struct Credentials: Sendable, Hashable {

        /// The PodcastIndex API key.
        public let apiKey: String

        /// The PodcastIndex API secret.
        public let apiSecret: String

        public init(apiKey: String, apiSecret: String) {
            self.apiKey = apiKey
            self.apiSecret = apiSecret
        }
    }

    /// Errors surfaced by Keychain operations.
    public enum KeychainError: Error, Sendable, Equatable {
        /// A credential value was empty and cannot be stored.
        case emptyValue
        /// The Keychain returned an unexpected `OSStatus`.
        case unhandled(OSStatus)
    }

    /// The Keychain service under which both items are grouped.
    private let service: String

    /// Keychain account key for the API key item.
    private let keyAccount = "podcastIndex.apiKey"

    /// Keychain account key for the API secret item.
    private let secretAccount = "podcastIndex.apiSecret"

    /// - Parameter service: The `kSecAttrService` namespace for the stored
    ///   items. Defaults to the app's PodcastIndex bundle namespace.
    public init(service: String = "pod.iwanturpod.podcastindex") {
        self.service = service
    }

    // MARK: - Save

    /// Persists the PodcastIndex `apiKey` and `apiSecret`, replacing any
    /// existing values.
    ///
    /// - Throws: ``KeychainError/emptyValue`` if either value is blank, or
    ///   ``KeychainError/unhandled(_:)`` on a Keychain failure.
    public func save(apiKey: String, apiSecret: String) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = apiSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !secret.isEmpty else { throw KeychainError.emptyValue }

        try set(key, account: keyAccount)
        try set(secret, account: secretAccount)
    }

    /// Persists a ``Credentials`` pair, replacing any existing values.
    public func save(_ credentials: Credentials) throws {
        try save(apiKey: credentials.apiKey, apiSecret: credentials.apiSecret)
    }

    // MARK: - Load

    /// The stored API key, or `nil` if none is saved.
    public var apiKey: String? { get(account: keyAccount) }

    /// The stored API secret, or `nil` if none is saved.
    public var apiSecret: String? { get(account: secretAccount) }

    /// Loads the complete ``Credentials`` pair.
    ///
    /// - Returns: The pair, or `nil` unless *both* the key and secret are
    ///   present (a half-written pair is treated as unconfigured).
    public func loadCredentials() -> Credentials? {
        guard let key = apiKey, let secret = apiSecret else { return nil }
        return Credentials(apiKey: key, apiSecret: secret)
    }

    // MARK: - Delete

    /// Removes both the stored API key and secret.
    ///
    /// Succeeds even if nothing was stored.
    ///
    /// - Throws: ``KeychainError/unhandled(_:)`` on a Keychain failure.
    public func deleteCredentials() throws {
        try remove(account: keyAccount)
        try remove(account: secretAccount)
    }

    // MARK: - Connection state (non-secret)

    /// Whether a complete credential pair is stored.
    ///
    /// Drives whether the Settings row shows the lock badge / "Add API key"
    /// affordance (§12.2) or an enable toggle.
    public var hasCredentials: Bool {
        apiKey != nil && apiSecret != nil
    }

    /// A redacted, display-safe hint for the stored key, e.g. `"key ending ••3F"`.
    ///
    /// Returns `nil` when no key is stored. Only the last two characters of the
    /// key are ever revealed; the secret is never surfaced.
    public var redactedDisplay: String? {
        guard let key = apiKey, !key.isEmpty else { return nil }
        let suffix = String(key.suffix(2))
        return "key ending ••\(suffix)"
    }

    // MARK: - Keychain primitives

    /// Base query identifying a single generic-password item.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Stores or replaces `value` for `account`.
    private func set(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandled(addStatus)
            }
        default:
            throw KeychainError.unhandled(updateStatus)
        }
    }

    /// Reads the stored string for `account`, or `nil` if absent / unreadable.
    private func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    /// Deletes the item for `account`; a missing item is not an error.
    private func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }
}

// MARK: - PodcastIndex credential provider

/// Bridges the stored key / secret pair to the ``PodcastIndexCredentialProviding``
/// abstraction consumed by ``PodcastIndexSource``, so the source can read the
/// same Keychain items the Settings UI writes.
extension KeychainStore: PodcastIndexCredentialProviding {

    /// The stored PodcastIndex credentials, or `nil` when none are configured.
    public func podcastIndexCredentials() -> PodcastIndexCredentials? {
        guard let credentials = loadCredentials() else { return nil }
        return PodcastIndexCredentials(
            key: credentials.apiKey,
            secret: credentials.apiSecret
        )
    }
}
