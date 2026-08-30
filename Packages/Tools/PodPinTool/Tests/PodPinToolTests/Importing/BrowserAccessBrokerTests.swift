import Foundation
import XCTest

@testable import PodPinTool

private final class RecordingFileManager: FileManager, @unchecked Sendable {
    private(set) var checkedPaths: [String] = []

    override func fileExists(atPath path: String) -> Bool {
        checkedPaths.append(path)
        return super.fileExists(atPath: path)
    }
}

final class BrowserAccessBrokerTests: XCTestCase {
    func testBrokerWithoutPlatformFileManagerDoesNotDiscoverProfiles() async {
        let profiles = await BrowserAccessBroker().profiles()

        XCTAssertTrue(profiles.isEmpty)
    }

    func testCookiePoliciesExcludeAuthenticationCookies() {
        let douyin = BrowserCookiePolicy(source: .douyin)
        XCTAssertTrue(douyin.accepts(name: "ttwid", domain: ".douyin.com"))
        XCTAssertFalse(douyin.accepts(name: "sessionid", domain: ".douyin.com"))
        XCTAssertFalse(douyin.accepts(name: "passport_auth_status", domain: ".douyin.com"))

        let bilibili = BrowserCookiePolicy(source: .bilibili)
        XCTAssertTrue(bilibili.accepts(name: "buvid3", domain: ".bilibili.com"))
        XCTAssertFalse(bilibili.accepts(name: "SESSDATA", domain: ".bilibili.com"))
        XCTAssertFalse(bilibili.accepts(name: "DedeUserID", domain: ".bilibili.com"))
    }

    func testLeaseRejectsWrongOperationAndReuse() throws {
        let url = URL(string: "https://www.douyin.com/video/123")!
        let lease = BrowserAccessLease(
            source: .douyin,
            sourceURL: url,
            contentIDs: ["123"],
            expiresAt: Date().addingTimeInterval(60),
            cookies: []
        )

        XCTAssertFalse(lease.consume(source: .douyin, url: url, contentID: "456"))
        XCTAssertTrue(lease.consume(source: .douyin, url: url, contentID: "123"))
        XCTAssertFalse(lease.consume(source: .douyin, url: url, contentID: "123"))
    }

    func testProfileDiscoveryOnlyIncludesSupportedChromiumFamilies() async throws {
        let fileManager = RecordingFileManager()
        let root = fileManager.temporaryDirectory
            .appending(
                path: "BrowserAccessBrokerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: root) }
        for relativePath in [
            "Google/Chrome/Default/Network",
            "Microsoft Edge/Profile 1/Network",
            "BraveSoftware/Brave-Browser/Default/Network",
        ] {
            try fileManager.createDirectory(
                at: root.appending(path: relativePath, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
            try Data().write(to: root.appending(path: relativePath).appending(path: "Cookies"))
        }
        let edgeState = #"{"profile":{"info_cache":{"Profile 1":{"name":"Work"}}}}"#
        try Data(edgeState.utf8).write(to: root.appending(path: "Microsoft Edge/Local State"))

        let profiles = await BrowserAccessBroker(
            reference: PodPinFileManagerReference(fileManager),
            applicationSupportURL: root
        ).profiles()

        XCTAssertEqual(Set(profiles.map(\.browser)), [.chrome, .edge])
        XCTAssertFalse(fileManager.checkedPaths.isEmpty)
        XCTAssertEqual(profiles.first(where: { $0.browser == .edge })?.displayName, "Work")
    }
}
