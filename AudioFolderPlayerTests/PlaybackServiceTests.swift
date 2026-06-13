import XCTest
@testable import AudioFolderPlayer

@MainActor
final class PlaybackServiceTests: XCTestCase {
    private final class RecordingAudioEngine: AudioEngine {
        var currentTimeSec: Double = 0
        var durationSec: Double = 0
        var onPlaybackEnded: (() -> Void)?
        private(set) var actions: [String] = []

        func load(url: URL) { actions.append("load:\(url.lastPathComponent)") }
        func play() { actions.append("play") }
        func pause() { actions.append("pause") }
        func seek(toSec seconds: Double) { actions.append("seek:\(seconds)") }
    }

    private func makeItem(_ name: String, durationSec: Double = 100) -> AudioItem {
        AudioItem(
            id: name, fileName: name,
            localURL: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSizeBytes: 1, durationSec: durationSec, positionSec: 0,
            status: .unplayed, updatedAt: Date()
        )
    }

    func test_play_withStartPosition_loadsSeeksAndPlays() {
        let engine = RecordingAudioEngine()
        let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])
        var reasons: [PlaybackItemChangeReason] = []
        service.onCurrentItemChanged = { _, reason in reasons.append(reason) }

        service.play(at: 0, startPositionSec: 42)

        XCTAssertEqual(engine.actions, ["load:a.mp3", "seek:42.0", "play"])
        XCTAssertEqual(reasons, [.manual])
    }

    func test_play_withStartPosition_clampsToItemDuration() {
        let engine = FakeAudioEngine()
        engine.durationSec = 120
        let service = PlaybackService(
            engine: engine,
            items: [makeItem("a.mp3", durationSec: 80)]
        )

        service.play(at: 0, startPositionSec: 100)

        XCTAssertEqual(engine.seekedToSec.last, 80)
    }

    func test_play_withStartPosition_fallsBackToEngineDuration() {
        let engine = FakeAudioEngine()
        engine.durationSec = 75
        let service = PlaybackService(
            engine: engine,
            items: [makeItem("a.mp3", durationSec: 0)]
        )

        service.play(at: 0, startPositionSec: 100)

        XCTAssertEqual(engine.seekedToSec.last, 75)
    }

    func test_play_withStartPosition_preservesPositionWhenDurationIsUnknown() {
        let engine = FakeAudioEngine()
        engine.durationSec = 0
        let service = PlaybackService(
            engine: engine,
            items: [makeItem("a.mp3", durationSec: 0)]
        )

        service.play(at: 0, startPositionSec: 42)

        XCTAssertEqual(engine.seekedToSec.last, 42)
    }

    func test_stop_pausesClearsCurrentItemAndNotifiesNil() throws {
        let engine = FakeAudioEngine()
        let item = makeItem("a.mp3")
        let service = PlaybackService(engine: engine, items: [item])
        var changedItems: [AudioItem?] = []
        service.onCurrentItemChanged = { item, _ in changedItems.append(item) }
        service.play(at: 0)

        service.stop()

        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(service.currentIndex)
        XCTAssertNil(service.currentItem)
        XCTAssertNil(try XCTUnwrap(changedItems.last))
    }

    func test_currentPositionAndDuration_exposeEngineValues() {
        let engine = FakeAudioEngine()
        engine.currentTimeSec = 12
        engine.durationSec = 90
        let service = PlaybackService(engine: engine)

        XCTAssertEqual(service.currentPositionSec, 12)
        XCTAssertEqual(service.currentDurationSec, 90)
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

    func test_skipForward_preservesPositiveTargetWhenDurationIsUnknown() {
        let engine = FakeAudioEngine()
        engine.currentTimeSec = 10
        engine.durationSec = 0
        let service = PlaybackService(engine: engine, items: [makeItem("a.mp3", durationSec: 0)])

        service.skipForward()

        XCTAssertEqual(engine.seekedToSec.last, 40)
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

    func test_playbackEnded_notifiesCompletedItemBeforeAdvancing() {
        let engine = FakeAudioEngine()
        let first = makeItem("a.mp3")
        let second = makeItem("b.mp3")
        let service = PlaybackService(engine: engine, items: [first, second])
        var events: [String] = []
        service.onItemCompleted = { events.append("completed:\($0.id)") }
        service.onCurrentItemChanged = { item, reason in
            events.append("changed:\(item?.id ?? "nil"):\(reason)")
        }
        service.play(at: 0)
        events.removeAll()

        engine.simulatePlaybackEnded()

        XCTAssertEqual(events, ["completed:\(first.id)", "changed:\(second.id):automatic"])
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
        service.onCurrentItemChanged = { item, _ in changedItems.append(item) }
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
        service.onCurrentItemChanged = { item, _ in changedItems.append(item) }
        service.play(at: 1)

        service.setItems([second, first])

        XCTAssertEqual(service.currentIndex, 0)
        XCTAssertEqual(service.currentItem, second)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(changedItems.count, 1)
        XCTAssertEqual(changedItems.compactMap(\.?.id), [second.id])
    }
}
