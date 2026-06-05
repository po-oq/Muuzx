# Step 1: ローカル再生 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 端末ローカル（アプリ専用領域）に置かれた mp3/m4a を一覧表示し、AVPlayer で連続再生・10秒戻し・30秒送り・次曲自動再生ができる最小 iOS アプリを作る。

**Architecture:** SwiftUI + MVVM。再生エンジンは `AudioEngine` プロトコルで抽象化し、実体（`AVPlayerAudioEngine`）と差し替え可能にする。これにより再生制御ロジック（`PlaybackService`）と一覧生成（`LocalAudioLibrary`）・識別子生成（`FileIdentifier`）を AVFoundation/UI 非依存の純ロジックとして TDD する。`docs/architecture.md` のサービス分割に従う。

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, XCTest, Xcode 16 / iOS 17+。

---

## 前提・環境

- ビルド/テストは **macOS + Xcode** で行う（このリポジトリのWSL環境では実行不可）。
- スキーム名 `AudioFolderPlayer`、テストターゲット `AudioFolderPlayerTests` を前提とする。
- テスト実行コマンドの `iPhone 16` は環境に存在するシミュレータ名に読み替える（一覧: `xcrun simctl list devices available`）。

## File Structure

このプランで作成するファイルと責務。

| パス | 責務 |
|---|---|
| `AudioFolderPlayer/Models/PlaybackStatus.swift` | 再生状態の列挙 |
| `AudioFolderPlayer/Models/AudioItem.swift` | 音声1件のモデル |
| `AudioFolderPlayer/Services/FileIdentifier.swift` | `fileId`（名前+サイズ、NFC正規化）生成。純ロジック |
| `AudioFolderPlayer/Services/LocalAudioLibrary.swift` | ローカルディレクトリを走査し AudioItem 配列を返す |
| `AudioFolderPlayer/Services/AudioEngine.swift` | 再生エンジンの抽象プロトコル |
| `AudioFolderPlayer/Infrastructure/Audio/AVPlayerAudioEngine.swift` | AVPlayer による AudioEngine 実装 |
| `AudioFolderPlayer/Services/PlaybackService.swift` | プレイリスト管理・スキップ・次曲自動再生。純ロジック |
| `AudioFolderPlayer/Infrastructure/FileSystem/AppDirectories.swift` | アプリ専用ディレクトリの解決/生成 |
| `AudioFolderPlayer/Services/SampleSeeder.swift` | 同梱サンプル音声を audio ディレクトリへ初回コピー |
| `AudioFolderPlayer/ViewModels/AudioListViewModel.swift` | 一覧・再生状態の UI 向け状態 |
| `AudioFolderPlayer/Views/AudioListView.swift` | ファイル一覧画面 |
| `AudioFolderPlayer/Views/MiniPlayerView.swift` | 下部ミニプレイヤー |
| `AudioFolderPlayer/App/AudioFolderPlayerApp.swift` | エントリポイント・依存組み立て |
| `AudioFolderPlayerTests/FileIdentifierTests.swift` | FileIdentifier のテスト |
| `AudioFolderPlayerTests/LocalAudioLibraryTests.swift` | LocalAudioLibrary のテスト |
| `AudioFolderPlayerTests/Support/FakeAudioEngine.swift` | テスト用の AudioEngine 偽実装 |
| `AudioFolderPlayerTests/PlaybackServiceTests.swift` | PlaybackService のテスト |

---

## Task 0: Xcode プロジェクト作成と構成

**Files:**
- Create: Xcode プロジェクト `AudioFolderPlayer`（GUI操作）

- [x] **Step 1: プロジェクト作成**

Xcode で File > New > Project > iOS > App。
- Product Name: `AudioFolderPlayer`
- Interface: SwiftUI
- Language: Swift
- Storage: None
- **Include Tests: ON**（`AudioFolderPlayerTests` が作られる）

リポジトリのルート（`/home/meled/ghq/github.com/po-oq/Muuzx` 相当の作業コピー）直下に作成する。

- [x] **Step 2: グループ（フォルダ）作成**

`AudioFolderPlayer` ターゲット配下に空グループを作る: `App`, `Models`, `Views`, `ViewModels`, `Services`, `Infrastructure/Audio`, `Infrastructure/FileSystem`, `Resources`。
テンプレ生成された `ContentView.swift` は削除し、`AudioFolderPlayerApp.swift` は `App/` へ移動する（中身は Task 9 で置き換える）。

