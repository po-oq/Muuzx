# Step 2: フォルダ取り込み Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Files/iCloud Drive の任意フォルダから mp3/m4a をアプリ専用領域へ取り込み、既存の一覧・再生機能で再生できるようにする。

**Architecture:** SwiftUI + MVVM。フォルダ選択は `FolderPicker` で SwiftUI に橋渡しし、コピー処理は `FolderImportService` に閉じ込める。前回取り込み情報と bookmark は小さなストアに分離し、再生位置/未再生状態の永続化は Step 4 に残す。

**Tech Stack:** Swift 5.9+, SwiftUI, UniformTypeIdentifiers, UIDocumentPickerViewController, XCTest, Xcode 16 / iOS 17+。

---

## 前提・環境

- 現在の作業ブランチは `codex/step2-folder-import-design`。
- Step 1 は `main` にマージ済みで、`AudioFolderPlayer` スキームが存在する。
- この環境では `iPhone 16` シミュレータの OS を明示する。
- テストコマンドは以下を基本にする。

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

## File Structure

このプランで作成・変更するファイルと責務。

| パス | 責務 |
|---|---|
| `AudioFolderPlayer/Infrastructure/FileSystem/AppDirectories.swift` | `audio/` に加え、`state/` と bookmark ファイル保存先を返す |
| `AudioFolderPlayer/Models/ImportMode.swift` | `replaceAll` / `mergeOverwrite` の取り込みモード |
| `AudioFolderPlayer/Models/FolderImportSummary.swift` | 前回取り込み表示用の summary |
| `AudioFolderPlayer/Services/FolderImportProgress.swift` | ファイル単位の取り込み進捗 |
| `AudioFolderPlayer/Services/FolderImportError.swift` | 取り込みエラーのユーザー向け文言 |
| `AudioFolderPlayer/Services/FolderImportSummaryStore.swift` | summary JSON の保存/復元 |
| `AudioFolderPlayer/Services/FolderImportService.swift` | フォルダ直下の mp3/m4a 列挙とローカルコピー |
| `AudioFolderPlayer/Infrastructure/FileSystem/FolderBookmarkStore.swift` | security-scoped bookmark の保存/復元 |
| `AudioFolderPlayer/Infrastructure/DocumentPicker/FolderPicker.swift` | UIDocumentPicker の SwiftUI wrapper |
| `AudioFolderPlayer/ViewModels/FolderViewModel.swift` | フォルダ画面状態、取り込み実行、一覧更新 |
| `AudioFolderPlayer/Views/FolderView.swift` | フォルダ画面、進捗、エラー、一覧導線 |
| `AudioFolderPlayer/App/AudioFolderPlayerApp.swift` | `FolderView` を入口にし、依存を組み立てる |
| `project.yml` | `Infrastructure/DocumentPicker` group を追加 |
| `AudioFolderPlayerTests/FolderImportSummaryStoreTests.swift` | summary store のテスト |
| `AudioFolderPlayerTests/FolderImportServiceTests.swift` | 取り込みサービスのテスト |
| `AudioFolderPlayerTests/FolderBookmarkStoreTests.swift` | bookmark store の保存/復元テスト |
| `AudioFolderPlayerTests/FolderViewModelTests.swift` | ViewModel の状態遷移テスト |
| `AudioFolderPlayerUITests/AudioFolderPlayerUITests.swift` | フォルダ画面から一覧へ進む UI smoke を追加 |

---

## Task 0: 保存先ディレクトリと project group を追加

**Files:**
- Modify: `AudioFolderPlayer/Infrastructure/FileSystem/AppDirectories.swift`
- Modify: `project.yml`

- [x] **Step 1: `AppDirectories` に state/bookmark 保存先を追加**

`AudioFolderPlayer/Infrastructure/FileSystem/AppDirectories.swift` を以下に置き換える。

