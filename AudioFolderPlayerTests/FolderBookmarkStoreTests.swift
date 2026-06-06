import XCTest
@testable import AudioFolderPlayer

final class FolderBookmarkStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("folder-bookmark.data")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_loadData_returnsNilWhenFileDoesNotExist() throws {
        let store = FolderBookmarkStore(fileURL: fileURL)

        XCTAssertNil(try store.loadData())
    }

    func test_saveAndLoadData_roundTripsBookmarkData() throws {
        let store = FolderBookmarkStore(fileURL: fileURL)
        let data = Data([1, 2, 3, 4])

        try store.saveData(data)

        XCTAssertEqual(try store.loadData(), data)
    }
}
