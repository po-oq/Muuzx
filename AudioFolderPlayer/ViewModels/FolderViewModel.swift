import Combine
import Foundation

@MainActor
final class FolderViewModel: ObservableObject {
    @Published private(set) var summary: FolderImportSummary?
    @Published private(set) var progress: FolderImportProgress?
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?

    private let importer: any FolderImporting
    private let summaryStore: any FolderImportSummaryStoring
    private let bookmarkStore: FolderBookmarkStore?
    private let reloadAudioList: () -> Void

    var hasImportedAudio: Bool {
        summary != nil
    }

    init(
        importer: any FolderImporting,
        summaryStore: any FolderImportSummaryStoring,
        bookmarkStore: FolderBookmarkStore? = nil,
        reloadAudioList: @escaping () -> Void = {}
    ) {
        self.importer = importer
        self.summaryStore = summaryStore
        self.bookmarkStore = bookmarkStore
        self.reloadAudioList = reloadAudioList
        summary = try? summaryStore.load()
    }

    func importFolder(_ url: URL, mode: ImportMode = .replaceAll) async {
        isImporting = true
        errorMessage = nil
        progress = nil

        defer {
            isImporting = false
        }

        do {
            try bookmarkStore?.saveBookmark(for: url)
            let result = try importer.importFolder(url, mode: mode) { [weak self] progress in
                self?.progress = progress
            }
            try summaryStore.save(result.summary)
            summary = result.summary
            reloadAudioList()
        } catch {
            if let localizedError = error as? LocalizedError,
               let errorDescription = localizedError.errorDescription {
                errorMessage = errorDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
