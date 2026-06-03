# Audio Folder Player 同期仕様 v1

## 1. 目的

iPhone/iPadなど複数端末間で、音声ファイルの再生状態を同期する。

音声ファイル本体は同期対象にしない。音声ファイル本体は各端末でiCloud Driveフォルダからローカルへ取り込む。

同期対象は再生状態のみとする。

## 2. 同期対象

同期対象は以下。

- 現在再生中のファイル
- 各ファイルの再生位置
- 各ファイルの状態
  - 未再生
  - 途中
  - 再生済み
- 各ファイルの最終更新日時
- アプリ全体の最終再生ファイル
- アプリ全体の最終更新日時

## 3. 同期対象外

以下は同期しない。

- 音声ファイル本体
- iCloud Drive上のフォルダ構造
- iCloud Drive上のファイル削除
- iCloud Drive上のファイル名変更
- ローカルキャッシュファイル本体
- 秒単位のリアルタイム再生位置
- Apple Podcasts/Apple Musicの状態

## 4. ファイル識別子

同期では、端末間で同じ音声ファイルを識別する必要がある。

MVPでは以下を組み合わせた文字列を `fileId` とする。

```text
normalizedFileName + fileSizeBytes
```

例。

```text
AWS設計入門 02.mp3|73400320
```

durationSec は `fileId` には含めない。durationは取得経路・VBR・OSバージョンで端末間に揺れが出るため、識別子から外す。durationは状態の保存フィールドとしてのみ保持する。

### 4.1 normalizedFileName

- ファイル名の前後空白を除去する
- 大文字小文字は区別しない
- **Unicode正規化（NFC統一）を必須とする**

`fileId` は端末間で完全一致する必要がある。APFS/iCloudのファイル名正規化（NFC/NFD）差で食い違わないよう、生成時に必ずNFCへ正規化する。

### 4.2 durationSec

- 音声メタデータから取得する
- 取得できない場合は0を入れる
- `fileId` の一部ではなく、状態の保存フィールドとして扱う

### 4.3 将来拡張

将来的にはSHA-256などのハッシュを使う余地を残す。

ただしMVPでは大容量音声ファイルの全量ハッシュ計算は避ける。

## 5. 状態モデル

各ファイルは以下の状態を持つ。

```json
{
  "fileId": "AWS設計入門 02.mp3|73400320",
  "fileName": "AWS設計入門 02.mp3",
  "durationSec": 4360,
  "positionSec": 2472.5,
  "status": "inProgress",
  "updatedAt": "2026-06-03T06:30:00+09:00"
}
```

### 5.1 status

`status` は以下。

- `unplayed`
- `inProgress`
- `played`

### 5.2 positionSec

- 未再生の場合は0
- 途中の場合は現在位置
- 再生済みの場合はdurationSec、または再生完了とみなす位置

### 5.3 再生済み判定

以下のいずれかを満たしたら再生済みにする。

- AVPlayerの再生完了イベントを受け取った
- `positionSec >= durationSec - playedThresholdSec`

`playedThresholdSec` はMVPでは30秒を推奨する。

## 6. 全体状態モデル

アプリ全体の同期状態は以下。

```json
{
  "schemaVersion": 1,
  "lastPlayedFileId": "AWS設計入門 02.mp3|73400320",
  "lastPlayedPositionSec": 2472.5,
  "lastUpdatedAt": "2026-06-03T06:30:00+09:00",
  "files": {
    "AWS設計入門 01.mp3|68157440": {
      "fileName": "AWS設計入門 01.mp3",
      "durationSec": 3922,
      "positionSec": 3922,
      "status": "played",
      "updatedAt": "2026-06-02T21:10:00+09:00"
    },
    "AWS設計入門 02.mp3|73400320": {
      "fileName": "AWS設計入門 02.mp3",
      "durationSec": 4360,
      "positionSec": 2472.5,
      "status": "inProgress",
      "updatedAt": "2026-06-03T06:30:00+09:00"
    }
  }
}
```

## 7. 同期ストレージ

MVPでは **iCloud Documents** を使う。アプリのiCloudコンテナ内に再生状態JSONを1ファイルとして置き、端末間で同期する。

