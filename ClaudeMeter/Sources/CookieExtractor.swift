import Foundation
import SQLite3

/// Extracts claude.ai session cookies from browser storage.
/// Safari uses binary cookies, Chrome uses SQLite with encryption.
/// We support both, plus manual paste as fallback.
enum CookieExtractor {

    // MARK: - Public

    /// Attempt to extract sessionKey from available browsers
    static func extractSessionKey() async -> String? {
        // 1. Try Chrome first (most common for claude.ai)
        if let key = extractFromChrome() {
            return key
        }

        // 2. Try Firefox
        if let key = extractFromFirefox() {
            return key
        }

        // 3. Safari binary cookies are sandboxed and harder to read
        //    User can paste manually via Settings

        return nil
    }

    // MARK: - Chrome

    /// Chrome stores cookies in an SQLite DB.
    /// On macOS, the cookie values are encrypted with the Keychain "Chrome Safe Storage" key.
    /// For simplicity, we read the encrypted value and decrypt with the system keychain.
    private static func extractFromChrome() -> String? {
        let cookiePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Default/Cookies")

        guard FileManager.default.fileExists(atPath: cookiePath.path) else { return nil }

        // Copy the DB to a temp location (Chrome locks it)
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudemeter_chrome_cookies.db")
        try? FileManager.default.removeItem(at: tempPath)

        do {
            try FileManager.default.copyItem(at: cookiePath, to: tempPath)
        } catch {
            print("Could not copy Chrome cookies DB: \(error)")
            return nil
        }

        defer { try? FileManager.default.removeItem(at: tempPath) }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(db) }

        let query = """
            SELECT encrypted_value, value FROM cookies
            WHERE host_key LIKE '%claude.ai%' AND name = 'sessionKey'
            LIMIT 1
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            // Try plaintext value first
            if let plaintext = sqlite3_column_text(stmt, 1) {
                let value = String(cString: plaintext)
                if !value.isEmpty { return value }
            }

            // Encrypted value needs Chrome Safe Storage key from Keychain
            if let blobPointer = sqlite3_column_blob(stmt, 0) {
                let blobSize = sqlite3_column_bytes(stmt, 0)
                let data = Data(bytes: blobPointer, count: Int(blobSize))
                return decryptChromeValue(data)
            }
        }

        return nil
    }

    /// Decrypt Chrome cookie value using the "Chrome Safe Storage" keychain entry
    private static func decryptChromeValue(_ encryptedData: Data) -> String? {
        // Chrome encrypted cookies on macOS:
        // - Prefix "v10" means encrypted with PBKDF2 derived key
        // - Key source: "Chrome Safe Storage" in Keychain
        // - PBKDF2: 1003 iterations, salt = "saltysalt", keylen = 16
        // - AES-128-CBC with IV = 16 bytes of space (0x20)

        guard encryptedData.count > 3 else { return nil }

        let prefix = String(data: encryptedData[0..<3], encoding: .utf8)
        guard prefix == "v10" else { return nil }

        // Get the password from Keychain
        guard let password = getChromeSafeStoragePassword() else { return nil }

        let ciphertext = encryptedData[3...]
        let salt = "saltysalt".data(using: .utf8)!
        let iv = Data(repeating: 0x20, count: 16)

        // PBKDF2 key derivation
        guard let key = pbkdf2(password: password, salt: salt, iterations: 1003, keyLength: 16) else {
            return nil
        }

        // AES-128-CBC decrypt
        return aesDecrypt(data: Data(ciphertext), key: key, iv: iv)
    }

    private static func getChromeSafeStoragePassword() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Chrome Safe Storage",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Firefox

    private static func extractFromFirefox() -> String? {
        let profilesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")

        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: profilesPath, includingPropertiesForKeys: nil
        ) else { return nil }

        for profileDir in profiles {
            let cookiePath = profileDir.appendingPathComponent("cookies.sqlite")
            guard FileManager.default.fileExists(atPath: cookiePath.path) else { continue }

            let tempPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("claudemeter_ff_cookies.db")
            try? FileManager.default.removeItem(at: tempPath)
            try? FileManager.default.copyItem(at: cookiePath, to: tempPath)
            defer { try? FileManager.default.removeItem(at: tempPath) }

            var db: OpaquePointer?
            guard sqlite3_open_v2(tempPath.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                continue
            }
            defer { sqlite3_close(db) }

            let query = """
                SELECT value FROM moz_cookies
                WHERE host LIKE '%claude.ai%' AND name = 'sessionKey'
                LIMIT 1
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }

            if sqlite3_step(stmt) == SQLITE_ROW,
               let value = sqlite3_column_text(stmt, 0) {
                return String(cString: value)
            }
        }

        return nil
    }

    // MARK: - Crypto Helpers (using CommonCrypto via C bridge)

    private static func pbkdf2(password: String, salt: Data, iterations: Int, keyLength: Int) -> Data? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        var derivedKey = Data(count: keyLength)

        let result = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passwordData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }

        return result == kCCSuccess ? derivedKey : nil
    }

    private static func aesDecrypt(data: Data, key: Data, iv: Data) -> String? {
        let outBufferSize = data.count + kCCBlockSizeAES128
        var outData = Data(count: outBufferSize)
        var outLength = 0

        let result = outData.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress, data.count,
                            outBytes.baseAddress, outBufferSize,
                            &outLength
                        )
                    }
                }
            }
        }

        guard result == kCCSuccess else { return nil }
        return String(data: outData[0..<outLength], encoding: .utf8)
    }
}

// MARK: - CommonCrypto C imports (add via bridging header or modulemap)
// These are the function signatures we need. In the actual project,
// import CommonCrypto via the bridging header.

import CommonCrypto
