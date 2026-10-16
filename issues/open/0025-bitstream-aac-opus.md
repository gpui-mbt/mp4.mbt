# 0025: AAC ADTS/ASC・Opusパケット補助を移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M4 コーデック支援
- 依存Issue: `0005`、`0010`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
音声コンテナのsample entry作成とAAC ADTS→MP4 raw AAC変換ができるようにする。

## 上流参照
- [src/bitstream/aac.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/aac.rs)
- [src/bitstream/opus.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/opus.rs)
- [tests/test_bitstream_aac.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_aac.rs)
- [tests/test_bitstream_opus.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_opus.rs)

## 実装手順（How）
1. AAC-LC AOT2のAudioSpecificConfigとADTS headerをparse/encodeし、サンプリング周波数・ch構成・frame sizeを扱う。上流のAAC-LC限定範囲を超えてHE-AAC対応と称しない。
2. ADTS frame payloadを抽出してesds/mp4a sample entryへ変換する補助、raw AACへADTSを付与する補助を作る。
3. Opus packet tocやdOps/Opus sample entryで上流が扱う項目の範囲を揃え、pre-skip/sample_rateを正しく保持する。
4. CRC付ADTS、複数raw data blockなど非対応の扱いを明記し、破損入力で不正sliceを作らない。

## 検証対象（What）
- [ ] 上流`beep-aac-audio.aac`、AAC/Opus MP4 fixtureでheader/entry一致。
- [ ] AAC ASC↔ADTS変換においてsample dataが変わらない。
- [ ] 無効sampling frequency index、channel layout、短いADTSで失敗分類一致。
- [ ] OpusのdOps roundtripとsize境界。

## 完了条件
- [ ] codec関連関数が外部からimportできる。
- [ ] 対応する音声codecのSampleEntryを作り、MP4 muxで利用可能。

## 非対象・境界
音声圧縮・PCM出力は対応範囲外。
