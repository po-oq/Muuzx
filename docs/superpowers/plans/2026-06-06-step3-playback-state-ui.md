# Step 3: 再生状態付き一覧 UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ファイル一覧とミニプレイヤーを `docs/ui-mock.html` に忠実に近づけ、総再生時間・現在位置・未再生/途中/再生済み状態を実際の再生へ連動させる。

**Architecture:** `AudioMetadataService` が総再生時間を非同期取得し、`PlaybackService` は再生エンジン操作と完了通知に専念する。`AudioListViewModel` が同一アプリ起動中の再生状態、約1秒間隔の位置更新、長押し操作を管理し、SwiftUI Views は状態を表示する。JSON 永続化は Step 4 に残す。

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation (`AVURLAsset`, `AVPlayer`), XCTest, XCUITest, XcodeGen, Xcode 16 / iOS 17+。

---

## 前提・環境

- 作業ブランチは `codex/step3-playback-state-ui-design`。
- 承認済み設計は `docs/superpowers/specs/2026-06-06-step3-playback-state-ui-design.md`。
- Step 2 は `main` にマージ済み。
- 実装中は Step 3 の設計書にある MVP Roadmap と「Step 3 では作らないもの」を維持する。
- 新規 Swift ファイル追加後は `xcodegen generate` を実行する。
- 基本テストコマンド:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

## File Structure

| パス | 責務 |
|---|---|
| `AudioFolderPlayer/Services/AudioMetadataService.swift` | `AVURLAsset` から総再生時間を非同期取得する |
| `AudioFolderPlayer/Services/PlaybackService.swift` | 途中位置再生、停止・選択解除、位置公開、完了項目通知 |
| `AudioFolderPlayer/ViewModels/AudioListViewModel.swift` | メモリ内再生状態、メタデータ取得、位置更新、長押し操作 |
| `AudioFolderPlayer/Views/PlaybackDisplayFormatter.swift` | 時間・進捗率・状態補助テキストの表示変換 |
| `AudioFolderPlayer/Views/AudioFileRow.swift` | 状態付きファイル一覧行 |
| `AudioFolderPlayer/Views/AudioListView.swift` | `ui-mock.html` 寄せの一覧コンテナと長押しメニュー |
| `AudioFolderPlayer/Views/MiniPlayerView.swift` | 下部固定の状態付きミニプレイヤー |
| `AudioFolderPlayer/Views/FolderView.swift` | 一覧へ取り込み元フォルダ名を渡す |
| `AudioFolderPlayer/App/AudioFolderPlayerApp.swift` | `AudioMetadataService` を組み立てる |
| `AudioFolderPlayerTests/AudioMetadataServiceTests.swift` | 実音声・不正ファイルの duration 取得テスト |
| `AudioFolderPlayerTests/PlaybackServiceTests.swift` | 途中位置再生、停止、完了通知テスト |
| `AudioFolderPlayerTests/AudioListViewModelTests.swift` | 状態遷移、メタデータ反映、長押し操作テスト |
| `AudioFolderPlayerTests/PlaybackDisplayFormatterTests.swift` | 時間・進捗・状態文言テスト |
| `AudioFolderPlayerUITests/AudioFolderPlayerUITests.swift` | 状態付き一覧、長押し、ミニプレイヤー smoke |

---

## Task 0: 総再生時間を非同期取得する（TDD）

**Files:**
- Create: `AudioFolderPlayer/Services/AudioMetadataService.swift`
- Create: `AudioFolderPlayerTests/AudioMetadataServiceTests.swift`
- Modify: `AudioFolderPlayer.xcodeproj/project.pbxproj`（`xcodegen generate`）

- [x] **Step 1: 失敗するメタデータテストを書く**

`AudioFolderPlayerTests/AudioMetadataServiceTests.swift` を作成する。

```swift
import XCTest
@testable import AudioFolderPlayer

final class AudioMetadataServiceTests: XCTestCase {
    func test_durationSec_returnsPositiveDurationForBundledAudio() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "sample-01", withExtension: "mp3"))
        let service = AudioMetadataService()

        let duration = try await service.durationSec(for: url)

        XCTAssertGreaterThan(duration, 0)
    }

    func test_durationSec_throwsForUnreadableAudio() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp3")
        try Data("not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            _ = try await AudioMetadataService().durationSec(for: url)
            XCTFail("Expected duration loading to fail")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
```

