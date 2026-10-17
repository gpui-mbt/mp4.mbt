# [P1 / M2] moof/traf/tfhd/trun/tfdt/mvexとsidx/mfraを移植する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0017-fmp4-boxes
Priority: P1
Milestone: M2
Depends on: [0008](./0008-movie-track-boxes.md), [0009](./0009-sample-tables.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

fMP4のsegment metadataとsample時間を読み書きするためのBox層を実装する。対象は `mvex/trex/mehd`、`moof/mfhd/traf/tfhd/tfdt/trun`、`sidx`、`mfra/tfra/mfro` で、version/flagsで分岐する型付きParser/Encoderとする。

## 背景

- 上流参照: [src/boxes_fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_fmp4.rs)、[tests/test_boxes_fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_fmp4.rs)。
- 上流の対応構造（固定コミット `1282b704` のソースで確認できる範囲）: `MoofBox` は `mfhd` 必須+`traf`列+未知box、`TrafBox` は `tfhd` 必須+`tfdt`任意+`trun`列+未知box、`TfhdBox` は7種のflagでoptional欄が決まり、`TfdtBox` はversion 0/1（32/64bit）を保持する。`TrunBox` はper-sampleのOption有無がrun全体で一致することを事前条件とし、負のcomposition_time_offsetがある場合にversion 1を選ぶ。`SidxBox` はv0/v1で32/64bitが変わり、`MfraBox` は `tfra` 列+`mfro`必須である。
- 継承の基礎: sample duration/sizeは `trun` → `tfhd.default_sample_*` → `trex.default_sample_*` の順で決まる（0018のdemuxが使う）。
- [0008](./0008-movie-track-boxes.md)（moov/trak）と[0009](./0009-sample-tables.md)（stbl/SampleTableAccessor）が基盤、[0005](./0005-safe-bytes.md)がsize境界検証の基盤になる。現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コードはない。

## 問題

- fMP4のsegment解析に必要なbox型がなく、[0018](./0018-fmp4-segment-demux.md)・[0019](./0019-fmp4-file-demux.md)・[0020](./0020-fmp4-segment-mux.md)が着手できない。
- version/flags依存のoptional欄を場当たり的に読むと、フィールド位置ずれ・offset計算の破綻・sample時間の誤りが生じる。
- 未知box・未定義flagsの許容範囲が決まっていないと、正しいファイルを拒否したり、壊れたファイルを通したりする。
- count・offsetの上限検証がないと、宣言sizeを信じた大量確保やoverflowが起きる（0000の代表的リスク）。

## 目標

- fMP4の必須boxが型付きでdecode/encodeできる。
- tfhd default値、base-data-offset、trun data-offset、sample composition time（符号付きを含む）の継承優先順位を固定する。
- count上限・offset overflow・親境界越え・flagsとoptional欄の不一致を定義済みエラーで受理しない。
- time/offset計算の根拠とテストが追跡できる。

## 対象外

- セグメント全体の状態機械（[0018](./0018-fmp4-segment-demux.md)〜[0020](./0020-fmp4-segment-mux.md)で実装する）。
- mdat payloadの意味解析・codec payloadのdecode。
- sample entryの正規化（[0010](./0010-sample-entries.md)の型を使う）。
- QUIC/HLS等の配信層。

## 提案する方針

- 対象boxは `mvex/trex/mehd`、`moof/mfhd/traf/tfhd/tfdt/trun`、`sidx`、`mfra/tfra/mfro` とする。配置は `src/boxes` を候補とし、0002の依存グラフに従う（ファイル名・分割は実装時に確定し、本issueへ追記する）。
- FullBoxのversion/flagsを型として保持し、flagsからoptional欄の有無を再構成する。tfhdはbase_data_offset / sample_description_index / default_sample_duration / default_sample_size / default_sample_flags / duration_is_empty / default_base_is_moofの7 flagを明示的に扱う。
- tfdtはversion 0/1の32/64bit差を保持し、値がu32に収まらない場合はencode時にversion 1を必須とする（上流の規則）。sidxも同じくv0/v1の値域で版を選ぶ。
- trunはper-sampleのduration/size/flags/composition_time_offsetのOption有無がrun全体で一致することをencodeの事前条件とし、不整合は最初の不一致sample indexとfield名を含むエラーにする（上流と同じ分類）。composition_time_offsetはversion 0がunsigned・version 1がsignedで、負値を含む場合はversion 1を選ぶ。
- 継承優先順位を固定する。sample duration = trun → tfhd.default_sample_duration → trex.default_sample_duration。sample sizeも同様。flagsはrun先頭サンプルにfirst_sample_flagsがあればそれを優先。data offsetの基準はtfhd.base_data_offset明示 → default_base_is_moof=trueはmoof先頭 → それ以外は直前trafのデータ末尾（先頭trafはmoof先頭）とし、[0018](./0018-fmp4-segment-demux.md)と共有できる関数に一元化する。
- 検証を厳しくする。各boxが親境界を越えない、flagsとoptional欄数の一致、trunのsample_countはpayload残量と照合し、per-sampleデータなしの場合の上限（上流は16,777,216）を設ける。offset/sizeの加算はoverflowを拒否する。
- 未知boxは保持（unknown相当）、未定義flagsは拒否を基本とし、上流仕様を参照して境界を実装時に確定する。sidxはreference列（reference_type/referenced_size/subsegment_duration/starts_with_sap/sap_type/sap_delta_time）、mfraはtfraの可変長フィールド（length_size_of_traf_num等）とmfro必須を保持する。

## 受け入れ条件

- [ ] Given trunのsample_countとoptional fieldの全代表組合せ（duration/size/flags/CTOの各有無、data_offset、first_sample_flags）, when decode→encode→decodeする, then 型が一致してラウンドトリップする。
- [ ] Given tfdt version 0/1、trun version 0/1、signed CTO、sidx v0/v1境界, when decode/encodeする, then 版の選択と保持が期待どおりになる。
- [ ] Given trafにtfhdが欠ける、trunのsample_countがpayload残量を超える、offset/size加算がoverflowする, when decodeする, then 定義済みエラーでFAILする。
- [ ] Given per-sample Option有無が混在するtrun, when encodeする, then 最初の不一致sample indexとfield名を含むエラーになり、不正なflagsを書かない。
- [ ] Given Rust oracleのfixture, when box treeとencode/decode結果を比較する, then 一致し、不一致はfield path単位で識別できる。
- [ ] Given 未知box, when 親boxをdecodeする, then unknownとして保持され、既知boxのdecode結果を変えない。

## テスト計画

- 現時点では `moon.mod` がなく、以下は0002・0005完了後に実行する。PASS / FAIL / 未実行を混同せず記録する。
  - `moon check --target native --deny-warn` と `moon test --target native`（および `--target js`）を実行し、結果とツールチェーンのバージョンを記録する。
  - wbtest: 各boxの最小/最大フィールド組合せ、親境界越え、count/payload不整合、overflow、未知box保持、trunのOption一貫性検証、版の自動選択を固定する。
- [0004](./0004-oracle-fixtures.md)のoracleとfixture manifestを使い、[tests/test_boxes_fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_fmp4.rs)が対象にするbox tree・encode/decode結果と比較する。fixtureは帰属確認済みのものに限定する。
- 継承優先順位（trun→tfhd→trex、data offsetの3モード）は[0018](./0018-fmp4-segment-demux.md)の統合テストより先にwbtestで固定する。
- 現時点では上記いずれも実行できない（`moon.mod` 未作成・oracle未整備。0002/0004完了後に有効化する）。未実行理由をレポートに明記する。

## リスク

- version/flagsの取り違えでフィールド位置がずれ、後続sampleが壊れる。全flags組合せのwbtestと[0018](./0018-fmp4-segment-demux.md)のoffset比較で検出する。
- defaults継承順の曖昧さ。trun→tfhd→trexの順を関数として一元化し、テストから参照する。
- 上限の設定が厳しすぎると正しいファイルを拒否し、緩すぎるとOOMになる。上流の上限（payload残量、per-sampleデータなしの16,777,216）と根拠を文書化して調整する。
- 未知boxの保持方法が[0018](./0018-fmp4-segment-demux.md)/[0019](./0019-fmp4-file-demux.md)の比較に影響する。未知boxが既知boxのdecode結果を変えないことをテストで固定する。
- ロールバック: 新規box型の追加が中心で既存公開APIを変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] fMP4構造box（moof/traf/tfhd/tfdt/trun/mvex/trex/mehd/sidx/mfra/tfra/mfro）の型付きParser/Encoder

