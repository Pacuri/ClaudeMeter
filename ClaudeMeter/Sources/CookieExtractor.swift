import Foundation
import SQLite3

/// Extracts claude.ai session cookies from browser storage.
/// Safari uses binary cookies, Chrome uses SQLite with encryption.
/// We support both, plus manual paste as fallback.
enum CookieExtractor {

    // MARK: - Public

    /// Attempt to extract sessionKey from available browsers
    /// Tries least-permission methods first, then falls back to file-based extraction
    static func extractSessionKey() async -> String? {
        // 1. Try Firefox first (unencrypted, no permissions needed)
        if let key = extractFromFirefox() {
            return key
        }

        // 2. Try Safari via AppleScript (needs Automation permission)
        if let key = extractFromSafariAppleScript() {
            return key
        }

        // 3. Try Safari binary cookies (needs Full Disk Access)
        if let key = extractFromSafari() {
            return key
        }

        // Note: Chrome is skipped — its cookies are encrypted and require
        // Keychain access which triggers scary system dialogs.

        return nil
    }

    // MARK: - Safari (AppleScript — lightweight permission)

    /// Uses AppleScript to ask Safari to run JavaScript on a claude.ai tab.
    /// Only requires Automation permission (one-time "Allow ClaudeMeter to control Safari?" prompt).
    /// Falls back to nil if sessionKey is httpOnly or no claude.ai tab is open.
    private static func extractFromSafariAppleScript() -> String? {
        let script = """
        tell application "System Events"
            if not (exists process "Safari") then return ""
        end tell

        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t contains "claude.ai" then
                        set cookieStr to do JavaScript "document.cookie" in t
                        repeat with pair in every text item of cookieStr
                        end repeat
                        return cookieStr
                    end if
                end repeat
            end repeat
        end tell
        return ""
        """

        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if error != nil { return nil }

        let cookieString = result.stringValue ?? ""
        // Parse "sessionKey=value" from cookie string
        for pair in cookieString.components(separatedBy: "; ") {
            let parts = pair.components(separatedBy: "=")
            if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespaces) == "sessionKey" {
                let value = parts.dropFirst().joined(separator: "=")
                if !value.isEmpty { return value }
            }
        }

        return nil
    }

    // MARK: - Safari

    /// Safari stores cookies in ~/Library/Cookies/Cookies.binarycookies
    /// This is Apple's binary cookie format — unencrypted but binary.
    private static func extractFromSafari() -> String? {
        let cookiePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Cookies/Cookies.binarycookies")

        guard FileManager.default.fileExists(atPath: cookiePath.path) else { return nil }

        // Copy to temp (Safari may lock it)
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudemeter_safari_cookies.binarycookies")
        try? FileManager.default.removeItem(at: tempPath)

        do {
            try FileManager.default.copyItem(at: cookiePath, to: tempPath)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tempPath) }

        guard let data = try? Data(contentsOf: tempPath) else { return nil }
        return parseBinaryCookies(data)
    }

    /// Parse Apple's binarycookies format
    /// Format: "cook" magic, page count, page sizes, then pages of cookies
    private static func parseBinaryCookies(_ data: Data) -> String? {
        guard data.count > 8 else { return nil }

        // Magic: "cook"
        let magic = String(data: data[0..<4], encoding: .ascii)
        guard magic == "cook" else { return nil }

        // Number of pages (big-endian UInt32)
        let numPages = data.readBigUInt32(at: 4)
        guard numPages > 0, numPages < 10000 else { return nil }

        // Page sizes array (each is big-endian UInt32)
        var pageSizes: [UInt32] = []
        for i in 0..<Int(numPages) {
            let size = data.readBigUInt32(at: 8 + i * 4)
            pageSizes.append(size)
        }

        // Pages start after header: 4 (magic) + 4 (count) + numPages*4 (sizes)
        var pageOffset = 8 + Int(numPages) * 4

        for pageSize in pageSizes {
            let pageEnd = pageOffset + Int(pageSize)
            guard pageEnd <= data.count else { break }

            if let key = parseCookiePage(data, offset: pageOffset, size: Int(pageSize)) {
                return key
            }
            pageOffset = pageEnd
        }

        return nil
    }

    /// Parse a single page of cookies
    private static func parseCookiePage(_ data: Data, offset: Int, size: Int) -> String? {
        guard size > 8 else { return nil }

        // Page header: 0x00000100 (little-endian)
        let numCookies = data.readLittleUInt32(at: offset + 4)
        guard numCookies > 0, numCookies < 10000 else { return nil }

        // Cookie offsets within the page
        var cookieOffsets: [UInt32] = []
        for i in 0..<Int(numCookies) {
            let co = data.readLittleUInt32(at: offset + 8 + i * 4)
            cookieOffsets.append(co)
        }

        for cookieOffset in cookieOffsets {
            let absOffset = offset + Int(cookieOffset)
            if let key = parseCookie(data, offset: absOffset) {
                return key
            }
        }

        return nil
    }

    /// Parse a single cookie record
    private static func parseCookie(_ data: Data, offset: Int) -> String? {
        guard offset + 44 <= data.count else { return nil }

        // Cookie record layout (all little-endian):
        // 0x00: size (4), 0x04: flags (4), 0x08: padding (4)
        // 0x0C: urlOffset (4), 0x10: nameOffset (4)
        // 0x14: pathOffset (4), 0x18: valueOffset (4)
        // 0x1C: comment (8), 0x24: padding2 (4)
        // 0x28: expirationDate (8), 0x30: creationDate (8)

        let urlOffset = Int(data.readLittleUInt32(at: offset + 0x0C))
        let nameOffset = Int(data.readLittleUInt32(at: offset + 0x10))
        let valueOffset = Int(data.readLittleUInt32(at: offset + 0x18))

        let url = data.readNullTerminatedString(at: offset + urlOffset)
        let name = data.readNullTerminatedString(at: offset + nameOffset)
        let value = data.readNullTerminatedString(at: offset + valueOffset)

        if let url = url, let name = name, let value = value,
           url.contains("claude.ai"), name == "sessionKey", !value.isEmpty {
            return value
        }

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

import CommonCrypto

// MARK: - Data Helpers for Binary Cookie Parsing

private extension Data {
    func readBigUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset..<offset+4).withUnsafeBytes {
            UInt32(bigEndian: $0.load(as: UInt32.self))
        }
    }

    func readLittleUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return subdata(in: offset..<offset+4).withUnsafeBytes {
            UInt32(littleEndian: $0.load(as: UInt32.self))
        }
    }

    func readNullTerminatedString(at offset: Int) -> String? {
        guard offset >= 0, offset < count else { return nil }
        var end = offset
        while end < count && self[end] != 0 { end += 1 }
        guard end > offset else { return nil }
        return String(data: subdata(in: offset..<end), encoding: .utf8)
    }
}
