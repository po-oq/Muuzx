import XCTest
@testable import AudioFolderPlayer

@MainActor
final class FolderViewModelTests: XCTestCase {
    private let sourceURL = URL(fileURLWithPath: "/tmp/AudioBooks", isDirectory: true)

    func test_init_loadsSavedSummary() throws {
        let savedSummary = makeSummary(folderName: "Saved")
        let store = FakeFolderImportSummaryStore(summary: savedSummary)

        let viewModel = FolderViewModel(
            importer: FakeFolderImporter(),
            summaryStore: store
        )

        XCTAssertEqual(viewModel.summary, savedSummary)
        XCTAssertTrue(viewModel.hasImportedAudio)
        XCTAssertEqual(store.loadCallCount, 1)
    }

    func test_importFolder_successUpdatesSummaryStoresSummaryRecordsProgressClearsErrorAndReloadsAudioListOnce() async throws {
        let expectedSummary = makeSummary(folderName: "Imported")
        let progress = FolderImportProgress(
            completedFiles: 1,
            totalFiles: 2,
            currentFileName: "chapter 1.mp3"
        )
        let importer = FakeFolderImporter(result: FolderImportResult(items: [], summary: expectedSummary))
        importer.progressToReport = progress
        let store = FakeFolderImportSummaryStore()
        var reloadCount = 0
        let viewModel = FolderViewModel(
            importer: importer,
            summaryStore: store,
            reloadAudioList: { reloadCount += 1 }
        )
        viewModel.errorMessage = "前回のエラー"

        await viewModel.importFolder(sourceURL, mode: .mergeOverwrite)

        XCTAssertFalse(viewModel.isImporting)
        XCTAssertEqual(viewModel.summary, expectedSummary)
        XCTAssertTrue(viewModel.hasImportedAudio)
        XCTAssertEqual(viewModel.progress, progress)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(store.savedSummaries, [expectedSummary])
        XCTAssertEqual(importer.importedSourceDirectory, sourceURL)
        XCTAssertEqual(importer.importedMode, .mergeOverwrite)
        XCTAssertEqual(reloadCount, 1)
    }

    func test_importFolder_errorSetsJapaneseMessageDoesNotReloadAndClearsImporting() async {
        let importer = FakeFolderImporter(error: FolderImportError.noSupportedAudioFiles)
        let store = FakeFolderImportSummaryStore()
        var reloadCount = 0
        let viewModel = FolderViewModel(
            importer: importer,
            summaryStore: store,
            reloadAudioList: { reloadCount += 1 }
        )

        await viewModel.importFolder(sourceURL)

        XCTAssertFalse(viewModel.isImporting)
        XCTAssertEqual(viewModel.errorMessage, "対応音声ファイルが見つかりませんでした。")
        XCTAssertNil(viewModel.summary)
        XCTAssertFalse(viewModel.hasImportedAudio)
        XCTAssertNil(viewModel.progress)
        XCTAssertTrue(store.savedSummaries.isEmpty)
        XCTAssertEqual(reloadCount, 0)
    }

    func test_importFolder_runsBlockingImporterOffMainThread() async {
        let importer = FakeFolderImporter()
        let viewModel = FolderViewModel(
            importer: importer,
            summaryStore: FakeFolderImportSummaryStore()
        )

        await viewModel.importFolder(sourceURL)

        XCTAssertEqual(importer.importedOnMainThread, false)
    }

    func test_importFolder_ignoresSecondCallWhileImportIsRunning() async {
        let expectedSummary = makeSummary(folderName: "Imported")
        let importer = BlockingFolderImporter(result: FolderImportResult(items: [], summary: expectedSummary))
        let store = FakeFolderImportSummaryStore()
        var reloadCount = 0
        let viewModel = FolderViewModel(
            importer: importer,
            summaryStore: store,
            reloadAudioList: { reloadCount += 1 }
        )

        let firstImport = Task {
            await viewModel.importFolder(sourceURL)
        }
        defer {
            importer.finishFirstImport()
        }

        let firstImportStarted = await Task.detached {
            importer.waitUntilFirstImportStarts(timeout: 2)
        }.value
        guard firstImportStarted else {
            XCTFail("First import did not start")
            return
        }
        XCTAssertTrue(viewModel.isImporting)

        await viewModel.importFolder(URL(fileURLWithPath: "/tmp/SecondSource", isDirectory: true), mode: .mergeOverwrite)

        XCTAssertEqual(importer.callCount, 1)
        XCTAssertTrue(viewModel.isImporting)
        XCTAssertNil(viewModel.summary)
        XCTAssertTrue(store.savedSummaries.isEmpty)
        XCTAssertEqual(reloadCount, 0)

        importer.finishFirstImport()
        await firstImport.value

        XCTAssertFalse(viewModel.isImporting)
        XCTAssertEqual(viewModel.summary, expectedSummary)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(store.savedSummaries, [expectedSummary])
        XCTAssertEqual(reloadCount, 1)
    }

    private func makeSummary(folderName: String) -> FolderImportSummary {
        FolderImportSummary(
            folderName: folderName,
            fileCount: 2,
            totalBytes: 1234,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private final class BlockingFolderImporter: FolderImporting, @unchecked Sendable {
    private let result: FolderImportResult
    private let firstImportStarted = DispatchSemaphore(value: 0)
    private let finishFirstImportSemaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    init(result: FolderImportResult) {
        self.result = result
    }

    func importFolder(
        _ sourceDirectory: URL,
        mode: ImportMode,
        progress: (FolderImportProgress) -> Void
    ) throws -> FolderImportResult {
        let invocation = lock.withLock {
            storedCallCount += 1
            return storedCallCount
        }

        if invocation == 1 {
            firstImportStarted.signal()
            finishFirstImportSemaphore.wait()
        }

        return result
    }

    func waitUntilFirstImportStarts(timeout: TimeInterval) -> Bool {
        firstImportStarted.wait(timeout: .now() + timeout) == .success
    }

    func finishFirstImport() {
        finishFirstImportSemaphore.signal()
    }
}

private final class FakeFolderImporter: FolderImporting, @unchecked Sendable {
    var result: FolderImportResult
    var error: Error?
    var progressToReport: FolderImportProgress?
    private(set) var importedSourceDirectory: URL?
    private(set) var importedMode: ImportMode?
    private(set) var importedOnMainThread: Bool?

    init(
        result: FolderImportResult = FolderImportResult(
            items: [],
            summary: FolderImportSummary(
                folderName: "Default",
                fileCount: 0,
                totalBytes: 0,
                importedAt: Date(timeIntervalSince1970: 0)
            )
        ),
        error: Error? = nil
    ) {
        self.result = result
        self.error = error
    }

    func importFolder(
        _ sourceDirectory: URL,
        mode: ImportMode,
        progress: (FolderImportProgress) -> Void
    ) throws -> FolderImportResult {
        importedSourceDirectory = sourceDirectory
        importedMode = mode
        importedOnMainThread = Thread.isMainThread
        if let progressToReport {
            progress(progressToReport)
        }
        if let error {
            throw error
        }
        return result
    }
}

private final class FakeFolderImportSummaryStore: FolderImportSummaryStoring, @unchecked Sendable {
    var summary: FolderImportSummary?
    private(set) var loadCallCount = 0
    private(set) var savedSummaries: [FolderImportSummary] = []

    init(summary: FolderImportSummary? = nil) {
        self.summary = summary
    }

    func load() throws -> FolderImportSummary? {
        loadCallCount += 1
        return summary
    }

    func save(_ summary: FolderImportSummary) throws {
        savedSummaries.append(summary)
    }
}
