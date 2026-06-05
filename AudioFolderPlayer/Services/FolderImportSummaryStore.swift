import Foundation

protocol FolderImportSummaryStoring: Sendable {
    func load() throws -> FolderImportSummary?
    func save(_ summary: FolderImportSummary) throws
}

struct FolderImportSummaryStore: FolderImportSummaryStoring, @unchecked Sendable {
    let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() throws -> FolderImportSummary? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(FolderImportSummary.self, from: data)
    }

    func save(_ summary: FolderImportSummary) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(summary)
        try data.write(to: fileURL, options: .atomic)
    }
}
