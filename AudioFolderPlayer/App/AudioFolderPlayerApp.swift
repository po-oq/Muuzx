import SwiftUI

@main
struct AudioFolderPlayerApp: App {
    @StateObject private var viewModel: AudioListViewModel

    init() {
        let audioDir = (try? AppDirectories.audioDirectory())
            ?? FileManager.default.temporaryDirectory
        try? SampleSeeder(destination: audioDir).seedIfEmpty()

        let library = LocalAudioLibrary(directory: audioDir)
        let playback = PlaybackService(engine: AVPlayerAudioEngine())
        _viewModel = StateObject(wrappedValue: AudioListViewModel(library: library, playback: playback))
    }

    var body: some Scene {
        WindowGroup {
            AudioListView(viewModel: viewModel)
        }
    }
}