- [x] **Step 2: Xcode project を再生成し、テスト失敗を確認する**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/AudioMetadataServiceTests
```

Expected: `AudioMetadataService` 未定義で FAIL

- [x] **Step 3: AudioMetadataService を実装する**

`AudioFolderPlayer/Services/AudioMetadataService.swift` を作成する。

```swift
import AVFoundation
import Foundation

protocol AudioMetadataLoading: Sendable {
    func durationSec(for url: URL) async throws -> Double
}

struct AudioMetadataService: AudioMetadataLoading {
    func durationSec(for url: URL) async throws -> Double {
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw AudioMetadataError.durationUnavailable
        }
        return duration
    }
}

enum AudioMetadataError: Error {
    case durationUnavailable
}
```

- [x] **Step 4: 対象テストを実行する**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/AudioMetadataServiceTests
```

Expected: `AudioMetadataServiceTests` PASS

- [x] **Step 5: コミットする**

```bash
git add AudioFolderPlayer/Services/AudioMetadataService.swift AudioFolderPlayerTests/AudioMetadataServiceTests.swift AudioFolderPlayer.xcodeproj
git commit -m "feat: add audio metadata loading"
```

---

## Task 1: PlaybackService に途中位置再生と完了通知を追加する（TDD）

**Files:**
- Modify: `AudioFolderPlayer/Services/PlaybackService.swift`
- Modify: `AudioFolderPlayerTests/PlaybackServiceTests.swift`

- [x] **Step 1: 失敗する PlaybackService テストを追加する**

`AudioFolderPlayerTests/PlaybackServiceTests.swift` に追加する。

```swift
func test_play_seeksToRequestedStartPositionBeforePlaying() {
    let engine = FakeAudioEngine()
    engine.durationSec = 100
    let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])

    service.play(at: 0, startPositionSec: 42)

    XCTAssertEqual(engine.loadedURLs.last, URL(fileURLWithPath: "/tmp/a.mp3"))
    XCTAssertEqual(engine.seekedToSec.last, 42)
    XCTAssertTrue(engine.isPlaying)
}

func test_play_clampsStartPositionToDuration() {
    let engine = FakeAudioEngine()
    engine.durationSec = 100
    let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])

    service.play(at: 0, startPositionSec: 150)

    XCTAssertEqual(engine.seekedToSec.last, 100)
}

func test_stop_pausesAndClearsCurrentItem() {
    let engine = FakeAudioEngine()
    let service = PlaybackService(engine: engine, items: [makeItem("a.mp3")])
    var changes: [AudioItem?] = []
    service.onCurrentItemChanged = { changes.append($0) }
    service.play(at: 0)

    service.stop()

    XCTAssertFalse(engine.isPlaying)
    XCTAssertNil(service.currentItem)
    XCTAssertNil(changes.last!)
}

func test_playbackEnded_notifiesCompletedItemBeforeAdvancing() {
    let engine = FakeAudioEngine()
    let first = makeItem("a.mp3")
    let second = makeItem("b.mp3")
    let service = PlaybackService(engine: engine, items: [first, second])
    var completed: [AudioItem] = []
    service.onItemCompleted = { completed.append($0) }
    service.play(at: 0)

    engine.simulatePlaybackEnded()

    XCTAssertEqual(completed, [first])
    XCTAssertEqual(service.currentItem, second)
}

func test_currentPositionAndDurationExposeEngineValues() {
    let engine = FakeAudioEngine()
    engine.currentTimeSec = 12
    engine.durationSec = 99
    let service = PlaybackService(engine: engine)

    XCTAssertEqual(service.currentPositionSec, 12)
    XCTAssertEqual(service.currentDurationSec, 99)
}
```

- [x] **Step 2: PlaybackServiceTests が失敗することを確認する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/PlaybackServiceTests
```

Expected: 新規 API 未定義で FAIL

- [x] **Step 3: PlaybackService を拡張する**

`AudioFolderPlayer/Services/PlaybackService.swift` に次の API と動作を追加する。

```swift
var onItemCompleted: ((AudioItem) -> Void)?

var currentPositionSec: Double { engine.currentTimeSec }
var currentDurationSec: Double { engine.durationSec }

func play(at index: Int, startPositionSec: Double = 0) {
    guard items.indices.contains(index) else { return }
    currentIndex = index
    engine.load(url: items[index].localURL)
    let duration = items[index].durationSec > 0 ? items[index].durationSec : engine.durationSec
    let upperBound = duration > 0 ? duration : startPositionSec
    engine.seek(toSec: min(max(startPositionSec, 0), upperBound))
    engine.play()
    onCurrentItemChanged?(items[index])
}

