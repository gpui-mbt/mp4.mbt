# 0030: gpui.mbt Native MP4 Inspectorを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P2
- フェーズ: M5 デモ拡張
- 依存Issue: `0013`、`0015`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
同じMoonBit coreを使い、gpui.mbtでNative file viewerを作る。Web側で実装した解析結果と同じcanonical modelを表示する。

## 上流参照
- [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)
- [examples/dump_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/index.html)

## 実装手順（How）
1. gpui.mbtの実公開APIと互換バージョンを固定し、ファイル選択・Box tree・track table・sample timeline・選択sampleのhex viewを組む。
2. NativeファイルI/Oをadapterに閉じ込め、parser/codec layerからgpuiやOS APIを参照しない。
3. 非同期読み込み・大容量向け仮想リスト・操作キャンセルを実装し、選択範囲だけをディスクからreadする。
4. LinuxでCI/build可能な範囲を先に仕上げ、macOS Apple Siliconで実ウィンドウの描画・入力・高DPIを別環境で検証する。
5. Web Dumpとの差は同じcanonical JSONの比較で検証する。スクリーンショットはUI回帰検証として別軸で扱う。

## 検証対象（What）
- [ ] Linuxで起動できる場合の画面表示・ファイル入力・トラック選択のE2E。
- [ ] Apple Silicon Macでは実機でBox tree表示・sample選択・ウィンドウ閉鎖を検証。未実行は未実行と明示。
- [ ] 同一fixtureに対するWeb/Nativeのtrack/sample結果が一致。
- [ ] 500MB以上等の大型fixtureについて全量読み込みが起きないことを計測。

## 完了条件
- [ ] Native版デモと操作方法、実機証拠がある。
- [ ] UI依存がcoreへ侵入していない。

## 非対象・境界
初回からWindows/Intel Macのフル互換を狙わない。音声/映像再生UIは後続課題。