```text
<iCloud Container>/Documents/playback-state.json
```

`NSUbiquitousKeyValueStore` は合計1MB上限があり、フォルダ単位の大量ファイル管理で破綻しうるため採用しない。

### 7.1 二層構成

- ローカル `Application Support/.../state/playback-state.json` を常に **source of truth** とする
- `SyncBackend`（`DocumentSyncBackend`）がiCloudコンテナのファイルへミラーする
- ローカル保存は常に成功扱い、iCloud反映は非同期・失敗しても例外を投げない

### 7.2 iCloud未設定・オフライン時

- iCloudにサインインしていない、またはiCloud Driveが無効な場合、iCloudコンテナURLは取得できない
- このときは **ローカルのみで正常動作**し、同期は静かに無効化する（単一端末アプリとして成立）
- UIには「端末内のみ（iCloud未設定）」と控えめに表示する

## 8. 同期タイミング

以下のタイミングでローカル状態を保存し、iCloudへ反映する。

- 一時停止
- 曲送り
- 曲戻し
- 再生完了
- 未再生に戻す操作
- 先頭から再生する操作
- アプリがバックグラウンドへ移行するとき
- アプリ終了相当のライフサイクルイベント

秒単位の連続同期はしない。

## 9. 保険同期

クラッシュや強制終了に備え、再生中は一定間隔でローカル保存のみ行う。

推奨。

```text
ローカル保存: 30〜60秒ごと
iCloud同期: 操作イベント時のみ
```

MVPでは、iCloud同期を頻繁に呼ばない。

## 10. 競合解決

競合解決は「最新更新勝ち」とする。

### 10.1 ファイル単位

同じ `fileId` の状態が複数端末で異なる場合、`updatedAt` が新しいものを採用する。

### 10.2 全体状態

`lastPlayedFileId` などアプリ全体の状態は、`lastUpdatedAt` が新しいものを採用する。

### 10.3 注意

片方の端末で古い状態を開いたまま操作すると、もう片方の端末の状態を上書きする可能性がある。

MVPではこの仕様を許容する。

## 11. 起動時の同期フロー

アプリ起動時。

1. ローカル状態を読み込む
2. iCloud（状態JSONファイル）から同期状態を読み込む。iCloud未設定時はこの手順をスキップする
3. ローカル状態とiCloud状態をマージする
4. ローカルに存在するファイルだけを再生可能として表示する
5. iCloud側に状態があるがローカルにファイルがない場合は、状態だけ保持し、再生対象にはしない

## 12. フォルダ取り込み後の同期フロー

iCloud Driveフォルダから音声ファイルを取り込んだ後。

1. ローカル音声ファイル一覧を作成する
2. 各ファイルの `fileId` を生成する
3. iCloud側の状態と照合する
4. 一致する `fileId` があれば再生位置・状態を反映する
5. 一致しないファイルは `unplayed` とする
6. ファイル名昇順で表示する

## 13. 未再生に戻す操作

ユーザーが任意のファイルを未再生に戻した場合。

```json
{
  "positionSec": 0,
  "status": "unplayed",
  "updatedAt": "現在時刻"
}
```

この変更はiCloudへ同期する。

## 14. 再生完了時

再生完了時。

1. 対象ファイルを `played` にする
2. `positionSec` を `durationSec` にする
3. `updatedAt` を更新する
4. 次のファイルがあれば自動再生する
5. 次のファイルを `lastPlayedFileId` にする
6. iCloudへ同期する

## 15. 同期失敗時

iCloud同期に失敗しても、ローカル再生は継続する。

- ローカル状態は必ず保存する
- UIに同期失敗を表示する
- 次回同期タイミングで再試行する

iCloud未設定（未サインイン/iCloud Drive無効）は「失敗」ではなく正常系として扱う。エラー表示はせず、「端末内のみ」と控えめに表示する。

## 16. スキーマバージョン

同期JSONには `schemaVersion` を持たせる。

MVPでは `1` とする。

将来の変更に備え、読み込み時は未知フィールドを無視できる実装にする。
