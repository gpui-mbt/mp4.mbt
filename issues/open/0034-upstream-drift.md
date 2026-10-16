# 0034: 上流追従と互換性監査を継続可能にする

- 状態: open（計画。未実装・未テスト）
- 優先度: P2
- フェーズ: M5 品質・保守
- 依存Issue: `0004`、`0016`、`0022`、`0033`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
固定SHAの上流から将来のdevelopへ更新するとき、API互換・意味互換・規格変更を混同せず段階的に判断できる運用を作る。

## 上流参照
- [CHANGES.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/CHANGES.md)
- [src/demux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file.rs)
- [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)
- [src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs)

## 実装手順（How）
1. baseline SHAを更新するPRごとに`CHANGES.md`・API一覧・対象filesを比較し、`source diff`と`contract delta`を生成する。
2. 新たなRust oracle outputを生成して旧baseline/new baseline/MoonBit candidateの三者を比較。上流の仕様変更による差分とMoonBitの未実装を別ラベルにする。
3. codec追加や規格改定、box構造追加などは機能Issueに分解し、既存の対応範囲を明示し続ける。
4. goldenの自動上書きではなくレビュー承認でbaselineを更新。元fixture/hashと変更理由を残す。
5.  upstream SHA が進んでも既存のMoonBit実装が自動的に互換と宣言されないよう、リリースmatrixに固定参照を表示する。

## 検証対象（What）
- [ ] 上流APIに仮の追加を入れた監査リハーサルで新旧差分が正しく検出される。
- [ ] 候補版が旧goldenにはPASS、新goldenにはFAILする区別を示す。
- [ ] Rust oracleが取得できない場合をUnverifiedとして記録。

## 完了条件
- [ ] 差分監査手順とupstream更新PRテンプレートがある。
- [ ] 追従時に対象Issue・テスト・実行結果をリンク可能。

## 非対象・境界
上流の更新を無確認で直接取り込む自動マージはしない。
