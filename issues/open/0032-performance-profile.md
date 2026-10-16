# 0032: Range I/O・メモリ・CPUのプロファイルを確立する

- 状態: open（計画。未実装・未テスト）
- 優先度: P2
- フェーズ: M5 品質
- 依存Issue: `0014`、`0015`、`0019`、`0022`
- 上流固定基準: `shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59`

## 目的
性能を根拠なくRust並みと称するのではなく、既存実装と同じ入力で処理速度・range read回数・peak memoryを観測する。

## 上流参照
- [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)
- [src/auxiliary.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/auxiliary.rs)
- [tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)

## 実装手順（How）
1. 短いfixture・長尺A/V・moov末尾・fMP4多segment・破損inputを性能setとして固定。ファイルサイズ、track数、sample数をmanifestに記録。
2. Nativeおよびブラウザでparse時間、peak retained bytes、読み取り要求回数、総I/O bytes、UI描画時間を収集。Rust nativeと比べるときはホストやI/O条件を明記する。
3. first metadata latency、sample/sec、反復parseのallocation、box tree virtualization、sample table accessorの計算量をプロファイルする。
4. 大きい`mdat`を複製しない、UIが巨大tableを全件描画しない、無限にrange再試行しない等の回帰条件を定める。
5. 改善後もgolden比較とfuzzを必ず再実行し、速度向上のため意味的互換性を崩さない。

## 検証対象（What）
- [ ] コマンド、入力SHA、OS/arch、MoonBit/Rust commit、warmup回数を付したベンチ出力。
- [ ] 繰返し実行で回帰傾向を測れる。
- [ ] 性能未測定なら数字を掲載しない。

## 完了条件
- [ ] 再現可能な計測手順と初期baselineがある。
- [ ] 主要ボトルネックがissue化され、先行最適化を抑制できる。

## 非対象・境界
CPU使用率や速度の未検証の改善倍率を目標値として捏造しない。
