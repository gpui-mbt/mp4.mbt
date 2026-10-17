# [P0 / M1] video／audio SampleEntryの型付き対応を作る

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0010-sample-entries
Priority: P0
Milestone: M1
Depends on: [0008](./0008-movie-track-boxes.md), [0009](./0009-sample-tables.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

`stsd` 配下の映像／音声 SampleEntry を型付きで decode/encode する。デモでコーデックと解像度／音声情報を表示できるようにし、後続の mux と codec-string が共通の型を使えるようにする。

## 背景

- 0008 が `moov`／`trak`／`mdia`／`minf` の時刻情報、0009 が `stbl` の sample 位置を担い、本 issue が `stsd` の sample entry を担う。3 つが揃って M1 のトラック表示と 0013 の demuxer が成立する。
- 上流の固定基準 [`1282b704`](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)（`develop` の調査時 HEAD）は [src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs) に `SampleEntry` enum（`Avc1` / `Hev1` / `Hvc1` / `Vp08` / `Vp09` / `Av01` / `Opus` / `Mp4a` / `Flac` / `Stpp` / `Wvtt` / `Tx3g` / `Unknown`）と `VisualSampleEntryFields` / `AudioSampleEntryFields` を持ち、必須の子 box（`avc1` なら `avcC`）を検査する（上流では `check_mandatory_box`）。
- 上流のテストは [tests/test_boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_sample_entry.rs)、descriptor の可変長整数・識別子は [src/descriptors.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/descriptors.rs) を参照する。
- デモ（0015）と codec string（0011）、mux（0022）は同じ `SampleEntry` 型を入力にする。

## 問題

- MoonBit 側に sample entry を型付きで保持する型がないと、`stsd` が raw bytes のままになり、コーデック種別・解像度・チャンネル数・サンプルレートを表示できない。
- `avcC` / `hvcC` / `vpcC` / `av1C` / `esds` / `dOps` / `dfLa` の中身を検証しないと、宣言と実データの食い違いや切断データを正常扱いにする余地が残る。
- 未知 sample entry を拒否すると、未対応 codec のファイルで track/sample の位置情報すら抽出できなくなる。
- descriptor（`esds`）の可変長サイズ・タグの解釈を誤ると、AAC 設定の取り出しとエラー分類が上流と食い違う。

## 目標

- `avc1`/`avcC`、`hev1`/`hvc1`/`hvcC`、`av01`/`av1C`、`vp08`/`vp09`/`vpcC` の映像 sample entry と `VisualSampleEntryFields` を移植する。
- `mp4a`/`esds`、`Opus`/`dOps`、`fLaC`/`dfLa` と `AudioSampleEntryFields` を型付き decode/encode する。descriptor で使用する可変長整数・識別子を実装する。
- 公開ヘルパー `video_resolution`、`audio_channel_count`、`audio_sample_rate`、`audio_sample_size` の意味を上流に揃える。
- 未知 sample entry は raw payload を保持し、未対応 codec でも track/sample の位置情報を抽出可能とする。
- sample entry 変更がサンプル単位で通知される契約を demux（0013）と共有する。
- M1 として H.264/AAC/Opus の情報表示が可能になる（AV1 等は対応範囲を段階的に明記する）。
- サンプル内の圧縮データを decode する機能は持たない。

## 対象外

- 映像／音声そのものの解凍・再圧縮（sample payload は raw bytes として扱う）。
- 字幕 sample entry（`stpp` / `wvtt` / `tx3g`）。0028 で独立拡張する。
- NAL 単位などの bitstream 解析（0024〜0026 の範囲）。
- ルート box tree（0007）と sample table（0009）そのものの実装。

## 提案する方針

- 対象は `src/boxes` 相当のパッケージに置く（package 名・ファイル分割は 0002 の命名表に従い実装時に確定する）。`SampleEntry` は上流と同じ variant 構成にし、`Unknown` に raw payload を保持する。
- 映像 entry は設定 box を型付けする: `avc1` は `avcC`、`hev1`/`hvc1` は `hvcC`、`av01` は `av1C`、`vp08`/`vp09` は `vpcC`。必須 box の欠落は上流と同じ明示エラーにし、未知の子 box は保持して再 encode で失わない。
- `VisualSampleEntryFields` は data_reference_index、width/height、horizresolution/vertresolution、frame_count、compressorname、depth を持たせる。`AudioSampleEntryFields` は data_reference_index、channelcount、samplesize、samplerate を持たせる（フィールド名・型は上流に対応させる）。
- 上流は `avcC` で SPS を最大 31、PPS を最大 255、chroma_format 系を profile 66/77/88 以外で扱う。`hvcC` の NAL 配列、`vpcC` の version 1、`av1C` の必須項目も含め、同種の上限・条件を再現し境界値テストで固定する。
- 音声 entry の必須 box（`mp4a` の `esds`、`Opus` の `dOps`、`fLaC` の `dfLa`）も同じ方針で検査する。`esds` は可変長サイズ（継続ビット）・タグ・`DecoderConfigDescriptor.object_type_indication`（AAC は `0x40`）を型付きで扱い、構造は [src/descriptors.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/descriptors.rs) を正とする。
- ヘルパーの互換性要件: `video_resolution` は映像 entry のみ `(width, height)` を返す。`audio_sample_rate` は整数部のみを返し小数部を切り捨てる（上流の NOTE と同じ。u16 範囲外はコーデック固有フィールドを優先する）。`audio_channel_count` / `audio_sample_size` も上流と同じ option の意味にする。
- 境界条件: 切断された `avcC`/`esds`、宣言長より長い配列 count、size のオーバーフローは panic せず定義済みエラーにする。decode → encode → decode の構造一致を golden で確認する。
- 0013 とは sample entry の取得と「変更時のみ通知」の契約だけを共有し、型の実装は本 issue に閉じる。

## 受け入れ条件

- [x] Given H.264 fixture の `avc1`/`avcC`, when decode して `video_resolution` を呼ぶ, then 幅・高さが Rust oracle の golden と一致する。（fixture `black-h264-video.mp4` / `black-h264-fmp4.mp4` の entry で `video_resolution=640x480` を凍結）
- [x] Given AAC-LC fixture の `mp4a`/`esds`, when decode する, then `audio_channel_count` / `audio_sample_rate` / `audio_sample_size` が golden と一致する。（fixture `beep-aac-audio.mp4`）
- [x] Given Opus・fLaC・AV1・VP9 の fixture, when decode する, then 各 entry の型・構造・metadata が golden と一致する。（`beep-opus-audio.mp4` / `beep-flac-audio.mp4` / `black-av1-video.mp4` / `black-vp9-video.mp4` / `black-h265-video.mp4` / `black-h265-hvc1-video.mp4`）
- [x] Given 未知 sample entry, when decode する, then `Unknown` として raw payload が保持され、同じファイルで 0013 が track/sample を抽出できる。（`Unknown` の保持はケース `unknown_zzzz` / `avc1_duplicate_avcc_second_unknown` で凍結。0013 での抽出は 0013 の契約に委譲）
- [x] Given 切断された `avcC`/`esds` と過大な array count, when decode する, then panic せず定義済みエラーを返す。（`avc1_truncated_fields`、`esds_sl_predefined_bad`、`avcc_sps_too_large`、`hvcc_nalu_too_large` ほか計 23 件の decode エラーケースを凍結）
- [x] Given 型付き entry, when encode → decode する, then 構造が一致する（golden で固定）。（oracle ケース・fixture ともに上流の再エンコードバイト列と一致を確認）
- [ ] Given 同一 track 内で sample entry が切り替わる fixture, when 0013 の demux が動く, then 変更されたサンプルだけに新しい entry が載る（契約テスト）。→ 0013 未実装のため未実行（本 issue の公開型は契約を共有できる形で確定）

## テスト計画

- `moon.mod` とパッケージが 0002 で整備された後に `moon check`、`moon test --target native`、`moon test --target js` を実行し、PASS / FAIL / 未実行を記録する。現時点のリポジトリには `moon.mod` も実装コードもないため、実行できない確認はすべて未実行として扱い PASS と混同しない。
- wbtest: `SampleEntry` の decode/encode roundtrip、ヘルパー 4 種の option の意味、必須 box 欠落・切断・過大 count のエラー分類を手作り byte 列で固定する。
- fixture 比較: 0004 の manifest と Rust oracle の golden で H.264/AAC/Opus/AV1/VP9 の型・構造・metadata と既知/未知の判定を比較する。golden は Rust 実行の証跡付きで作る（手入力しない）。
- 手動確認: 0015 の Dump でコーデック・解像度・音声パラメータが表示されること、0016 の差分 Lab で対応する field path に差分が出ないことを確認する。
- 実装詳細（package 名・公開関数名）は 0002 と実装時に確定し、確定内容を本 issue へ追記する。

## リスク

- 上流との encode 差分（未知 box の保持順・デフォルト値）で roundtrip golden が不一致になる。unknown box を保持する方針と golden で切り分ける。
- ヘルパーの option 意味（音声で None、sample rate 切り捨て）を誤ると下流の表示が静かに変わる。上流の NOTE どおり wbtest で固定する。
- `esds` descriptor の実装を誤ると AAC 設定と 0011 の codec string が連鎖的に誤る。descriptor 単体のテストを先に置く。
- 過大 count・切断データでの allocation 増大。0005 の limits に従い、上限超過は明示エラーにする。
- ロールバック: 新規の型と parser/encoder が中心で、0009 の既存契約を変えない。問題時は該当コミットの revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] video／audio SampleEntry の型付き decode/encode と情報取得ヘルパー