- [x] **Step 3: ビルド確認**

Run: `xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `BUILD SUCCEEDED`

- [x] **Step 4: コミット**

```bash
git add -A
git commit -m "chore: scaffold AudioFolderPlayer Xcode project (Step1)"
```

---

## Task 1: モデル定義（PlaybackStatus / AudioItem）

**Files:**
- Create: `AudioFolderPlayer/Models/PlaybackStatus.swift`
- Create: `AudioFolderPlayer/Models/AudioItem.swift`

- [x] **Step 1: PlaybackStatus を作成**

```swift
import Foundation

enum PlaybackStatus: String, Codable, Equatable {
    case unplayed
    case inProgress
    case played
}
```

- [x] **Step 2: AudioItem を作成**

```swift
import Foundation

struct AudioItem: Identifiable, Codable, Equatable {
    let id: String          // fileId: normalizedName|sizeBytes
    var fileName: String
    var localURL: URL
    var fileSizeBytes: Int64
    var durationSec: Double
    var positionSec: Double
    var status: PlaybackStatus
    var updatedAt: Date
}
```

- [x] **Step 3: ビルド確認**

Run: `xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `BUILD SUCCEEDED`

- [x] **Step 4: コミット**

```bash
git add AudioFolderPlayer/Models/
git commit -m "feat: add PlaybackStatus and AudioItem models"
```

---

## Task 2: FileIdentifier（TDD）

`fileId = 正規化ファイル名 + "|" + サイズ`。正規化は「前後空白除去 → NFC正規化 → 小文字化」。

**Files:**
- Create: `AudioFolderPlayer/Services/FileIdentifier.swift`
- Test: `AudioFolderPlayerTests/FileIdentifierTests.swift`

- [x] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import AudioFolderPlayer

final class FileIdentifierTests: XCTestCase {
    func test_make_combinesNormalizedNameAndSize() {
        let id = FileIdentifier.make(fileName: "AWS設計入門 02.mp3", sizeBytes: 73_400_320)
        XCTAssertEqual(id, "aws設計入門 02.mp3|73400320")
    }

    func test_normalize_trimsWhitespace() {
        XCTAssertEqual(FileIdentifier.normalize("  track.mp3  "), "track.mp3")
    }

    func test_normalize_isCaseInsensitive() {
        XCTAssertEqual(FileIdentifier.normalize("Track.MP3"), "track.mp3")
    }

    func test_normalize_usesNFC() {
        // "が" を NFD（か + 濁点）で構成した文字列が NFC へ正規化されること
        let nfd = "\u{304B}\u{3099}.mp3"           // か + 結合濁点
        let nfc = "\u{304C}.mp3"                    // が（合成済み）
        XCTAssertEqual(FileIdentifier.normalize(nfd), nfc)
    }
}
```

- [x] **Step 2: テストが失敗することを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/FileIdentifierTests`
Expected: コンパイルエラー（`FileIdentifier` 未定義）で FAIL

- [x] **Step 3: 最小実装を書く**

```swift
import Foundation

enum FileIdentifier {
    /// fileId = 正規化ファイル名 + "|" + サイズ（byte）
    static func make(fileName: String, sizeBytes: Int64) -> String {
        "\(normalize(fileName))|\(sizeBytes)"
    }

    /// 前後空白除去 → NFC正規化 → 小文字化。端末間で完全一致させるための正規化。
    static func normalize(_ fileName: String) -> String {
        fileName
            .trimmingCharacters(in: .whitespaces)
            .precomposedStringWithCanonicalMapping   // NFC
            .lowercased()
    }
}
```

- [x] **Step 4: テストが通ることを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/FileIdentifierTests`
Expected: PASS（4 tests）

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Services/FileIdentifier.swift AudioFolderPlayerTests/FileIdentifierTests.swift
git commit -m "feat: add FileIdentifier with NFC-normalized fileId"
```

---

## Task 3: LocalAudioLibrary（TDD）

ディレクトリを走査し、mp3/m4a のみを `AudioItem` 化してファイル名昇順（自然順）で返す。

**Files:**
- Create: `AudioFolderPlayer/Services/LocalAudioLibrary.swift`
- Test: `AudioFolderPlayerTests/LocalAudioLibraryTests.swift`

- [x] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import AudioFolderPlayer