```swift
import Foundation

enum AppDirectories {
    static let appFolderName = "AudioFolderPlayer"

    static func appSupportRoot(_ fm: FileManager = .default) throws -> URL {
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let url = base.appendingPathComponent(appFolderName, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func audioDirectory(_ fm: FileManager = .default) throws -> URL {
        let url = try appSupportRoot(fm).appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func stateDirectory(_ fm: FileManager = .default) throws -> URL {
        let url = try appSupportRoot(fm).appendingPathComponent("state", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func folderImportSummaryFile(_ fm: FileManager = .default) throws -> URL {
        try stateDirectory(fm).appendingPathComponent("folder-import-summary.json")
    }

    static func folderBookmarkFile(_ fm: FileManager = .default) throws -> URL {
        try stateDirectory(fm).appendingPathComponent("folder-bookmark.data")
    }
}
```

- [x] **Step 2: `project.yml` に DocumentPicker group を追加**

`groups:` に以下を追加する。

```yaml
  - AudioFolderPlayer/Infrastructure/DocumentPicker
```

- [x] **Step 3: Xcode project を再生成**

Run:

```bash
xcodegen generate
```

Expected: `Created project at .../AudioFolderPlayer.xcodeproj`

- [x] **Step 4: ビルド確認**

Run:

```bash
xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: `BUILD SUCCEEDED`

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Infrastructure/FileSystem/AppDirectories.swift project.yml AudioFolderPlayer.xcodeproj
git commit -m "chore: add folder import storage paths"
```

---

## Task 1: ImportMode / FolderImportSummary / SummaryStore（TDD）

**Files:**
- Create: `AudioFolderPlayer/Models/ImportMode.swift`
- Create: `AudioFolderPlayer/Models/FolderImportSummary.swift`
- Create: `AudioFolderPlayer/Services/FolderImportSummaryStore.swift`
- Test: `AudioFolderPlayerTests/FolderImportSummaryStoreTests.swift`

- [x] **Step 1: 失敗するテストを書く**

`AudioFolderPlayerTests/FolderImportSummaryStoreTests.swift` を作成する。

```swift
import XCTest
@testable import AudioFolderPlayer

final class FolderImportSummaryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("folder-import-summary.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_load_returnsNilWhenFileDoesNotExist() throws {
        let store = FolderImportSummaryStore(fileURL: fileURL)

        XCTAssertNil(try store.load())
    }

    func test_saveAndLoad_roundTripsSummary() throws {
        let store = FolderImportSummaryStore(fileURL: fileURL)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = FolderImportSummary(
            folderName: "AudioBooks",
            fileCount: 2,
            totalBytes: 1234,
            importedAt: date
        )

        try store.save(summary)

        XCTAssertEqual(try store.load(), summary)
    }
}
```

- [x] **Step 2: テストが失敗することを確認**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderImportSummaryStoreTests
```

Expected: `FolderImportSummaryStore` または `FolderImportSummary` 未定義で FAIL

- [x] **Step 3: モデルを作成**

`AudioFolderPlayer/Models/ImportMode.swift` を作成する。

```swift
import Foundation

enum ImportMode: Equatable {
    case replaceAll
    case mergeOverwrite
}
```

`AudioFolderPlayer/Models/FolderImportSummary.swift` を作成する。

```swift
import Foundation

struct FolderImportSummary: Codable, Equatable {
    var folderName: String
    var fileCount: Int
    var totalBytes: Int64
    var importedAt: Date
}
```

- [x] **Step 4: SummaryStore を実装**

`AudioFolderPlayer/Services/FolderImportSummaryStore.swift` を作成する。

```swift
import Foundation

struct FolderImportSummaryStore {
    let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL,
        fileManager: FileManager = .default,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() throws -> FolderImportSummary? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(FolderImportSummary.self, from: data)
    }

    func save(_ summary: FolderImportSummary) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(summary)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

- [x] **Step 5: テストが通ることを確認**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderImportSummaryStoreTests
```

Expected: `Executed 2 tests, with 0 failures`

- [x] **Step 6: コミット**

```bash
git add AudioFolderPlayer/Models/ImportMode.swift AudioFolderPlayer/Models/FolderImportSummary.swift AudioFolderPlayer/Services/FolderImportSummaryStore.swift AudioFolderPlayerTests/FolderImportSummaryStoreTests.swift
git commit -m "feat: add folder import summary store"
```

---

## Task 2: FolderImportService（TDD）

**Files:**
- Create: `AudioFolderPlayer/Services/FolderImportProgress.swift`
- Create: `AudioFolderPlayer/Services/FolderImportError.swift`
- Create: `AudioFolderPlayer/Services/FolderImportService.swift`
- Test: `AudioFolderPlayerTests/FolderImportServiceTests.swift`

- [x] **Step 1: 失敗するテストを書く**

`AudioFolderPlayerTests/FolderImportServiceTests.swift` を作成する。

```swift
import XCTest
@testable import AudioFolderPlayer

