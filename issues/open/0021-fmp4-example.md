# 0021: 上流examples/fmp4.rsのMux/Demux統合デモを移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M2 fragmented MP4
- 依存Issue: `0018`、`0020`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
疑似H.264動画とOpus音声を複数segmentに記録し、MoonBit自身とRustで読み戻せる実行可能なintegration exampleを作る。

## 上流参照
- [examples/fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/fmp4.rs)
- [tests/test_mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_fmp4_segment.rs)
- [tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)

## 実装手順（How）
1. `examples/fmp4`でH.264 `avc1/avcC` とOpus `Opus/dOps`のsample entry、疑似sample bytes、durationとkeyframeを決定的に生成。
2. segmentごとにサンプルをmdat payload相対位置で配置し、`create_media_segment_metadata`の後ろへpayloadを結合する。`init_segment_bytes`は観測済みtrackから生成する。
3. 全segmentを`Fmp4SegmentDemuxer`で読み戻し、track kind、timestamp、payload bytes、sample count、keyframe、CTTSを比較。
4. 検証用artifactにinit.mp4、segment-0001.m4s等、manifest JSON、比較結果を保存し、参照コマンドをREADMEへ載せる。
5. 失敗時にはsegment番号・sample番号・期待/実際の差分で非0終了する。

## 検証対象（What）
- [ ] 少なくともvideo+audio、複数segmentのroundtrip。
- [ ] Rust側のsegment demuxでも生成物を読み込める。
- [ ] 異なるsample順・size・offsetで比較が確実にFAILする。

## 完了条件
- [ ] CLIから実行可能な上流fmp4例と意味的に同等のexampleがある。
- [ ] 相互運用テストがCI greenの必須対象になる。

## 非対象・境界
疑似H.264/Opusのpayloadはデコード可能な実メディアとは限らない。『実際に動画を再生できた』と誤報しない。
