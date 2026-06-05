import XCTest
@testable import AudioFolderPlayer

final class FolderImportServiceTests: XCTestCase {
    private var rootDir: URL!
    private var sourceDir: URL!
    private var audioDir: URL!

    override func setUpWithError() throws {
        rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceDir = rootDir.appendingPathComponent("Source", isDirectory: true)
        audioDir = rootDir.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootDir)
    }

    private func write(_ name: String, bytes: Int, in directory: URL? = nil) throws {
        let data = Data(repeating: UInt8(bytes % 255), count: bytes)
        try data.write(to: (directory ?? sourceDir).appendingPathComponent(name))
    }

    private func mkdir(_ name: String, in directory: URL? = nil) throws {
        try FileManager.default.createDirectory(
            at: (directory ?? sourceDir).appendingPathComponent(name, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func test_importFolder_copiesOnlySupportedAudioFilesInNaturalOrder() throws {
        try write("track 10.mp3", bytes: 10)
        try write("track 2.m4a", bytes: 20)
        try write("notes.txt", bytes: 30)
        try write(".hidden.mp3", bytes: 40)
        try mkdir("Nested")
        try write("nested.mp3", bytes: 50, in: sourceDir.appendingPathComponent("Nested", isDirectory: true))
        var progress: [FolderImportProgress] = []
        let service = FolderImportService(destinationDirectory: audioDir)

        let result = try service.importFolder(sourceDir, mode: .replaceAll) { progress.append($0) }

        XCTAssertEqual(result.items.map(\.fileName), ["track 2.m4a", "track 10.mp3"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("track 2.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("track 10.mp3").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("notes.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent(".hidden.mp3").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("nested.mp3").path))
        XCTAssertEqual(progress.map(\.completedFiles), [1, 2])
        XCTAssertEqual(progress.map(\.totalFiles), [2, 2])
        XCTAssertEqual(progress.map(\.currentFileName), ["track 2.m4a", "track 10.mp3"])
        XCTAssertEqual(result.summary.folderName, "Source")
        XCTAssertEqual(result.summary.fileCount, 2)
        XCTAssertEqual(result.summary.totalBytes, 30)
    }

    func test_importFolder_throwsWhenNoSupportedAudioFilesExist() throws {
        try write("notes.txt", bytes: 30)
        let service = FolderImportService(destinationDirectory: audioDir)

        XCTAssertThrowsError(try service.importFolder(sourceDir, mode: .replaceAll)) { error in
            XCTAssertEqual(error as? FolderImportError, .noSupportedAudioFiles)
        }
    }

    func test_importFolder_throwsSourceAccessDeniedWhenSourceDoesNotExist() throws {
        let missingDir = rootDir.appendingPathComponent("Missing", isDirectory: true)
        let service = FolderImportService(destinationDirectory: audioDir)

        XCTAssertThrowsError(try service.importFolder(missingDir, mode: .replaceAll)) { error in
            XCTAssertEqual(error as? FolderImportError, .sourceAccessDenied)
        }
    }

    func test_replaceAll_removesExistingDestinationFilesBeforeCopying() throws {
        try write("old.mp3", bytes: 9, in: audioDir)
        try write("old.txt", bytes: 8, in: audioDir)
        try write("new.mp3", bytes: 10)
        let service = FolderImportService(destinationDirectory: audioDir)

        _ = try service.importFolder(sourceDir, mode: .replaceAll)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("old.mp3").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("old.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("new.mp3").path))
    }

    func test_replaceAll_whenSourceIsDestination_preservesFilesAndReturnsExistingItems() throws {
        try write("track 10.mp3", bytes: 10, in: audioDir)
        try write("track 2.m4a", bytes: 20, in: audioDir)
        try write("notes.txt", bytes: 30, in: audioDir)
        let sameDirectory = audioDir.appendingPathComponent(".", isDirectory: true)
        var progress: [FolderImportProgress] = []
        let service = FolderImportService(destinationDirectory: audioDir)

        let result = try service.importFolder(sameDirectory, mode: .replaceAll) { progress.append($0) }

        XCTAssertEqual(result.items.map(\.fileName), ["track 2.m4a", "track 10.mp3"])
        XCTAssertEqual(progress.map(\.completedFiles), [1, 2])
        XCTAssertEqual(progress.map(\.totalFiles), [2, 2])
        XCTAssertEqual(progress.map(\.currentFileName), ["track 2.m4a", "track 10.mp3"])
        XCTAssertEqual(result.summary.folderName, "Audio")
        XCTAssertEqual(result.summary.fileCount, 2)
        XCTAssertEqual(result.summary.totalBytes, 30)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("track 2.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("track 10.mp3").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("notes.txt").path))
    }

    func test_mergeOverwrite_keepsLocalOnlyFilesAndOverwritesSameName() throws {
        try write("local-only.mp3", bytes: 9, in: audioDir)
        try write("same.mp3", bytes: 5, in: audioDir)
        try write("same.mp3", bytes: 22)
        let service = FolderImportService(destinationDirectory: audioDir)

        _ = try service.importFolder(sourceDir, mode: .mergeOverwrite)

        let sameSize = try fileSize(at: audioDir.appendingPathComponent("same.mp3"))
        XCTAssertEqual(sameSize, 22)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("local-only.mp3").path))
    }

    func test_mergeOverwrite_whenSourceIsDestination_preservesFilesAndReturnsExistingItems() throws {
        try write("same.mp3", bytes: 22, in: audioDir)
        let sameDirectory = audioDir.appendingPathComponent(".", isDirectory: true)
        let service = FolderImportService(destinationDirectory: audioDir)

        let result = try service.importFolder(sameDirectory, mode: .mergeOverwrite)

        XCTAssertEqual(result.items.map(\.fileName), ["same.mp3"])
        XCTAssertEqual(result.summary.folderName, "Audio")
        XCTAssertEqual(result.summary.fileCount, 1)
        XCTAssertEqual(result.summary.totalBytes, 22)
        XCTAssertEqual(try fileSize(at: audioDir.appendingPathComponent("same.mp3")), 22)
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size]
        if let number = size as? NSNumber {
            return number.int64Value
        }
        return Int64(size as? Int ?? 0)
    }
}