final class FolderImportServiceTests: XCTestCase {
    private var sourceDir: URL!
    private var audioDir: URL!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        sourceDir = root.appendingPathComponent("Source", isDirectory: true)
        audioDir = root.appendingPathComponent("Audio", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sourceDir.deletingLastPathComponent())
    }

    private func write(_ name: String, bytes: Int, in directory: URL? = nil) throws {
        let data = Data(repeating: UInt8(bytes % 255), count: bytes)
        try data.write(to: (directory ?? sourceDir).appendingPathComponent(name))
    }

    func test_importFolder_copiesOnlySupportedAudioFilesInNaturalOrder() throws {
        try write("track 10.mp3", bytes: 10)
        try write("track 2.m4a", bytes: 20)
        try write("notes.txt", bytes: 30)
        var progress: [FolderImportProgress] = []
        let service = FolderImportService(destinationDirectory: audioDir)

        let result = try service.importFolder(sourceDir, mode: .replaceAll) { progress.append($0) }

        XCTAssertEqual(result.items.map(\.fileName), ["track 2.m4a", "track 10.mp3"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("track 2.m4a").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("track 10.mp3").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("notes.txt").path))
        XCTAssertEqual(progress.map(\.completedFiles), [1, 2])
        XCTAssertEqual(progress.map(\.totalFiles), [2, 2])
        XCTAssertEqual(result.summary.folderName, "Source")
        XCTAssertEqual(result.summary.fileCount, 2)
        XCTAssertEqual(result.summary.totalBytes, 30)
    }

    func test_importFolder_throwsWhenNoSupportedAudioFilesExist() throws {
        try write("notes.txt", bytes: 30)
        let service = FolderImportService(destinationDirectory: audioDir)

        XCTAssertThrowsError(try service.importFolder(sourceDir, mode: .replaceAll)) { error in
            XCTAssertEqual(error as? FolderImportError, .noSupportedAudioFiles)
        }
    }

    func test_replaceAll_removesExistingAudioBeforeCopying() throws {
        try write("old.mp3", bytes: 9, in: audioDir)
        try write("new.mp3", bytes: 10)
        let service = FolderImportService(destinationDirectory: audioDir)

        _ = try service.importFolder(sourceDir, mode: .replaceAll)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("old.mp3").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("new.mp3").path))
    }

    func test_mergeOverwrite_keepsLocalOnlyFilesAndOverwritesSameName() throws {
        try write("local-only.mp3", bytes: 9, in: audioDir)
        try write("same.mp3", bytes: 5, in: audioDir)
        try write("same.mp3", bytes: 22)
        let service = FolderImportService(destinationDirectory: audioDir)

        _ = try service.importFolder(sourceDir, mode: .mergeOverwrite)

        let sameSize = try FileManager.default
            .attributesOfItem(atPath: audioDir.appendingPathComponent("same.mp3").path)[.size] as? Int
        XCTAssertEqual(sameSize, 22)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioDir.appendingPathComponent("local-only.mp3").path))
    }
}
```

- [x] **Step 2: テストが失敗することを確認**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderImportServiceTests
```

Expected: `FolderImportService` 未定義で FAIL

- [x] **Step 3: 進捗とエラー型を作成**

`AudioFolderPlayer/Services/FolderImportProgress.swift` を作成する。

```swift
import Foundation

struct FolderImportProgress: Equatable {
    var completedFiles: Int
    var totalFiles: Int
    var currentFileName: String
}
```

`AudioFolderPlayer/Services/FolderImportError.swift` を作成する。

```swift
import Foundation

enum FolderImportError: LocalizedError, Equatable {
    case noSupportedAudioFiles
    case sourceAccessDenied
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .noSupportedAudioFiles:
            return "対応音声ファイルが見つかりませんでした。"
        case .sourceAccessDenied:
            return "フォルダにアクセスできませんでした。"
        case .copyFailed(let fileName):
            return "\(fileName) のコピーに失敗しました。"
        }
    }
}
```

