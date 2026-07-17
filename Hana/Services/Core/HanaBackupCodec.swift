import Foundation

actor HanaBackupCodec {
    static let shared = HanaBackupCodec()

    func encode(_ archive: HanaBackupArchive) throws -> Data {
        try HanaBackupArchive.encode(archive)
    }

    func readArchive(from url: URL) throws -> HanaBackupArchive {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try HanaBackupArchive.decode(Data(contentsOf: url))
    }
}
