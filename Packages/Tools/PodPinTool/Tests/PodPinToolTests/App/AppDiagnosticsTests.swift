import Foundation
import XCTest

@testable import PodPinTool

final class AppDiagnosticsTests: XCTestCase {
    func testErrorClassificationUsesStableCodes() {
        XCTAssertEqual(PresentedError.from(URLError(.notConnectedToInternet)).code, .network)
        XCTAssertEqual(
            PresentedError.from(ContentImportError.toolUnavailable("yt-dlp")).code, .externalTool)
        XCTAssertEqual(
            PresentedError.from(
                ContentImportError.browserAccessRequired(
                    PlatformVerificationRequest(
                        source: .bilibili, url: URL(string: "https://www.bilibili.com")!)
                )
            ).code, .browserAuthorization)
    }

    func testRedactRemovesURLsAuthorizationSecretsUsernamesAndAbsolutePaths() {
        let redacted = AppDiagnostics.redact(
            "request https://example.com/media?token=url-secret "
                + "Bearer bearer-secret Authorization: Basic auth-secret "
                + "access_token=access-secret client_secret=client-secret "
                + "apiKey=api-secret user_name=alice "
                + "path=/Users/alice/My Private/audio.m4a"
        )

        for sensitiveValue in [
            "example.com", "url-secret", "bearer-secret", "auth-secret",
            "access-secret", "client-secret", "api-secret", "alice", "/Users/",
            "Private/audio.m4a",
        ] {
            XCTAssertFalse(redacted.contains(sensitiveValue), "Leaked: \(sensitiveValue)")
        }
        XCTAssertTrue(redacted.contains("[redacted-url]"))
        XCTAssertTrue(redacted.contains("[redacted-authorization]"))
        XCTAssertTrue(redacted.contains("[redacted-sensitive-value]"))
        XCTAssertTrue(redacted.contains("[redacted-path]"))
    }

}