- [x] **Step 4: FolderImportService を実装**

`AudioFolderPlayer/Services/FolderImportService.swift` を作成する。

```swift
import Foundation

struct FolderImportResult: Equatable {
    var items: [AudioItem]
    var summary: FolderImportSummary
}

struct FolderImportService {
    let destinationDirectory: URL
    private let fileManager: FileManager

    init(destinationDirectory: URL, fileManager: FileManager = .default) {
        self.destinationDirectory = destinationDirectory
        self.fileManager = fileManager
    }

    func importFolder(
        _ sourceDirectory: URL,
        mode: ImportMode,
        progress: (FolderImportProgress) -> Void = { _ in }
    ) throws -> FolderImportResult {
        let accessed = sourceDirectory.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                sourceDirectory.stopAccessingSecurityScopedResource()
            }
        }

        guard fileManager.fileExists(atPath: sourceDirectory.path) else {
            throw FolderImportError.sourceAccessDenied
        }

        let sourceFiles = try supportedFiles(in: sourceDirectory)
        guard !sourceFiles.isEmpty else {
            throw FolderImportError.noSupportedAudioFiles
        }

        try prepareDestination(for: mode)

        var completed = 0
        for sourceURL in sourceFiles {
            let destinationURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                throw FolderImportError.copyFailed(sourceURL.lastPathComponent)
            }
            completed += 1
            progress(FolderImportProgress(
                completedFiles: completed,
                totalFiles: sourceFiles.count,
                currentFileName: sourceURL.lastPathComponent
            ))
        }

        let items = try LocalAudioLibrary(directory: destinationDirectory, fileManager: fileManager).loadItems()
        let importedNames = Set(sourceFiles.map(\.lastPathComponent))
        let importedItems = items.filter { importedNames.contains($0.fileName) }
        let summary = FolderImportSummary(
            folderName: sourceDirectory.lastPathComponent,
            fileCount: importedItems.count,
            totalBytes: importedItems.reduce(Int64(0)) { $0 + $1.fileSizeBytes },
            importedAt: Date()
        )
        return FolderImportResult(items: importedItems, summary: summary)
    }

    private func supportedFiles(in directory: URL) throws -> [URL] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        return try urls
            .filter { LocalAudioLibrary.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true
            }
            .sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
    }

    private func prepareDestination(for mode: ImportMode) throws {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        switch mode {
        case .replaceAll:
            let existing = try fileManager.contentsOfDirectory(
                at: destinationDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in existing {
                try fileManager.removeItem(at: url)
            }
        case .mergeOverwrite:
            break
        }
    }
}
```

- [x] **Step 5: テストが通ることを確認**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderImportServiceTests
```

Expected: `Executed 4 tests, with 0 failures`

- [x] **Step 6: コミット**

```bash
git add AudioFolderPlayer/Services/FolderImportProgress.swift AudioFolderPlayer/Services/FolderImportError.swift AudioFolderPlayer/Services/FolderImportService.swift AudioFolderPlayerTests/FolderImportServiceTests.swift
git commit -m "feat: add folder import service"
```

---

## Task 3: FolderBookmarkStore（TDD）

**Files:**
- Create: `AudioFolderPlayer/Infrastructure/FileSystem/FolderBookmarkStore.swift`
- Test: `AudioFolderPlayerTests/FolderBookmarkStoreTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`AudioFolderPlayerTests/FolderBookmarkStoreTests.swift` を作成する。

```swift
import XCTest
@testable import AudioFolderPlayer

final class FolderBookmarkStoreTests: XCTestCase {
    private var tempDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("folder-bookmark.data")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_loadData_returnsNilWhenFileDoesNotExist() throws {
        let store = FolderBookmarkStore(fileURL: fileURL)

        XCTAssertNil(try store.loadData())
    }

    func test_saveAndLoadData_roundTripsBookmarkData() throws {
        let store = FolderBookmarkStore(fileURL: fileURL)
        let data = Data([1, 2, 3, 4])

        try store.saveData(data)

        XCTAssertEqual(try store.loadData(), data)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderBookmarkStoreTests
```

Expected: `FolderBookmarkStore` 未定義で FAIL

