# 0015: MoonBit/JSのブラウザMP4 Dumpデモを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M1 MP4読取
- 依存Issue: `0013`、`0014`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
ファイルをドラッグ&ドロップするとBox Tree・track・sample timelineが更新されるGitHub Pages用ブラウザデモを作る。

## 上流参照
- [examples/dump_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/index.html)
- [examples/dump_wasm/src](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/src)
- [crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)

## 実装手順（How）
1. MoonBit coreはJS targetで動かし、UIアダプタがFile.sliceでRange I/Oを提供する。ファイル全量を最初からArrayBuffer化しない。
2. Boxツリーはtype/offset/size/parent、track一覧はcodec/width/height/sample count/timescale、sample一覧はDTS/PTS/duration/keyframe/offset/sizeを表示する。
3. サイズ・sample数に応じたlazy render/virtual listとキャンセル機構を用意し、大容量・切断・異常MP4でもUIが固まらない。
4. 非対応codecは『構造は読めるが再生は非対象』と示す。ファイルはローカルで解析し外部へアップロードしない。
5. 静的ビルドを`web/`相当へ出力しPagesで公開。CLIと同じcanonical JSON exportを提供。

## 検証対象（What）
- [ ] AAC/AVC/AV1 fixtureでBox Treeとトラック情報が表示される。
- [ ] ファイル選択→別ファイル再選択→キャンセル時に古い結果が残らない。
- [ ] 不正boxで処理中断しても画面が残り、場所/原因/対処のエラーを出す。
- [ ] ブラウザでページreload後も秘密の入力ファイルを勝手に保存しない。

## 完了条件
- [ ] Playwright等のブラウザ実操作テストを実行できる。
- [ ] Pagesで静的デモが開ける。
- [ ] スクリーンショットと表示されたJSONをCIで取得できる。

## 非対象・境界
MP4をブラウザで再生すること・ファイルをネット送信することは、この段階では扱わない。
