import XCTest
@testable import AudioFolderPlayer

final class LocalAudioLibraryTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, bytes: Int) throws {
        let data = Data(repeating: 0, count: bytes)
        try data.write(to: tempDir.appendingPathComponent(name))
    }

    private func mkdir(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func test_loadItems_returnsOnlySupportedExtensions() throws {
        try write("a.mp3", bytes: 10)
        try write("b.m4a", bytes: 10)
        try write("readme.txt", bytes: 10)
        try write("c.flac", bytes: 10)

        let items = try LocalAudioLibrary(directory: tempDir).loadItems()

        XCTAssertEqual(items.map(\.fileName), ["a.mp3", "b.m4a"])
    }

    func test_loadItems_sortsByNaturalFileNameOrder() throws {
        try write("track 10.mp3", bytes: 10)
        try write("track 2.mp3", bytes: 10)
        try write("track 1.mp3", bytes: 10)

        let items = try LocalAudioLibrary(directory: tempDir).loadItems()

        XCTAssertEqual(items.map(\.fileName), ["track 1.mp3", "track 2.mp3", "track 10.mp3"])
    }

    func test_loadItems_populatesIdAndSize() throws {
        try write("song.mp3", bytes: 1234)

        let items = try LocalAudioLibrary(directory: tempDir).loadItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].fileSizeBytes, 1234)
        XCTAssertEqual(items[0].id, "song.mp3|1234")
        XCTAssertEqual(items[0].status, .unplayed)
    }

    func test_loadItems_ignoresDirectoriesWithSupportedExtensions() throws {
        try mkdir("folder.mp3")
        try write("song.mp3", bytes: 10)

        let items = try LocalAudioLibrary(directory: tempDir).loadItems()

        XCTAssertEqual(items.map(\.fileName), ["song.mp3"])
    }
}
