# 0022: 通常MP4 FileMuxer・追記・finalizeの移植

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M3 通常MP4書込
- 依存Issue: `0009`、`0010`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
サンプルdataとmetadataから通常MP4ファイルを生成する。絶対offsetの整合、moov/metatdata、通常/faststartを正確に実装する。

## 上流参照
- [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)
- [src/mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux.rs)
- [tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)

## 実装手順（How）
1. `Mp4FileMuxer`、`Sample`、`Mp4FileMuxerOptions`、`TrackMetadata`、`FinalizedBoxes`を移植。`initial_boxes_bytes()`をまず書き、payload追記後に`append_sample()`、最後に`finalize()`のoffset-and-bytes差分を書込側に返す。
2. `Sample.data_offset`はファイル先頭からの絶対位置。`append_sample`前の実書込と位置一致が必須。`advance_position`は別途0027で追加。
3. 同一TrackKindは1トラックまで（Audio/Video/Subtitle）。sample_entryの初回必須と変更時の継承、timescale一致、duration累積を検証する。
4. `stts`、`ctts`、`stsc`、`stsz`、`stco/co64`、`stss`をサンプル列から構築。映像全sample非keyframeでNoSyncSamples、音声・字幕のstss省略条件も上流仕様に合わせる。
5. `reserved_moov_box_size`と`estimate_maximum_moov_box_size`でfaststartを扱い、moov推定不足・実offset不一致・finalize二重呼出し等を正しくエラー化する。
6. created timeと言語/hdlr.nameは明示オプションで管理し、テストデフォルトは決定的にする。

## 検証対象（What）
- [ ] audio-only、video-only、A/V、empty、mixed timescale、sample entry変更とfaststartを検証。
- [ ] Rust→MoonBit、MoonBit→Rustの両方向demuxでsample payload/timestamp等を比較。
- [ ] CTTS負値・正値の上限、offset>2^32、stco/co64切替、予備moov容量不足。
- [ ] PositionMismatch、AlreadyFinalized、NoSyncSamples、MissingSampleEntryの失敗を検証。

## 完了条件
- [ ] 生成MP4が少なくともRust版とMoonBit版で読める。
- [ ] サンプル位置と実ファイルサイズが整合する。
- [ ] 公開APIとエラーが文書化される。

## 非対象・境界
現段階のMP4 writerがH.264/AAC等のcodecをエンコードするわけではない。
