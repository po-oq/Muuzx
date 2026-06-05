import XCTest
@testable import AudioFolderPlayer

final class PlaybackServiceTests: XCTestCase {
    private func makeItem(_ name: String) -> AudioItem {
        AudioItem(
            id: name, fileName: name,
            localURL: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSizeBytes: 1, durationSec: 100, positionSec: 0,
            status: .unplayed, updatedAt: Date()
        )
    }

    func test_skipForward_advances30Seconds() {
        let engine = FakeAudioEngine()
        engine.currentTimeSec = 10
        engine.durationSec = 100
        let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])

        service.skipForward()

        XCTAssertEqual(engine.seekedToSec.last, 40)
    }

    func test_skipForward_clampsToDuration() {
        let engine = FakeAudioEngine()
        engine.currentTimeSec = 90
        engine.durationSec = 100
        let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])

        service.skipForward()

        XCTAssertEqual(engine.seekedToSec.last, 100)
    }

    func test_skipBackward_rewinds10Seconds() {
        let engine = FakeAudioEngine()
        engine.currentTimeSec = 50
        engine.durationSec = 100
        let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])

        service.skipBackward()

        XCTAssertEqual(engine.seekedToSec.last, 40)
    }

    func test_skipBackward_clampsToZero() {
        let engine = FakeAudioEngine()
        engine.currentTimeSec = 5
        engine.durationSec = 100
        let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])

        service.skipBackward()

        XCTAssertEqual(engine.seekedToSec.last, 0)
    }
}