- [ ] **Step 3: FolderBookmarkStore を実装**

`AudioFolderPlayer/Infrastructure/FileSystem/FolderBookmarkStore.swift` を作成する。

```swift
import Foundation

struct FolderBookmarkStore {
    let fileURL: URL
    private let fileManager: FileManager

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func loadData() throws -> Data? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        return try Data(contentsOf: fileURL)
    }

    func saveData(_ data: Data) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    func saveBookmark(for folderURL: URL) throws {
        let data = try folderURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try saveData(data)
    }

    func resolveBookmark() throws -> URL? {
        guard let data = try loadData() else {
            return nil
        }
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        return isStale ? nil : url
    }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderBookmarkStoreTests
```

Expected: `Executed 2 tests, with 0 failures`

- [ ] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Infrastructure/FileSystem/FolderBookmarkStore.swift AudioFolderPlayerTests/FolderBookmarkStoreTests.swift
git commit -m "feat: add folder bookmark store"
```

---

## Task 4: FolderViewModel（TDD）

**Files:**
- Create: `AudioFolderPlayer/ViewModels/FolderViewModel.swift`
- Test: `AudioFolderPlayerTests/FolderViewModelTests.swift`

- [ ] **Step 1: 失敗するテストを書く**

`AudioFolderPlayerTests/FolderViewModelTests.swift` を作成する。

```swift
import XCTest
@testable import AudioFolderPlayer