final class LocalAudioLibraryTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ name: String, bytes: Int) throws {
        let data = Data(repeating: 0, count: bytes)
        try data.write(to: tempDir.appendingPathComponent(name))
    }

    func test_loadItems_returnsOnlySupportedExtensions() throws {
        try write("a.mp3", bytes: 10)
        try write("b.m4a", bytes: 10)
        try write("readme.txt", bytes: 10)
        try write("c.flac", bytes: 10)

        let items = try LocalAudioLibrary(directory: tempDir).loadItems()

        XCTAssertEqual(items.map(\.fileName), ["a.mp3", "b.m4a"])
    }

    func test_loadItems_sortsByNaturalFileNameOrder() throws {
        try write("track 10.mp3", bytes: 10)
        try write("track 2.mp3", bytes: 10)
        try write("track 1.mp3", bytes: 10)

        let items = try LocalAudioLibrary(directory: tempDir).loadItems()

        XCTAssertEqual(items.map(\.fileName), ["track 1.mp3", "track 2.mp3", "track 10.mp3"])
    }

    func test_loadItems_populatesIdAndSize() throws {
        try write("song.mp3", bytes: 1234)

        let items = try LocalAudioLibrary(directory: tempDir).loadItems()

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].fileSizeBytes, 1234)
        XCTAssertEqual(items[0].id, "song.mp3|1234")
        XCTAssertEqual(items[0].status, .unplayed)
    }
}
```

- [x] **Step 2: テストが失敗することを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/LocalAudioLibraryTests`
Expected: コンパイルエラー（`LocalAudioLibrary` 未定義）で FAIL

- [x] **Step 3: 最小実装を書く**

```swift
import Foundation

struct LocalAudioLibrary {
    static let supportedExtensions: Set<String> = ["mp3", "m4a"]

    let directory: URL
    private let fileManager: FileManager

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func loadItems() throws -> [AudioItem] {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        let items = try urls
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { url -> AudioItem in
                let size = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                let name = url.lastPathComponent
                return AudioItem(
                    id: FileIdentifier.make(fileName: name, sizeBytes: size),
                    fileName: name,
                    localURL: url,
                    fileSizeBytes: size,
                    durationSec: 0,
                    positionSec: 0,
                    status: .unplayed,
                    updatedAt: Date()
                )
            }

        return items.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }
}
```

- [x] **Step 4: テストが通ることを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/LocalAudioLibraryTests`
Expected: PASS（3 tests）

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Services/LocalAudioLibrary.swift AudioFolderPlayerTests/LocalAudioLibraryTests.swift
git commit -m "feat: add LocalAudioLibrary directory scan"
```

---

## Task 4: AudioEngine プロトコルと実装

再生制御を抽象化し、`PlaybackService` をテスト可能にする。

**Files:**
- Create: `AudioFolderPlayer/Services/AudioEngine.swift`
- Create: `AudioFolderPlayer/Infrastructure/Audio/AVPlayerAudioEngine.swift`
- Create: `AudioFolderPlayerTests/Support/FakeAudioEngine.swift`

- [x] **Step 1: AudioEngine プロトコルを作成**

```swift
import Foundation

protocol AudioEngine: AnyObject {
    var currentTimeSec: Double { get }
    var durationSec: Double { get }
    func load(url: URL)
    func play()
    func pause()
    func seek(toSec seconds: Double)
    /// 再生が末尾まで到達したときに呼ばれる
    var onPlaybackEnded: (() -> Void)? { get set }
}
```

- [x] **Step 2: AVPlayerAudioEngine を作成**

```swift
import AVFoundation

final class AVPlayerAudioEngine: AudioEngine {
    private let player = AVPlayer()
    var onPlaybackEnded: (() -> Void)?

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didPlayToEnd(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var currentTimeSec: Double {
        let t = player.currentTime().seconds
        return t.isFinite ? t : 0
    }

    var durationSec: Double {
        guard let d = player.currentItem?.duration.seconds, d.isFinite else { return 0 }
        return d
    }

    func load(url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
    }

    func play() { player.play() }
    func pause() { player.pause() }

    func seek(toSec seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    @objc private func didPlayToEnd(_ note: Notification) {
        guard (note.object as? AVPlayerItem) === player.currentItem else { return }
        onPlaybackEnded?()
    }
}
```

- [x] **Step 3: FakeAudioEngine（テスト用）を作成**

