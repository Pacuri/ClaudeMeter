import Foundation
import Security

/// Extracts OAuth tokens from Claude CLI (Claude Code) credentials.
/// Claude Code stores OAuth tokens in either:
/// 1. macOS Keychain under "Claude Code-credentials"
/// 2. ~/.claude/.credentials.json
enum OAuthExtractor {

    struct OAuthCredentials {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    // MARK: - Public

    /// Try to extract OAuth credentials from Claude CLI
    static func extractCredentials() -> OAuthCredentials? {
        // 1. Try Keychain first (preferred, more secure)
        if let creds = extractFromKeychain() {
            return creds
        }

        // 2. Fall back to credentials file
        if let creds = extractFromCredentialsFile() {
            return creds
        }

        return nil
    }

    // MARK: - Keychain

    private static func extractFromKeychain() -> OAuthCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }

        return parseCredentialsJSON(data)
    }

    // MARK: - Credentials File

    private static func extractFromCredentialsFile() -> OAuthCredentials? {
        let credPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")

        guard let data = try? Data(contentsOf: credPath) else { return nil }

        return parseCredentialsJSON(data)
    }

    // MARK: - Parsing

    private static func parseCredentialsJSON(_ data: Data) -> OAuthCredentials? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Try direct token fields
        if let accessToken = json["accessToken"] as? String, !accessToken.isEmpty {
            let refreshToken = json["refreshToken"] as? String
            let expiresAt = (json["expiresAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0 / 1000) }
            return OAuthCredentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
        }

        // Try nested "claude.ai" or "default" key
        for key in ["claude.ai", "default"] {
            if let nested = json[key] as? [String: Any],
               let accessToken = nested["accessToken"] as? String, !accessToken.isEmpty {
                let refreshToken = nested["refreshToken"] as? String
                let expiresAt = (nested["expiresAt"] as? TimeInterval).map { Date(timeIntervalSince1970: $0 / 1000) }
                return OAuthCredentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
            }
        }

        // Try oauth_token field (some versions use this)
        if let token = json["oauth_token"] as? String, !token.isEmpty {
            return OAuthCredentials(accessToken: token, refreshToken: nil, expiresAt: nil)
        }

        return nil
    }
}
