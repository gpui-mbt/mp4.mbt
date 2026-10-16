# 0009: stblとSampleTableAccessorを移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0008`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
sample-to-chunkとtime-to-sampleからサンプル位置・再生時間を復元する核心。ここが正しければ大部分の普通のMP4 demuxを実装できる。

## 上流参照
- [src/boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_moov_tree.rs)
- [src/auxiliary.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/auxiliary.rs)
- [tests/test_boxes_moov_tree.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_moov_tree.rs)
- [fuzz/fuzz_targets/fuzz_sample_table_accessor.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_sample_table_accessor.rs)

## 実装手順（How）
1. `stsd`/`stts`/`ctts`/`stsc`/`stsz`/`stco`/`co64`/`stss`/`sdtp`/`cslg`をparser/encoderに展開する。
2. `SampleTableAccessor`にsample index→chunk/file offset・size・sample_description_index・DTS/duration/CTTS・sync flagsを返すAPIを用意する。
3. `ctts`version0 unsigned / version1 signedと`co64`を扱い、offset超過や非単調テーブル・index跨ぎを明示的に拒否。
4. 反復中の位置取得はサンプル個数に対してO(n)を目指し、全sampleの巨大配列を最初から生成しない。
5. trackごとに独立したtimebaseとサンプル走査状態を保持する。

## 検証対象（What）
- [ ] sample数1/複数、複数chunk、同じchunkの複数sample、stsz固定/可変。
- [ ] CTTS正負、co64>2^32、stco境界、stss欠落（全sync扱い）。
- [ ] stsc欠落・逆順・sample_count不整合・総duration overflowを不正入力として処理。
- [ ] 固定上流fixtureのsample offset/size/timestampをRust oracleと全件比較。

## 完了条件
- [ ] sample indexから実bytesの範囲を再現できる。
- [ ] 複数trackの時刻基準が保持される。
- [ ] 巨大テーブルを扱うときの計算量とlimitsが文書化される。

## 非対象・境界
ここではcodec固有のNAL/OBUのデコードをしない。
