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

    func test_playbackEnded_advancesToNextTrack() {
        let engine = FakeAudioEngine()
        let service = PlaybackService(
            engine: engine,
            items: [makeItem("a.mp3"), makeItem("b.mp3")]
        )
        service.play(at: 0)

        engine.simulatePlaybackEnded()

        XCTAssertEqual(service.currentIndex, 1)
        XCTAssertEqual(engine.loadedURLs.last, URL(fileURLWithPath: "/tmp/b.mp3"))
        XCTAssertTrue(engine.isPlaying)
    }

    func test_playbackEnded_onLastTrack_stops() {
        let engine = FakeAudioEngine()
        let service = PlaybackService(
            engine: engine,
            items: [makeItem("a.mp3"), makeItem("b.mp3")]
        )
        service.play(at: 1)

        engine.simulatePlaybackEnded()

        XCTAssertNil(service.currentIndex)
    }

    func test_setItems_whenCurrentItemIsRemoved_stopsAndClearsCurrentItem() throws {
        let engine = FakeAudioEngine()
        let first = makeItem("a.mp3")
        let second = makeItem("b.mp3")
        let service = PlaybackService(engine: engine, items: [first, second])
        var changedItems: [AudioItem?] = []
        service.onCurrentItemChanged = { changedItems.append($0) }
        service.play(at: 1)

        service.setItems([first])

        XCTAssertNil(service.currentIndex)
        XCTAssertNil(service.currentItem)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(changedItems.count, 2)
        XCTAssertNil(try XCTUnwrap(changedItems.last))
    }

    func test_setItems_whenCurrentItemStillExists_updatesCurrentIndexToNewPosition() {
        let engine = FakeAudioEngine()
        let first = makeItem("a.mp3")
        let second = makeItem("b.mp3")
        let service = PlaybackService(engine: engine, items: [first, second])
        var changedItems: [AudioItem?] = []
        service.onCurrentItemChanged = { changedItems.append($0) }
        service.play(at: 1)

        service.setItems([second, first])

        XCTAssertEqual(service.currentIndex, 0)
        XCTAssertEqual(service.currentItem, second)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(changedItems.count, 1)
        XCTAssertEqual(changedItems.compactMap(\.?.id), [second.id])
    }
}
