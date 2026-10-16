# 0033: README・API・example・配布とversionを整備する

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M5 配布
- 依存Issue: `0003`、`0013`、`0014`、`0015`、`0016`、`0031`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
使う人がdemoからAPI、テスト、制限、移植元まで到達できるようにし、達成済み機能だけを段階的に配布する。

## 上流参照
- [README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.md)
- [README.en.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.en.md)
- [crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)
- [AGENTS.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/AGENTS.md)

## 実装手順（How）
1. README.mbt.mdと短いREADME.mdへ、対応表、現在のphase、install、Native CLI、ブラウザDemo、Rust比較結果を記載。
2. mooncakesで利用できる公開モジュール名、version、ライセンス、リリースタグとgit SHAの対応を整備し、`moon publish`可能な体裁にする。実際のpublishは別途明示承認があるまでしない。
3. 対応表は`Implemented / Partial / Not started / Blocked`と`verified targets`を分離。C API/WASM APIの完全互換は約束しない。
4. API exampleは実行可能コードを載せ、`moon check/test/fmt/info`の成功証跡とRust oracle SHAをrelease checklistに追加。
5. M1読取版はalphaとして、M2 fMP4、M3通常mux、M4 codec拡張のリリース基準を分けて記録する。

## 検証対象（What）
- [ ] クリーンNative/JS環境でREADMEのコマンドを順番に実行。
- [ ] 未対応APIを利用する例が実行可能と誤記されない。
- [ ] docsのsample outputと実結果が一致。
- [ ] タグのversionとsource SHAが一致する。

## 完了条件
- [ ] リリース文書と互換性matrixが作成される。
- [ ] 適正なライセンス・上流クレジット・fixture帰属がある。
- [ ] publish可否と実施状況を明示する。

## 非対象・境界
この計画へのcommitではタグ作成・mooncakes公開・GitHub Releaseは行わない。
