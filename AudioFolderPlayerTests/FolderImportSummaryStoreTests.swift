import XCTest
@testable import AudioFolderPlayer

final class FolderImportSummaryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("folder-import-summary.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_load_returnsNilWhenFileDoesNotExist() throws {
        let store = FolderImportSummaryStore(fileURL: fileURL)

        XCTAssertNil(try store.load())
    }

    func test_saveAndLoad_roundTripsSummary() throws {
        let store = FolderImportSummaryStore(fileURL: fileURL)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = FolderImportSummary(
            folderName: "AudioBooks",
            fileCount: 2,
            totalBytes: 1234,
            importedAt: date
        )

        try store.save(summary)

        XCTAssertEqual(try store.load(), summary)
    }
}