```swift
import Foundation
@testable import AudioFolderPlayer

final class FakeAudioEngine: AudioEngine {
    var currentTimeSec: Double = 0
    var durationSec: Double = 0
    var onPlaybackEnded: (() -> Void)?

    private(set) var loadedURLs: [URL] = []
    private(set) var seekedToSec: [Double] = []
    private(set) var isPlaying = false

    func load(url: URL) { loadedURLs.append(url) }
    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func seek(toSec seconds: Double) {
        currentTimeSec = seconds
        seekedToSec.append(seconds)
    }

    /// テストから再生終端イベントを発火する
    func simulatePlaybackEnded() { onPlaybackEnded?() }
}
```

- [x] **Step 4: ビルド確認**

Run: `xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `BUILD SUCCEEDED`

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Services/AudioEngine.swift AudioFolderPlayer/Infrastructure/Audio/AVPlayerAudioEngine.swift AudioFolderPlayerTests/Support/FakeAudioEngine.swift
git commit -m "feat: add AudioEngine abstraction and AVPlayer impl"
```

---

## Task 5: PlaybackService スキップ制御（TDD）

10秒戻し・30秒送り。境界は `[0, duration]` にクランプする。

**Files:**
- Create: `AudioFolderPlayer/Services/PlaybackService.swift`
- Test: `AudioFolderPlayerTests/PlaybackServiceTests.swift`

- [x] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import AudioFolderPlayer

final class PlaybackServiceTests: XCTestCase {
    private func makeItem(_ name: String) -> AudioItem {
        AudioItem(
            id: name, fileName: name,
            localURL: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSizeBytes: 1, durationSec: 100, positionSec: 0,
            status: .unplayed, updatedAt: Date()
        )
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
}
```

- [x] **Step 2: テストが失敗することを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/PlaybackServiceTests`
Expected: コンパイルエラー（`PlaybackService` 未定義）で FAIL

- [x] **Step 3: 最小実装を書く**

```swift
import Foundation

final class PlaybackService {
    static let skipForwardSec: Double = 30
    static let skipBackwardSec: Double = 10

    private let engine: AudioEngine
    private(set) var items: [AudioItem]
    private(set) var currentIndex: Int?

    init(engine: AudioEngine, items: [AudioItem] = []) {
        self.engine = engine
        self.items = items
        engine.onPlaybackEnded = { [weak self] in self?.handlePlaybackEnded() }
    }

    var currentItem: AudioItem? {
        guard let i = currentIndex, items.indices.contains(i) else { return nil }
        return items[i]
    }

    func setItems(_ items: [AudioItem]) { self.items = items }

    func play(at index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
        engine.load(url: items[index].localURL)
        engine.play()
    }

    func resume() { engine.play() }
    func pause() { engine.pause() }

    func skipForward() {
        let target = min(engine.currentTimeSec + Self.skipForwardSec, engine.durationSec)
        engine.seek(toSec: target)
    }

    func skipBackward() {
        let target = max(engine.currentTimeSec - Self.skipBackwardSec, 0)
        engine.seek(toSec: target)
    }

    private func handlePlaybackEnded() {
        // Task 6 で実装
    }
}
```

- [x] **Step 4: テストが通ることを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/PlaybackServiceTests`
Expected: PASS（4 tests）

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Services/PlaybackService.swift AudioFolderPlayerTests/PlaybackServiceTests.swift
git commit -m "feat: add PlaybackService skip controls"
```

---

## Task 6: PlaybackService 次曲自動再生（TDD）

再生終端で次のファイルへ進む。最後のファイルなら停止する。

**Files:**
- Modify: `AudioFolderPlayer/Services/PlaybackService.swift`（`handlePlaybackEnded`）
- Test: `AudioFolderPlayerTests/PlaybackServiceTests.swift`（追記）

- [x] **Step 1: 失敗するテストを追記**

`PlaybackServiceTests` クラス内に以下を追加する。

```swift
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
```

- [x] **Step 2: テストが失敗することを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/PlaybackServiceTests`
Expected: `test_playbackEnded_advancesToNextTrack` と `test_playbackEnded_onLastTrack_stops` が FAIL

- [x] **Step 3: handlePlaybackEnded を実装**

`PlaybackService` の `handlePlaybackEnded` を置き換える。

```swift
    private func handlePlaybackEnded() {
        guard let i = currentIndex else { return }
        let next = i + 1
        if items.indices.contains(next) {
            play(at: next)
        } else {
            currentIndex = nil
        }
    }
```

- [x] **Step 4: テストが通ることを確認**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:AudioFolderPlayerTests/PlaybackServiceTests`
Expected: PASS（6 tests）

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Services/PlaybackService.swift AudioFolderPlayerTests/PlaybackServiceTests.swift
git commit -m "feat: auto-advance to next track on playback end"
```

---

## Task 7: AppDirectories と SampleSeeder

audio ディレクトリの解決と、同梱サンプル音声の初回コピー。

**Files:**
- Create: `AudioFolderPlayer/Infrastructure/FileSystem/AppDirectories.swift`
- Create: `AudioFolderPlayer/Services/SampleSeeder.swift`
- Create: `AudioFolderPlayer/Resources/`（サンプル mp3 を 2〜3 件追加）

- [x] **Step 1: AppDirectories を作成**

```swift
import Foundation

enum AppDirectories {
    static let appFolderName = "AudioFolderPlayer"

