# Audio Folder Player アーキテクチャ v1

## 1. 基本アーキテクチャ

```text
SwiftUI Views
  ↓
ViewModels
  ↓
Application Services
  ├── FolderImportService
  ├── PlaybackService
  ├── PlaybackStateStore
  ├── CloudSyncService (SyncBackend / DocumentSyncBackend)
  └── LocalAudioLibrary
  ↓
iOS Frameworks
  ├── UIDocumentPicker (+ security-scoped bookmark)
  ├── FileManager / NSFileCoordinator
  ├── AVPlayer / AVAudioSession
  └── iCloud Documents (Ubiquitous Container + NSMetadataQuery)
```

## 2. 設計方針

- iCloud Driveは取り込み元として扱う
- 再生は端末ローカルの音声ファイルを対象にする
- 音声ファイル本体は端末間同期しない
- 再生状態のみ iCloud Documents（状態JSONファイル）で同期する
- ローカル状態を常に source of truth とし、iCloudへはミラーする
- iCloud未設定時はローカルのみで動作し、同期は静かに無効化する
- ファイル操作アプリではなく音声再生アプリとして実装する
- UIはGoodReaderライクなファイル一覧と下部ミニプレイヤーを中心にする

## 3. ディレクトリ構成案

```text
AudioFolderPlayer/
├── App/
│   └── AudioFolderPlayerApp.swift
├── Models/
│   ├── AudioItem.swift
│   ├── PlaybackStatus.swift
│   ├── PlaybackState.swift
│   └── ImportMode.swift
├── Views/
│   ├── FolderView.swift
│   ├── AudioListView.swift
│   ├── MiniPlayerView.swift
│   ├── NowPlayingView.swift
│   └── ImportProgressView.swift
├── ViewModels/
│   ├── FolderViewModel.swift
│   ├── AudioListViewModel.swift
│   └── PlayerViewModel.swift
├── Services/
│   ├── FolderImportService.swift
│   ├── LocalAudioLibrary.swift
│   ├── PlaybackService.swift
│   ├── PlaybackStateStore.swift
│   ├── CloudSyncService.swift        // SyncBackend を束ねる調整役
│   ├── SyncBackend.swift             // protocol（差し替え可能な同期抽象）
│   ├── DocumentSyncBackend.swift     // iCloud Documents 実装
│   └── AudioMetadataService.swift
├── Infrastructure/
│   ├── DocumentPicker/
│   │   └── FolderPicker.swift
│   ├── FileSystem/
│   │   ├── AppDirectories.swift
│   │   └── FolderBookmarkStore.swift // security-scoped bookmark の保存/復元
│   └── Audio/
│       └── RemoteCommandCenterHandler.swift
└── Resources/
```

## 4. ローカル保存先

音声ファイルはアプリのローカル領域に保存する。

推奨。

```text
Library/Application Support/AudioFolderPlayer/audio/
Library/Application Support/AudioFolderPlayer/state/
```

例。

```text
Application Support/
└── AudioFolderPlayer/
    ├── audio/
    │   ├── AWS設計入門 01.mp3
    │   ├── AWS設計入門 02.mp3
    │   └── RSSクローラー設計 01.m4a
    └── state/
        └── playback-state.json
```

### 4.1 バックアップ除外

`audio/` の音声本体はiCloud Driveから再取得できるため、`URLResourceValues.isExcludedFromBackup = true` を設定し、端末バックアップの肥大化を防ぐ。

### 4.2 状態の二層構成

`state/playback-state.json` を常に source of truth とし、`DocumentSyncBackend` がiCloudコンテナのファイルへミラーする。iCloud未設定時もこのローカル状態だけでアプリは完結する。

## 5. 主要モデル

### 5.1 AudioItem

```swift
struct AudioItem: Identifiable, Codable, Equatable {
    let id: String
    var fileName: String
    var localURL: URL
    var fileSizeBytes: Int64
    var durationSec: Double
    var positionSec: Double
    var status: PlaybackStatus
    var updatedAt: Date
}
```

### 5.2 PlaybackStatus

```swift
enum PlaybackStatus: String, Codable {
    case unplayed
    case inProgress
    case played
}
```

### 5.3 PlaybackState

