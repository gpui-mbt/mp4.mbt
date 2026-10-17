# [P0 / M1] MoonBit/JSのブラウザMP4 Dumpデモを作る

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0015-web-mp4-dump
Priority: P0
Milestone: M1
Depends on: [0013](./0013-mp4-file-demux.md), [0014](./0014-demux-example.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

ファイルをドラッグ&ドロップするとBox Tree・track・sample timelineが更新されるGitHub Pages用ブラウザデモを作る。MoonBit coreはJS targetで動かし、UIアダプタがFile.sliceでRange I/Oを提供する。解析はブラウザ内で完結させ、ファイルを外部へ送信しない。

## 背景

- M1の成果物として、Native CLI `demux`（[0014](./0014-demux-example.md)）と並ぶ「目で見て試せる」Web成果物を提供する。0000のアーキテクチャでは `web/` と Range Input Adapter が core の外側に位置し、UIアダプタと Dump UI が core の公開 API だけを使う。
- 上流参照: [examples/dump_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/index.html)、[examples/dump_wasm/src](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/src)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)。
- 上流の dump_wasm は入力ファイル全量をArrayBuffer化してwasmへ渡し、JSONをtextareaへ出す構成で、出力JSONに未知boxの `"unknown": true` があり、boxの出現順は入力順を反映しない場合があると注意書きしている。本移植では同じ制約をそのまま採用せず、Range I/Oと表示順の対応を改善する。
- 現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コード・`web/` はない。本issueは [0013](./0013-mp4-file-demux.md) と [0014](./0014-demux-example.md) の完了後に着手する。

## 問題

- MP4の構造を確認する手段がNative CLIしかなく、環境構築なしに人がBox Treeやsampleを眺められない。
- 上流方式のファイル全量ArrayBuffer化は大容量ファイルでメモリを圧迫し、解析の中断もできない。
- 非対応codec・切断ファイル・不正boxのような異常系でUIがどう振る舞うかが定義されていない。

## 目標

- ファイル選択/ドラッグ&ドロップからBox Tree・track一覧・sample一覧の表示までの経路が動く。
- File.sliceベースのRange I/Oで、ファイル全量を最初からArrayBuffer化しない。
- 大容量・切断・異常MP4でもUIが固まらず、解析をキャンセルできる。
- ファイルはローカルで解析し、外部へアップロードしない。非対応codecは「構造は読めるが再生は非対象」と示す。
- 静的ビルドを `web/` 相当へ出力しPagesで公開できる。CLIと同じcanonical JSON exportを提供する。

## 対象外

- MP4をブラウザで再生すること、WebCodecsによる変換（[0029](./0029-webcodecs-transcode.md)）。
- ファイルのネット送信・外部アップロード・クラウド保存。
- Rust/WASMとの比較表示（[0016](./0016-rust-moonbit-diff.md)が担当する）。
- 解析結果の自動永続化（reload後の復元は行わない）。

## 提案する方針

- MoonBit coreをJS targetでビルドし（0002のtarget方針）、DOM/File APIに触れるのはUIアダプタだけに限定する。アダプタが `File.slice` で要求範囲を読み、0005のRange Input境界（`position` と `size` の要求契約）に従ってcoreへ渡す。
- 表示項目は既存仕様どおりとする。Boxツリーはtype/offset/size/parent、track一覧はcodec/width/height/sample count/timescale、sample一覧はDTS/PTS/duration/keyframe/offset/size。64bit値は0000のデータ契約に従い十進文字列で保持し、Numberへ強制変換しない。
- サイズ・sample数に応じたlazy render/virtual listを実装し、解析のキャンセル機構を用意する。別ファイル再選択・キャンセル時に古い結果が混ざらないよう、処理世代（generation）をUI状態で管理し、世代が古い結果を破棄する。UIフレームワークの有無・ファイル分割・ビルド方式は実装時に確定し、本issueへ追記する。
- 異常系: 不正boxで処理が中断しても画面は残し、エラーに場所・原因・対処（再選択や対応範囲の説明）を含める。非対応codecは構造の表示可否と再生非対応を分けた文言で示す。
- 静的ビルドを `web/` 相当へ出力しPagesで公開する。同一fixtureに対するcanonical JSON exportはCLI（[0014](./0014-demux-example.md)）と共通schemaとし、後続の[0016](./0016-rust-moonbit-diff.md)が差分比較の入力に使えるようにする。
- fixtureは[0004](./0004-oracle-fixtures.md)のmanifestに載る帰属確認済みのものだけを使う。

## 受け入れ条件

