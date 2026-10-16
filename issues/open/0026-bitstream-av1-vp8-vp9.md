# 0026: AV1/VP8/VP9 bitstream metadataを移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P2
- フェーズ: M4 コーデック支援
- 依存Issue: `0005`、`0010`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
AV1 OBUやVPxヘッダーから解像度・profile・キー判定情報を扱い、av1C/vpcCを適切に生成する。

## 上流参照
- [src/bitstream/av1.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/av1.rs)
- [src/bitstream/vp8.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/vp8.rs)
- [src/bitstream/vp9.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/vp9.rs)
- [tests/test_bitstream_av1.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_av1.rs)
- [tests/test_bitstream_vp8.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_vp8.rs)
- [tests/test_bitstream_vp9.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_vp9.rs)

## 実装手順（How）
1. AV1のLEB128、OBU header、Sequence Header、Frame Header先頭の必要欄をparse。`av1C configOBUs`とsampleの`obu_has_size_field`条件を分ける。
2. VP8 key frame headerとVP9 uncompressed headerなど、上流の範囲だけを実装。codec full decoderに手を出さない。
3. av01/vp08/vp09 sample entry生成に必要なprofile/level/depth/resolution情報を抽出し、codec_stringと矛盾しないようにする。
4. OBU size超過・reserved bit・壊れたframe headerに対する上限とエラーを設け、target間一致を検証する。

## 検証対象（What）
- [ ] 上流AV1 configOBUs、black-av1-video.mp4、VP8/VP9短小fixtureを使用。
- [ ] LEB128長さ不足/overflow、OBU size mismatch、VP9 frame marker不正。
- [ ] sample entryとcodec stringがRust oracle結果に一致。

## 完了条件
- [ ] 3 codecの対象helperとテストを持つ。
- [ ] 対応未完成ならREADMEにpartialと明示し、未実装関数は公開しない。

## 非対象・境界
画素のdecode、色変換、圧縮率・映像品質の測定はしない。
