# 0010: video／audio SampleEntryの型付き対応を作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0008`、`0009`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
デモでコーデックと解像度／音声情報を表示し、後続muxとcodec-stringが共通の型を使えるようにする。

## 上流参照
- [src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs)
- [tests/test_boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_sample_entry.rs)
- [src/descriptors.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/descriptors.rs)

## 実装手順（How）
1. `avc1/avcC`、`hev1/hvc1/hvcC`、`av01/av1C`、`vp08/vp09/vpcC`の映像sample entryとVisualSampleEntryFieldsを移植する。
2. `mp4a/esds`、`Opus/dOps`、`fLaC/dfLa`とAudioSampleEntryFieldsを型付きdecode/encodeする。descriptorで使用する可変長整数・識別子を実装する。
3. unknown sample entryはraw payloadを保持する。未対応codecでもtrack/sampleの位置情報を抽出可能とする。
4. 公開ヘルパー`video_resolution`、`audio_channel_count`、`audio_sample_rate`、`audio_sample_size`の意味を上流に揃える。
5. sample entry変更がサンプル単位で通知される契約をdemuxと共有。サンプル内の圧縮データをデコードする機能は持たない。

## 検証対象（What）
- [ ] H.264/AAC/Opus/AV1/VP9 fixtureに対するsample entry型・構造・metadataを比較。
- [ ] 未知sample entry、切断されたavcC/esds、過大array countを安全に拒否／保持。
- [ ] encode→decodeの構造一致。固定pointのaudio sample rate上限と切り捨て仕様。

## 完了条件
- [ ] M1としてH.264/AAC/Opusの表示が可能（AV1等は対応範囲を段階的に明記）。
- [ ] 既知/未知の判定がRust oracleと一致。
- [ ] テストが上流のsample-entryケースを参照している。

## 非対象・境界
映像/音声そのものの解凍・再圧縮は扱わない。字幕sample-entryは0028で独立拡張。