```swift
struct PlaybackState: Codable {
    var schemaVersion: Int
    var lastPlayedFileId: String?
    var lastPlayedPositionSec: Double
    var lastUpdatedAt: Date
    var files: [String: AudioItemState]
}
```

### 5.4 AudioItemState

```swift
struct AudioItemState: Codable {
    var fileName: String
    var durationSec: Double
    var positionSec: Double
    var status: PlaybackStatus
    var updatedAt: Date
}
```

### 5.5 ImportMode

```swift
enum ImportMode {
    case replaceAll
    case mergeOverwrite
}
```

## 6. FolderImportService

### 責務

- UIDocumentPickerで選択されたフォルダURL、または `FolderBookmarkStore` から復元したURLを受け取る
- security-scoped resource を `start/stopAccessingSecurityScopedResource` でペア管理する
- フォルダ内の音声ファイルを列挙する
- 対応形式以外を除外する
- 未ダウンロード（プレースホルダ）ファイルのダウンロードを確保する
- ローカル保存先へコピーする
- 取り込み進捗を通知する
- 取り込み結果としてAudioItem一覧を返す

### 取り込みフェーズ

取り込みは3フェーズで進める。

1. **列挙**: フォルダ内の対応形式ファイルを列挙する
2. **ダウンロード確保**: `ubiquitousItemDownloadingStatus` が `.current` でないファイルは、`NSFileCoordinator` の協調読み込み（`coordinate(readingItemAt:options:[])`）で実体ダウンロードの完了を待つ。外部フォルダにも堅牢で、進捗はファイル単位（n/N件）で表示する
3. **コピー**: ローカル保存先へコピーする

### 中断と再開

- 取り込み中は `beginBackgroundTask` で短時間の延命を取る
- 取り込みは再開可能（idempotent）にする。既コピー済みファイルはスキップし、次回起動で続きから再取り込みする
- 中断はユーザーに通知する

### フォルダ権限の永続化

- 選択フォルダのsecurity-scoped bookmarkを `FolderBookmarkStore` に保存する
- 「再同期」はブックマークから復元したURLでワンタップ再取り込みする
- 「別フォルダ選択」はUIDocumentPickerを開く
- 復元時 `isStale` ならブックマークを作り直す。アクセス不可なら再選択を促す
- iOSのため bookmark 解決に `.withSecurityScope` は付けない

### 取り込み対象

MVPでは以下。

- `.mp3`
- `.m4a`

### 取り込みモード

#### replaceAll

1. ローカルaudioディレクトリを削除する
2. ローカル状態を必要に応じて初期化する
3. 選択フォルダ内の音声ファイルをコピーする

#### mergeOverwrite

1. ローカルaudioディレクトリは残す
2. 同名ファイルは上書きする
3. 新規ファイルは追加する
4. ローカルにだけ存在するファイルは残す

## 7. LocalAudioLibrary

### 責務

- ローカルaudioディレクトリを管理する
- ローカル音声ファイル一覧を返す
- ファイル名昇順でソートする
- AudioItemのfileIdを生成する
- ローカル容量使用量を算出する

## 8. PlaybackService

### 責務

- AVPlayerを管理する
- 再生/一時停止を行う
- 10秒戻しを行う
- 30秒送りを行う
- 曲終了イベントを検知する
- 次ファイル自動再生を行う
- 現在位置を取得する
- ロック画面/コントロールセンター操作を処理する

### 再生エンジン

MVPは単一 `AVPlayer` を使い、再生終了イベント（`AVPlayerItemDidPlayToEndTime`）で次ファイルをロードする。現在ファイル追跡・任意ファイルへのジャンプ・未再生に戻す操作の制御が素直なため。`AVQueuePlayer` は将来のギャップレス化候補に留める。

### バックグラウンド再生

- AVAudioSessionをplaybackカテゴリで構成する
- Background ModesのAudioを有効化する
- Now Playing Infoを更新する
- Remote Command Centerで再生/停止/スキップを受け取る

## 9. PlaybackStateStore

### 責務

- ローカル状態JSONを読み書きする
- AudioItemの状態を更新する
- 起動時にローカル状態を復元する
- 一定間隔のローカル保存に対応する

### 保存先

```text
Application Support/AudioFolderPlayer/state/playback-state.json
```

## 10. CloudSyncService / SyncBackend

### SyncBackend 抽象

