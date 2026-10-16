# 0013: Sans I/O通常MP4 Demuxerを移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0009`、`0010`、`0012`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
v0.1の主要API：`Mp4FileDemuxer`でトラックと時系列順sampleを取り出す。少なくともH.264/AAC/Opus fixtureのトラック情報・サンプルmetadataを再現する。

## 上流参照
- [src/demux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file.rs)
- [src/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux.rs)
- [tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)
- [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)

## 実装手順（How）
1. `RequiredInput { position, size? }`/`Input { position, data }`/`TrackInfo`/`Sample`/`DemuxError`をAPIとして定義。`InputRequired`、DecodeError、SampleTableError、InvalidStateを区別する。
2. `ReadFtyp`→`ReadMoov`→`Initialized`状態機械を実装。Rust上流は`handle_input`が要求された範囲を一度に満たす必要があるため、公開I/O契約とアダプタ内での再取得・結合を明確にする。
3. `tracks()`でtrack_id/kind/duration/timescaleを返す。`next_sample()`はdecode timestamp順（時間比較はtrackごとのtimescaleを跨ぎ、精度劣化なし）を維持。
4. Sampleには`timestamp`＝DTS、`duration`、`composition_time_offset`（PTS=DTS+CTTS）、`data_offset`＝ファイル絶対位置、`data_size`、`keyframe`、変更時のみsample_entryを載せる。
5. moovが末尾のファイルでも必要位置から再読込できるようにし、コアではディスク全量読込を禁止する。

## 検証対象（What）
- [ ] 上流`examples/demux.rs`の先頭10sample分の表示データが一致。
- [ ] AAC/Opus/AV1/video-only、複数track、moov先頭/末尾、CTTS付きのoffset/timestampを全sample検証。
- [ ] 未充足Input、短いrange、EOF、不正stbl、unsupported handlerで適切なエラー。
- [ ] sample順序はトラックID順ではなくDTS時間順。異timebase同時刻のtie-breakもRustと一致。

## 完了条件
- [ ] 公開APIにdemuxerと4種のエラーを持つ。
- [ ] Rust goldenとのsemantics一致をCIで確認し、対象fixture数を示す。
- [ ] 大きなmdatを全メモリへ保持しない。

## 非対象・境界
sample payloadをcodecとして解凍しない。`Fmp4FileDemuxer`は0019、`Fmp4SegmentDemuxer`は0018で別実装。
