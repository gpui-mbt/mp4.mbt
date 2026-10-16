# 0002: MoonBitモジュール・公開APIとターゲット基盤を作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M0 基盤
- 依存Issue: `0001`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
初期commitはREADMEのみ。ライブラリとしてビルド・テスト可能な骨格と、後続Issueが並行実装できるパッケージ境界を用意する。

## 上流参照
- [src/lib.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/lib.rs)
- [src/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux.rs)
- [src/mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux.rs)
- [src/codec.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs)

## 実装手順（How）
1. `moon.mod`のnameを`gpui-mbt/mp4`相当に設定する（実際のmooncakes名前空間と衝突を確認）。package directory単位に`moon.pkg`を置き、`codec`・`boxes`・`demux`・`mux`・`bitstream`の依存方向を明示。
2. `src/bytes`・`src/box`・`src/boxes`・`src/demux`・`src/mux`・`src/bitstream`を候補に、循環参照のない依存グラフを実装し、公開API名は上流の型に対応付けた命名表で統一する。
3. coreはOS/Node/DOMを必要としない。最低限のtargetをNativeとJSとし、WASM/WASM-GCはツールチェーンで可能性を検証してからCIへ追加する。
4. APIドキュメントの各例は`moon.pkg`の実パッケージ名を使い、未実装APIの空スタブや偽実装を公開しない。
5. `.gitignore`、`LICENSE`、`README.mbt.md`、`CHANGELOG`と最低限のテストを追加する。`moon info`で生成した`.mbti`差分を公開APIレビューの入力にする。

## 検証対象（What）
- [ ] クリーン環境で`moon check`、`moon test`、`moon info`、`moon fmt`を実行し、バージョンと成否を記録。
- [ ] JSとNative各targetの共通pureパッケージをimportできる。
- [ ] 生成された`.mbti`に予定外の公開関数が含まれない。

## 完了条件
- [ ] coreの空でない最小機能（例：FourCC値とテスト）が2 targetで実行できる。
- [ ] 依存グラフとバージョン固定が記録される。
- [ ] READMEに実際に成功したコマンドだけが記載される。

## 非対象・境界
起動だけ成功するダミーdemuxer/muxerは追加しない。配布は0033で扱う。
