# Step 2: フォルダ取り込み Design

## 1. 目的

Step 2 では、Step 1 で作ったローカル再生の芯を保ったまま、Files/iCloud Drive 上の任意フォルダから mp3/m4a をアプリ専用領域へ取り込めるようにする。

完了時点で確認できる状態は、「フォルダを選ぶ -> 音声ファイルがローカルへコピーされる -> 一覧に表示される -> タップして再生できる」こと。

## 2. MVP Roadmap

Step 2 以降で全体像を見失わないよう、MVP までの切り方をここに固定する。

1. Step 1: ローカル再生（完了）
2. Step 2: フォルダ画面 + フォルダ選択 + ローカル取り込み
3. Step 3: 一覧/ミニプレイヤーを `ui-mock.html` 寄せ + 再生状態表示
4. Step 4: 再生位置/状態の JSON 永続化
5. Step 5: Now Playing 画面 + バックグラウンド再生
6. Step 6: iCloud 状態同期
7. Step 7: フォルダ再指定/再同期/エラー仕上げ

この Roadmap は `docs/architecture.md` の実装順序をベースにしつつ、各 Step が画面上で動作確認しやすい単位になるように並べ替えたもの。

## 3. Step 2 の範囲

Step 2 で作るもの。

- `FolderView`: フォルダ画面。前回取り込み情報、取り込みボタン、一覧への導線、取り込み中の進捗、エラーを表示する。
- `FolderViewModel`: フォルダ画面の状態管理。取り込み開始、進捗、成功、失敗、一覧更新の橋渡しを行う。
- `FolderPicker`: SwiftUI から `UIDocumentPickerViewController` を呼び出す薄い wrapper。フォルダ選択のみを扱う。
- `FolderImportService`: 選択フォルダ内の mp3/m4a を列挙し、アプリ専用 `audio/` ディレクトリへコピーする。
- `FolderImportSummary`: 取り込み元フォルダ名、ファイル数、容量、最終取り込み日時を保持する表示用モデル。
- `FolderImportSummaryStore`: Step 2 では前回取り込み情報だけを軽量に保存/復元する。再生位置や未再生状態は保存しない。
- `ImportMode`: 後続の再指定に備え、`replaceAll` と `mergeOverwrite` の型を用意する。

Step 2 の取り込み動作。

- 対応形式は `.mp3` と `.m4a`。
- 対応音声ファイルが 0 件の場合はコピーせず、ユーザーにエラー表示する。
- `replaceAll` は既存の `audio/` を空にしてからコピーする。
- `mergeOverwrite` は同名ファイルを上書きし、新規ファイルを追加し、ローカルにだけあるファイルは残す。
- コピー完了後、既存の `AudioListViewModel.load()` 相当の経路で一覧を再読み込みする。
- ファイル一覧と再生制御は Step 1 の実装を使い続ける。

## 4. Step 2 では作らないもの

以下は意図的に後続 Step へ送る。

- 再生位置、未再生/途中/再生済み状態の本格保存（Step 4）
- 進捗バー、再生中バッジ、長押しメニューなど一覧 UI の完成形（Step 3）
- Now Playing 画面と再生速度 UI（Step 5）
- ロック画面/コントロールセンター操作、バックグラウンド再生（Step 5）
- iCloud Documents による状態同期（Step 6）
- stale bookmark の本格復旧 UI、再同期の詳細モード、容量不足など全エラーの仕上げ（Step 7）
- 音声ファイル本体の iCloud 同期、ストリーミング再生、ファイル編集機能

## 5. 画面構成

Step 2 の入口は `FolderView` にする。初回起動時はフォルダ画面を表示し、取り込み済み音声がある場合は一覧へ進めるようにする。

表示内容。

- タイトル: `フォルダ`
- 前回取り込み元: フォルダ名、ファイル数、容量、最終取り込み日時
- 主操作: `別フォルダを選択`
- 取り込み済みの場合: `一覧を開く`
- 取り込み中: `n / total` のファイル単位進捗
- エラー: 対応音声なし、コピー失敗、フォルダアクセス失敗

Step 2 の UI は `docs/ui-mock.html` のフォルダ画面に寄せるが、細部の見た目調整は Step 3 以降へ送る。まずは操作経路と状態表示を優先する。