同期先を差し替え可能にするため、`SyncBackend` プロトコルで抽象化する。MVPの実装は `DocumentSyncBackend`（iCloud Documents）。将来CloudKit等へ差し替え可能にする。

```swift
protocol SyncBackend {
    func load() throws -> PlaybackState?
    func save(_ state: PlaybackState) throws   // ローカルは常に成功、iCloud反映は非同期・失敗を投げない
    var externalChange: AsyncStream<Void> { get } // 外部変更通知の統一窓口
}
```

### DocumentSyncBackend 責務

- iCloudコンテナの `Documents/playback-state.json` へPlaybackStateを保存/読み込みする
- `NSFileCoordinator` で協調読み書きする
- `NSMetadataQuery` で外部端末からの変更を検知する
- iCloud未設定（コンテナURLが`nil`）時はローカルのみで動作し、同期は no-op にする

### CloudSyncService 責務

- ローカル状態とクラウド状態をマージする
- 同期状態（成功/失敗/端末内のみ）をUIへ通知する

### 競合解決

- ファイル単位では `updatedAt` が新しい状態を採用する
- 全体状態では `lastUpdatedAt` が新しい状態を採用する

詳細は `sync-spec.md` を参照する。

## 11. View構成

### 11.1 FolderView

- 前回フォルダ名
- ファイル数
- 使用容量
- 最終同期日時
- 再同期ボタン
- 別フォルダ選択ボタン
- 同期状態

### 11.2 AudioListView

- ファイル一覧
- 未再生太字
- 進捗バー
- 再生中表示
- 長押しメニュー
- 下部ミニプレイヤー

### 11.3 MiniPlayerView

- 現在ファイル名
- 再生/停止
- 10秒戻し
- 30秒送り
- 現在位置/総時間
- 進捗バー

### 11.4 NowPlayingView

- 詳細再生画面
- 再生/停止
- 10秒戻し
- 30秒送り
- 進捗バー
- 再生速度変更の配置余地
- 未再生に戻す操作

## 12. 状態更新イベント

以下のイベントで状態を更新する。

- 再生開始
- 一時停止
- 曲送り
- 曲戻し
- 10秒戻し
- 30秒送り
- 再生完了
- 未再生に戻す
- アプリのバックグラウンド移行

## 13. エラーハンドリング

ユーザーに表示するエラー。

- 音声ファイルが見つからない
- フォルダへのアクセス権がない
- iCloud Driveのファイルを読み込めない
- ローカルコピーに失敗した
- ローカル容量が不足している
- 音声メタデータを取得できない
- 再生できない
- iCloud同期に失敗した

同期失敗時もローカル再生は止めない。

## 14. MVP実装順序

### Step 1: ローカル再生

- ローカルに同梱または手動配置したmp3/m4aを一覧表示
- AVPlayerで再生
- 次ファイル自動再生
- 10秒戻し/30秒送り

### Step 2: フォルダ取り込み

- UIDocumentPickerでフォルダ選択
- security-scoped bookmark の保存/復元（FolderBookmarkStore）
- 音声ファイル列挙
- 未ダウンロードファイルのダウンロード確保（NSFileCoordinator）
- ローカルコピー（再開可能）
- 取り込み進捗表示

### Step 3: 状態管理

- 未再生/途中/再生済み
- 進捗バー
- 未再生に戻す
- ローカルJSON保存

### Step 4: バックグラウンド再生

- AVAudioSession
- Background Audio
- Now Playing Info
- Remote Command Center

### Step 5: iCloud状態同期

- SyncBackend / DocumentSyncBackend（iCloud Documents）
- NSMetadataQuery による外部変更検知
- 起動時マージ
- 最新更新勝ち
- iCloud未設定時はローカルのみ（同期no-op）
- 同期状態表示（端末内のみ含む）

### Step 6: UI仕上げ

- `ui-mock.html` の見た目に近づける
- フォルダ画面
- ファイル一覧画面
- 下部ミニプレイヤー
- 再生画面

## 15. Codex向け実装指示

- `requirements-v1.md` を最優先仕様とする
- `ui-mock.html` の画面構成と見た目をSwiftUIで再現する
- `sync-spec.md` に従って再生状態を同期する
- `architecture.md` のサービス分割を基本とする
- まずMVPを完成させる
- Podcast、Apple Music連携、ファイル編集機能は実装しない
