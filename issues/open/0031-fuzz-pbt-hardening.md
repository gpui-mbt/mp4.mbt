# 0031: 変異テスト・fuzz・大規模不正入力の堅牢化

- 状態: open（計画。未実装・未テスト）
- 優先度: P1
- フェーズ: M5 品質
- 依存Issue: `0004`、`0005`、`0006`、`0013`、`0018`、`0022`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
信頼できないメディアを処理するライブラリとして、panic/無限ループ/メモリ爆発を防ぎ、正しい入力まで拒否する退行も捕捉する。

## 上流参照
- [fuzz/fuzz_targets/fuzz_box_header.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_box_header.rs)
- [fuzz/fuzz_targets/fuzz_mp4_file_demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_demux.rs)
- [fuzz/fuzz_targets/fuzz_fmp4_segment_demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_fmp4_segment_demux.rs)
- [fuzz/fuzz_targets/fuzz_mp4_file_mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_mux.rs)
- [pbt/tests](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/pbt/tests)

## 実装手順（How）
1. Box Header/Tree、sample table、各demuxer、各muxer、codec helperに、size/count/offset/flagsを壊すmutation corpusを作る。
2. 上流Rust fuzz targetを対応表化し、MoonBitで実施可能なproperty-based testを導入。RustとMoonBitへ同一bytesを渡す差分testを追加する。
3. 入力サイズ、最大box深さ/個数、最大samples、解析時間/step回数の制限をcore/APIに実装。停止条件を明示する。
4. decoder→encoder→decoderのsemantic roundtrip、offset monotonicity、元データ範囲内のsampleのみ返る不変条件を検証。
5. crashしたseedは最小化し回帰fixtureとして管理、種別・SHA・再現コマンドを残す。

## 検証対象（What）
- [ ] random seed再現、invalid size=0/1/uuid、入れ子10^n、sample count過大。
- [ ] short bufferとseek要求の循環が停止する。
- [ ] 意図的な1-byte mutationによるRust/MoonBit双方の異常処理を比較。
- [ ] fuzz実行時間・回数・実行済みtargetを記録し、未実行をPASSにしない。

## 完了条件
- [ ] CIのfast property suiteが常時動き、長いfuzzは別ワークフローで実行可能。
- [ ] 無限ループや明白なpanicが既知corpusで再発しない。
- [ ] 残余リスクがREADMEに示される。

## 非対象・境界
恣意的なfixed seedだけで『fuzz完了』としない。第三者レビューと追加検証で補う。
