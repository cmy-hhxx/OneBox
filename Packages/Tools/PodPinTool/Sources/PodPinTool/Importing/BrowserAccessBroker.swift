import CommonCrypto
import Foundation
import SQLite3
import Security

enum ChromiumBrowser: String, CaseIterable, Sendable {
    case chrome
    case edge
    case chromium

    var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .edge: "Microsoft Edge"
        case .chromium: "Chromium"
        }
    }

    fileprivate var applicationSupportPath: String {
        switch self {
        case .chrome: "Google/Chrome"
        case .edge: "Microsoft Edge"
        case .chromium: "Chromium"
        }
    }

    fileprivate var keychainService: String {
        switch self {
        case .chrome: "Chrome Safe Storage"
        case .edge: "Microsoft Edge Safe Storage"
        case .chromium: "Chromium Safe Storage"
        }
    }

    fileprivate var keychainAccount: String {
        switch self {
        case .chrome: "Chrome"
        case .edge: "Microsoft Edge"
        case .chromium: "Chromium"
        }
    }
}

struct BrowserProfile: Identifiable, Equatable, Sendable {
    let browser: ChromiumBrowser
    let directoryName: String
    let displayName: String
    let userDataURL: URL

    var id: String { "\(browser.rawValue):\(directoryName)" }
    var browserName: String { browser.displayName }
}

protocol BrowserAccessAuthorizing: Sendable {
    func profiles() async -> [BrowserProfile]
    func authorize(
        profile: BrowserProfile,
        request: PlatformVerificationRequest,
        contentIDs: Set<String>
    ) async throws -> BrowserAccessLease
    func revoke(_ lease: BrowserAccessLease) async
}

enum BrowserAccessError: LocalizedError, Equatable, Sendable {
    case unsupportedSource
    case invalidProfile
    case keychainDenied
    case cookiesUnavailable
    case cookieDatabaseUnavailable

    var errorDescription: String? {
        switch self {
        case .unsupportedSource: "该来源不支持借用浏览器访客状态。"
        case .invalidProfile: "浏览器 Profile 已失效，请重新选择。"
        case .keychainDenied: "无法取得浏览器安全存储授权；未读取任何 Cookie。"
        case .cookiesUnavailable: "所选 Profile 没有可用的访客/风控 Cookie。"
        case .cookieDatabaseUnavailable: "无法以只读方式打开所选浏览器的 Cookie 数据库。"
        }
    }
}

