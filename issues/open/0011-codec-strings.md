# 0011: RFC 6381 codec stringをSampleEntryから生成する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M1 MP4読取
- 依存Issue: `0010`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
MP4 Dumpのcodec列とブラウザWebCodecs設定に使う文字列を、ファイル名推測ではなくsample entry由来で生成する。

## 上流参照
- [src/codec_string.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec_string.rs)
- [tests/test_codec_string.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_codec_string.rs)

## 実装手順（How）
1. codec id一覧を上流に一致させる。AVC `avc1.640028`、HEVC `hev1/hvc1`、AV1 `av01`、VP8/VP9、AAC `mp4a.40.2`、Opus/FLACの処理を分ける。
2. 各codec boxに格納されたbitfieldから必要なprofile/level/bit-depthを導出する。未知entryをsilent fallbackで正常文字列に変換せずUnsupportedとする。
3. 文字列はcanonicalな小文字hexやゼロ埋め桁数を使用し、元の4CC大小文字を保持。
4. parse-only codecとの整合性を明示し、WebCodecsの実機サポート判定は別レイヤーに委ねる。

## 検証対象（What）
- [ ] AVC High `avc1.640028`、AAC-LC `mp4a.40.2`、AV1 `av01.0.01M.08`などをRust oracleと一致。
- [ ] 未知codecと欠落esds/壊れたASCでUnsupportedかInvalidDataを区別。
- [ ] JS/Nativeでlocaleに依存しない同一文字列になる。

## 完了条件
- [ ] 公開`from_sample_entry`相当のAPIが実装・文書化される。
- [ ] 文字列の一致を同一sample entryのgoldenで確認する。

## 非対象・境界
コーデックのハードウェア利用可能性、エンコードや再生可否の判定はしない。
