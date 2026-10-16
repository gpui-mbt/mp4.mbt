# 0017: moof/traf/tfhd/trun/tfdt/mvexとsidx/mfraを移植する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M2 fragmented MP4
- 依存Issue: `0008`、`0009`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
fMP4のsegment metadataとsample時間を読み書きするためのBox層を実装する。

## 上流参照
- [src/boxes_fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_fmp4.rs)
- [tests/test_boxes_fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_boxes_fmp4.rs)

## 実装手順（How）
1. `mvex/trex/mehd`、`moof/mfhd/traf/tfhd/tfdt/trun`をversion/flagsで分岐する型付きParser/Encoderへ実装する。
2. `sidx`参照時間・offset/size、`mfra/tfra/mfro`ランダムアクセスindexも後続対応のため構造を整理する。
3. tfhd default sample duration/size/flags、base-data-offset、trun data-offset、sample composition time（符号付きを含む）の継承優先順位を固定する。
4. 各boxが親境界を越えないこと、flagsとオプション欄数の一致、count上限を厳しく検証する。
5. 未定義flagsや未知boxはどこまで許容/保存するか上流仕様を参照して明示する。

## 検証対象（What）
- [ ] trun sample_countとoptional fieldの全代表組合せをテスト。
- [ ] tfdt version0/1、trun version0/1、signed CTO、sidx v0/v1境界。
- [ ] trafにtfhdが欠ける、count不正、offset overflowでFAILする。
- [ ] Rust fixtureのbox tree・encode/decode結果と比較。

## 完了条件
- [ ] fMP4の必須boxが型付きでdecode/encodeできる。
- [ ] time/offset計算の根拠とテストが追跡できる。

## 非対象・境界
セグメント全体の状態機械は0018〜0020で実装する。
