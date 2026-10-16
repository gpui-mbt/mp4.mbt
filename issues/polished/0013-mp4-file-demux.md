# [P0 / M1] Sans I/O通常MP4 Demuxerを移植する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0013-mp4-file-demux
Priority: P0
Milestone: M1
Depends on: [0009](./0009-sample-tables.md), [0010](./0010-sample-entries.md), [0012](./0012-file-kind-detector.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

v0.1 の主要 API として Sans I/O の `Mp4FileDemuxer` を移植し、トラックと時系列順 sample を取り出せるようにする。少なくとも H.264/AAC/Opus fixture のトラック情報・サンプル metadata を上流と一致させる。

## 背景

- 上流の固定基準 [`1282b704`](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59) の [src/demux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file.rs) は `Mp4FileDemuxer`（`required_input` / `handle_input` / `tracks` / `next_sample`）と `TrackInfo` / `Sample` / `RequiredInput` / `Input` / `DemuxError` を定義し、`ReadFtypBoxHeader → ReadFtypBox → ReadMoovBoxHeader → ReadMoovBox → Initialized` の状態機械で `moov` までを読む。公開型の再輸出は [src/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux.rs) にある。
- 上流の fixture テストは [tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)、動作例は [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs) にある。
- 0009 の `SampleTableAccessor` がサンプル位置と時間を、0010 の `SampleEntry` がコーデック情報を、0012 の kind 判定がファイル種別を担う。本 issue はそれらを束ねて demuxer にする。
- 0004 の Rust oracle golden と同じ fixture で semantic 一致を判定する。

## 問題

- Sans I/O の入力契約（`RequiredInput` の position/size、`handle_input` が要求範囲を一度に満たすこと）を曖昧にすると、呼び出し側の range 読取と再要求が上流と食い違い、semantic 一致を確認できない。
- sample 順序を track ID 順や浮動小数の比較で実装すると、timescale 跨ぎの同時刻比較で丸め誤差や tie-break のずれが入る。
- `data_offset` の基準（ファイル絶対位置）や `timestamp = DTS` の契約を混同すると、payload が別範囲を指す。
- `moov` が末尾のファイルでコアが全量読込を強いると、巨大ファイルでメモリを使い果たす。
- `DemuxError` の 4 区分を潰すと、再要求すべきか失敗すべきかが呼び出し側で判断できない。

## 目標

- 公開 API: `Mp4FileDemuxer` 相当の demuxer と `RequiredInput` / `Input` / `TrackInfo` / `Sample`、`InputRequired`、`DecodeError`、`SampleTableError`、`InvalidState` の 4 区分を持つ `DemuxError` 相当を定義する。
- `tracks()` が track_id / kind / duration / timescale を返す。
- `next_sample()` が decode timestamp 順に sample を返す（比較は track ごとの timescale を跨ぎ、浮動小数を経由せず精度劣化がない形で行う）。
- `Sample` に timestamp（DTS）、duration、composition_time_offset（PTS = DTS + CTTS。`ctts` 未設定と 0 を区別する）、data_offset（ファイル絶対位置）、data_size、keyframe、変更時のみ sample_entry を載せる。
- `moov` が末尾のファイルでも必要位置から再読込できるようにし、コアではディスク全量読込を禁止する。
- Rust golden との semantic 一致を CI で確認し、対象 fixture 数を示す。
- 大きな `mdat` を全メモリへ保持しない。

## 対象外

- sample payload を codec として解凍すること（本 issue は位置と metadata までを扱う）。
- `Fmp4SegmentDemuxer`（0018）と `Fmp4FileDemuxer`（0019）。fMP4 は別実装とする。
- ファイル種別判定そのもの（0012）と fMP4 の構造 box（0017）。
- `prev_sample` / `seek` は上流に対応物があるが、本 issue の受入に含めるか実装時に確定する（含めない場合は後続 issue を立てる）。

## 提案する方針

- 対象は `src/demux` 相当のパッケージに置く（package 名・ファイル分割は 0002 の命名表に従い実装時に確定する）。公開名・型名は上流に対応付けた命名表を使う。
- 状態機械は上流どおりとし、`ftyp` と `moov` の decode に 0007 / 0008 を使う。初期化時に `trak` ごとに `tkhd.track_id`、`mdhd.duration`/`timescale`、`hdlr.handler_type` → `TrackKind`（`vide`/`soun`/字幕 2 種）を読み、`stbl` から 0009 の accessor を構築する。
- I/O 契約の互換性: `handle_input` は `required_input` が示した範囲を包含する入力を一度に受け取り、部分消費をしない。要求を満たさない入力はエラー状態になり、以降 `required_input` は none 相当になる（上流と同じ）。要求範囲より大きい入力を渡すことは許容する。
- `next_sample` は全 track の次の sample から最も早い timestamp を選び、その track を 1 つ進める。比較は各 track の timestamp を timescale で割った整数系の値で行い、異 timebase の同時刻 tie-break は上流実装（走査順で先の track が残る）に合わせて golden で固定する。
- `Sample.sample_entry` は、sample entry の index が変わった場合だけ前 sample の entry と内容を比較し、変更があれば `Some` を載せる。最初の sample は常に `Some` とする（上流と同じ）。
- エラー分類: `DecodeError`（box decode・不正入力）、`SampleTableError`（0009 の accessor エラー）、`InvalidState`（初期化前の呼び出しなど）、`InputRequired`（追加入力の要求）の 4 区分を維持する。
- 互換性要件: `Sample.timestamp` は DTS、PTS は DTS + CTTS、`ctts` 未設定（None）と 0 を区別し、`data_offset` はファイル絶対位置とする（0000 の「変更できないデータ契約」1 / 2）。
- 境界条件: 未充足 Input、短い range、EOF、不正 `stbl`、handler 未知の track を上流と同じ扱いにする。上流 `1282b704` は `hdlr` が vide/soun/subt/text 以外の track を追加せず skip するため、oracle でも同じ track 集合になることを確認する。sample index のオーバーフローも明示エラーにする。
- `moov` 末尾のファイルは `required_input` の offset skip と range 読取だけで扱い、1MB 単位の分割受信はアダプタ（0014）側で結合する。

## 受け入れ条件

- [ ] Given pinned Rust oracle の golden, when 同じ fixture を MoonBit demuxer へ入力する, then track の id / kind / duration / timescale が一致する。
- [ ] Given 上流 `examples/demux.rs` と同条件（先頭 10 sample 表示）, when 比較する, then 表示データが一致する。
- [ ] Given AAC/Opus/AV1/video-only・複数 track・`moov` 先頭/末尾・CTTS 付きの fixture, when 全 sample を走査する, then DTS / CTTS / offset / size / keyframe が golden と一致する。
- [ ] Given 複数 track で DTS が並ぶ, when `next_sample` を呼ぶ, then track ID 順ではなく DTS 時間順で返り、異 timebase の同時刻 tie-break も上流実装と一致する。
- [ ] Given 未充足の Input と短い range, when `handle_input` する, then `InputRequired` 相当になり呼び出し側が再読込できる。
- [ ] Given 入力が要求位置で EOF に達する, when `handle_input` する, then 明示エラーになり再要求を繰り返さない。
- [ ] Given 不正な `stbl`, when 初期化・走査する, then `SampleTableError` 相当のエラーになる。
- [ ] Given 未知 handler の track, when `tracks()` する, then 上流 oracle と同じ track 集合になる（skip され、panic しない）。
- [ ] Given 大きな `mdat`, when sample を走査する, then payload を全メモリへ保持しない（読取量の証跡）。

## テスト計画

- `moon.mod` とパッケージが 0002 で整備された後に `moon check`、`moon test --target native`、`moon test --target js` を実行し、PASS / FAIL / 未実行を記録する。現時点で `moon.mod` も実装コードもないため、実行できない確認はすべて未実行として扱い PASS と混同しない。
- wbtest: 状態遷移と I/O 契約（要求範囲、部分消費なし、エラー保持）を手作り byte 列で固定する。tie-break と CTTS の None / 0 の区別も純ロジックのテストで固定する。
- Rust 差分: 0004 の oracle で pinned SHA の `cargo run --example demux -- <fixture>` を実行し、track / sample の golden と全件比較する。比較は 0016 の差分 Lab と共通 schema で行う。
- fixture: 通常 MP4（`moov` 先頭/末尾）、複数 track、CTTS 付き、AAC/Opus/AV1、video-only を 0004 の manifest から選び、対象 fixture 数を記録する。
- メモリ確認: `mdat` が大きい fixture で読取範囲と保持量をログに取り、全量保持がないことを確認する（0032 の測定枠組みと整合させる）。
- 手動確認: 0014 の CLI から同じ結果が表示されることを確認する。

## リスク

- `data_offset` / `timestamp` の基準混同は下流の payload 読取を静かに壊す。0000 の契約 1 / 2 を golden で固定する。
- `handle_input` の契約差（分割受信の許容）で Rust と挙動が割れる。コアは上流と同じ契約にし、分割の結合はアダプタに限定する。
- tie-break と timescale 比較の実装差。上流と同一の規則を wbtest で固定し、異 timebase の fixture を必ず含める。
- sample entry の毎回比較による性能劣化。index が同じ場合は内容比較しない上流の最適化を踏襲する。
- ロールバック: 新規モジュール中心で既存 API を変えない。問題時は該当コミットの revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] Sans I/O 通常 MP4 demuxer と track / sample 公開 API

## 注記

- upstream の対応物: [src/demux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file.rs)、[src/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux.rs)、[tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)、[examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)。
- 関連: [0009](./0009-sample-tables.md) / [0010](./0010-sample-entries.md) / [0012](./0012-file-kind-detector.md)（前提）、[0014](./0014-demux-example.md)（CLI）、[0015](./0015-web-mp4-dump.md) / [0016](./0016-rust-moonbit-diff.md)（表示と差分）、[0018](./0018-fmp4-segment-demux.md) / [0019](./0019-fmp4-file-demux.md)（fMP4 の demux）。
- 関連ロードマップ: [0000](./0000-implementation-roadmap.md) の M1 と「変更できないデータ契約」1 / 2 / 4。
- 証跡ルール: checkbox は実行証拠のある項目のみ完了にし、Rust oracle の未実行を「一致」と扱わない（0000 の進捗更新の規則 1 とテスト分類）。
- 実装時の未決事項: `prev_sample` / `seek` を本 issue に含めるか、公開 API 名、パッケージ配置は実装時に確定する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
