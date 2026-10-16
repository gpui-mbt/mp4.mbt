# 0028: stpp/wvtt/tx3g字幕trackを移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M4 コーデック支援
- 依存Issue: `0008`、`0010`、`0018`、`0022`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
上流が対応する3種の字幕トラックを読取・書込の両方で扱い、表示UIではsubtitleとして列挙できるようにする。

## 上流参照
- [docs/subtitle.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/docs/subtitle.md)
- [src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs)
- [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)
- [src/mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_fmp4_segment.rs)

## 実装手順（How）
1. `stpp`(TTML/IMSC)、`wvtt`(WebVTT cue boxes)、`tx3g`(3GPP Timed Text)のsample entryと子boxを型付きでparser/encoderに追加する。
2. track handlerとmedia headerの対応（stpp=subt/sthd、wvtt=text/sthd、tx3g=text/nmhd）を維持する。
3. 1つの字幕trackに非両立形式を混ぜた場合MixedSampleEntriesで拒否し、language/name等のmetadataを保持する。
4. サンプルpayloadはraw bytesのまま扱う。wvtt cue／TTML XML／tx3g styleの描画パーサは含めない。
5. 同一TrackKindは字幕も1トラックまでという現状制約をREADMEに明記する。

## 検証対象（What）
- [ ] 各種sample entryのencode/decodeとtrack kindの識別。
- [ ] stpp+tx3gの不正混在を拒否、同じhandler/media_headerの合法変種を受け入れる。
- [ ] 字幕のsample DTS/duration/keyframe・payload bytesが両muxer/demuxerで保存される。

## 完了条件
- [ ] M4字幕機能表に対応3形式と制限が明示される。
- [ ] 上流`docs/subtitle.md`と整合するfixture/テストがある。

## 非対象・境界
字幕テキストの意味解釈・字幕レンダリング・多言語字幕の同時Muxは非対象。
