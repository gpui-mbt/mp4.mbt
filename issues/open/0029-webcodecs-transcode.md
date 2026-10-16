# 0029: WebCodecsでローカルMP4変換デモを作る

- 状態: open（計画。未実装・未テスト）
- 優先度: P2
- フェーズ: M5 デモ拡張
- 依存Issue: `0015`、`0022`、`0024`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
『MoonBitのdemux/mux + ブラウザのWebCodecs』でローカルのH.264映像から新しいMP4を生成し、メタデータを双方の表示画面で調べられるようにする。

## 上流参照
- [examples/transcode_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/transcode_wasm/index.html)
- [examples/transcode_wasm/transcode.js](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/transcode_wasm/transcode.js)

## 実装手順（How）
1. 入力はローカルFile API、MP4 parseとsample列抽出・出力構成はMoonBit core、codec変換はブラウザ提供の`VideoDecoder`/`VideoEncoder`を使用する責務分離。
2. H.264 inputからH.264（ブラウザが対応する場合）の出力を最小ゴールとする。AV1/HEVC/VP9の選択肢は`isConfigSupported()`で実機判定し、不可はDisabledにする。
3. DTS/PTS/CTTS/edit listやキーフレームの境界、音声トラックを保持/除外する仕様を明示する。上流デモはedts未考慮でAV syncずれ得ることを参照し、当初は映像単一trackのfileに限定。
4. 全ファイルを一括保持しない分割処理を優先し、不可ならサイズ上限を明示する。キャンセル・異常・出力downloadを実装する。
5. 公開デモのREADMEにブラウザ別の実測サポート結果と制限を載せる。

## 検証対象（What）
- [ ] H.264短いfixtureをWebCodecsで変換し、出力MP4のtrack/sampleをMoonBit/Rust demuxで解析。
- [ ] codec非対応ブラウザでクラッシュせず明示的に無効化。
- [ ] 映像のみ/巨大file/キャンセル/不正inputの動作をE2Eで確認。

## 完了条件
- [ ] ブラウザ内で入力から出力MP4が生成・再解析できる。
- [ ] 上流の制約とMoonBit移植の制約が明記される。

## 非対象・境界
MoonBit製のH.264/AV1エンコーダーを実装するわけではない。Safari/Chrome全機能対応を証拠なしに表明しない。
