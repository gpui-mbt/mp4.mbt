# [P0 / M1] MP4／fMP4種別検出をRange I/Oで実装する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0012-file-kind-detector
Priority: P0
Milestone: M1
Depends on: [0007](./0007-root-box-tree.md), [0008](./0008-movie-track-boxes.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

`moov` 内の `mvex` の有無から通常 MP4 と fragmented MP4 を判定する Sans I/O の kind detector（`Mp4FileKindDetector` 相当）を移植する。拡張子に頼らず、巨大／non-faststart ファイルでも必要な range だけを段階的に読んで判定する。

## 背景

- 上流の固定基準 [`1282b704`](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59) の [src/demux_mp4_file_kind_detector.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file_kind_detector.rs) は `Mp4FileKind { Mp4, FragmentedMp4 }`、`Mp4FileKindDetector` の `required_input()` / `handle_input()` / `file_kind()` と、`ReadFtypBoxHeader → ReadFtypBox → ReadTopLevelBoxHeader → ReadMoovBox → Detected` の状態機械を持つ。判定は `MoovBox` の `mvex` の有無による。
- 入力契約は `RequiredInput { position, size: Option }` / `Input { position, data }` と `DemuxError` を共有し、`size = None` は EOF までを意味する（0013 と同じ型を使う）。
- 上流のテストは [tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)、fuzz target は [fuzz/fuzz_targets/fuzz_mp4_file_kind_detector.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_kind_detector.rs) にある。
- 0007 の box header / box tree と 0008 の `MoovBox`（`mvex`）を前提にする。

## 問題

- ファイル全量をメモリに読む実装では巨大 MP4 でメモリを浪費し、non-faststart（`moov` 末尾）では先頭だけの読みで判定できない。
- 必要範囲に足りない入力と、壊れたファイル（box 長異常・EOF）を区別しないと、呼び出し側が再要求すべきか失敗すべきか判断できない。
- `size == 0`（末尾まで）、large size、`moov` 未発見、終端付近のオーバーフローを明示的に扱わないと、無限ループや誤判定の余地が残る。
- `ftyp` ブランドや拡張子だけで判定すると、通常 MP4 と fMP4 をブランドで区別できないケースを誤る。

## 目標

- `moov`／`mvex` で `Mp4FileKind` を判定する（拡張子・ブランド依存にしない）。
- 巨大 `mdat` の payload を読まず、non-faststart でも必要 range だけで判定を完了する。
- 不足した入力は必要入力を保持して再要求し、短い入力と壊れたファイルの違いを維持する。
- `size == 0`、large size、`moov` が末尾、`moov` 未発見、未知 box を明示的に扱う。
- Kind Detector 単独で JS/Native に同じ結果を返す。
- 要求 range と終了条件のテストを持つ。

## 対象外

- 拡張子のみでの判断（しない）。
- Hybrid MP4 固有の最終化判定（0029 で扱う）。
- `Fmp4SegmentDemuxer` / `Fmp4FileDemuxer`（0018 / 0019）の media data 解釈。
- box の意味解析そのもの（0007 / 0008 の範囲）。

## 提案する方針

- 対象は `src/demux` 相当のパッケージに置く（package 名・ファイル分割は 0002 の命名表に従い実装時に確定する）。公開 API は上流と同じ 3 つ（必要入力の照会・入力の投入・判定結果の取得）とする。
- 状態機械は上流どおりとし、`ftyp` の box header → `ftyp` 本体 → top-level box header の走査 → `moov` 本体 → 判定確定、の順で進める。`moov` 本体の decode は 0008 の `MoovBox` を使い、`mvex` の有無だけで kind を決める。
- top-level 走査では header の size に従って次の box へオフセットを進める。large size を含む size の解釈は 0007 の box header に委ね、`mdat` の payload は要求しない。未知の top-level box は size に従って読み飛ばす。
- I/O 契約の互換性: `required_input` は `position` と `size: Option`（`None` は EOF まで）を返す。`handle_input` は要求範囲を包含するデータを受け取り、要求を満たさない入力は上流と同じ規則で扱う（要求開始位置から見てデータが不足していれば終端到達として `DecodeError`、要求範囲が含まれなければ再要求）。エラーは保持して以降 `required_input` を閉じ、相互呼び出しの無限ループを防ぐ。
- 境界条件（上流実装と同じ）: `ftyp` の size 0 は不正として拒否する。`moov` より前の top-level box の size 0 は未対応としてエラーにする。`moov` の size 0 は末尾までの意味として受理する。`moov` 未発見の EOF、オフセット加算のオーバーフロー、`usize` 範囲外の size は明示エラーにする。
- 要求範囲が大きい場合の結合は呼び出し側アダプタ（0014）の責務とし、コアは分割受信を仮定しない。
- 実装時に確定する点: `ftyp` 以外の先頭 box の受理順、エラー文言、fuzz 入力の長さ上限は実装時に確定して本 issue へ追記する。

## 受け入れ条件

- [ ] Given 通常 MP4 fixture, when detector へ段階的に入力を与える, then `Mp4` を返す。
- [ ] Given fMP4 fixture（`moov` に `mvex` あり）, when 判定する, then `FragmentedMp4` を返す。
- [ ] Given non-faststart fixture（`moov` 末尾）, when 判定する, then 全文を読まずに確定し、要求 range が `mdat` payload を含まない（証跡付き）。
- [ ] Given 巨大な `mdat` の宣言, when 判定する, then `mdat` の payload を読まずに次の box へ進む。
- [ ] Given 必要範囲に足りない入力, when `handle_input` する, then 再要求（`InputRequired` 相当）になり、同一位置でデータが終わっていれば明示エラーになる。
- [ ] Given 異常な box 長・`moov` なし・終端付近のオーバーフロー, when 判定する, then 固まらず明示エラーを返す。
- [ ] Given 同じ fixture, when JS と Native で判定する, then 同じ `Mp4FileKind` になる。

## テスト計画

- `moon.mod` とパッケージが 0002 で整備された後に `moon check`、`moon test --target native`、`moon test --target js` を実行し、PASS / FAIL / 未実行を記録する。現時点で `moon.mod` も実装コードもないため、実行できない確認はすべて未実行として扱い PASS と混同しない。
- wbtest: 手作り byte 列で状態遷移（`ftyp` → top-level → `moov`）、size 0 / large size、要求範囲の再発行、エラーの保持、終端オーバーフローを固定する。要求された range の列をテストで検証する。
- fixture 比較: 0004 の manifest にある通常 MP4、fMP4、non-faststart の各 fixture で Rust oracle と同じ kind を確認する。Rust 側も同じ入力 bytes から実行し、golden を手入力しない。
- fuzz / PBT: 上流 fuzz target を参照し、ランダム byte 列で panic・無限ループ・範囲外参照がないことを確認する（0031 の枠組みで実行し、実行できるまで未実行と記録する）。
- 手動確認: `mdat` が巨大な fixture で読み取り range のログを取り、payload を読んでいないことの証跡とする。

## リスク

- 状態機械の再要求ループによる無限ループ。エラーの保持と `required_input` の閉鎖を wbtest で固定する。
- `size == 0` の解釈差（`moov` 前の top-level は未対応）で Rust と結果が割れる。上流の扱いをそのまま移植する。
- range 計算の誤りで `mdat` を誤読し、誤った box を `moov` として扱う。開始位置と長さの検証を wbtest に置く。
- 将来 Hybrid MP4 の判定条件が増えて責務が混ざる。本 issue は `moov`/`mvex` 判定に限定し、拡張は別 issue にする。
- ロールバック: 新規の状態機械と純ロジックが中心で既存 API に触れない。問題時は該当コミットの revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] `moov`/`mvex` による MP4／fMP4 kind detector

## 注記

- upstream の対応物: [src/demux_mp4_file_kind_detector.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file_kind_detector.rs)、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)、[fuzz/fuzz_targets/fuzz_mp4_file_kind_detector.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_kind_detector.rs)。
- 関連: [0007](./0007-root-box-tree.md) / [0008](./0008-movie-track-boxes.md)（前提）、[0013](./0013-mp4-file-demux.md)（demux 本体）、[0019](./0019-fmp4-file-demux.md)（fMP4 file demux）、[0029](./0029-webcodecs-transcode.md)（Hybrid 最終化）。
- 関連ロードマップ: [0000](./0000-implementation-roadmap.md) の M1。最短スライスでは 0003 と並行に 0012 を進める。
- 証跡ルール: checkbox は実際に実行した証拠がある項目だけ完了にする（0000 の進捗更新の規則 1）。要求 range のログを証跡として残す。
- 実装時の未決事項: 公開 API 名、パッケージ配置、fuzz の実行環境は実装時に確定する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