- [x] Given AAC/AVC/AV1 fixture, when ブラウザでファイルを選択する, then Box Treeとトラック情報（codec/width/height/timescale等）が表示される。（E2E は AVC fixture で実ブラウザ確認、AAC/AV1/VP9/Opus/HEVC/FLAC/fMP4 は release bundle を Node で駆動して同一路径を確認。codec は表示した sample の entry 由来で、AV1 は `av01.0.04M.08`、AAC は `mp4a.40.2`）
- [x] Given 表示済みの状態, when 別のファイルを再選択する, then 前のファイルの解析結果が残らない。（E2E で再選択後の tree 再描画を確認。`app.js` の generation 番号で古い非同期結果を破棄）
- [x] Given 解析中の状態, when キャンセルする, then 解析が中断してUIが操作可能な状態へ戻る。（`mp4dump_cancel` で `next_request` が `""` になりセッション停止。完了後も同じボタンで結果をクリアできる。E2E で確認）
- [x] Given 不正boxを含むfixture, when 解析が中断する, then 画面は残り、場所・原因・対処を含むエラーが表示される。（切断ファイル・garbage・moov 欠落を Node で確認し `failed` + `error_json`（kind/position/message）を検証。E2E のエラーパスは unsupported codec 文言と併せて確認）
- [x] Given ページをreloadする, when デモを再度開く, then 直前の入力ファイルと解析結果は自動保存されていない。（実装上 storage API を一切使わない。設計上の確認）
- [x] Given 大容量fixture, when 解析する, then ファイル全量のArrayBufferを最初に確保しない（read要求のrange記録で確認する）。（h264 fixture で要求列 `{0,32},{32,32},{40,32},{844,32},{844,791}`、計 919/1635 バイト。`mdat` payload を跨ぐ要求がないことを E2E と wbtest で固定）
- [x] Given 同一fixture, when CLIとブラウザでJSON exportする, then 両者を共通schemaとして比較でき、値の差をfield path単位で識別できる。（`src/demux_report` を CLI/Web で共有。`tracks`/`samples`/`shown_samples`/`truncated` は同一 fixture で完全一致。`file` は basename/パス差のみ、Web 側は `format`/`box_tree`/`requests` など disjoint な追加フィールド）
- [ ] Given Pagesへデプロイした静的ビルド, when URLを開く, then デモが読み込まれ、ファイル選択ができる。（未実行。`pages.yml` は CI 成功後の `web/dist` デプロイ設定済み。手動確認は merge 後の公開 URL で行う）

## テスト計画

- 現時点では `moon.mod` がなく、以下は0002完了後に実行する。PASS / FAIL / 未実行を混同せず記録する。
  - `moon check --target js` と `moon test --target js` を実行し、結果とツールチェーンのバージョンを記録する。
  - wbtest: Range I/Oアダプタが要求するrange列、世代管理で古い結果を破棄する判定、64bit値の文字列化、canonical JSONのkey順を固定する。
- Playwright等のブラウザ実操作テストを実行できる形にする。
  - File選択→tree/timeline表示→別ファイル再選択→キャンセルを操作し、スクリーンショットと表示JSONをCI artifactに保存する。
  - 不正box fixtureでエラー表示（場所・原因・対処）を確認する。
  - 大容量fixtureでreadしたrange列を取得し、全量読込でないことを確認する。
- Pages: デプロイ後のURLを開き、静的デモが操作できることを手動確認する。手動確認は実行日・ブラウザ名・版を記録する。
- fixtureは0004のmanifest（SHA256付き）を使い、checksumとupstream SHAを証跡に残す。ライセンス未確認素材は使わない。
- 現時点ではブラウザE2E・Pages公開のいずれも実行できない。未実行理由（`moon.mod` と `web/` が未作成）をレポートに明記する。

## リスク

- 大容量ファイルで範囲readが増えて表示が遅くなる。virtual listと必要範囲のまとめ読みで抑える。
- 世代管理の不備でキャンセル後に古い結果が混ざる。再選択・キャンセルのwbtestとE2Eで固定する。
- JSのNumber精度で64bit offsetが壊れる。文字列保持の契約を0000/0005と共有し、表示直前まで変換しない。
- 非対応codecを「再生可能」に見せてしまう。構造可読と再生非対応を文言で分離する。
- 上流dump_wasmは全量ArrayBuffer方式であり、本issueは意図的に異なる入出力方式を取る。この差分は仕様として文書化し、上流と同一の内部実装を前提にしない。
- ロールバック: UI・ビルドスクリプトの追加が中心で、coreの公開API契約を変えない。問題時は該当ディレクトリの削除とPages設定の復元で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] MoonBit/JSのブラウザMP4 Dumpデモ（Range I/O・キャンセル・canonical JSON export）

