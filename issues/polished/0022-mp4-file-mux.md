# [P1 / M3] 通常MP4 FileMuxer・追記・finalizeの移植

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0022-mp4-file-mux
Priority: P1
Milestone: M3
Depends on: [0009](./0009-sample-tables.md), [0010](./0010-sample-entries.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

サンプルdataとmetadataから通常MP4ファイルを生成する`Mp4FileMuxer`を移植する。絶対offsetの整合、moov/metadata、通常配置とfaststartを正確に扱い、`initial_boxes_bytes()` → payload追記 → `append_sample()` → `finalize()`の差分書込契約でcaller側のI/Oと分離する。

## 背景

- 現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コード・動作テストはない。本issueはM3（通常MP4書込）の中核で、[0009](./0009-sample-tables.md)（stbl/SampleTableAccessor）と[0010](./0010-sample-entries.md)（sample entry）の上に構築する。
- 上流参照: [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[src/mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux.rs)、[tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)。
- データ契約（0000の変更できないデータ契約3）: `Mp4FileMuxer.append_sample`の入力offsetは出力ファイル絶対位置。fMP4のmdat payload相対位置（[0020](./0020-fmp4-segment-mux.md)）と取り違えない。
- faststart用の余白管理は`reserved_moov_box_size`/`estimate_maximum_moov_box_size`相当で扱う。追加の書込位置契約は[0027](./0027-hybrid-faststart.md)の範囲とする。

## 問題

- MoonBit側に通常MP4 writerがないため、M3のgate（sample実offsetの一致、生成物をRust/MoonBit双方のdemuxerで読める）が成立しない。
- `Sample.data_offset`の絶対位置契約、`append_sample`前の実書込との位置一致、`finalize`のoffset-and-bytes差分の返却を固定しないと、表が指す位置と実データがずれる壊れ方を検出できない。
- stts/ctts/stsc/stsz/stco・co64/stssの構築、stss省略条件、sample entryの初回必須と変更継承、timescale一致、duration累積の規則が未定義。
- faststartの予備moov容量不足、実offset不一致、finalize二重呼出しといった失敗の分類が必要。
- ロールバック前提の変更履歴・互換性記録がなく、出力の再現性が説明できない。

## 目標

- `Mp4FileMuxer`・`Sample`・`Mp4FileMuxerOptions`・`TrackMetadata`・`FinalizedBoxes`を移植し、`initial_boxes_bytes()`を先に書き、payload追記後に`append_sample()`、最後に`finalize()`のoffset-and-bytes差分を書込側へ返す。
- 生成MP4がMoonBitとRust双方のdemuxerで読め、sampleの実offsetとファイルサイズが整合する。
- faststart/通常配置の両方でsamplesの同一性が保たれ、公開APIとエラーが文書化される。

## 対象外

- コーデックのエンコード（H.264/AAC等）。writerは既知のsample entryとpayloadを書き込むだけで、圧縮・変換をしない。
- `advance_position`相当のHybrid MP4契約（[0027](./0027-hybrid-faststart.md)）。
- fMP4 segment mux（[0020](./0020-fmp4-segment-mux.md)）と生成CLI（[0023](./0023-mp4-mux-example.md)）。
- sample payloadの生成・解釈。payloadはraw bytesとして扱う。

## 提案する方針

- `Mp4FileMuxer`、`Sample`、`Mp4FileMuxerOptions`、`TrackMetadata`、`FinalizedBoxes`をupstream互換で実装する。`initial_boxes_bytes()`をまず書き、payload追記後に`append_sample()`、最後に`finalize()`のoffset-and-bytes差分を書込側へ返す。`advance_position`は別途[0027](./0027-hybrid-faststart.md)で追加する。
- `Sample.data_offset`はファイル先頭からの絶対位置。`append_sample`前の実書込と位置一致が必須。不一致は`PositionMismatch`として拒否する。
- 同一TrackKindは1トラックまで（Audio/Video/Subtitle各1）。sample entryの初回必須と変更時の継承、timescale一致、duration累積を検証する。
- `stts`、`ctts`、`stsc`、`stsz`、`stco/co64`、`stss`をサンプル列から構築する。映像全sample非keyframeでNoSyncSamples、音声・字幕のstss省略条件も上流仕様に合わせる。
- `reserved_moov_box_size`と`estimate_maximum_moov_box_size`でfaststartを扱い、moov推定不足・実offset不一致・finalize二重呼出し等を正しくエラー化する。
- created timeと言語/hdlr.nameは明示オプションで管理し、テストデフォルトは決定的にする。
- 公開APIのシグネチャ・モジュール配置（例: `src/mux`配下）は実装時に確定して本issueへ追記する。JS/Nativeで同一挙動にし、書込I/Oはcallerに残す（Sans I/O原則。読み戻し側は[0013](./0013-mp4-file-demux.md)）。

## 受け入れ条件

- [ ] Given audio-onlyのsample列, when `initial_boxes_bytes`→追記→`append_sample`→`finalize`を実行する, then MoonBitとRust双方のdemuxer（[0013](./0013-mp4-file-demux.md)相当）が生成MP4を読み、sample payloadとtimestampが一致する。
- [ ] Given video-onlyで全sample非keyframeの入力, when finalizeする, then NoSyncSamplesに相当する明示エラーになる。
- [ ] Given 映像keyframe混在の入力, when finalizeする, then `stss`がkeyframeを列挙し、demuxerのkeyframe判定と一致する。
- [ ] Given sample entry変更を含むtrackで初回entryあり, when appendする, then変更時のみentryが更新され、初回なしは MissingSampleEntry で拒否される。
- [ ] Given faststart有効で`reserved_moov_box_size`を指定する, when finalizeする, then moovが予約域に収まり、sample実offsetがfinalize返却値と一致する。
- [ ] Given offsetを実書込位置と不一致にした入力, when `append_sample`する, then PositionMismatchで拒否され、壊れたファイルを出力しない。
- [ ] Given `finalize`を2回呼ぶ, when 2回目を実行する, then AlreadyFinalized で拒否される。
- [ ] Given 64bit absolute offsetが必要なファイル, when stco/co64の切替条件に達する, then正しいboxが選ばれ、demuxerで読める。

## テスト計画

- `moon check`と`moon test --target native`を実行し、PASS / FAIL / 未実行を記録する（現時点では`moon.mod`と実装がなく実行不能。0002完了後に有効化する）。
- unit/wbtest: `initial_boxes_bytes`とfinalize差分のoffset計算、position mismatch検出、stss省略条件、timescale一致判定、reserved_moov容量不足、二重finalizeを固定する。
- Rust→MoonBit、MoonBit→Rustの両方向demuxでsample payload/timestamp等を比較する。CTTS負値・正値の上限、offset>2^32でのstco/co64切替、予備moov容量不足、PositionMismatch、AlreadyFinalized、NoSyncSamples、MissingSampleEntryの失敗を検証する。
- 相互運用の証跡はPASS / FAIL / 未実行を混同せず、実行コマンド・OS/arch・コミットSHA・fixture checksumとともに記録する。Rust oracle未整備の間は未実行理由を書く。
- 生成した一時ファイルはworkspace内（例: `target/`配下）に限定し、fixtureを上書きしない。

## リスク

- offset基準（ファイル絶対位置）の取り違えで、表とデータがずれたMP4を出す。append前の位置一致検証と両方向roundtrip（[0013](./0013-mp4-file-demux.md) / Rust oracle）で検出する。
- faststartのmoov推定不足がサイズ超過やoffsetずれを起こす。予約域超過をfinalize時の明示エラーにし、境界をwbtestで固定する。
- stss省略条件の不一致で一部プレイヤーのkeyframe解釈が変わる。上流仕様との一致をRust oracleの観測で確認する。
- 64bit offset（co64）の分岐漏れ。offset>2^32のfixtureで切替を検証する。
- ロールバック: 新規mux APIの追加が中心で、既存read-only API契約を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] 通常MP4 FileMuxer（initial_boxes_bytes/append_sample/finalizeとfaststart）を追加

## 注記

- 上流参照: [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[src/mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux.rs)、[tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)。
- 関連: [0009](./0009-sample-tables.md)（stbl/accessor）、[0010](./0010-sample-entries.md)（sample entry）、[0023](./0023-mp4-mux-example.md)（roundtrip CLI）、[0027](./0027-hybrid-faststart.md)（advance_position/Hybrid）。
- 未決事項（実装時に確定して追記する）: モジュール/ファイル名、エラー型の命名と分類、JavaScript targetでの任意精度整数の扱い。
- 証跡: finalizeの差分bytesと実ファイルoffsetの突合結果、Rust/MoonBit双方のdemux観測値をログまたはartifactに残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
