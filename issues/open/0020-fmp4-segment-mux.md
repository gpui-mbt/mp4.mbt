# 0020: Fmp4SegmentMuxerのinit/media生成とオフセット管理

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M2 fragmented MP4
- 依存Issue: `0010`、`0017`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
Rust例と互換性のあるfMP4初期化segmentとメディアsegmentを生成する。

## 上流参照
- [src/mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_fmp4_segment.rs)
- [tests/test_mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_fmp4_segment.rs)

## 実装手順（How）
1. `SegmentMuxerOptions`/`Fmp4SegmentMuxer`のAPIを実装。最初のsampleからtrack kind/timescale/sample-entryを学習し、`init_segment_bytes()`で観測済みの内容を出す。
2. `create_media_segment_metadata(samples)`は`moof`と`mdat` headerだけ出し、payload本体は呼出側に配置を要求する。sample.data_offsetは**当該mdat payload先頭からの相対位置**で検証。
3. trackごとのdecode_time、sequence number、sample entry index、`trun` flags、`tfdt`、optional `sidx`/`mfra`の段階的な生成を実装する。
4. 同一TrackKindは現状1トラック（Audio/Video/Subtitle各1）。同一segment・同一track内でsample entryが混在するときは上流互換の制約を検証する。
5. CTTSの書込範囲はfMP4ではsigned i32を基準とし、通常MP4の広いunsigned CTTS範囲と混同しない。

## 検証対象（What）
- [ ] AVC1+Opus複数segmentを生成し、RustとMoonBitのsegment demuxer双方で読み戻す。
- [ ] offset gap/overlap、sample length不一致、timescale mismatch、EmptyTracks/EmptySamplesの負例。
- [ ] segmentにpayloadが含まれないこととmoof/trunのoffsetがpayloadを指すことを確認。
- [ ] init segmentのsample entryの更新とsidx/mfraの索引を照合。

## 完了条件
- [ ] muxerが有効なinit+mediaを発行でき、各sampleのbytesが復元可能。
- [ ] Rustのstructural oracle/roundtripで検証可能。

## 非対象・境界
実コーデックのエンコード、QUIC/HLS配信はしない。
