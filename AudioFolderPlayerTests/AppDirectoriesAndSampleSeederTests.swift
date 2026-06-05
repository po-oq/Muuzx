import XCTest
@testable import AudioFolderPlayer

final class AppDirectoriesAndSampleSeederTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_audioDirectoryCreatesAudioFolderUnderAppSupportRoot() throws {
        let fm = FileManager.default
        let url = try AppDirectories.audioDirectory(fm)

        XCTAssertEqual(url.lastPathComponent, "audio")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, AppDirectories.appFolderName)
        XCTAssertTrue(fm.fileExists(atPath: url.path))
    }

    func test_seedIfEmptyCopiesBundledAudioFilesOnlyWhenDestinationIsEmpty() throws {
        let bundleURL = tempDir.appendingPathComponent("Samples.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: bundleURL.appendingPathComponent("sample-test.mp3"))
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))

        let destination = tempDir.appendingPathComponent("audio", isDirectory: true)
        let seeder = SampleSeeder(bundle: bundle, destination: destination)

        try seeder.seedIfEmpty()
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("sample-test.mp3").path
        ))

        try "keep".write(
            to: destination.appendingPathComponent("existing.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.removeItem(at: destination.appendingPathComponent("sample-test.mp3"))

        try seeder.seedIfEmpty()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent("sample-test.mp3").path
        ))
    }
}
