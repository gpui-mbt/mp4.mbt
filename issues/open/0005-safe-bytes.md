# 0005: Bounds-safeなバイト列・ビット列・エラー型を作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0002`、`0004`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
MP4の大半は信頼できない長さ付きbinary入力であり、整数overflowや境界外参照を統一して防ぐ土台が必要。

## 上流参照
- [src/codec.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs)
- [src/basic_types.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs)
- [src/bitstream.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream.rs)

## 実装手順（How）
1. read cursor/write cursorにBig Endian u8/16/24/32/64、signed値、FourCC、固定小数、範囲付きslice取得、必要容量を定義する。全て位置更新を成功後に行い、失敗時には不完全な状態を残さない。
2. 計算は`offset + size`を直接使わずchecked arithmeticにする。u64からJSのNumberやNativeのindexへの変換境界を明記する。
3. bit reader/writerはMSB順、skip、固定幅読み・書き、bit幅上限、終端チェックをサポートし、後続NAL/AAC/AV1で共用する。
4. 上流`ErrorKind`のInvalidInput/InvalidData/Unsupported等に対応する失敗分類とbox type／byte offset／理由を保持する。ユーザー入力のためにpanicしない。
5. 巨大入力でのallocationとnestingを制限する`ParseLimits`をcoreに設け、既定値／上限変更と未取得rangeの扱いを記録する。

## 検証対象（What）
- [ ] BE read/writeの固定パターンとzero-length／短いbufferでの正確な位置保持。
- [ ] u64最大・`2^53`境界・符号付きCTTS・負数相当を混ぜた境界入力。
- [ ] cursor offset overflow、符号伸長、最大値以上の確保をエラーとして検出。
- [ ] JS/Nativeで同じ値とエラー分類を返す。

## 完了条件
- [ ] 暗黙のint overflow／境界外アクセスがない。
- [ ] テスト名が何を検証するか分かり、正常/異常両方の例がある。
- [ ] 公開APIはI/Oに依存しない。

## 非対象・境界
ByteArray／Bytesの実装方法はターゲット制約を計測して選ぶ。動画像のdecoded pixel bufferなどは対象外。