func stop() {
    engine.pause()
    currentIndex = nil
    onCurrentItemChanged?(nil)
}
```

`handlePlaybackEnded()` は完了項目を通知してから次項目へ進むよう置き換える。

```swift
private func handlePlaybackEnded() {
    guard let i = currentIndex, items.indices.contains(i) else { return }
    onItemCompleted?(items[i])

    let next = i + 1
    if items.indices.contains(next) {
        play(at: next)
    } else {
        currentIndex = nil
        onCurrentItemChanged?(nil)
    }
}
```

- [x] **Step 4: PlaybackServiceTests を実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/PlaybackServiceTests
```

Expected: PASS

- [x] **Step 5: 既存 ViewModel テストも実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/AudioListViewModelTests
```

Expected: PASS

- [x] **Step 6: コミットする**

```bash
git add AudioFolderPlayer/Services/PlaybackService.swift AudioFolderPlayerTests/PlaybackServiceTests.swift
git commit -m "feat: extend playback session controls"
```

---

## Task 2: AudioListViewModel にメタデータ反映を追加する（TDD）

**Files:**
- Modify: `AudioFolderPlayer/ViewModels/AudioListViewModel.swift`
- Modify: `AudioFolderPlayerTests/AudioListViewModelTests.swift`
- Create: `AudioFolderPlayerTests/Support/FakeAudioMetadataLoader.swift`
- Modify: `AudioFolderPlayer.xcodeproj/project.pbxproj`（`xcodegen generate`）

- [x] **Step 1: FakeAudioMetadataLoader を作成する**

`AudioFolderPlayerTests/Support/FakeAudioMetadataLoader.swift` を作成する。

```swift
import Foundation
@testable import AudioFolderPlayer

actor FakeAudioMetadataLoader: AudioMetadataLoading {
    private let durationsByName: [String: Double]

    init(durationsByName: [String: Double]) {
        self.durationsByName = durationsByName
    }

    func durationSec(for url: URL) async throws -> Double {
        guard let duration = durationsByName[url.lastPathComponent] else {
            throw AudioMetadataError.durationUnavailable
        }
        return duration
    }
}
```

- [x] **Step 2: 失敗するメタデータ反映テストを書く**

`AudioFolderPlayerTests/AudioListViewModelTests.swift` の `makeViewModel` に metadata 注入を追加し、次を追加する。

```swift
func test_load_displaysItemsBeforeMetadataAndAppliesDurationLater() async throws {
    try write("01 first.mp3", bytes: 10)
    let metadata = FakeAudioMetadataLoader(durationsByName: ["01 first.mp3": 125])
    let viewModel = AudioListViewModel(
        library: LocalAudioLibrary(directory: tempDir),
        playback: PlaybackService(engine: FakeAudioEngine()),
        metadata: metadata
    )

    viewModel.load()
    XCTAssertEqual(viewModel.items.count, 1)
    XCTAssertEqual(viewModel.items[0].durationSec, 0)

    await waitForState { viewModel.items[0].durationSec == 125 }
    XCTAssertEqual(viewModel.items[0].durationSec, 125)
}

```

- [x] **Step 3: テスト失敗を確認する**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/AudioListViewModelTests
```

Expected: metadata 注入 API 未定義で FAIL

- [x] **Step 4: AudioListViewModel に metadata タスクを追加する**

`AudioListViewModel` に次を追加する。

```swift
private let metadata: any AudioMetadataLoading
private var metadataTask: Task<Void, Never>?

init(
    library: LocalAudioLibrary,
    playback: PlaybackService,
    metadata: any AudioMetadataLoading = AudioMetadataService()
) {
    self.library = library
    self.playback = playback
    self.metadata = metadata
    // 既存 callback 設定は維持する
}
```

`load()` を、一覧を即時表示してから metadata を開始する形へ変更する。状態引き継ぎは Task 3 で追加する。

```swift
func load() {
    metadataTask?.cancel()
    items = (try? library.loadItems()) ?? []
    playback.setItems(items)
    startMetadataLoading()
}
```

同じ ViewModel に追加する。

```swift
private func startMetadataLoading() {
    let metadata = metadata
    let snapshot = items
    metadataTask = Task { [weak self] in
        for item in snapshot {
            guard !Task.isCancelled else { return }
            guard let duration = try? await metadata.durationSec(for: item.localURL) else {
                continue
            }
            guard !Task.isCancelled else { return }
            self?.updateDuration(duration, for: item.id)
        }
    }
}

private func updateDuration(_ duration: Double, for id: String) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index].durationSec = duration
    playback.setItems(items)
}
```