## 注記

- upstream の対応物: [src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs)、[tests/test_boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_sample_entry.rs)、[src/descriptors.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/descriptors.rs)。
- 関連: [0008](./0008-movie-track-boxes.md) / [0009](./0009-sample-tables.md)（前提）、[0011](./0011-codec-strings.md)（codec string）、[0013](./0013-mp4-file-demux.md)（変更通知の契約）、[0022](./0022-mp4-file-mux.md) / [0028](./0028-subtitle-sample-entry.md)（mux と字幕）。
- 関連ロードマップ: [0000](./0000-implementation-roadmap.md) の M1 と「変更できないデータ契約」1。
- 証跡ルール: checkbox は実際に実行した証拠がある項目だけ完了にする（0000 の進捗更新の規則 1）。
- 実装時の未決事項: package 名・ファイル分割、公開型・関数名、descriptor の内部構造の写し方は 0002 と実装時に確定する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
- 2026-10-17: 実装確定内容を追記。`src/bytes` に `Uint`（上流 `Uint<T,BITS,OFFSET>` の実行時フィールド化）、`NonZeroU16`、`read`/`write_fixed_16_16_unsigned` を追加。`src/boxes` に `descriptors.mbt`（`EsDescriptor`/`DecoderConfigDescriptor`/`DecoderSpecificInfo`/`SlConfigDescriptor`）、`esds_box.mbt`、`sample_entry_fields.mbt`（`Visual`/`AudioSampleEntryFields`）、設定 box（`avcc`/`hvcc`/`vpcc`/`av1c`/`dops`/`dfla`）と entry box（`avc1`/`hev1`/`hvc1`/`vp08`/`vp09`/`av01`/`Opus`/`mp4a`/`fLaC`）を追加し、`SampleEntry` を型付き variant + `Unknown` に書き換えた。字幕系（`stpp`/`wvtt`/`tx3g`）は上流と異なり型付き variant を持たず `Unknown` 分類のまま（0028 の一時差）。ヘルパー 4 種は上流の option 意味を再現（`audio_channel_count` は下位 8 bit、`audio_sample_rate` は整数部切り捨て）。
- 2026-10-17: oracle `sample-entries` / `sample-entries-cases` / `sample-entries-fixtures` を追加。ケース表 38 件（全 9 variant、必須子欠落、version 系・境界系エラー、`avc1_profile100_no_tail` の decode 成功 / encode 失敗の非対称、未知子・重複設定 box）と fixture 9 件（各 mp4 の `stsd` entry を上流で再エンコード）を `src/boxes/sample_entry_oracle_*_test.mbt` として生成し、`sample_entry_oracle_test.mbt` が snapshot 行と再エンコードバイト列を差分比較する。
- 2026-10-17: 証跡（unit）: `moon test` 366/366 PASS、`moon test --target js` 366/366 PASS、`moon test --target native` 366/366 PASS。新規テスト: `Uint` / `NonZeroU16`（`src/bytes/*_test.mbt`）、oracle 差分 2 件（ケース表・fixture）。`moon check` / `moon check --target js` は warning 0。`moon fmt` / `moon info` 実施、`pkg.generated.mbti` に `Uint`/`NonZeroU16`/固定小数点 helper と `src/boxes` の公開 box 群を確認。
- 2026-10-17: 実装・検証・ドキュメント・CI の全項目を完了し、done へ移行。
