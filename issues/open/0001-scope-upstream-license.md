# 0001: 上流互換の対象・責務・ライセンスを固定する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M0 基盤
- 依存Issue: なし
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
単なるREADMEの『port』から、Rust版との互換性を検証できる独立MoonBitライブラリへ進める。最初は通常MP4 demux＋Dumpデモ、次に通常MP4 mux／fMP4、最後に拡張コーデック・GUI。移植成功とソースコピーを混同しない。

## 上流参照
- [README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.md)
- [AGENTS.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/AGENTS.md)
- [src/lib.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/lib.rs)
- [crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)

## 実装手順（How）
1. 上流の固定コミット、ライセンス、参照API、対応RFC/ISO規格を `docs/upstream.md` に記録する。上流との差分はcommit SHA更新時に評価し、暗黙のlatest追従を禁止。
2. 互換性を`wire`（MP4 bytes）、`semantic`（track/sample等）、`surface`（公開関数）の3層に分ける。M1ではsemantic一致を基本とし、厳密なバイト一致は該当箇所だけ明示する。
3. 非I/OのMP4 coreと`native file`／`browser File`アダプタを分離。ライブラリの純粋部分からファイル・ネットワーク・DOMを参照しない。
4. ライセンス表記、著作権告知、上流由来のfixtureの配布可否と帰属を確認する。READMEには原著作者と独立移植である旨を明示する。
5. 仕様範囲表に`Mp4FileKindDetector`、3種類のdemuxer、2種類のmuxer、Box/codec string、bitstream helper、C/WASMの対応可否を列挙する。

## 検証対象（What）
- [ ] 上流SHAと対象APIの一覧がドキュメントから追跡できる。
- [ ] 下位I/Oとcore間の責務を説明する設計例をレビューできる。
- [ ] 外部fixtureやコードのライセンス/帰属が確認され、未確認素材を同梱しない。

## 完了条件
- [ ] `docs/upstream.md` と `docs/scope.md` にv0.1/v0.2以降の境界がある。
- [ ] M1で未対応の機能がsupportedと誤表記されない。
- [ ] 独立レビューで上流参照と法的表示の欠落がない。

## 非対象・境界
libwebrtc、H.264/H.265/AV1エンコーダーやデコーダー本体、C ABI完全互換、リアルタイム再生はcoreの対象外。Rust実装をラップするだけのFFIを『MoonBit port』と称さない。
