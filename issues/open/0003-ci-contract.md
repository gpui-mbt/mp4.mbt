# 0003: 継続的チェック・変更管理の品質ゲートを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M0 基盤
- 依存Issue: `0002`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
後続30件のIssueを安全に進めるため、MoonBit品質ゲートとRust oracleとの差分報告の置き場所を先に整備する。

## 上流参照
- [.github/workflows/ci.yml](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/.github/workflows/ci.yml)
- [Cargo.toml](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/Cargo.toml)

## 実装手順（How）
1. CIで`moon check`／`moon test`／`moon fmt`の差分チェックと`moon info`公開API差分を行う。targetは実際に対応するNative、JSでmatrix化する。
2. Rust oracleは固定SHA、`cargo` toolchain、検証用スクリプトを明示して再現可能にする。上流testdataやRust buildを毎ジョブ無制限にcloneしない。
3. unit・fixture・golden・E2E・fuzz・performanceを分離し、各PRで必要な最小チェックを定義する。大きなE2Eも失敗を隠さず報告できるようにする。
4. GitHub PagesデモはCI greenの成果物を別workflowで公開。`main`の全内容をPagesへコピーする手順にはせず、Pagesの出力ディレクトリを限定する。
5. 必須チェックは実施したコマンド／target／commit SHA／PASS・FAIL・SKIPを識別。独立レビューはApprove相当・P1なしをマージ判定に使う。

## 検証対象（What）
- [ ] 意図的に構文エラーを注入すると`moon check`が赤くなる。
- [ ] fixture期待値を改変するとgolden比較ジョブが赤くなる（ジョブ完成時）。
- [ ] target未対応時のSKIPはPASSとして集計されない。

## 完了条件
- [ ] CIの実行ログでtarget別に結果が確認できる。
- [ ] Pages deployはcoreテスト失敗時に動かない。
- [ ] レビューを受けるための再現コマンドがドキュメント化される。

## 非対象・境界
CIをgreenにするためのテスト無効化、固定値assert、未検証結果のPASS表示をしない。
