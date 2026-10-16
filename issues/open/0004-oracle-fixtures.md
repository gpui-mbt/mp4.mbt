# 0004: Rust oracle・fixture・正規化goldenを構築する

- 状態: open（計画。未実装・未テスト）
- 優先度: P0
- フェーズ: M0 基盤
- 依存Issue: `0001`、`0002`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`（`develop` の調査時HEAD）

## 目的
Rust互換性を主観で判定せず、同じ入力bytes→両実装→同じ観測値で判定する。特に大きな64bit値と順序を損失なく扱う。

## 上流参照
- [tests/testdata](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/testdata)
- [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)
- [examples/fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/fmp4.rs)
- [tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)
- [tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)

## 実装手順（How）
1. 上流`1282b704`での小さなfixture（black-h264-video.mp4、black-h264-fmp4.mp4、beep-aac-audio.mp4、beep-opus-audio.mp4、black-av1-video.mp4など）を候補に、帰属とSHA256付きmanifestを作る。
2. 固定上流cloneから実Rust実装を実行するoracleコマンドを用意。ランダム・日時・出力パスなどを固定し、外部システム依存を排除。
3. 結果を`kind`、track ID/kind/timescale/duration、sample順序/DTS/CTTS/keyframe/offset/size、box tree、エラー種別と位置に正規化する。64bit整数はJSONの数値でなく十進文字列で持ち、差分が見えるschemaを定義。
4. expected goldenはRust oracle run IDとupstream SHAを紐付ける。candidateが失敗した場合は差分ではなく未検証/実行失敗にする。goldenを手入力して『一致』を作らない。
5. fixture群に正常、moov先頭/末尾、複数track、切断、巨大size宣言、未知box、字幕、fMP4 multi-segmentを分類。未取得素材はgeneratorで作る。

## 検証対象（What）
- [ ] 生成済みgoldenが同じRust SHA・fixtureから決定的に再生成される。
- [ ] 64bit `2^53+1` 等の整数がgolden出力で丸められない。
- [ ] データ変更・順序変更・エラー区分変更で比較がFAILする。
- [ ] 上流fixture不在／ライセンス未確認時は対象テストを未実行として報告する。

## 完了条件
- [ ] `tests/fixtures/manifest`と`tools/oracle`の実行手順がある。
- [ ] RustとMoonBitを区別した実行証跡が保存できる。
- [ ] 結果一覧にPass/Fail/Unverifiedの3状態がある。

## 非対象・境界
公開配布できることを確かめていない外部テストメディアは保存しない。動画エンコード再現をこのIssueの前提にしない。