## 注記

- 上流参照: [src/boxes_fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_fmp4.rs)、[tests/test_boxes_fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_fmp4.rs)。
- 関連: [0005](./0005-safe-bytes.md)（byte処理/error）、[0008](./0008-movie-track-boxes.md)、[0009](./0009-sample-tables.md)、[0010](./0010-sample-entries.md)、[0018](./0018-fmp4-segment-demux.md)、[0019](./0019-fmp4-file-demux.md)、[0020](./0020-fmp4-segment-mux.md)。
- 運用: fixture checksum・upstream SHA・実行コマンドを証跡に残す（0004/0034の方針）。
- 未決事項（実装時に確定して追記する）: 未定義flagsと未知boxの許容範囲、`mvex/trex/mehd` の上流定義との対応、`src/boxes` 内の分割。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。


## 検証

- 実装: `src/boxes` / `src/demux` / `src/mux` / `src/examples` に追加し、`moon test --target native` と `--target js` を実行した（2026-10-17、PASS）。
- MoonBit の unit / roundtrip テストは PASS。Rust oracle との完全な差分比較はこの環境では未実行のため **UNVERIFIED**（oracle 依存の受入項目は PASS と扱わない）。
- `moon fmt --check` と `moon info` は実行済み。生成された `.mbti` を同時に更新する。