actor BrowserAccessBroker: BrowserAccessAuthorizing {
    private let applicationSupportURL: URL?
    private let fileManagerReference: PodPinFileManagerReference?

    init() {
        applicationSupportURL = nil
        fileManagerReference = nil
    }

    init(
        reference: PodPinFileManagerReference,
        applicationSupportURL: URL? = nil
    ) {
        self.fileManagerReference = reference
        self.applicationSupportURL =
            applicationSupportURL
            ?? reference.value.homeDirectoryForCurrentUser.appending(
                path: "Library/Application Support",
                directoryHint: .isDirectory
            )
    }

    func profiles() -> [BrowserProfile] {
        guard fileManagerReference != nil, applicationSupportURL != nil else { return [] }
        return ChromiumBrowser.allCases.flatMap(discoverProfiles).sorted {
            ($0.browser.rawValue, $0.displayName, $0.directoryName)
                < ($1.browser.rawValue, $1.displayName, $1.directoryName)
        }
    }

    func authorize(
        profile: BrowserProfile,
        request: PlatformVerificationRequest,
        contentIDs: Set<String>
    ) throws -> BrowserAccessLease {
        guard request.source == .douyin || request.source == .bilibili else {
            throw BrowserAccessError.unsupportedSource
        }
        guard let applicationSupportURL else {
            throw BrowserAccessError.invalidProfile
        }
        let expectedRoot = applicationSupportURL.appending(
            path: profile.browser.applicationSupportPath,
            directoryHint: .isDirectory
        ).standardizedFileURL
        guard profile.userDataURL.standardizedFileURL == expectedRoot,
            Self.isSafeProfileDirectory(profile.directoryName)
        else { throw BrowserAccessError.invalidProfile }

        let password = try keychainPassword(for: profile.browser)
        let policy = BrowserCookiePolicy(source: request.source)
        let cookiesURL =
            expectedRoot
            .appending(path: profile.directoryName, directoryHint: .isDirectory)
            .appending(path: "Network/Cookies", directoryHint: .notDirectory)
        let cookies = try readCookies(
            at: cookiesURL,
            password: password,
            policy: policy
        )
        guard !cookies.isEmpty else { throw BrowserAccessError.cookiesUnavailable }
        return BrowserAccessLease(
            source: request.source,
            sourceURL: request.url,
            contentIDs: contentIDs,
            expiresAt: Date().addingTimeInterval(10 * 60),
            cookies: cookies
        )
    }

    func revoke(_ lease: BrowserAccessLease) {
        lease.revoke()
    }

    private func discoverProfiles(browser: ChromiumBrowser) -> [BrowserProfile] {
        guard let applicationSupportURL, let fileManager = fileManagerReference?.value else {
            return []
        }
        let root = applicationSupportURL.appending(
            path: browser.applicationSupportPath,
            directoryHint: .isDirectory
        )
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let localStateURL = root.appending(path: "Local State")
        let infoCache: [String: Any]
        if let data = try? Data(contentsOf: localStateURL),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = json["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: Any]
        {
            infoCache = cache
        } else {
            infoCache = [:]
        }

        var directories = Set(infoCache.keys.filter(Self.isSafeProfileDirectory))
        if fileManager.fileExists(atPath: root.appending(path: "Default").path) {
            directories.insert("Default")
        }
        return directories.compactMap { directory in
            let cookiePath = root.appending(path: directory).appending(path: "Network/Cookies")
            guard fileManager.fileExists(atPath: cookiePath.path) else { return nil }
            let details = infoCache[directory] as? [String: Any]
            let name = (details?["name"] as? String)?.trimmingCharacters(
                in: .whitespacesAndNewlines)
            return BrowserProfile(
                browser: browser,
                directoryName: directory,
                displayName: name?.isEmpty == false ? name! : directory,
                userDataURL: root
            )
        }
    }

    private func keychainPassword(for browser: ChromiumBrowser) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: browser.keychainService,
            kSecAttrAccount as String: browser.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw BrowserAccessError.keychainDenied
        }
        return data
    }

    private func readCookies(
        at databaseURL: URL,
        password: Data,
        policy: BrowserCookiePolicy
    ) throws -> [HTTPCookie] {
        var database: OpaquePointer?
        guard
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                nil
            ) == SQLITE_OK, let database
        else {
            if let database { sqlite3_close(database) }
            throw BrowserAccessError.cookieDatabaseUnavailable
        }
        defer { sqlite3_close(database) }

        let domainPredicates = policy.domainSuffixes.map { _ in "(host_key = ? OR host_key LIKE ?)"
        }
        let namePlaceholders = policy.allowedNames.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT host_key, name, path, value, encrypted_value, expires_utc, is_secure
            FROM cookies
            WHERE (\(domainPredicates.joined(separator: " OR ")))
              AND name IN (\(namePlaceholders))
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
            let statement
        else { throw BrowserAccessError.cookieDatabaseUnavailable }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var index: Int32 = 1
        for suffix in policy.domainSuffixes {
            sqlite3_bind_text(statement, index, suffix, -1, transient)
            index += 1
            sqlite3_bind_text(statement, index, "%\(suffix)", -1, transient)
            index += 1
        }
        for name in policy.allowedNames.sorted() {
            sqlite3_bind_text(statement, index, name, -1, transient)
            index += 1
        }

        var cookies: [HTTPCookie] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let domain = Self.string(statement, column: 0),
                let name = Self.string(statement, column: 1),
                policy.accepts(name: name, domain: domain)
            else { continue }
            let path = Self.string(statement, column: 2) ?? "/"
            let plainValue = Self.string(statement, column: 3)
            let encrypted = Self.data(statement, column: 4)
            let value =
                plainValue?.isEmpty == false
                ? plainValue
                : encrypted.flatMap { decrypt($0, password: password) }
            guard let value, !value.isEmpty else { continue }

            let expires = Self.chromeDate(sqlite3_column_int64(statement, 5))
            if let expires, expires <= Date() { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [
                .domain: domain,
                .path: path,
                .name: name,
                .value: value,
                .secure: sqlite3_column_int(statement, 6) != 0 ? "TRUE" : "FALSE",
            ]
            properties[.expires] = expires
            if let cookie = HTTPCookie(properties: properties) {
                cookies.append(cookie)
            }
        }
        return cookies
    }

    private func decrypt(_ encrypted: Data, password: Data) -> String? {
        guard encrypted.count > 3,
            encrypted.starts(with: Data("v10".utf8)) || encrypted.starts(with: Data("v11".utf8))
        else { return nil }
        var key = Data(count: kCCKeySizeAES128)
        let derivation = key.withUnsafeMutableBytes { keyBuffer in
            password.withUnsafeBytes { passwordBuffer in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBuffer.bindMemory(to: Int8.self).baseAddress,
                    password.count,
                    "saltysalt",
                    9,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    1003,
                    keyBuffer.bindMemory(to: UInt8.self).baseAddress,
                    kCCKeySizeAES128
                )
            }
        }
        guard derivation == kCCSuccess else { return nil }

        let cipher = encrypted.dropFirst(3)
        var output = Data(count: cipher.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBuffer in
            key.withUnsafeBytes { keyBuffer in
                cipher.withUnsafeBytes { cipherBuffer in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionPKCS7Padding),
                        keyBuffer.baseAddress,
                        kCCKeySizeAES128,
                        Array(repeating: UInt8(0x20), count: kCCBlockSizeAES128),
                        cipherBuffer.baseAddress,
                        cipher.count,
                        outputBuffer.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.removeSubrange(outputLength..<output.count)
        if let value = String(data: output, encoding: .utf8) { return value }
        guard output.count > 32 else { return nil }
        return String(data: output.dropFirst(32), encoding: .utf8)
    }

    private static func string(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private static func data(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }

    private static func chromeDate(_ microseconds: Int64) -> Date? {
        guard microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(microseconds) / 1_000_000 - 11_644_473_600)
    }

    private static func isSafeProfileDirectory(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
            && !value.contains(":")
    }
}

struct BrowserCookiePolicy: Sendable {
    let domainSuffixes: [String]
    let allowedNames: Set<String>

    init(source: SupportedSource) {
        switch source {
        case .douyin:
            domainSuffixes = ["douyin.com", "iesdouyin.com"]
            allowedNames = ["ttwid", "s_v_web_id", "msToken"]
        case .bilibili:
            domainSuffixes = ["bilibili.com", "b23.tv"]
            allowedNames = ["buvid3", "buvid4", "b_nut", "buvid_fp", "b_lsid"]
        case .fireside, .xiaoyuzhou:
            domainSuffixes = []
            allowedNames = []
        }
    }

    func accepts(name: String, domain: String) -> Bool {
        guard allowedNames.contains(name) else { return false }
        let normalized = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domainSuffixes.contains { normalized == $0 || normalized.hasSuffix(".\($0)") }
    }
}
