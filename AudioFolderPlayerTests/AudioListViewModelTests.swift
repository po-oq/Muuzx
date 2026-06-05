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

    private func makeViewModel() throws -> (AudioListViewModel, FakeAudioEngine) {
        try write("01 first.mp3", bytes: 10)
        try write("02 second.mp3", bytes: 20)

        let engine = FakeAudioEngine()
        let library = LocalAudioLibrary(directory: tempDir)
        let playback = PlaybackService(engine: engine)
        let viewModel = AudioListViewModel(library: library, playback: playback)
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