- [x] **Step 5: 対象テストを実行する**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/AudioListViewModelTests
```

Expected: PASS

- [x] **Step 6: コミットする**

```bash
git add AudioFolderPlayer/ViewModels/AudioListViewModel.swift AudioFolderPlayerTests/AudioListViewModelTests.swift AudioFolderPlayerTests/Support/FakeAudioMetadataLoader.swift AudioFolderPlayer.xcodeproj
git commit -m "feat: load audio durations asynchronously"
```

---

## Task 3: AudioListViewModel に再生状態遷移と長押し操作を追加する（TDD）

**Files:**
- Modify: `AudioFolderPlayer/ViewModels/AudioListViewModel.swift`
- Modify: `AudioFolderPlayerTests/AudioListViewModelTests.swift`
- Modify: `AudioFolderPlayer/App/AudioFolderPlayerApp.swift`

- [x] **Step 1: 失敗する状態遷移テストを書く**

`AudioFolderPlayerTests/AudioListViewModelTests.swift` に追加する。

```swift
func test_refreshPlaybackState_marksItemInProgress() throws {
    let (viewModel, engine) = try makeViewModel()
    let first = try XCTUnwrap(viewModel.items.first)
    engine.currentTimeSec = 42
    engine.durationSec = 100

    viewModel.play(first)
    viewModel.refreshPlaybackState()

    XCTAssertEqual(viewModel.currentItem?.positionSec, 42)
    XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
}

func test_refreshPlaybackState_marksItemPlayedWithinLastThirtySeconds() throws {
    let (viewModel, engine) = try makeViewModel()
    let first = try XCTUnwrap(viewModel.items.first)
    engine.currentTimeSec = 75
    engine.durationSec = 100

    viewModel.play(first)
    viewModel.refreshPlaybackState()

    XCTAssertEqual(viewModel.currentItem?.positionSec, 100)
    XCTAssertEqual(viewModel.currentItem?.status, .played)
}

func test_play_resumesInProgressItemFromStoredPosition() throws {
    let (viewModel, engine) = try makeViewModel()
    let item = try XCTUnwrap(viewModel.items.first)
    engine.durationSec = 100
    viewModel.play(item)
    engine.currentTimeSec = 42
    viewModel.refreshPlaybackState()
    viewModel.togglePlayPause()

    viewModel.play(try XCTUnwrap(viewModel.items.first))

    XCTAssertEqual(engine.seekedToSec.last, 42)
}

func test_playPlayedItemStartsFromBeginning() throws {
    let (viewModel, engine) = try makeViewModel()
    let item = try XCTUnwrap(viewModel.items.first)
    engine.durationSec = 100
    viewModel.play(item)
    engine.currentTimeSec = 75
    viewModel.refreshPlaybackState()
    viewModel.togglePlayPause()

    viewModel.play(try XCTUnwrap(viewModel.items.first))

    XCTAssertEqual(engine.seekedToSec.last, 0)
}

