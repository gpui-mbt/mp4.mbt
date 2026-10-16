# 0016: 同一MP4でRust/WASMとMoonBitの差分を可視化する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M1 MP4読取
- 依存Issue: `0004`、`0015`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
左右比較で『似ている』ではなく、同一入力に対して一致した項目・不一致の箇所が分かる conformance lab にする。

## 上流参照
- [examples/dump_wasm](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm)
- [crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)
- [tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)

## 実装手順（How）
1. 上流Rust/WASMを固定コミットからビルドした参照実装とし、MoonBit/JSをcandidateにする。両方へ同じFile bytesを与え、コードパスは別々に維持する。
2. Rust側のC/WASM JSON bridgeは`mp4_demux_sample_to_json`等の公開関数から取得し、候補の出力を共通JSON schemaに変換。未知項目をゼロ埋めする変換は禁止。
3. 左/右のtrack list・sample list・box treeを並置し、差分はfield path・expected/actual・対象sample index・source commitを表示する。
4. 64bit数値は文字列化、CTTS未設定と0の区別、timebase付き比較、sample entry変更条件、エラー型一致を保証する。
5. candidateのビルド失敗やoracle不能をUnverifiedとして扱い、差分なしをPASSと混同しない。

## 検証対象（What）
- [ ] 少なくとも3 fixtureでRust/MoonBitの結果と比較レポートを保存。
- [ ] 意図的に1sampleのdurationを変えると正しいfieldに不一致を出す。
- [ ] Rust側実装/版違いを差分へ書き出す。
- [ ] Browser E2Eが実際に両ロジックを起動していることを検証する。

## 完了条件
- [ ] 差分レポートと実行証跡をCI artifact化。
- [ ] 同じ入力に対する両実装の独立性がレビュー可能。
- [ ] Pass/Fail/UnverifiedをUIとCIで区別。

## 非対象・境界
Rustの解析結果をMoonBit側に埋め込んで『一致』させない。gpui-conformanceの画面比較との統合は任意の後続作業。