## 注記

- 上流参照: [examples/dump_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/index.html)、[examples/dump_wasm/src](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/src)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)。wasm APIのJSON化関数（`mp4_demux_sample_to_json` / `mp4_demux_track_info_to_json`）はREADMEで公開されており、[0016](./0016-rust-moonbit-diff.md)の比較対象になる。
- 関連: [0013](./0013-mp4-file-demux.md)（demuxer）、[0014](./0014-demux-example.md)（CLI）、[0016](./0016-rust-moonbit-diff.md)（差分Lab）、[0029](./0029-webcodecs-transcode.md)（WebCodecs変換）、[0030](./0030-native-gpui-inspector.md)（Native版）。
- 運用: 公開Pagesへ入力ファイルを置かない。CI証跡はスクリーンショット・JSON・read rangeログに限定する。
- 実装時に確定した事項（2026-10-18 記録）:
  - ディレクトリ構成: `web/index.html` + `web/app.js` + `web/style.css` + `web/build.sh`（静的ビルド）+ `web/e2e/e2e.mjs`（Playwright E2E）。`web/dist/` は生成物で gitignore 済み。
  - JS 公開方式: `src/webdump` を `pkgtype(kind: "foreign_library")` とし、`#export_name("mp4dump_*")` の 11 関数を ESM バンドル（`web/dist/mp4.js`、release で約 706KB）として出力。`extern "js"` は使わず、DOM/File API はすべて `web/app.js` に閉じる。`UInt64`↔`BigInt`、`Bytes`↔`Uint8Array` を実機確認済み。
  - セッション機械: `walk`（box header 巡回）→ `detect`（`Mp4FileKindDetector`）→ `demux`（`Mp4FileDemuxer`）→ `moov`（`build_box_tree` で `moov` 子孫取得）→ `collect`（sample 列挙）→ `ready` / `failed` / `cancelled`。要求は `{"position","size"}` の JSON 文字列、応答は `mp4dump_feed(Bytes)`。供給済み range はキャッシュして重複要求を即座に解消する。
  - canonical JSON schema: `src/demux_report` を CLI と共有。`{file, tracks:[{index,track_id,kind,codec,duration,timescale}], samples:[...], shown_samples, truncated}` に Web 側は `file_size`/`format`/`state`/`sample_total`/`box_tree`/`requests`/`error` を追加。track の `codec` は表示した sample の entry 由来 RFC 6381 文字列（sample 無しは `null`）。
  - UI フレームワーク: なし（vanilla HTML/CSS/JS）。sample 一覧は windowing 付き table で仮想化。言語は上流 dump_wasm に倣い日本語。
  - キャンセル/世代管理: `app.js` の generation 番号で再選択・キャンセル時に古い `File.slice` 結果を破棄。解析完了後もキャンセルボタンは有効のまま残し、結果のクリアとして機能する（E2E で小 fixture が一瞬で完了する競合を回避するため）。
  - Pages デプロイ: `.github/workflows/pages.yml` は `main` 上の CI 成功後 + 手動 dispatch で `sh web/build.sh` → `web/dist` のみ artifact 化して deploy。CI 失敗時は一切デプロイしない。
  - CI: `web-build` job で release bundle 構築 + Node ESM smoke（create/next_request/state/cancel）を追加。Playwright E2E はブラウザ DL を CI に入れない方針でローカルツールとした。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
- 2026-10-18: 実装・検証完了のため done へ。証跡: `moon test` 412/412 PASS、`moon test --target js` 412/412、`moon test --target native` 428/428（CLI 16 件含む）、`moon check` native/js とも 0 error / 0 warning、`moon fmt`/`moon info` 適用済み。release bundle を Node で駆動し 9 fixture 全て `ready`（fMP4 は `format=fragmented` で sample 0）、切断/garbage/moov 欠落は `failed`+`InvalidData`、cancel は `cancelled`+空要求を確認。headless Chromium の Playwright E2E（`web/e2e/e2e.mjs`）14/14 PASS: 選択→tree/track/sample/JSON 表示、再選択、cancel/clear、`mdat` payload 非要求（919/1635 bytes）を検証。CLI `--json` と `mp4dump_report_json` の `tracks`/`samples`/`shown_samples`/`truncated` が同一 fixture で完全一致することを確認（`file` は basename/パス差のみ）。Pages 公開 URL の手動確認のみ未実行（merge 後に実施）。
