import SwiftUI
import UniformTypeIdentifiers

struct PNGDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.png]

    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
