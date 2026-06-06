import XCTest
@testable import AudioFolderPlayer

final class AudioMetadataServiceTests: XCTestCase {
    func test_duration_returnsPositiveDurationForBundledMP3() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-01", withExtension: "mp3"))
        let service = AudioMetadataService()

        let duration = try await service.duration(for: url)

        XCTAssertGreaterThan(duration, 0)
    }

    func test_duration_throwsDurationUnavailableForInvalidMP3() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp3")
        try Data("not an mp3".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let service = AudioMetadataService()

        do {
            _ = try await service.duration(for: url)
            XCTFail("Expected durationUnavailable")
        } catch {
            XCTAssertEqual(error as? AudioMetadataError, .durationUnavailable)
        }
    }
}