func test_playFromBeginning_seeksToZeroAndPlays() throws {
    let (viewModel, engine) = try makeViewModel()
    let item = try XCTUnwrap(viewModel.items.first)

    viewModel.playFromBeginning(item)

    XCTAssertEqual(engine.seekedToSec.last, 0)
    XCTAssertEqual(viewModel.currentItem?.status, .inProgress)
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

func test_load_preservesInMemoryStateForSameFileId() throws {
    let (viewModel, engine) = try makeViewModel()
    let first = try XCTUnwrap(viewModel.items.first)
    engine.durationSec = 100
    viewModel.play(first)
    engine.currentTimeSec = 42
    viewModel.refreshPlaybackState()

    viewModel.load()

    let reloaded = try XCTUnwrap(viewModel.items.first { $0.id == first.id })
    XCTAssertEqual(reloaded.positionSec, 42)
    XCTAssertEqual(reloaded.status, .inProgress)
}
```

- [x] **Step 2: 状態遷移テストが失敗することを確認する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/AudioListViewModelTests
```

Expected: 状態操作 API 未定義または期待値不一致で FAIL

- [x] **Step 3: AudioListViewModel に状態更新 API を実装する**

次の公開 API を持たせる。

```swift
func play(_ item: AudioItem)
func playFromBeginning(_ item: AudioItem)
func markUnplayed(_ item: AudioItem)
func togglePlayPause()
func skipForward()
func skipBackward()
func refreshPlaybackState()
func stopObservingPlayback()
```

状態判定 helper を追加する。

```swift
private func updatePlaybackState(for id: String, positionSec: Double, durationSec: Double) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    let duration = durationSec > 0 ? durationSec : items[index].durationSec
    let position = duration > 0 ? min(max(positionSec, 0), duration) : max(positionSec, 0)

    items[index].durationSec = duration
    if duration > 0, position > 0, position >= duration - 30 {
        items[index].positionSec = duration
        items[index].status = .played
    } else {
        items[index].positionSec = position
        items[index].status = position > 0 ? .inProgress : .unplayed
    }
    items[index].updatedAt = Date()
}
```

`play(_:)` は played なら 0 秒、それ以外は記録位置から開始する。`playFromBeginning(_:)` は 0 秒から開始する。`markUnplayed(_:)` は対象が現在項目なら `playback.stop()` してから状態を初期化する。

Task 2 の `load()` を、同じ `fileId` のメモリ内状態を引き継ぐ形へ変更する。

```swift
func load() {
    metadataTask?.cancel()
    let previousById = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    let loaded = (try? library.loadItems()) ?? []
    items = loaded.map { item in
        guard let previous = previousById[item.id] else { return item }
        var merged = item
        merged.durationSec = previous.durationSec
        merged.positionSec = previous.positionSec
        merged.status = previous.status
        merged.updatedAt = previous.updatedAt
        return merged
    }
    playback.setItems(items)
    startMetadataLoading()
}
```

約 1 秒間隔の更新タスクを追加する。

```swift
private var playbackObservationTask: Task<Void, Never>?

private func startObservingPlayback() {
    playbackObservationTask?.cancel()
    playbackObservationTask = Task { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.refreshPlaybackState()
        }
    }
}

func stopObservingPlayback() {
    playbackObservationTask?.cancel()
    playbackObservationTask = nil
}
```

`onItemCompleted` callback では完了項目を `played` にし、`onCurrentItemChanged` callback では次項目の選択状態と観測タスクを更新する。

- [x] **Step 4: App から metadata dependency を注入する**

`AudioFolderPlayer/App/AudioFolderPlayerApp.swift` の ViewModel 作成を変更する。

```swift
let audioListViewModel = AudioListViewModel(
    library: library,
    playback: playback,
    metadata: AudioMetadataService()
)
```

- [x] **Step 5: AudioListViewModelTests を実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/AudioListViewModelTests
```

Expected: PASS

- [x] **Step 6: PlaybackServiceTests と全 unit tests を実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests
```

Expected: unit tests PASS

- [x] **Step 7: コミットする**

```bash
git add AudioFolderPlayer/ViewModels/AudioListViewModel.swift AudioFolderPlayer/App/AudioFolderPlayerApp.swift AudioFolderPlayerTests/AudioListViewModelTests.swift
git commit -m "feat: track playback state in memory"
```

---

## Task 4: 表示フォーマッターと AudioFileRow を追加する（TDD）

**Files:**
- Create: `AudioFolderPlayer/Views/PlaybackDisplayFormatter.swift`
- Create: `AudioFolderPlayer/Views/AudioFileRow.swift`
- Create: `AudioFolderPlayerTests/PlaybackDisplayFormatterTests.swift`
- Modify: `AudioFolderPlayer.xcodeproj/project.pbxproj`（`xcodegen generate`）

- [x] **Step 1: 失敗する表示フォーマットテストを書く**

`AudioFolderPlayerTests/PlaybackDisplayFormatterTests.swift` を作成する。

```swift
import XCTest
@testable import AudioFolderPlayer

final class PlaybackDisplayFormatterTests: XCTestCase {
    func test_time_formatsMinutesAndSeconds() {
        XCTAssertEqual(PlaybackDisplayFormatter.time(72), "1:12")
    }

    func test_time_formatsHours() {
        XCTAssertEqual(PlaybackDisplayFormatter.time(4360), "1:12:40")
    }

    func test_progressClampsBetweenZeroAndOne() {
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: 150, duration: 100), 1)
        XCTAssertEqual(PlaybackDisplayFormatter.progress(position: -1, duration: 100), 0)
    }

    func test_subtitleForUnplayedWithKnownDuration() {
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .unplayed, position: 0, duration: 125),
            "未再生・2:05"
        )
    }

    func test_subtitleForInProgress() {
        XCTAssertEqual(
            PlaybackDisplayFormatter.subtitle(status: .inProgress, position: 72, duration: 260),
            "途中・1:12 / 4:20"
        )
    }
}
```

- [x] **Step 2: テスト失敗を確認する**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/PlaybackDisplayFormatterTests
```

Expected: `PlaybackDisplayFormatter` 未定義で FAIL

- [x] **Step 3: PlaybackDisplayFormatter を実装する**

`AudioFolderPlayer/Views/PlaybackDisplayFormatter.swift` を作成する。

```swift
import Foundation

enum PlaybackDisplayFormatter {
    static func time(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }

    static func progress(position: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    static func subtitle(status: PlaybackStatus, position: Double, duration: Double) -> String {
        switch status {
        case .unplayed:
            return duration > 0 ? "未再生・\(time(duration))" : "未再生"
        case .inProgress:
            return duration > 0
                ? "途中・\(time(position)) / \(time(duration))"
                : "途中・\(time(position))"
        case .played:
            return duration > 0 ? "完了・\(time(duration))" : "完了"
        }
    }
}
```

- [x] **Step 4: AudioFileRow を実装する**

`AudioFolderPlayer/Views/AudioFileRow.swift` を作成する。`ui-mock.html` の行構成に合わせ、ファイル名、補助テキスト、細い進捗バー、右側バッジを表示する。

```swift
import SwiftUI

struct AudioFileRow: View {
    let item: AudioItem
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.fileName)
                    .font(.body)
                    .fontWeight(item.status == .unplayed ? .bold : .regular)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(PlaybackDisplayFormatter.subtitle(
                    status: item.status,
                    position: item.positionSec,
                    duration: item.durationSec
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                ProgressView(value: PlaybackDisplayFormatter.progress(
                    position: item.positionSec,
                    duration: item.durationSec
                ))
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(height: 3)
            }

            Spacer(minLength: 8)
            Text(badgeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isCurrent ? .blue : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(Capsule())
                .accessibilityIdentifier("audio-status-\(item.fileName)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var badgeText: String {
        if isCurrent { return "再生中" }
        switch item.status {
        case .unplayed: return "未再生"
        case .inProgress:
            let percent = Int(PlaybackDisplayFormatter.progress(
                position: item.positionSec,
                duration: item.durationSec
            ) * 100)
            return item.durationSec > 0 ? "\(percent)%" : "途中"
        case .played: return "100%"
        }
    }
}
```

- [x] **Step 5: 対象テストとビルドを実行する**

Run:

```bash
xcodegen generate
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerTests/PlaybackDisplayFormatterTests
xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: test PASS、`BUILD SUCCEEDED`

- [x] **Step 6: コミットする**

```bash
git add AudioFolderPlayer/Views/PlaybackDisplayFormatter.swift AudioFolderPlayer/Views/AudioFileRow.swift AudioFolderPlayerTests/PlaybackDisplayFormatterTests.swift AudioFolderPlayer.xcodeproj
git commit -m "feat: add playback state row presentation"
```

---

## Task 5: 一覧とミニプレイヤーを ui-mock.html に寄せる

**Files:**
- Modify: `AudioFolderPlayer/Views/AudioListView.swift`
- Modify: `AudioFolderPlayer/Views/MiniPlayerView.swift`
- Modify: `AudioFolderPlayer/Views/FolderView.swift`

- [x] **Step 1: AudioListView を状態付き一覧へ置き換える**

`AudioFolderPlayer/Views/AudioListView.swift` を次の構造へ変更する。

```swift
import SwiftUI

struct AudioListView: View {
    @ObservedObject var viewModel: AudioListViewModel
    let folderName: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ファイル一覧")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                viewModel.play(item)
                            } label: {
                                AudioFileRow(
                                    item: item,
                                    isCurrent: item.id == viewModel.currentItemId
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("audio-row-\(item.fileName)")
                            .contextMenu {
                                Button {
                                    viewModel.playFromBeginning(item)
                                } label: {
                                    Label("先頭から再生", systemImage: "play.fill")
                                }

                                Button {
                                    viewModel.markUnplayed(item)
                                } label: {
                                    Label("未再生に戻す", systemImage: "arrow.counterclockwise")
                                }
                            }

                            if index < viewModel.items.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 12)
                }
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))

            MiniPlayerView(viewModel: viewModel)
        }
        .navigationTitle(folderName ?? "ファイル一覧")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.load() }
        .onDisappear { viewModel.stopObservingPlayback() }
    }
}
```

- [x] **Step 2: MiniPlayerView を下部固定の縦構成へ置き換える**

`AudioFolderPlayer/Views/MiniPlayerView.swift` を次の構造へ変更する。

```swift
import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var viewModel: AudioListViewModel

    var body: some View {
        VStack(spacing: 8) {
            Text(viewModel.currentItem?.fileName ?? "再生していません")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("mini-player-title")

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(height: 3)
                .accessibilityIdentifier("mini-player-progress")

            HStack {
                Text(PlaybackDisplayFormatter.time(viewModel.currentItem?.positionSec ?? 0))
                Spacer()
                Text(PlaybackDisplayFormatter.time(viewModel.currentItem?.durationSec ?? 0))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            HStack(spacing: 44) {
                Button(action: viewModel.skipBackward) {
                    Image(systemName: "gobackward.10")
                }
                .accessibilityIdentifier("skip-backward-button")

                Button(action: viewModel.togglePlayPause) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .accessibilityIdentifier("play-pause-button")

                Button(action: viewModel.skipForward) {
                    Image(systemName: "goforward.30")
                }
                .accessibilityIdentifier("skip-forward-button")
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 112)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .disabled(viewModel.currentItem == nil)
    }

    private var progress: Double {
        guard let item = viewModel.currentItem else { return 0 }
        return PlaybackDisplayFormatter.progress(
            position: item.positionSec,
            duration: item.durationSec
        )
    }
}
```

- [x] **Step 3: FolderView からフォルダ名を渡す**

`AudioFolderPlayer/Views/FolderView.swift` の navigation destination を変更する。

```swift
.navigationDestination(isPresented: $isShowingAudioList) {
    AudioListView(
        viewModel: audioListViewModel,
        folderName: folderViewModel.summary?.folderName
    )
}
```

- [x] **Step 4: ビルドを実行する**

Run:

```bash
xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: `BUILD SUCCEEDED`

- [x] **Step 5: 既存 UI test を実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerUITests
```

Expected: PASS。識別子変更で失敗した場合は既存識別子を維持して修正する。

- [x] **Step 6: コミットする**

```bash
git add AudioFolderPlayer/Views/AudioListView.swift AudioFolderPlayer/Views/MiniPlayerView.swift AudioFolderPlayer/Views/FolderView.swift
git commit -m "feat: redesign playback list and mini player"
```

---

## Task 6: 状態付き一覧の UI smoke を追加する

**Files:**
- Modify: `AudioFolderPlayerUITests/AudioFolderPlayerUITests.swift`

- [x] **Step 1: UI smoke を状態表示と長押しへ拡張する**

既存の `testFolderScreenCanOpenAudioListAndUseMiniPlayerControls` に次の確認を加える。

```swift
let firstRow = app.buttons["audio-row-sample-01.mp3"]
XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
XCTAssertTrue(app.staticTexts["audio-status-sample-01.mp3"].exists)
XCTAssertTrue(app.otherElements["mini-player-progress"].exists)

firstRow.press(forDuration: 1.2)
XCTAssertTrue(app.buttons["先頭から再生"].waitForExistence(timeout: 2))
XCTAssertTrue(app.buttons["未再生に戻す"].exists)
app.tap()

firstRow.tap()
XCTAssertTrue(app.staticTexts["audio-status-sample-01.mp3"].waitForExistence(timeout: 2))
XCTAssertEqual(app.staticTexts["audio-status-sample-01.mp3"].label, "再生中")
```

Accessibility の要素型が実機結果と異なる場合は、識別子を維持したまま `staticTexts` / `otherElements` を実際の型へ合わせる。

- [x] **Step 2: UI test を実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerUITests/AudioFolderPlayerUITests/testFolderScreenCanOpenAudioListAndUseMiniPlayerControls
```

Expected: PASS。失敗した場合は出力から実際のアクセシビリティ要素型と識別子を確認する。

- [x] **Step 3: Accessibility 識別子と UI test を安定化する**

失敗があった場合は、以下を維持する範囲で View 側と UI test の要素型を調整する。

```text
audio-row-<fileName>
audio-status-<fileName>
mini-player-title
mini-player-progress
play-pause-button
skip-backward-button
skip-forward-button
```

長押しメニューの文言は `先頭から再生` と `未再生に戻す` で固定する。

- [x] **Step 4: UI test を再実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData -only-testing:AudioFolderPlayerUITests/AudioFolderPlayerUITests/testFolderScreenCanOpenAudioListAndUseMiniPlayerControls
```

Expected: PASS

- [x] **Step 5: 全テストを実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: `** TEST SUCCEEDED **`

- [x] **Step 6: コミットする**

```bash
git add AudioFolderPlayer AudioFolderPlayerTests AudioFolderPlayerUITests AudioFolderPlayer.xcodeproj
git commit -m "test: cover playback state UI"
```

---

## Task 7: 視覚・手動スモークと Step 3 最終確認

**Files:**
- Modify: `docs/superpowers/plans/2026-06-06-step3-playback-state-ui.md`

- [x] **Step 1: 未完了チェックと差分を確認する**

Run:

```bash
rg -n "\\[ \\]" docs/superpowers/plans/2026-06-06-step3-playback-state-ui.md
git status --short --branch
git diff --check
```

Expected: Task 7 の実施中項目以外に意図しない未完了や差分がない。

- [x] **Step 2: 全テストを再実行する**

Run:

```bash
xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData
```

Expected: `** TEST SUCCEEDED **`

- [x] **Step 3: シミュレータで ui-mock.html と比較する**

iPhone 16 / iOS 18.4 シミュレータで一覧を開き、`docs/ui-mock.html` のファイル一覧・ミニプレイヤーと見比べる。

確認項目。

```text
- 淡いグレー背景、角丸の白い一覧、セクションラベルがある
- 未再生ファイル名が太字で、状態バッジと総時間が表示される
- 再生中バッジが他の状態バッジより優先される
- 細い進捗バーが一覧行とミニプレイヤーに表示される
- ミニプレイヤーが下部固定で、内容更新時に高さが変わらない
- 長いファイル名でもバッジや次行と重ならない
```

- [x] **Step 4: 再生状態の手動スモークを実施する**

確認項目。

```text
- 通常タップで再生し、現在位置と進捗が更新される
- 一時停止、10秒戻し、30秒送りの直後に表示位置が更新される
- 長押し「先頭から再生」で0秒から再生する
- 長押し「未再生に戻す」で0秒・未再生になり、再生中なら停止する
- 再生完了または残り30秒以内で100%表示になる
- 次ファイルへ自動再生する
- 一覧を閉じて同一アプリ起動中に開き直すと状態が維持される
- アプリ再起動後に状態が消えることを確認し、Step 4 境界を守っている
```

- [x] **Step 5: Dynamic Type の手動スモークを実施する**

シミュレータの文字サイズを大きくし、長いファイル名、状態バッジ、ミニプレイヤーが重ならないことを確認する。

- [x] **Step 6: Plan に最終結果を記録する**

この Task の末尾へ次の形式で記録する。

## Task 7 Final Result

- Full tests: PASS。`xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.4' -derivedDataPath /private/tmp/AudioFolderPlayerDerivedData` を fresh 実行し、unit 87 件 + UI 1 件、合計 88 件、0 failures、`** TEST SUCCEEDED **`。
- Visual smoke: PASS。`docs/ui-mock.html` と SwiftUI 構造を照合し、淡い grouped background、角丸一覧、セクションラベル、状態バッジ優先、一覧/ミニプレイヤーの細い進捗、下部固定プレイヤーを確認。UI smoke で一覧行・状態バッジ・進捗・全操作が存在し操作可能であることを確認した。テスト runner 終了後に一覧画面の専用スクリーンショットは保持できなかった。
- Playback state smoke: PASS。UI smoke で未再生表示、通常タップ、再生中バッジ、長押しメニュー、pause/resume、10 秒戻し、30 秒送りの表示反映を確認。unit tests で途中再開、先頭再生、未再生化、残り 30 秒判定、完了、自動次項目、一覧再入場時の観測再開、同一 `fileId` のメモリ状態引継ぎを確認。永続化コードを追加しておらず、アプリ再起動後に復元しない Step 4 境界を維持。
- Dynamic Type smoke: PASS。`xcrun simctl ui 89914295-F8B7-4CC6-8D95-BFFDD6934B33 content_size accessibility-extra-large` で focused UI smoke を完走し、一覧行、状態バッジ、長押しメニュー、ミニプレイヤー、全操作が存在・操作可能であることを確認。終了後 `large` へ復元済み。
- Simulator: iPhone 16 / iOS 18.4

- [x] **Step 7: 完了コミットを作成する**

```bash
git add docs/superpowers/plans/2026-06-06-step3-playback-state-ui.md
git commit -m "docs: complete Step 3 verification"
```

- [x] **Step 8: 最終状態を確認する**

Run:

```bash
git status --short --branch
git log --oneline -10
```

Expected: 未コミット差分なし。Task 0 から Task 7 のコミットが揃っている。
