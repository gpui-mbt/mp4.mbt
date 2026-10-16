# 0023: 通常MP4書込・roundtrip CLIサンプルを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M3 通常MP4書込
- 依存Issue: `0013`、`0022`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
通常MP4の作成・再読込を1コマンドで検証し、媒体なしでも動く最小サンプルを用意する。

## 上流参照
- [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)
- [crates/wasm/examples/mux.js](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/examples/mux.js)
- [tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)

## 実装手順（How）
1. `examples/mux`で固定Opus/AAC sample entryと既知payloadを組み立て、`initial_boxes_bytes`→payload追記→`append_sample`→`finalize`結果の指定offset書込を行う。
2. CLIは`--faststart`、`--output`と`--verify`を用意し、`--verify`ではMoonBitとRust oracle双方のdemux結果を比較する。
3. 書き込むファイルを破壊しないよう既存ファイルoverwriteの明示許可を要求。失敗時は一時ファイルを削除するか、安全に残してパスを報告する。
4. 再実行可能な小さなfixtureと説明を追加し、テスト時は生成時刻を固定する。

## 検証対象（What）
- [ ] 最小サンプルがMoonBitで正しくroundtripする。
- [ ] faststart / non-faststartでmoov位置とsamplesの同一性を確認。
- [ ] finalizeのoffset対応を書かずに失敗させる異常ケースを検出。
- [ ] Rust demuxが出力MP4を受理する。

## 完了条件
- [ ] CLI smoke testとgoldenがCIにある。
- [ ] ファイルがユーザーが指定したパスに正しく生成される。

## 非対象・境界
複数音声言語trackは上流現行設計上サポート外。
