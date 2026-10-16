# 0014: 上流demux.rs相当のCLIサンプルを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0013`、`0004`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
目で見て試せる最初の成果物。`moon run`でファイルを指定し、トラック一覧と先頭Nサンプルを表示する。

## 上流参照
- [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)

## 実装手順（How）
1. `examples/demux`コマンドをNative targetで実装。file pathと`--max-samples`、`--json`を公開する。
2. `required_input`へ対応するseek/readを行い、`size=None`の場合の読み方、1MB上限の分割I/Oと要求範囲の蓄積を明確にする。要求範囲が1MBより大きい場合、単純な断片`handle_input`では上流契約違反になるため、安全に結合できる範囲だけ受け入れ、上限超過なら明示エラーにする。
3. 通常MP4からtrack ID/kind、duration/timescale、sample DTS/CTTS/keyframe/offset/sizeを出す。JSONは64bit整数を文字列にする。
4. 誤ったパス、非MP4、途中で切れたファイルのexit codeとエラー表示を統一。
5. READMEに`moon run ... -- file.mp4`など実際のMoonBit CLIに基づく実行例を記載する。

## 検証対象（What）
- [ ] 上流`cargo run --example demux -- fixture.mp4`と同じtrack/sample情報を表示。
- [ ] 先頭10件/全件/0件、空・途中切断・エラー時exit statusを検証。
- [ ] 64bit offsetのJSON精度を壊さない。

## 完了条件
- [ ] CLI実行・出力をCI smoke testに追加する。
- [ ] 再現コマンドと代表出力がREADMEにある。
- [ ] 入力読取の最大メモリが設定可能。

## 非対象・境界
GUIとWebブラウザには未対応。入力のメディアデコードはしない。