@MainActor
final class FolderViewModelTests: XCTestCase {
    func test_init_loadsSavedSummary() throws {
        let summary = FolderImportSummary(
            folderName: "AudioBooks",
            fileCount: 3,
            totalBytes: 999,
            importedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let store = FakeFolderImportSummaryStoring(summary: summary)

        let viewModel = FolderViewModel(
            importer: FakeFolderImporting(result: .success(FolderImportResult(items: [], summary: summary))),
            summaryStore: store,
            bookmarkStore: nil,
            reloadAudioList: {}
        )

        XCTAssertEqual(viewModel.summary, summary)
    }

    func test_importFolder_successUpdatesSummaryProgressAndReloadsList() async throws {
        let item = AudioItem(
            id: "track.mp3|10",
            fileName: "track.mp3",
            localURL: URL(fileURLWithPath: "/tmp/track.mp3"),
            fileSizeBytes: 10,
            durationSec: 0,
            positionSec: 0,
            status: .unplayed,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let summary = FolderImportSummary(
            folderName: "Source",
            fileCount: 1,
            totalBytes: 10,
            importedAt: Date(timeIntervalSince1970: 2)
        )
        let importer = FakeFolderImporting(result: .success(FolderImportResult(items: [item], summary: summary)))
        let store = FakeFolderImportSummaryStoring()
        var reloadCount = 0
        let viewModel = FolderViewModel(
            importer: importer,
            summaryStore: store,
            bookmarkStore: nil,
            reloadAudioList: { reloadCount += 1 }
        )

        await viewModel.importFolder(URL(fileURLWithPath: "/tmp/Source"))

        XCTAssertEqual(viewModel.summary, summary)
        XCTAssertEqual(store.savedSummary, summary)
        XCTAssertEqual(viewModel.progress?.completedFiles, 1)
        XCTAssertEqual(viewModel.progress?.totalFiles, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(reloadCount, 1)
    }

    func test_importFolder_errorSetsMessageAndDoesNotReload() async {
        let importer = FakeFolderImporting(result: .failure(FolderImportError.noSupportedAudioFiles))
        var reloadCount = 0
        let viewModel = FolderViewModel(
            importer: importer,
            summaryStore: FakeFolderImportSummaryStoring(),
            bookmarkStore: nil,
            reloadAudioList: { reloadCount += 1 }
        )

        await viewModel.importFolder(URL(fileURLWithPath: "/tmp/empty"))

        XCTAssertEqual(viewModel.errorMessage, "対応音声ファイルが見つかりませんでした。")
        XCTAssertEqual(reloadCount, 0)
        XCTAssertFalse(viewModel.isImporting)
    }
}

private final class FakeFolderImporting: FolderImporting {
    let result: Result<FolderImportResult, Error>

    init(result: Result<FolderImportResult, Error>) {
        self.result = result
    }

    func importFolder(
        _ sourceDirectory: URL,
        mode: ImportMode,
        progress: (FolderImportProgress) -> Void
    ) throws -> FolderImportResult {
        progress(FolderImportProgress(completedFiles: 1, totalFiles: 1, currentFileName: "track.mp3"))
        return try result.get()
    }
}

private final class FakeFolderImportSummaryStoring: FolderImportSummaryStoring {
    var summary: FolderImportSummary?
    var savedSummary: FolderImportSummary?

    init(summary: FolderImportSummary? = nil) {
        self.summary = summary
    }

    func load() throws -> FolderImportSummary? {
        summary
    }

    func save(_ summary: FolderImportSummary) throws {
        savedSummary = summary
        self.summary = summary
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderViewModelTests
```

Expected: `FolderViewModel` または `FolderImporting` 未定義で FAIL

- [ ] **Step 3: Protocol を既存サービスへ追加**

`AudioFolderPlayer/Services/FolderImportService.swift` の先頭付近に protocol を追加し、`FolderImportService` を適合させる。

```swift
protocol FolderImporting {
    func importFolder(
        _ sourceDirectory: URL,
        mode: ImportMode,
        progress: (FolderImportProgress) -> Void
    ) throws -> FolderImportResult
}
```

`struct FolderImportService` の宣言を以下に変更する。

```swift
struct FolderImportService: FolderImporting {
```

`AudioFolderPlayer/Services/FolderImportSummaryStore.swift` の先頭付近に protocol を追加し、store を適合させる。

```swift
protocol FolderImportSummaryStoring {
    func load() throws -> FolderImportSummary?
    func save(_ summary: FolderImportSummary) throws
}
```

`struct FolderImportSummaryStore` の宣言を以下に変更する。

```swift
struct FolderImportSummaryStore: FolderImportSummaryStoring {
```

- [ ] **Step 4: FolderViewModel を実装**

`AudioFolderPlayer/ViewModels/FolderViewModel.swift` を作成する。

```swift
import Foundation

@MainActor
final class FolderViewModel: ObservableObject {
    @Published private(set) var summary: FolderImportSummary?
    @Published private(set) var progress: FolderImportProgress?
    @Published private(set) var isImporting = false
    @Published var errorMessage: String?

    private let importer: FolderImporting
    private let summaryStore: FolderImportSummaryStoring
    private let bookmarkStore: FolderBookmarkStore?
    private let reloadAudioList: () -> Void

    init(
        importer: FolderImporting,
        summaryStore: FolderImportSummaryStoring,
        bookmarkStore: FolderBookmarkStore?,
        reloadAudioList: @escaping () -> Void
    ) {
        self.importer = importer
        self.summaryStore = summaryStore
        self.bookmarkStore = bookmarkStore
        self.reloadAudioList = reloadAudioList
        self.summary = try? summaryStore.load()
    }

    var hasImportedAudio: Bool {
        summary != nil
    }

    func importFolder(_ url: URL, mode: ImportMode = .replaceAll) async {
        isImporting = true
        errorMessage = nil
        progress = nil

        do {
            try bookmarkStore?.saveBookmark(for: url)
            let result = try importer.importFolder(url, mode: mode) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.progress = progress
                }
            }
            try summaryStore.save(result.summary)
            summary = result.summary
            reloadAudioList()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isImporting = false
    }
}
```

- [ ] **Step 5: テストが通ることを確認**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderViewModelTests
```

Expected: `Executed 3 tests, with 0 failures`

- [ ] **Step 6: 関連テストも確認**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/FolderImportServiceTests -only-testing:AudioFolderPlayerTests/FolderImportSummaryStoreTests
```

Expected: importer/store tests が PASS

- [ ] **Step 7: コミット**

```bash
git add AudioFolderPlayer/ViewModels/FolderViewModel.swift AudioFolderPlayer/Services/FolderImportService.swift AudioFolderPlayer/Services/FolderImportSummaryStore.swift AudioFolderPlayerTests/FolderViewModelTests.swift
git commit -m "feat: add FolderViewModel"
```

---

## Task 5: FolderPicker と FolderView

**Files:**
- Create: `AudioFolderPlayer/Infrastructure/DocumentPicker/FolderPicker.swift`
- Create: `AudioFolderPlayer/Views/FolderView.swift`

- [ ] **Step 1: FolderPicker を作成**

`AudioFolderPlayer/Infrastructure/DocumentPicker/FolderPicker.swift` を作成する。

```swift
import SwiftUI
import UniformTypeIdentifiers

struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
```

- [ ] **Step 2: FolderView を作成**

`AudioFolderPlayer/Views/FolderView.swift` を作成する。

```swift
import SwiftUI

struct FolderView: View {
    @ObservedObject var folderViewModel: FolderViewModel
    @ObservedObject var audioListViewModel: AudioListViewModel
    @State private var isShowingFolderPicker = false
    @State private var isShowingAudioList = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                summarySection
                actionSection
                Spacer()
            }
            .padding()
            .navigationTitle("フォルダ")
            .sheet(isPresented: $isShowingFolderPicker) {
                FolderPicker(
                    onPick: { url in
                        isShowingFolderPicker = false
                        Task {
                            await folderViewModel.importFolder(url)
                        }
                    },
                    onCancel: {
                        isShowingFolderPicker = false
                    }
                )
            }
            .alert("取り込みできませんでした", isPresented: errorBinding) {
                Button("OK") {
                    folderViewModel.errorMessage = nil
                }
            } message: {
                Text(folderViewModel.errorMessage ?? "")
            }
            .navigationDestination(isPresented: $isShowingAudioList) {
                AudioListView(viewModel: audioListViewModel)
            }
            .onAppear {
                audioListViewModel.load()
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("前回の取り込み元")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(folderViewModel.summary?.folderName ?? "未選択")
                    .font(.title3)
                    .fontWeight(.bold)

                if let summary = folderViewModel.summary {
                    Text("\(summary.fileCount)ファイル・\(ByteCountFormatter.string(fromByteCount: summary.totalBytes, countStyle: .file))")
                        .foregroundStyle(.secondary)
                    Text("最終取り込み: \(summary.importedAt.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                } else {
                    Text("音声フォルダを選択してください。")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                isShowingFolderPicker = true
            } label: {
                Label("別フォルダを選択", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(folderViewModel.isImporting)

            if folderViewModel.hasImportedAudio || !audioListViewModel.items.isEmpty {
                Button {
                    audioListViewModel.load()
                    isShowingAudioList = true
                } label: {
                    Label("一覧を開く", systemImage: "music.note.list")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if folderViewModel.isImporting {
                ProgressView(progressText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var progressText: String {
        guard let progress = folderViewModel.progress else {
            return "取り込み中..."
        }
        return "\(progress.completedFiles) / \(progress.totalFiles): \(progress.currentFileName)"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { folderViewModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    folderViewModel.errorMessage = nil
                }
            }
        )
    }
}
```

- [ ] **Step 3: ビルド確認**

Run:

```bash
xcodegen generate
xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: コミット**

```bash
git add AudioFolderPlayer/Infrastructure/DocumentPicker/FolderPicker.swift AudioFolderPlayer/Views/FolderView.swift
git commit -m "feat: add folder import UI"
```

---

## Task 6: アプリ入口を FolderView に接続

**Files:**
- Modify: `AudioFolderPlayer/App/AudioFolderPlayerApp.swift`

- [ ] **Step 1: App エントリを置き換える**

`AudioFolderPlayer/App/AudioFolderPlayerApp.swift` を以下に置き換える。

```swift
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
```

- [ ] **Step 2: ビルド確認**

Run:

```bash
xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: 全テスト確認**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: 全 unit/UI tests が PASS

- [ ] **Step 4: コミット**

```bash
git add AudioFolderPlayer/App/AudioFolderPlayerApp.swift
git commit -m "feat: show folder import screen at launch"
```

---

## Task 7: UI smoke と手動スモーク記録

**Files:**
- Modify: `AudioFolderPlayer/Views/FolderView.swift`
- Modify: `AudioFolderPlayerUITests/AudioFolderPlayerUITests.swift`
- Modify: `docs/superpowers/plans/2026-06-05-step2-folder-import.md`

- [ ] **Step 1: FolderView に UI テスト用 identifier を追加**

`AudioFolderPlayer/Views/FolderView.swift` に以下の identifier を追加する。

```swift
.accessibilityIdentifier("folder-summary-title")
```

これは前回取り込み元のフォルダ名 `Text` に付ける。

```swift
Text(folderViewModel.summary?.folderName ?? "未選択")
    .font(.title3)
    .fontWeight(.bold)
    .accessibilityIdentifier("folder-summary-title")
```

`別フォルダを選択` button に以下を付ける。

```swift
.accessibilityIdentifier("choose-folder-button")
```

`一覧を開く` button に以下を付ける。

```swift
.accessibilityIdentifier("open-audio-list-button")
```

- [ ] **Step 2: UI テストを FolderView 入口に合わせる**

`AudioFolderPlayerUITests/AudioFolderPlayerUITests.swift` を以下に置き換える。

```swift
import XCTest

final class AudioFolderPlayerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFolderScreenCanOpenAudioListAndUseMiniPlayerControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["folder-summary-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose-folder-button"].exists)

        let openListButton = app.buttons["open-audio-list-button"]
        XCTAssertTrue(openListButton.waitForExistence(timeout: 5))
        openListButton.tap()

        let firstSample = app.buttons["audio-row-sample-01.mp3"]
        let secondSample = app.buttons["audio-row-sample-02.mp3"]
        XCTAssertTrue(firstSample.waitForExistence(timeout: 5))
        XCTAssertTrue(secondSample.exists)

        firstSample.tap()

        XCTAssertTrue(app.images["current-item-speaker"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["mini-player-title"].label, "sample-01.mp3")

        let playPauseButton = app.buttons["play-pause-button"]
        XCTAssertTrue(playPauseButton.exists)
        playPauseButton.tap()
        playPauseButton.tap()

        app.buttons["skip-backward-button"].tap()
        app.buttons["skip-forward-button"].tap()
    }
}
```

- [ ] **Step 3: UI テストを実行**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerUITests/AudioFolderPlayerUITests/testFolderScreenCanOpenAudioListAndUseMiniPlayerControls
```

Expected: `Executed 1 test, with 0 failures`

- [ ] **Step 4: 全テストを実行**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: unit/UI tests がすべて PASS

- [ ] **Step 5: 手動スモークを実施**

シミュレータで以下を確認する。

1. アプリを起動すると `フォルダ` 画面が出る。
2. `別フォルダを選択` を押すと Files picker が出る。
3. mp3/m4a を含むフォルダを選択できる。
4. 取り込み進捗が表示される。
5. 取り込み完了後、前回取り込み情報が更新される。
6. `一覧を開く` で取り込み済みファイルが表示される。
7. ファイルをタップすると再生中表示とミニプレイヤーが更新される。

- [ ] **Step 6: スモーク結果を plan に追記**

`docs/superpowers/plans/2026-06-05-step2-folder-import.md` の末尾に以下の形式で結果を追記する。

```markdown
## Task 7 Smoke Result

- Full tests: PASS (`xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData`)
- UI smoke: PASS
- Manual folder import smoke: PASS
- Simulator: iPhone 16 / iOS 18.4
```

- [ ] **Step 7: コミット**

```bash
git add AudioFolderPlayer/Views/FolderView.swift AudioFolderPlayerUITests/AudioFolderPlayerUITests.swift docs/superpowers/plans/2026-06-05-step2-folder-import.md
git commit -m "test: add folder import smoke coverage"
```

---

## Task 8: Step 2 最終確認

**Files:**
- Modify: `docs/superpowers/plans/2026-06-05-step2-folder-import.md`

- [ ] **Step 1: 未完了チェックを確認**

Run:

```bash
rg -n "\\[ \\]" docs/superpowers/plans/2026-06-05-step2-folder-import.md
```

Expected: 実装完了時点では output なし。実装途中なら残タスクを確認する。

- [ ] **Step 2: 全テストを再実行**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 3: git status を確認**

Run:

```bash
git status --short --branch
```

Expected: `## codex/step2-folder-import-design` のみ、未コミット差分なし。

- [ ] **Step 4: 完了コミットが揃っていることを確認**

Run:

```bash
git log --oneline -8
```

Expected: Task 0 から Task 7 までのコミットが含まれる。
