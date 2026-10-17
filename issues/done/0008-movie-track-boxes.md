# [P0 / M1] moov／trak／mdia／minfと時刻情報を移植する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
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

- [x] Given moovにtrackが1／複数／0の入力, when parseする, then 正常系は型付きTrackInfoが得られ、異常系は定義済みエラーになる。
- [x] Given `mvhd`/`tkhd`/`mdhd`のversion 0/1, when parseする, then 32bit/64bit幅の時間・durationが正しく復元される。
- [x] Given timescale=0, when parseする, then 上流と同じ扱い（または定義済みエラー）になり、暗黙の除算やfloat丸めが起きない。
- [x] Given `hdlr`が音声／映像／字幕, when parseする, then 対応するTrackKindが得られ、未知handlerは定義した扱いになる。
- [x] Given 欠落mandatory box・重複box・不正なnested範囲, when parseする, then 定義済みエラーで失敗する。
- [x] Given TrackInfoの時間値, when Rust oracleと比較する, then track ID／kind／duration／timescaleが一致する。
- [x] Given `elst`付きの入力, when parseする, then edit listはparse・保持され、上流がしない時刻補正が追加されない。
- [x] Given metadata表示に必要な情報, when 型から取得する, then track一覧の表示項目を取得できる。

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
- 2026-10-17: moov/trak/mdia/minf typed port + timestamps の実装に着手（設計は /tmp/opencode/mp4mbt/tasks/0008-moov-tree.md に凍結済み）
- 2026-10-17: 設計確定: 未知handlerは `HdlrBox::track_kind() -> TrackKind?` が `None`（丸めない）。重複boxは最初の1個のみ採用し、以降は `unknown_boxes` に保持。公開名は上流と同名（`MoovBox` / `MvhdBox` / `TrakBox` / `TkhdBox` / `EdtsBox` / `ElstBox` / `MdiaBox` / `MdhdBox` / `HdlrBox` / `MinfBox` / `MediaHeader` / `DinfBox` / `DrefBox` / `UrlBox` と `Mp4FileTime` / `Utf8String` / `LanguageCode` / `TrackKind` / `NonZeroU32`）。欠落必須boxは上流と同じ "Missing mandatory '<name>' box in '<parent>' box"（`InvalidData`）。`mdhd.timescale` は `NonZeroU32` で 0 を `InvalidInput` "Expected a non-zero integer, but got 0" として拒否。UTF-8/NUL の失敗は上流の `Error::invalid_input` に合わせ `InvalidInput`。明示の差: `mvex`/`mehd`/`trex` は 0017 まで `unknown_boxes`、`stbl` は 0009 まで `unknown_boxes`（上流 `MinfBox` は `stbl` を必須にするが 0008 では `dinf` のみ必須。0009 で戻す）。docs/upstream.md に記録。
- 2026-10-17: 追加値型（src/bytes）: `Mp4FileTime`（秒 `UInt64` 保持、`from_secs`/`as_secs`/`from_unix_seconds`。上流の `Duration` 受け渡しは意図的に移植しない）、`Utf8String`（NUL 終端 Encode/Decode、NUL なし `InvalidData` "Null-terminated string not found"、不正 UTF-8 拒否）、`LanguageCode`（3 バイト 0x60..=0x7F、`from_packed`/`to_packed`、`undefined()`）、`TrackKind::{Audio, Video, Subtitle}`、`NonZeroU32`、`ReadCursor::read_fixed_8_8_unsigned` / `WriteCursor::write_fixed_8_8_unsigned`（smhd の balance 用）。
- 2026-10-17: 追加box（src/boxes）: moov 以下の型付きツリー14型と `RootBox::Moov`。`Encode` は canonical（最小32bit幅、`BoxSize::with_payload_size` + `BoxHeader::new`）、`children()` は型付き子→未知の順。`HdlrBox` は `handler_type_vide()/soun()/subt()/text()` ヘルパーを持つ。
- 2026-10-17: 証跡: `moon check`（native/js）警告 0、`moon test --target native` 262 件 PASS、`--target js` 262 件 PASS（内訳: src/bytes 88 件、src/boxes 129 件）、`moon fmt --check` 差分なし、`moon info` 更新済み（`src/boxes/pkg.generated.mbti` に14 box型、`src/bytes/pkg.generated.mbti` に5値型と 8.8 unsigned 読み書きを追加）。unit: version 0/1（u32::MAX 超で再 encode が version 1 になることを含む）、timescale=0 の上流理由一致、必須 box 欠落の8経路（mvhd/tkhd/mdia/mdhd/hdlr/minf/dinf/dref）、重複 mvhd/vmhd の first-wins、未知 box の保持順と `children()` 順、hdlr の vide/soun/subt/text→TrackKind と未知 `zzzz`→None、name の生バイト往復、elst v0/v1・負 media_time・空、url の self-contained/location/NUL 欠落、smhd/vmhd/sthd/nmhd と media_header なし、decode 失敗時の cursor rollback、手組み MoovBox の encode→decode 往復。
- 2026-10-17: Differential: `tools/oracle` に `moov-tree` / `moov-tree-cases` / `moov-tree-fixtures` を追加。固定 SHA の上流 `MoovBox::decode` の `path=value` スナップショット（mvhd 8 行 + track ごとの tkhd/edts/mdia/minf 行）を固定ケース表（31 件）と埋め込み fixture 2 件（`black-h264-video.mp4` / `black-h264-fmp4.mp4` のトップレベル `moov` を抽出、791/770 バイト、sha256 `833eeff1900482f1456952e2a01aad46a1341cb11d0d0d93c5927616b1cb0d6b` / `d4086105a21f8ed7590ae3ed42fde84645475807a0a277a035e85a7b67577cdf`）で比較し一致。成功ケースの `minf` には上流が必須とする `stbl` を最小構成で埋め込む。error ケースは `kind` を常に、`reason` は oracle が非空のときのみ比較（上流 `insufficient_buffer` は reason 空のため。テストに理由コメントを記載）。`cargo test` 13 件 PASS。生成物 `src/boxes/moov_tree_oracle_cases_test.mbt` / `moov_tree_oracle_fixtures_test.mbt` は再生成→`moon fmt` で md5 一致（`7219ddd7d354497e46c27aee4d9b984f` / `b4715643cafc1ee401f146e2371a97b1`）し、CI は再生成→`moon fmt`→`git diff` で検証する（`.github/workflows/ci.yml` / `docs/ci.md` / `tools/oracle/README.md` 更新）。
- 2026-10-17: fixture 9/9 検証済み（`moon run tools/oracle/regenerate_fixtures.mbtx -- --check`: `fixtures: 9, unchanged: 9, written: 0, failures: 0`）。`CHANGES.md` / `docs/upstream.md` / `docs/scope.md` も同じ変更で更新。実装・検証・ドキュメント更新・CI 検証を完了し、done へ移行。
