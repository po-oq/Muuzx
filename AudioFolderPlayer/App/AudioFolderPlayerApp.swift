import SwiftUI

@main
struct AudioFolderPlayerApp: App {
    @StateObject private var audioListViewModel: AudioListViewModel
    @StateObject private var folderViewModel: FolderViewModel

    init() {
        let fileManager = FileManager.default
        let audioDir = (try? AppDirectories.audioDirectory(fileManager))
            ?? fileManager.temporaryDirectory
        let stateDir = (try? AppDirectories.stateDirectory(fileManager))
            ?? fileManager.temporaryDirectory

        if (try? LocalAudioLibrary(directory: audioDir).loadItems().isEmpty) == true {
            try? SampleSeeder(destination: audioDir).seedIfEmpty()
        }

        let library = LocalAudioLibrary(directory: audioDir)
        let playback = PlaybackService(engine: AVPlayerAudioEngine())
        let audioListViewModel = AudioListViewModel(library: library, playback: playback)

        let summaryStore = FolderImportSummaryStore(
            fileURL: stateDir.appendingPathComponent("folder-import-summary.json")
        )
        let bookmarkStore = FolderBookmarkStore(
            fileURL: stateDir.appendingPathComponent("folder-bookmark.data")
        )
        let importer = FolderImportService(destinationDirectory: audioDir)
        let folderViewModel = FolderViewModel(
            importer: importer,
            summaryStore: summaryStore,
            bookmarkStore: bookmarkStore,
            reloadAudioList: {
                audioListViewModel.load()
            }
        )

        _audioListViewModel = StateObject(wrappedValue: audioListViewModel)
        _folderViewModel = StateObject(wrappedValue: folderViewModel)
    }

    var body: some Scene {
        WindowGroup {
            FolderView(
                folderViewModel: folderViewModel,
                audioListViewModel: audioListViewModel
            )
        }
    }
}