    static func appSupportRoot(_ fm: FileManager = .default) throws -> URL {
        let base = try fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return base.appendingPathComponent(appFolderName, isDirectory: true)
    }

    static func audioDirectory(_ fm: FileManager = .default) throws -> URL {
        let url = try appSupportRoot(fm).appendingPathComponent("audio", isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
```

- [x] **Step 2: SampleSeeder を作成**

```swift
import Foundation

/// 同梱されたサンプル音声を、audio ディレクトリが空のときだけコピーする（Step1 の動作確認用）。
struct SampleSeeder {
    let bundle: Bundle
    let destination: URL
    private let fileManager: FileManager

    init(bundle: Bundle = .main, destination: URL, fileManager: FileManager = .default) {
        self.bundle = bundle
        self.destination = destination
        self.fileManager = fileManager
    }

    func seedIfEmpty() throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = try fileManager.contentsOfDirectory(atPath: destination.path)
        guard existing.isEmpty else { return }

        for ext in ["mp3", "m4a"] {
            for src in bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [] {
                let dest = destination.appendingPathComponent(src.lastPathComponent)
                try? fileManager.copyItem(at: src, to: dest)
            }
        }
    }
}
```

- [x] **Step 3: サンプル音声を追加**

短い mp3 を 2〜3 件（例: `sample-01.mp3`, `sample-02.mp3`）用意し、Xcode で `AudioFolderPlayer` ターゲットに追加する（Copy items if needed: ON、Add to target: AudioFolderPlayer）。著作権フリー音源か自作の数秒の無音mp3でよい。

> 無音mp3の作成例（ffmpeg がある場合）: `ffmpeg -f lavfi -i anullsrc=r=44100:cl=mono -t 5 -q:a 9 sample-01.mp3`

- [x] **Step 4: ビルド確認**

Run: `xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `BUILD SUCCEEDED`

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Infrastructure/FileSystem/AppDirectories.swift AudioFolderPlayer/Services/SampleSeeder.swift AudioFolderPlayer/Resources/
git commit -m "feat: add AppDirectories and bundled sample seeding"
```

---

## Task 8: AudioListViewModel

一覧と再生状態を UI へ橋渡しする。

**Files:**
- Create: `AudioFolderPlayer/ViewModels/AudioListViewModel.swift`

- [x] **Step 1: AudioListViewModel を作成**

```swift
import Foundation

@MainActor
final class AudioListViewModel: ObservableObject {
    @Published private(set) var items: [AudioItem] = []
    @Published private(set) var currentItemId: String?
    @Published private(set) var isPlaying: Bool = false

    private let library: LocalAudioLibrary
    private let playback: PlaybackService

    init(library: LocalAudioLibrary, playback: PlaybackService) {
        self.library = library
        self.playback = playback
    }

    func load() {
        items = (try? library.loadItems()) ?? []
        playback.setItems(items)
    }

    func play(_ item: AudioItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        playback.play(at: index)
        currentItemId = item.id
        isPlaying = true
    }

    func togglePlayPause() {
        if isPlaying {
            playback.pause()
            isPlaying = false
        } else {
            playback.resume()
            isPlaying = true
        }
    }

    func skipForward() { playback.skipForward() }
    func skipBackward() { playback.skipBackward() }

    var currentItem: AudioItem? {
        items.first { $0.id == currentItemId }
    }
}
```

- [x] **Step 2: ビルド確認**

Run: `xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `BUILD SUCCEEDED`

- [x] **Step 3: コミット**

```bash
git add AudioFolderPlayer/ViewModels/AudioListViewModel.swift
git commit -m "feat: add AudioListViewModel"
```

---

## Task 9: SwiftUI Views とアプリ組み立て

ファイル一覧＋下部ミニプレイヤー。

**Files:**
- Create: `AudioFolderPlayer/Views/MiniPlayerView.swift`
- Create: `AudioFolderPlayer/Views/AudioListView.swift`
- Modify: `AudioFolderPlayer/App/AudioFolderPlayerApp.swift`

- [x] **Step 1: MiniPlayerView を作成**

```swift
import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject var viewModel: AudioListViewModel

    var body: some View {
        HStack(spacing: 16) {
            Text(viewModel.currentItem?.fileName ?? "再生していません")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: viewModel.skipBackward) {
                Image(systemName: "gobackward.10")
            }
            Button(action: viewModel.togglePlayPause) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            Button(action: viewModel.skipForward) {
                Image(systemName: "goforward.30")
            }
        }
        .padding()
        .background(.thinMaterial)
        .disabled(viewModel.currentItem == nil)
    }
}
```

- [x] **Step 2: AudioListView を作成**

```swift
import SwiftUI

struct AudioListView: View {
    @ObservedObject var viewModel: AudioListViewModel

    var body: some View {
        VStack(spacing: 0) {
            List(viewModel.items) { item in
                Button {
                    viewModel.play(item)
                } label: {
                    HStack {
                        Text(item.fileName)
                            .fontWeight(item.status == .unplayed ? .bold : .regular)
                        Spacer()
                        if item.id == viewModel.currentItemId {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                    }
                }
            }
            MiniPlayerView(viewModel: viewModel)
        }
        .onAppear { viewModel.load() }
    }
}
```

- [x] **Step 3: App エントリを置き換え**

```swift
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
```

- [x] **Step 4: ビルド確認**

Run: `xcodebuild build -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: `BUILD SUCCEEDED`

- [x] **Step 5: コミット**

```bash
git add AudioFolderPlayer/Views/ AudioFolderPlayer/App/AudioFolderPlayerApp.swift
git commit -m "feat: add audio list and mini player UI"
```

---

## Task 10: シミュレータ手動スモークテスト

**Files:** なし（手動確認）

- [x] **Step 1: 全テスト実行**

Run: `xcodebuild test -scheme AudioFolderPlayer -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: 全テスト PASS（FileIdentifier 4 + LocalAudioLibrary 3 + PlaybackService 6 = 13）

- [x] **Step 2: シミュレータで起動して確認**

Xcode で Run（⌘R）。以下を目視確認する。
- サンプル音声がファイル名昇順で一覧表示される
- 未再生ファイルが太字
- タップで再生が始まり、再生中ファイルにスピーカーアイコンが付く
- ミニプレイヤーの再生/一時停止が効く
- 10秒戻し / 30秒送りが効く
- 1曲再生完了後に次の曲へ自動で進む（短いサンプルで確認）

- [x] **Step 3: 確認結果を記録**

問題があれば該当 Task に戻る。問題なければ Step1 完了。

---

## Self-Review（スペック対応確認）

| spec 要件（Step1 範囲） | 対応 Task |
|---|---|
| ローカル保存ファイルを対象に再生 | Task 3, 5, 9 |
| ファイル名昇順で一覧表示 | Task 3（自然順ソート）, 9 |
| ファイル名昇順で連続再生 | Task 6 |
| 再生完了後に自動で次ファイル | Task 6 |
| 10秒戻し | Task 5 |
| 30秒送り | Task 5 |
| 下部ミニプレイヤー（再生/停止・10秒戻し・30秒送り・ファイル名） | Task 9 |
| 未再生ファイルの太字表示 | Task 9 |
| 再生中バッジ | Task 9 |
| 対応形式 mp3/m4a のみ | Task 3 |
| fileId（名前+サイズ・NFC） | Task 2 |

**Step1 範囲外（後続プランで対応）:** フォルダ取り込み（Step2）／進捗バー・未再生に戻す・JSON保存（Step3）／バックグラウンド再生・ロック画面操作（Step4）／iCloud同期（Step5）／再生画面・UI仕上げ（Step6）。

> 注: 一覧の進捗バーや位置/総時間の表示は状態管理（Step3）と統合するため、本プランでは未再生太字＋再生中バッジまでに留める（YAGNI）。
