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

    private func waitForState(_ condition: @escaping () -> Bool) async {
        for _ in 0..<10 where !condition() {
            await Task.yield()
        }
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

    func test_playbackEnded_advancesCurrentItemAndKeepsPlaying() async throws {
        let (viewModel, engine) = try makeViewModel()
        let first = try XCTUnwrap(viewModel.items.first)
        let second = try XCTUnwrap(viewModel.items.dropFirst().first)

        viewModel.play(first)
        engine.simulatePlaybackEnded()
        await waitForState { viewModel.currentItemId == second.id }

        XCTAssertEqual(viewModel.currentItemId, second.id)
        XCTAssertEqual(viewModel.currentItem, second)
        XCTAssertTrue(viewModel.isPlaying)
    }

    func test_playbackEnded_onLastItemClearsCurrentItemAndStopsPlaying() async throws {
        let (viewModel, engine) = try makeViewModel()
        let last = try XCTUnwrap(viewModel.items.last)

        viewModel.play(last)
        engine.simulatePlaybackEnded()
        await waitForState { viewModel.currentItemId == nil }

        XCTAssertNil(viewModel.currentItemId)
        XCTAssertNil(viewModel.currentItem)
        XCTAssertFalse(viewModel.isPlaying)
    }
}
