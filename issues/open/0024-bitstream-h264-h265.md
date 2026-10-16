# 0024: H.264/H.265 NALとsample entry補助を移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M4 コーデック支援
- 依存Issue: `0005`、`0010`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
RTSP録画やMP4 muxのため、Annex B↔length-prefixedの変換とSPS/VPSなどからのcodec設定情報抽出を提供する。

## 上流参照
- [src/bitstream/h264.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/h264.rs)
- [src/bitstream/h265.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/h265.rs)
- [src/bitstream/nal.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/nal.rs)
- [tests/test_bitstream_h264.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_h264.rs)
- [tests/test_bitstream_h265.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_h265.rs)

## 実装手順（How）
1. NAL framingを共通化し、H.264とH.265のheader検証、Annex B start code 3/4byte、長さprefix 1/2/4byteなど上流の有効幅を表現する。
2. H.264 SPS/PPS、H.265 VPS/SPS/PPSを必要範囲だけ解析し、`avcC`/`hvcC`を構築する補助関数を作る。
3. NAL header付きEBSPを保ち、SPS parse内部でのみRBSP化する。reserved length sizeと不正emulation bytesを明示扱い。
4. 無効ヘッダー、空NAL、trailing zero、過大length、NAL中途切断、禁止bit設定の扱いを上流と合わせる。
5. track sample entry作成の自動化はオプションで、入力bitstreamが必ず正しい動画とは断定しない。

## 検証対象（What）
- [ ] 上流`h264-sps-pps-annexb.bin`/`h265-vps-sps-pps-annexb.bin`と同じ結果。
- [ ] Annex B↔length-prefixed変換の戻し試験（必要な正規化例外を明記）。
- [ ] SPS/VPSの切断・zero padding・予約lengthで安全にエラー。

## 完了条件
- [ ] ユーティリティ公開APIが純粋でJS/Native共通。
- [ ] 作ったavcC/hvcCがSampleEntryから読み直せる。

## 非対象・境界
H.264/H.265デコード・エンコードはしない。
