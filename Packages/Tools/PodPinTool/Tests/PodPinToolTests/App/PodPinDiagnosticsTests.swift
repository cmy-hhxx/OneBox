import Foundation
import OneBoxRuntime
import XCTest
import os

@testable import PodPinTool

@MainActor
final class PodPinDiagnosticsTests: XCTestCase {
    func testStartupReportsOriginalDatabaseErrorExactlyOnce() async throws {
        let events = OSAllocatedUnfairLock<[OneBoxRuntime.DiagnosticEvent]>(initialState: [])
        let defaults = UserDefaults(suiteName: "PodPinDiagnosticsTests-\(UUID())")!
        let store = PodPinStore(
            preferences: AppPreferences(defaults: defaults),
            databaseFactory: {
                throw NSError(
                    domain: "SQLiteFixture", code: 26,
                    userInfo: [
                        NSLocalizedDescriptionKey: "file is not a database"
                    ])
            },
            diagnostics: ToolDiagnostics { event in events.withLock { $0.append(event) } }
        )

        await store.start()

        let recorded = events.withLock { $0 }
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.operation, "library.open")
        XCTAssertTrue(recorded.first?.message.contains("SQLiteFixture (26)") == true)
        XCTAssertTrue(recorded.first?.message.contains("file is not a database") == true)
        await store.shutdown()
    }

    func testImportReportsOriginalTransportFailureBeforePresentation() async throws {
        let events = OSAllocatedUnfairLock<[OneBoxRuntime.DiagnosticEvent]>(initialState: [])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiagnosticFailureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let importer = PodPinContentImporter(sourceAdapters: [
            BilibiliContentAdapter(transport: URLSessionHTTPTransport(session: session))
        ])
        let store = PodPinStore(
            preferences: AppPreferences(
                defaults: UserDefaults(suiteName: "PodPinDiagnosticsTests-\(UUID())")!),
            importer: importer,
            diagnostics: ToolDiagnostics { event in events.withLock { $0.append(event) } }
        )

        let result = await store.probe(urlText: "https://www.bilibili.com/video/BV1MN4dewEQZ")

        XCTAssertNil(result)
        XCTAssertEqual(store.importIssue?.code, .sourceParsing)
        let recorded = events.withLock { $0 }
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded.first?.operation, "import.probe")
        XCTAssertTrue(recorded.first?.message.contains("NSURLErrorDomain (-1001)") == true)
        XCTAssertTrue(recorded.first?.message.contains("fixture transport timeout") == true)
        await store.shutdown()
    }
}

private final class DiagnosticFailureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(
            self,
            didFailWithError: NSError(
                domain: NSURLErrorDomain, code: NSURLErrorTimedOut,
                userInfo: [NSLocalizedDescriptionKey: "fixture transport timeout"]
            ))
    }
    override func stopLoading() {}
}
