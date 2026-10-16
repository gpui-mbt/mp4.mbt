# [P0 / M1] moov／trak／mdia／minfと時刻情報を移植する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0008-movie-track-boxes
Priority: P0
Milestone: M1
Depends on: [0007](./0007-root-box-tree.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

MP4の映画単位とトラック単位を構造化し、track ID・kind・duration・timescaleを正確に取り出す。version 0/1の時間幅、`hdlr`の種別、必須子boxの過不足、edit listの保持までを型付きで扱い、[0009](./0009-sample-tables.md)以降の共通metadata型にする。

## 背景

- 上流は [src/boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_moov_tree.rs) でmoov以下を型付き解析し、[tests/test_boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_moov_tree.rs) が構造と時刻を固定している。基本型は [src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs) に対応する。本issueはこの移植である。
- 前提として[0007](./0007-root-box-tree.md)のBoxNodeと未知box保持が必要になる。
- 消費側は[0009](./0009-sample-tables.md)（sample table）、[0010](./0010-sample-entries.md)（sample entryの型）、[0012](./0012-file-kind-detector.md)、[0013](./0013-mp4-file-demux.md)、[0015](./0015-web-mp4-dump.md)（Inspectorのtrack表示）、[0016](./0016-rust-moonbit-diff.md)（差分）である。
- 未実装状態: `mp4.mbt`はREADMEと`issues/`だけで、`moon.mod`もpackageもない（[0000](./0000-implementation-roadmap.md)）。

## 問題

- moov以下のboxを型付きで読み、必須子boxの欠落・重複・不正な入れ子を検出する実装がない。
- version 0と1で時刻・durationの幅（32bit/64bit）が異なり、同じ型で流用すると値が壊れる。
- `hdlr`の音声・映像・字幕に対応するTrackKindと未知handlerの扱い、`sthd`/`nmhd`/`vmhd`/`smhd`の合法な組が未定義である。
- Duration／timescaleを浮動小数にすると比較で丸めが入り、DTSとPTSを混同する危険がある。
- edit list（`elst`）のparse・保持の範囲が未定義だと、demux側で勝手な時刻補正をし得る。

## 目標

- `mvhd`/`tkhd`/`mdhd`/`hdlr`/`minf`/`dinf`/`edts`/`elst`等を上流の型に対応させ、version 0/1の時間・duration幅の違いを実装する。
- `hdlr`の音声・映像・字幕に対応するTrackKindと未知handlerの扱いを定義する。`sthd`/`nmhd`/`vmhd`/`smhd`の合法な組を明示する。
- Moov構造の必須子boxの重複・欠落・入れ子の不正値を検出する。未知boxは保持し、known boxの必須項目は型付けする。
- Duration／timescaleは整数のまま保持し、秒表示だけ有理数変換する。DTSとPTSを混同しない。
- edit list（`elst`）はまずparse・保持までとし、demuxの時刻補正を上流がしない場合は勝手に加えない。
- 主要metadata型とテストを公開し、metadata表示デモに必要な情報を取得可能にする。タイムスタンプの暗黙のfloat丸めがない。

## 対象外

- 字幕ペイロードの意味解析は[0028](./0028-subtitle-sample-entry.md)で扱う。
- editsを使った再生時刻調整は非対象。parse・保持に留める。
- sample tableの詳細（`stbl`配下）は[0009](./0009-sample-tables.md)、sample entryの種類は[0010](./0010-sample-entries.md)の範囲。

## 提案する方針

- 候補package`src/boxes`（[0000](./0000-implementation-roadmap.md)の提案パッケージ）にmoov以下のtyped boxを実装し、[0007](./0007-root-box-tree.md)のBoxNodeの上に構築する。実際の`moon.pkg`分割と公開名は[0002](./0002-moonbit-bootstrap.md)で確定する。
- `mvhd`/`tkhd`/`mdhd`/`hdlr`/`minf`/`dinf`/`edts`/`elst`等を上流の型に対応させる。version 0/1の時間・duration幅（32bit/64bit）の違いを明示的に実装する。
- `hdlr`から音声・映像・字幕に対応するTrackKindを導出し、未知handlerの扱いを定義する。`sthd`/`nmhd`/`vmhd`/`smhd`の合法な組を仕様として明示する。
- Moov構造の必須子boxの重複・欠落・入れ子の不正値を検出する。未知boxは保持し、known boxの必須項目は型付けする。
- Duration／timescaleは整数のまま保持する。秒表示だけ有理数変換し、DTSとPTSを混同しない（PTS=DTS+composition_time_offsetの契約は[0000](./0000-implementation-roadmap.md)のデータ契約1）。
- edit list（`elst`）はparse・保持までとし、demuxの時刻補正を上流がしない場合は勝手に加えない。
- 互換性要件: [0004](./0004-oracle-fixtures.md)のoracleでTrackInfoのtrack ID／kind／duration／timescaleと時刻値を比較する。[0009](./0009-sample-tables.md)以降は同じmetadata型を使う。
- 境界条件: moov内のtrack 1／複数／0、`mvhd`/`tkhd`/`mdhd`のversion 0/1、timescale=0、各TrackKind、edit-list境界、欠落mandatory box、重複box、不正なnested範囲をテスト表に置く。

## 受け入れ条件

- [ ] Given moovにtrackが1／複数／0の入力, when parseする, then 正常系は型付きTrackInfoが得られ、異常系は定義済みエラーになる。
- [ ] Given `mvhd`/`tkhd`/`mdhd`のversion 0/1, when parseする, then 32bit/64bit幅の時間・durationが正しく復元される。
- [ ] Given timescale=0, when parseする, then 上流と同じ扱い（または定義済みエラー）になり、暗黙の除算やfloat丸めが起きない。
- [ ] Given `hdlr`が音声／映像／字幕, when parseする, then 対応するTrackKindが得られ、未知handlerは定義した扱いになる。
- [ ] Given 欠落mandatory box・重複box・不正なnested範囲, when parseする, then 定義済みエラーで失敗する。
- [ ] Given TrackInfoの時間値, when Rust oracleと比較する, then track ID／kind／duration／timescaleが一致する。
- [ ] Given `elst`付きの入力, when parseする, then edit listはparse・保持され、上流がしない時刻補正が追加されない。
- [ ] Given metadata表示に必要な情報, when 型から取得する, then track一覧の表示項目を取得できる。

## テスト計画

- `moon.mod`とpackageがまだ無いため、本issueの確認は現時点で未実行とする。PASS / FAIL / 未実行を独立に記録し、実行できない確認をPASSと書かない（[0000](./0000-implementation-roadmap.md)）。
- 将来実行するコマンド: `moon check`、`moon fmt`の差分チェック、`moon info`、`moon test --target native`、`moon test --target js`。実行時はtarget・commit SHA・fixture checksum・日時を証跡に残す。
- Unit（whitebox）テスト: track 1／複数／0、`mvhd`/`tkhd`/`mdhd`のversion 0/1、timescale=0、各TrackKind、edit-list境界、欠落・重複box、不正なnested範囲。
- Differential: [0004](./0004-oracle-fixtures.md)のoracleでTrackInfoの時間をRust版と比較する。64bit整数は十進文字列で比較する（[0000](./0000-implementation-roadmap.md)のデータ契約6）。
- 手動確認: [0015](./0015-web-mp4-dump.md)のDumpでtrack一覧を表示する時点で確認する。本issue単体ではUIを作らない。
- 実行できない確認: 上流fixtureの権利・取得が未確認のテストは未実行として報告する（[0004](./0004-oracle-fixtures.md)と同じ扱い）。

## リスク

- 32bit/64bit幅の取り違え: version 0/1で同じ型を流用すると値が壊れる。versionごとのdecodeテストを必須にする。
- timescale=0の除算: 秒表示や比較でゼロ除算が起き得る。整数保持と有理数変換の境界で明示的に扱う。
- 未知handlerの丸め: 未知の`hdlr`をvideo扱いなどに丸めると後続のtrack判定が誤る。定義した扱い（保持・unsupported）を固定する。
- edit listの過剰解釈: 上流がしない時刻補正をMoonBit側で足すと差分が出る。parse・保持に留める。
- 重複boxの決定規則: どちらを採用するか未定義だとRustとずれる。決定規則をUnitテストで固定する。
- ロールバック: 新規型の追加が中心で成功パスの既存契約を変えない。問題時は該当commitのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] moov／trak／mdia／minfの型付き解析と時刻情報の保持を追加

## 注記

- upstreamの対応物: [src/boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_moov_tree.rs)、[tests/test_boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_moov_tree.rs)、[src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)。
- 関連: [0007](./0007-root-box-tree.md)（前提）、[0009](./0009-sample-tables.md) / [0010](./0010-sample-entries.md)（後続）、[0012](./0012-file-kind-detector.md) / [0013](./0013-mp4-file-demux.md)（消費者）、[0015](./0015-web-mp4-dump.md) / [0016](./0016-rust-moonbit-diff.md)（表示と差分）、[0028](./0028-subtitle-sample-entry.md)（字幕の非対象範囲）。
- 証跡ルール: checkboxは実際に実行した証拠がある項目だけ完了にする。実行コマンド・target・commit SHA・fixture checksum・PASS/FAIL/未実行の区分を残す（[0000](./0000-implementation-roadmap.md)と[0003](./0003-ci-contract.md)に整合）。
- 実装時の未決事項: TrackKindの未知handler表現、重複boxの採用規則、公開型名。確定後は本issueへ追記する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
