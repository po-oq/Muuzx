import Combine
import XCTest
@testable import AudioFolderPlayer

@MainActor
final class AudioListViewModelTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeViewModel(
        metadata: any AudioMetadataLoading = FakeAudioMetadataLoader(durations: [:])
    ) throws -> (AudioListViewModel, FakeAudioEngine) {
        try write("01 first.mp3", bytes: 10)
        try write("02 second.mp3", bytes: 20)

        let engine = FakeAudioEngine()
        let library = LocalAudioLibrary(directory: tempDir)
        let playback = PlaybackService(engine: engine)
        let viewModel = AudioListViewModel(library: library, playback: playback, metadata: metadata)
        viewModel.load()

        return (viewModel, engine)
    }

    private func write(_ name: String, bytes: Int) throws {
        let data = Data(repeating: 0, count: bytes)
        try data.write(to: tempDir.appendingPathComponent(name))
    }

    func test_deinit_releasesPlaybackServiceAndEngine() {
        weak var weakPlayback: PlaybackService?
        weak var weakEngine: FakeAudioEngine?

        autoreleasepool {
            let engine = FakeAudioEngine()
            let playback = PlaybackService(engine: engine)
            let library = LocalAudioLibrary(directory: tempDir)
            let viewModel = AudioListViewModel(
                library: library,
                playback: playback,
                metadata: FakeAudioMetadataLoader(durations: [:])
            )
            weakPlayback = playback
            weakEngine = engine
            _ = viewModel
        }

        XCTAssertNil(weakPlayback)
        XCTAssertNil(weakEngine)
    }

    func test_load_updatesDurationAsynchronously() async throws {
        let metadata = ControllableAudioMetadataLoader()
        let (viewModel, _) = try makeViewModel(metadata: metadata)
        let request = await metadata.waitForRequest(at: 0)
        let durationUpdated = expectation(description: "duration updated")
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if items.first?.durationSec == 125 {
                durationUpdated.fulfill()
            }
        }

        XCTAssertEqual(viewModel.items.first?.durationSec, 0)

        await metadata.complete(request, with: 125)
        await fulfillment(of: [durationUpdated], timeout: 1)

        XCTAssertEqual(viewModel.items.first?.durationSec, 125)
        XCTAssertEqual(viewModel.items.dropFirst().first?.durationSec, 0)
        let secondRequest = await metadata.waitForRequest(at: 1)
        await metadata.fail(secondRequest)
        _ = cancellable
    }

    func test_load_whenDurationArrivesForInProgressItem_marksItPlayedAtDuration() async throws {
        let metadata = ControllableAudioMetadataLoader()
        let (viewModel, engine) = try makeViewModel(metadata: metadata)
        let request = await metadata.waitForRequest(at: 0)
        let first = try XCTUnwrap(viewModel.items.first)
        viewModel.play(first)
        engine.currentTimeSec = 75
        viewModel.refreshPlaybackState()
        viewModel.togglePlayPause()
        let durationUpdated = expectation(description: "duration updated")
        var didObserveDuration = false
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if !didObserveDuration, items.first?.durationSec == 100 {
                didObserveDuration = true
                durationUpdated.fulfill()
            }
        }

        await metadata.complete(request, with: 100)
        await fulfillment(of: [durationUpdated], timeout: 1)

        let item = try XCTUnwrap(viewModel.items.first)
        XCTAssertEqual(item.durationSec, 100)
        XCTAssertEqual(item.positionSec, 100)
        XCTAssertEqual(item.status, .played)
        _ = cancellable
    }

    func test_load_whenDurationArrivesImmediatelyAfterPlay_preservesCurrentItemInProgress() async throws {
        let metadata = ControllableAudioMetadataLoader()
        let (viewModel, _) = try makeViewModel(metadata: metadata)
        let request = await metadata.waitForRequest(at: 0)
        viewModel.play(try XCTUnwrap(viewModel.items.first))
        let durationUpdated = expectation(description: "duration updated")
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if items.first?.durationSec == 100 {
                durationUpdated.fulfill()
            }
        }

        await metadata.complete(request, with: 100)
        await fulfillment(of: [durationUpdated], timeout: 1)

        XCTAssertEqual(viewModel.currentItem?.positionSec, 0)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
        XCTAssertTrue(viewModel.isPlaying)
        _ = cancellable
    }

    func test_load_whenDurationArrivesImmediatelyAfterPlayFromBeginning_preservesCurrentItemInProgress() async throws {
        let metadata = ControllableAudioMetadataLoader()
        let (viewModel, _) = try makeViewModel(metadata: metadata)
        let request = await metadata.waitForRequest(at: 0)
        viewModel.playFromBeginning(try XCTUnwrap(viewModel.items.first))
        let durationUpdated = expectation(description: "duration updated")
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if items.first?.durationSec == 100 {
                durationUpdated.fulfill()
            }
        }

        await metadata.complete(request, with: 100)
        await fulfillment(of: [durationUpdated], timeout: 1)

        XCTAssertEqual(viewModel.currentItem?.positionSec, 0)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
        XCTAssertTrue(viewModel.isPlaying)
        _ = cancellable
    }

    func test_load_whenDurationArrivesAfterPausingAtZero_marksCurrentItemUnplayed() async throws {
        let metadata = ControllableAudioMetadataLoader()
        let (viewModel, _) = try makeViewModel(metadata: metadata)
        let request = await metadata.waitForRequest(at: 0)
        viewModel.play(try XCTUnwrap(viewModel.items.first))
        viewModel.togglePlayPause()
        let durationUpdated = expectation(description: "duration updated")
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if items.first?.durationSec == 100 {
                durationUpdated.fulfill()
            }
        }

        await metadata.complete(request, with: 100)
        await fulfillment(of: [durationUpdated], timeout: 1)

        XCTAssertEqual(viewModel.currentItem?.positionSec, 0)
        XCTAssertEqual(viewModel.currentItem?.status, .unplayed)
        XCTAssertFalse(viewModel.isPlaying)
        _ = cancellable
    }

    func test_load_whenDurationArrivesForPlayedItem_setsPositionToDuration() async throws {
        let metadata = ControllableAudioMetadataLoader()
        let (viewModel, engine) = try makeViewModel(metadata: metadata)
        let request = await metadata.waitForRequest(at: 0)
        let first = try XCTUnwrap(viewModel.items.first)
        viewModel.play(first)
        engine.currentTimeSec = 75
        engine.simulatePlaybackEnded()
        let durationUpdated = expectation(description: "duration updated")
        var didObserveDuration = false
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if !didObserveDuration, items.first?.durationSec == 100 {
                didObserveDuration = true
                durationUpdated.fulfill()
            }
        }

        await metadata.complete(request, with: 100)
        await fulfillment(of: [durationUpdated], timeout: 1)

        let item = try XCTUnwrap(viewModel.items.first)
        XCTAssertEqual(item.durationSec, 100)
        XCTAssertEqual(item.positionSec, 100)
        XCTAssertEqual(item.status, .played)
        _ = cancellable
    }

    func test_load_whenReloaded_ignoresCompletedRequestFromPreviousLoad() async throws {
        let metadata = ControllableAudioMetadataLoader()
        let (viewModel, _) = try makeViewModel(metadata: metadata)
        let oldRequest = await metadata.waitForRequest(at: 0)
        let oldRequestProcessed = expectation(description: "old request processed as cancelled")
        viewModel.onMetadataCancellationProcessed = {
            oldRequestProcessed.fulfill()
        }

        viewModel.load()
        let newRequest = await metadata.waitForRequest(at: 1)

        let newDurationApplied = expectation(description: "new duration applied")
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if items.first?.durationSec == 125 {
                newDurationApplied.fulfill()
            }
        }

        await metadata.complete(oldRequest, with: 111)
        await fulfillment(of: [oldRequestProcessed], timeout: 1)
        viewModel.onMetadataCancellationProcessed = nil
        XCTAssertEqual(viewModel.items.first?.durationSec, 0)

        await metadata.complete(newRequest, with: 125)
        await fulfillment(of: [newDurationApplied], timeout: 1)

        XCTAssertEqual(viewModel.items.first?.durationSec, 125)
        let secondNewRequest = await metadata.waitForRequest(at: 2)
        await metadata.fail(secondNewRequest)
        _ = cancellable
    }

    func test_playbackEnded_advancesCurrentItemAndKeepsPlaying() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)

        viewModel.play(first)
        engine.simulatePlaybackEnded()

        XCTAssertEqual(viewModel.currentItemId, second.id)
        XCTAssertEqual(viewModel.currentItem?.id, second.id)
        XCTAssertEqual(viewModel.currentItem?.positionSec, 0)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
        XCTAssertTrue(viewModel.isPlaying)
    }

    func test_playbackEnded_onLastItemClearsCurrentItemAndStopsPlaying() throws {
        let (viewModel, engine) = try makeViewModel()
        let last = try XCTUnwrap(viewModel.items.last)

        viewModel.play(last)
        engine.simulatePlaybackEnded()

        XCTAssertNil(viewModel.currentItemId)
        XCTAssertNil(viewModel.currentItem)
        XCTAssertFalse(viewModel.isPlaying)
    }

    func test_refreshPlaybackState_marksItemInProgress() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        engine.durationSec = 100

        viewModel.play(first)
        engine.currentTimeSec = 42
        viewModel.refreshPlaybackState()

        XCTAssertEqual(viewModel.currentItem?.positionSec, 42)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
    }

    func test_refreshPlaybackState_marksItemPlayedWithinLastThirtySeconds() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        engine.durationSec = 100

        viewModel.play(first)
        engine.currentTimeSec = 75
        viewModel.refreshPlaybackState()

        XCTAssertEqual(viewModel.currentItem?.positionSec, 100)
        XCTAssertEqual(viewModel.currentItem?.status, .played)
    }

    func test_refreshPlaybackState_withUnknownDurationDoesNotMarkItemPlayed() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)

        viewModel.play(first)
        engine.currentTimeSec = 75
        viewModel.refreshPlaybackState()

        XCTAssertEqual(viewModel.currentItem?.positionSec, 75)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
    }

    func test_play_resumesInProgressItemFromStoredPosition() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)
        engine.durationSec = 100
        viewModel.play(first)
        engine.currentTimeSec = 42
        viewModel.refreshPlaybackState()
        viewModel.play(second)

        viewModel.play(try XCTUnwrap(viewModel.items.first))

        XCTAssertEqual(engine.seekedToSec.last, 42)
        XCTAssertEqual(viewModel.currentItem?.positionSec, 42)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
    }

    func test_playPlayedItemStartsFromBeginning() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)
        engine.durationSec = 100
        viewModel.play(first)
        engine.currentTimeSec = 75
        viewModel.refreshPlaybackState()
        viewModel.play(second)

        viewModel.play(try XCTUnwrap(viewModel.items.first))

        XCTAssertEqual(engine.seekedToSec.last, 0)
    }

    func test_playFromBeginning_startsAtZeroAndMarksItemInProgress() throws {
        let (viewModel, engine) = try makeViewModel()
        let item = try XCTUnwrap(viewModel.items.first)

        viewModel.playFromBeginning(item)

        XCTAssertEqual(engine.seekedToSec.last, 0)
        XCTAssertEqual(viewModel.currentItem?.positionSec, 0)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
        XCTAssertTrue(viewModel.isPlaying)
    }

    func test_markUnplayed_currentItemStopsAndClearsSelection() throws {
        let (viewModel, engine) = try makeViewModel()
        let item = try XCTUnwrap(viewModel.items.first)
        viewModel.play(item)

        viewModel.markUnplayed(item)

        XCTAssertNil(viewModel.currentItem)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(viewModel.items[0].positionSec, 0)
        XCTAssertEqual(viewModel.items[0].status, .unplayed)
    }

    func test_markUnplayed_nonCurrentItemResetsItsState() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)
        engine.durationSec = 100
        viewModel.play(first)
        engine.currentTimeSec = 42
        viewModel.refreshPlaybackState()
        viewModel.play(second)

        viewModel.markUnplayed(try XCTUnwrap(viewModel.items.first))

        XCTAssertEqual(viewModel.currentItemId, second.id)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(viewModel.items[0].positionSec, 0)
        XCTAssertEqual(viewModel.items[0].status, .unplayed)
    }

    func test_load_preservesInMemoryStateForSameFileId() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        engine.durationSec = 100
        viewModel.play(first)
        engine.currentTimeSec = 42
        viewModel.refreshPlaybackState()
        let stateBeforeReload = try XCTUnwrap(viewModel.items.first)

        viewModel.load()

        let reloaded = try XCTUnwrap(viewModel.items.first { $0.id == first.id })
        XCTAssertEqual(reloaded.durationSec, 100)
        XCTAssertEqual(reloaded.positionSec, 42)
        XCTAssertEqual(reloaded.status, .inProgress)
        XCTAssertEqual(reloaded.updatedAt, stateBeforeReload.updatedAt)
    }

    func test_load_whenCurrentItemWasRemovedStopsAndClearsSelection() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        viewModel.play(first)
        try FileManager.default.removeItem(at: first.localURL)

        viewModel.load()

        XCTAssertNil(viewModel.currentItem)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertFalse(engine.isPlaying)
    }

    func test_playbackEnded_marksCompletedItemPlayedAndAdvancesToNext() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)
        engine.durationSec = 100
        viewModel.play(first)

        engine.simulatePlaybackEnded()

        let completed = try XCTUnwrap(viewModel.items.first { $0.id == first.id })
        XCTAssertEqual(completed.positionSec, 100)
        XCTAssertEqual(completed.status, .played)
        XCTAssertEqual(viewModel.currentItemId, second.id)
        XCTAssertTrue(viewModel.isPlaying)
    }

    func test_playbackEnded_resetsInProgressNextItemToBeginning() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)
        engine.durationSec = 100
        viewModel.play(second)
        engine.currentTimeSec = 42
        viewModel.refreshPlaybackState()
        viewModel.play(first)

        engine.simulatePlaybackEnded()

        XCTAssertEqual(engine.seekedToSec.last, 0)
        XCTAssertEqual(viewModel.currentItemId, second.id)
        XCTAssertEqual(viewModel.currentItem?.positionSec, 0)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
    }

    func test_playbackEnded_resetsPlayedNextItemToBeginning() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)
        engine.durationSec = 100
        viewModel.play(second)
        engine.currentTimeSec = 75
        viewModel.refreshPlaybackState()
        viewModel.play(first)

        engine.simulatePlaybackEnded()

        XCTAssertEqual(engine.seekedToSec.last, 0)
        XCTAssertEqual(viewModel.currentItemId, second.id)
        XCTAssertEqual(viewModel.currentItem?.positionSec, 0)
        XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
    }

    func test_playbackEnded_thenMarkUnplayed_isNotOverwrittenByDelayedCompletion() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)
        engine.durationSec = 100
        viewModel.play(first)

        engine.simulatePlaybackEnded()
        viewModel.markUnplayed(first)

        let updated = try XCTUnwrap(viewModel.items.first { $0.id == first.id })
        XCTAssertEqual(updated.positionSec, 0)
        XCTAssertEqual(updated.status, .unplayed)
        XCTAssertEqual(viewModel.currentItemId, second.id)
    }

    func test_pauseImmediatelyUpdatesDisplayedPosition() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        viewModel.play(first)
        engine.currentTimeSec = 42

        viewModel.togglePlayPause()

        XCTAssertEqual(viewModel.currentItem?.positionSec, 42)
        XCTAssertFalse(viewModel.isPlaying)
    }

    func test_startObservingPlaybackIfNeeded_afterListReentryRefreshesPosition() async throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        viewModel.play(first)
        viewModel.stopObservingPlayback()
        engine.currentTimeSec = 42
        let positionUpdated = expectation(description: "position updated after observation restarts")
        var didObservePositionUpdate = false
        let cancellable = viewModel.$items.dropFirst().sink { items in
            if items.first?.positionSec == 42, !didObservePositionUpdate {
                didObservePositionUpdate = true
                positionUpdated.fulfill()
            }
        }

        viewModel.load()
        viewModel.startObservingPlaybackIfNeeded()

        await fulfillment(of: [positionUpdated], timeout: 2)
        XCTAssertEqual(viewModel.currentItem?.positionSec, 42)
        _ = cancellable
    }

    func test_skipImmediatelyUpdatesDisplayedPosition() throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        engine.durationSec = 100
        viewModel.play(first)
        engine.currentTimeSec = 20

        viewModel.skipForward()
        XCTAssertEqual(viewModel.currentItem?.positionSec, 50)

        viewModel.skipBackward()
        XCTAssertEqual(viewModel.currentItem?.positionSec, 40)
    }
}
