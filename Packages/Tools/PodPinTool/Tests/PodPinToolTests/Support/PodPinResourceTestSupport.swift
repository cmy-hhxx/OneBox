import Foundation
import XCTest

@testable import PodPinTool

extension FixtureContentImporter {
    static func testFixture(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FixtureContentImporter {
        let audioURL = try XCTUnwrap(
            Bundle.module.url(
                forResource: "podpin-sample",
                withExtension: "m4a"
            ),
            file: file,
            line: line
        )
        return FixtureContentImporter(audioURL: audioURL)
    }
}

extension XCTestCase {
    func makeTestExecutable(named name: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory.appending(
            path: "PodPinExecutableTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let executableURL = directoryURL.appending(
            path: name,
            directoryHint: .notDirectory
        )
        try "#!/bin/sh\nexit 0\n".write(
            to: executableURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return executableURL
    }
}