## 6. サービス設計

### FolderImportService

責務。

- 選択されたフォルダ URL を受け取る。
- security-scoped resource にアクセスできる場合は `startAccessingSecurityScopedResource()` と `stopAccessingSecurityScopedResource()` をペアで扱う。
- フォルダ直下の mp3/m4a を列挙する。
- ファイル名の自然順で並べる。
- コピー先 `audio/` を準備する。
- `ImportMode` に従って既存ファイルを扱う。
- コピー進捗を通知する。
- コピー結果として `AudioItem` 一覧と `FolderImportSummary` を返す。

Step 2 ではフォルダ直下のみを対象にする。サブフォルダ再帰は MVP 仕様に明記されていないため実装しない。

### FolderImportSummaryStore

責務。

- 前回取り込み元フォルダ名、ファイル数、容量、最終取り込み日時を保存する。
- アプリ起動時に `FolderView` へ表示できるよう復元する。

保存形式は小さな JSON を `Application Support/AudioFolderPlayer/state/folder-import-summary.json` に置く。Step 4 の playback-state JSON とは別ファイルにし、後で統合や再配置がしやすい形にする。

### Bookmark

Step 2 では、選択フォルダの security-scoped bookmark 保存を実装対象に含める。ただし失効時の高度な復旧フローは Step 7 に回す。

- 保存: `FolderBookmarkStore` に bookmark data を保存する。
- 復元: 起動時に前回フォルダ URL を復元できる場合は `再同期` の土台として保持する。
- 復元不可または stale の場合は、Step 2 では「再選択が必要」と表示する。

## 7. データフロー

1. ユーザーが `別フォルダを選択` をタップする。
2. `FolderPicker` が folder URL を返す。
3. `FolderViewModel` が `FolderImportService.importFolder(url, mode: .replaceAll)` を呼ぶ。
4. `FolderImportService` が対応音声を列挙する。
5. 0 件なら `FolderViewModel` がエラーを表示する。
6. 1 件以上なら `audio/` へコピーし、進捗を更新する。
7. コピー完了後、`FolderImportSummaryStore` が summary を保存する。
8. `AudioListViewModel` がローカル `audio/` を再読み込みする。
9. ユーザーは一覧へ進み、既存の再生機能で再生する。

## 8. エラー処理

Step 2 でユーザーに表示するエラー。

- 対応音声ファイルが見つからない。
- フォルダにアクセスできない。
- ファイルコピーに失敗した。
- 前回フォルダの権限を復元できない。

エラー表示は SwiftUI の alert かインラインメッセージでよい。詳細なエラー分類やリトライ UI の磨き込みは Step 7 へ送る。

## 9. テスト方針

単体テスト。

- `FolderImportServiceTests`
  - mp3/m4a のみをコピーする。
  - 非対応拡張子を無視する。
  - 対応音声 0 件ならエラーにする。
  - `replaceAll` が既存 audio ファイルを削除してからコピーする。
  - `mergeOverwrite` が既存ローカルファイルを残し、同名ファイルを上書きする。
  - コピー結果が自然順になる。
- `FolderImportSummaryStoreTests`
  - summary を保存/復元できる。
  - 保存ファイルがない場合は nil を返す。
- `FolderViewModelTests`
  - 成功時に summary と一覧更新状態を反映する。
  - 0 件エラーを表示状態に変換する。

UI スモーク。

- 自動 UI テストでは document picker 操作は扱わない。
- 既存のサンプルまたはテスト注入した状態で、フォルダ画面から一覧へ進めることを確認する。
- 実際の Files/iCloud Drive フォルダ選択は手動スモーク項目として記録する。

## 10. 完了条件

Step 2 は以下を満たしたら完了。

- フォルダ画面がアプリ入口として表示される。
- Files/iCloud Drive のフォルダを選択できる。
- 選択フォルダ直下の mp3/m4a がローカル `audio/` へコピーされる。
- 対応音声 0 件の場合にエラー表示される。
- 取り込み中の進捗が表示される。
- 取り込み完了後、一覧にコピー済みファイルが表示される。
- 一覧からタップして再生できる。
- 前回取り込み情報が再起動後も表示される。
- `xcodebuild test` が通る。
- シミュレータで、フォルダ選択から再生までの手動スモークが通る。
