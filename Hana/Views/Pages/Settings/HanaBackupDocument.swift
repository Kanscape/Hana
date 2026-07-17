import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let hanaBackup = UTType(exportedAs: "sh.celia.hana.backup", conformingTo: .json)
}

struct HanaBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.hanaBackup, .json] }
    static var writableContentTypes: [UTType] { [.hanaBackup] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw HanaBackupError.missingFileData
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
