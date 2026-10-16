# [P1 / M5] 変異テスト・fuzz・大規模不正入力の堅牢化

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: test/0031-fuzz-pbt-hardening
Priority: P1
Milestone: M5
Depends on: [0004](./0004-oracle-fixtures.md), [0005](./0005-safe-bytes.md), [0006](./0006-box-header.md), [0013](./0013-mp4-file-demux.md), [0018](./0018-fmp4-segment-demux.md), [0022](./0022-mp4-file-mux.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

信頼できないメディアを処理するライブラリとして、panic・無限ループ・メモリ爆発を防ぎ、正しい入力まで拒否する退行も捕捉する。Box Header/Tree、sample table、各demuxer、各muxer、codec helperへmutation corpusとproperty-based test（PBT）を導入し、上流Rust fuzz targetとの対応表、失敗seedの回帰管理、入力リミットと停止条件を整備する。

## 背景

- 上流Rust側の参照元: [fuzz/fuzz_targets/fuzz_box_header.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_box_header.rs)、[fuzz/fuzz_targets/fuzz_mp4_file_demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_demux.rs)、[fuzz/fuzz_targets/fuzz_fmp4_segment_demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_fmp4_segment_demux.rs)、[fuzz/fuzz_targets/fuzz_mp4_file_mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_mux.rs)、[pbt/tests](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/pbt/tests)。
- [0000](./0000-implementation-roadmap.md) のテスト区分表はFuzz/PBTを「boundary mutation、壊れたbox、random seeds」に対する「panic/無限loop/範囲外参照をしない、発見seedを回帰化」と定義し、検証状態はPASS / FAIL / UNVERIFIED / NOT_RUNを独立に記録するとしている（§8）。
- [0000](./0000-implementation-roadmap.md) のリスク表は「巨大/壊れた入力」の対処に [0005](./0005-safe-bytes.md) / [0006](./0006-box-header.md) / [0007](./0007-root-box-tree.md) / 本issueを対応させている。
- 前提: [0006](./0006-box-header.md) のBoxHeader（size=1/0/uuid）、[0005](./0005-safe-bytes.md) の安全なbyte処理と`ParseLimits`、[0013](./0013-mp4-file-demux.md) / [0018](./0018-fmp4-segment-demux.md) のdemux、[0022](./0022-mp4-file-mux.md) のmuxが対象である。[0004](./0004-oracle-fixtures.md) のRust oracle・fixture manifestと [0016](./0016-rust-moonbit-diff.md) の差分スキーマを比較の基盤にする。
- 2026-10-16時点で `moon.mod` も実装コードもないため、本issueは計画であり未実装・未テストである。

## 問題

- MoonBit側に上流fuzz target/PBTに対応する実行手段と対応表がない。
- size/count/offset/flagsを壊した入力でpanic・無限ループ・制限なしallocationが起きる可能性が未検証である。
- 入力サイズ、最大box深さ/個数、最大samples、解析時間/step回数の制限と停止条件がcore/APIに未実装で、どこで止まるべきか文書化されていない。
- crash seedの最小化・保存・再現コマンドの運用がない。
- 1-byte mutationをRust/MoonBitへ同一bytesで渡す差分比較手段がない。
- 正常入力を拒否する退行（過剰な制限・境界誤り）を検出するsuiteがない。

## 目標

- 各層にmutation corpusとPBTを置き、上流fuzz targetとの対応表を保つ。
- 入力サイズ、最大box深さ/個数、最大samples、解析時間/step回数の制限をcore/APIに実装し、停止条件を明示する。
- 不変条件（decoder→encoder→decoderのsemantic roundtrip、offset monotonicity、元データ範囲内のsampleのみ返る）を検証する。
- crash seedは最小化して回帰fixtureとして管理し、種別・SHA・再現コマンドを残す。
- CIのfast property suiteが常時動き、長いfuzzは別ワークフローで実行可能にする。
- 残余リスクをREADMEに示す。
- 未実行をPASSにしない。

## 対象外

- 恣意的なfixed seedだけで『fuzz完了』としない。第三者レビューと追加検証で補う。
- 上流Rust targetの移植完了そのものを目的にせず、MoonBitで実施可能な範囲を対応表で管理する。未対応のtargetは未対応と明示する。
- sample payloadのdecode/encode品質（[0013](./0013-mp4-file-demux.md) の非対象）は扱わず、codec helperのcorpus対象は各helper issueの完了後に追加する。
- fuzz自体の実行基盤構築のうち、CI全体の構成は [0003](./0003-ci-contract.md) の範囲とし、本issueはsuiteとtargetの追加に限定する。

## 提案する方針

- corpus: Box Header/Tree（[0006](./0006-box-header.md) / [0007](./0007-root-box-tree.md)）、sample table（[0009](./0009-sample-tables.md)）、各demuxer（[0013](./0013-mp4-file-demux.md) / [0018](./0018-fmp4-segment-demux.md) / [0019](./0019-fmp4-file-demux.md)）、各muxer（[0020](./0020-fmp4-segment-mux.md) / [0022](./0022-mp4-file-mux.md)）、codec helper（[0011](./0011-codec-strings.md) 等）に対し、size/count/offset/flagsを壊すmutation corpusを作る。corpusの保存形式・ファイル名は実装時に確定する。
- 対応表: 上流の [fuzz_box_header.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_box_header.rs)、[fuzz_mp4_file_demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_demux.rs)、[fuzz_fmp4_segment_demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_fmp4_segment_demux.rs)、[fuzz_mp4_file_mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/fuzz/fuzz_targets/fuzz_mp4_file_mux.rs)、[pbt/tests](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/pbt/tests) を対応表化し、MoonBitで実施可能なPBTを導入する。使用するPBT機構は実装時に確定する。
- 差分: RustとMoonBitへ同一bytesを渡す差分testを追加する。比較は [0016](./0016-rust-moonbit-diff.md) のJSON schemaと [0004](./0004-oracle-fixtures.md) のfixture規則に従い、Rust oracleが取得できない場合はUNVERIFIEDとする。
- リミット: [0005](./0005-safe-bytes.md) が導入する`ParseLimits`を基盤に、入力サイズ、最大box深さ/個数、最大samples、解析時間/step回数の制限をcore/APIへ実装し、停止条件（どのエラーでどう止まるか）を明示する。0005との役割分担と既定値は実装時に突き合わせて確定する。
- 不変条件: decoder→encoder→decoderのsemantic roundtrip、offset monotonicity、元データ範囲内のsampleのみ返る条件をproperty suiteで固定する。
- seed運用: crashしたseedは最小化し、種別・SHA・再現コマンドを付けて回帰fixtureとして管理する。追加はレビュー経由とする。
- 実行分離: fast property suiteをCI常時実行、長時間fuzzを別ワークフローとする（[0003](./0003-ci-contract.md) の分離方針と整合）。
- 互換性要件: 正常fixtureのgolden（[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)）をPASSし続けること。リミット既定値の変更は比較結果に影響し得るため、変更時に0004/0016へ同時反映する。
- 境界条件: corpusはfixture帰属・ライセンス確認（0001/0004）が済んだ素材のみ保存し、確認できない実メディアをコミットしない。

## 受け入れ条件

- [ ] Given mutation corpus, when 各targetを実行する, then panic・無限ループ・制限なしallocationが発生せず、停止条件どおりに終了する。
- [ ] Given 指定したrandom seed, when fuzzを再実行する, then 同じ結果が再現でき、種別・SHA・再現コマンドが記録されている。
- [ ] Given invalid size=0/1/uuid、入れ子10^n、sample count過大の入力, when 解析する, then 明示されたエラーまたは停止条件で終わり、panicしない。
- [ ] Given short bufferとseek要求の循環を誘発する入力, when 解析する, then 処理が有限stepで停止する。
- [ ] Given 同一bytesへの意図的な1-byte mutation, when RustとMoonBitへ投入する, then 双方の異常処理の差分が比較レポートとして得られる。
- [ ] Given 正常fixture, when property suiteを実行する, then 正しい入力の拒否（退行）が検出されない。
- [ ] Given crashしたseed, when 最小化して回帰fixtureに追加する, then 既知corpusで再発しない。
- [ ] Given decoder→encoder→decoderのroundtrip, when 不変条件（offset monotonicity・元データ範囲内のsampleのみ返る）を検証する, then 違反がない。
- [ ] Given CIのfast property suite, when 実行する, then 常時動作し、長いfuzzは別ワークフローで実行可能である。
- [ ] fuzz実行時間・回数・実行済みtargetが記録され、未実行がPASSとして集計されない。
- [ ] 残余リスクがREADMEに示されている。

## テスト計画

- 現時点では実行できない: `moon.mod` がないため、`moon check` / `moon test --target native` / `moon test --target js` は実行不可である。以後の実行結果はPASS / FAIL / 未実行（NOT_RUN / UNVERIFIED）を分けて記録する。
- 実行予定コマンド: fast suiteは `moon test --target native`（および `--target js`）を基本とし、長時間fuzzは別ワークフローの専用コマンドで実行する。コマンド名・harness名は実装時に確定し、本issueへ追記する。
- wbtest/unit: mutation corpusの各ケースを決定的に実行し、seed最小化の手順を固定する。
- Rust差分: 固定SHAの上流Rustへ同一bytesを入力し、MoonBit側の結果と比較する。oracle取得不能時はUNVERIFIEDとし、一致扱いしない。
- 記録: 実行時間・回数・target・seed・各commit SHA・再現コマンドを残す。未実行はNOT_RUNとして明示する。
- ライセンス確認: corpusへ保存する素材は0001/0004の帰属確認規則に従う。

## リスク

- fuzzコストによるCI肥大: fast suiteと長時間ワークフローを分離し、定期実行または手動起動とする（[0003](./0003-ci-contract.md) の分割に合わせる）。
- 偽の完了（恣意的fixed seedのみ）: 対応表・実行記録・第三者レビューと追加検証で補い、実施した範囲だけを完了とする。
- 過剰なリミットで正常入力を拒否: 正常fixtureのsuiteと0004/0016のgolden比較で境界を検証する。既定値変更は同時に反映する。
- corpusのライセンス・帰属: 0004のmanifest規則に従い、確認できない素材は保存せず未実行と記録する。
- Rust/MoonBit挙動差の誤ラベル: 仕様変更 / 未実装 / 候補バグ / Unverifiedのラベルを [0016](./0016-rust-moonbit-diff.md) / [0034](./0034-upstream-drift.md) と揃える。
- データ形式: goldenと比較レポートは0004/0016のschemaを再利用し、64bit値の文字列化等の比較規則を変えない。
- ロールバック: テストとcorpusの追加は独立コミットに分けてrevert可能にする。リミットの既定値変更は公開契約に影響し得るため、変更時に品質ゲート（0003）とCHANGESへ記録する。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] 不正入力に対する解析リミット（入力サイズ、box深さ/個数、sample数、step数）と停止条件をcore APIに追加
- [ADD] crash seedの回帰corpusとfast property suiteを追加

## 注記

- 関連: [0004](./0004-oracle-fixtures.md)（golden/manifest）、[0005](./0005-safe-bytes.md)（`ParseLimits`とerror分類）、[0006](./0006-box-header.md)（size=1/0/uuid）、[0013](./0013-mp4-file-demux.md) / [0018](./0018-fmp4-segment-demux.md) / [0022](./0022-mp4-file-mux.md)（対象実装）、[0016](./0016-rust-moonbit-diff.md)（差分）、[0034](./0034-upstream-drift.md)（ラベル運用）、[0003](./0003-ci-contract.md)（CI分離）。
- 上流参照: 個別のfuzz target URLと [pbt/tests](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/pbt/tests) は背景と提案する方針に列挙した。
- 未決事項: PBT機構、corpus/seedの保存形式、リミット既定値、長時間fuzzの実行基盤は実装時に確定し、本issueへ追記する。
- 証跡: 実行時間・回数・target・seed・再現コマンド・SHAをログまたはartifactとして残し、未実行をPASSと扱わない。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
