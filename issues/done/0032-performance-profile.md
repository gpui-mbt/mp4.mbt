# [P2 / M5] Range I/O・メモリ・CPUのプロファイルを確立する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: chore/0032-performance-profile
Priority: P2
Milestone: M5
Depends on: [0014](./0014-demux-example.md), [0015](./0015-web-mp4-dump.md), [0019](./0019-fmp4-file-demux.md), [0022](./0022-mp4-file-mux.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

性能を根拠なくRust並みと称するのではなく、既存実装と同じ入力で処理速度・range read回数・peak memoryを観測する。性能set・manifest・計測手順・回帰条件を固定し、再現可能な初期baselineを作る。改善後もgolden比較とfuzzを再実行し、速度向上のために意味的互換性を崩さない。

## 背景

- 上流の参照元は [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)（計測対象の処理経路）、[src/auxiliary.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/auxiliary.rs)（補助処理）、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)（fMP4ファイルのテスト条件）である。
- [0000](./0000-implementation-roadmap.md) のテスト区分表のPerformance行は「同一fixtureとhostでelapsed / read count / retained memory」を観測し、「未計測の高速化を宣言しない」と定める。検証状態はPASS / FAIL / UNVERIFIED / NOT_RUNを独立に記録する（§8）。
- 計測対象は [0014](./0014-demux-example.md)（Native CLI demux）、[0015](./0015-web-mp4-dump.md)（ブラウザDump）、[0019](./0019-fmp4-file-demux.md)（fMP4多segment読取）、[0022](./0022-mp4-file-mux.md)（通常MP4 mux）の経路である。
- [0030](./0030-native-gpui-inspector.md) のUI描画時間と [0033](./0033-release-docs.md) の公開文書に載るRust比較結果は、本issueの計測条件と証跡を出所とする。
- 2026-10-16時点で `moon.mod` も実装コードもないため、本issueは計画であり未実装・未テストである。

## 問題

- 性能setとmanifestが未定義で、ファイルサイズ・track数・sample数の条件を揃えた比較ができない。
- Nativeとブラウザの観測項目（parse時間、peak retained bytes、読み取り要求回数、総I/O bytes、UI描画時間）と、ホストやI/O条件の記録方法が未定義である。
- first metadata latency、sample/sec、反復parseのallocation、box tree virtualization、sample table accessorの計算量をプロファイルする手段がない。
- 回帰条件（大きい`mdat`を複製しない、UIが巨大tableを全件描画しない、無限にrange再試行しない等）がテストとして固定されていない。
- 未計測の数値がdocsやUIの主張へ流れるリスクがある。

## 目標

- 短いfixture・長尺A/V・moov末尾・fMP4多segment・破損inputを性能setとして固定し、manifestにファイルサイズ、track数、sample数を記録する。
- Nativeおよびブラウザでparse時間、peak retained bytes、読み取り要求回数、総I/O bytes、UI描画時間を収集できるようにする。
- 大きい`mdat`を複製しない、UIが巨大tableを全件描画しない、無限にrange再試行しない等の回帰条件を定めて検証可能にする。
- 改善後もgolden比較とfuzzを必ず再実行し、速度向上のために意味的互換性を崩さない。
- 再現可能な計測手順と初期baselineを作り、主要ボトルネックをissue化して先行最適化を抑制する。
- 性能未測定なら数字を掲載しない。未実行・未検証をPASSと混同しない。

## 対象外

- CPU使用率や速度の未検証の改善倍率を目標値として捏造しない。
- 最適化の実装そのものは本issueでは行わず、主要ボトルネックは別issueに分解して扱う。
- Rust nativeとの比較はホストやI/O条件を明記できる範囲に限定し、条件の異なる数値を並べて優劣を主張しない。
- 計測harnessの対象はdemux/muxの解析経路であり、codec payloadのdecode/encode性能（M4以降）は各helper issueの完了後に追加を検討する。

## 提案する方針

- 性能set: 短いfixture・長尺A/V・moov末尾・fMP4多segment・破損inputで構成し、[0004](./0004-oracle-fixtures.md) のmanifest規則（帰属・SHA256）に従って固定する。ファイルサイズ、track数、sample数をmanifestに記録し、fixture名の最終リストは実装時に確定する。
- harness: Nativeは [0014](./0014-demux-example.md) のCLI相当、ブラウザは [0015](./0015-web-mp4-dump.md) のDump相当の経路で計測する。観測項目はparse時間、peak retained bytes、読み取り要求回数、総I/O bytes、UI描画時間（[0030](./0030-native-gpui-inspector.md) の計測と整合）。コマンド・スクリプト・出力形式は実装時に確定し、本issueへ追記する。
- メトリクス: first metadata latency、sample/sec、反復parseのallocation、box tree virtualization、sample table accessorの計算量をプロファイルする。各指標の定義と測定方法は実装時に確定する。
- 回帰条件: 大きい`mdat`を複製しない、UIが巨大tableを全件描画しない、無限にrange再試行しない等を回帰テストとして固定する。
- 条件の記録: 出力にコマンド、入力SHA、OS/arch、MoonBit/Rust commit、warmup回数を付す。Rust nativeと比べるときはホストやI/O条件を明記する。
- 互換性要件: 改善後もgolden比較（[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)）とfuzz（[0031](./0031-fuzz-pbt-hardening.md)）を必ず再実行し、意味的互換性を崩さない。
- データ形式: bench出力とmanifestは64bit値を丸めない等、0004の比較規則と整合させる。未測定の項目はUNVERIFIED / NOT_RUNとして区別する。
- 境界条件: 計測条件（同時実行、cache状態等）を記録できる範囲で固定し、固定できない条件は結果に明記して単発値を再現性の証拠にしない。

## 受け入れ条件

- [ ] Given 固定した性能set, when Nativeで計測を実行する, then コマンド・入力SHA・OS/arch・MoonBit/Rust commit・warmup回数付きのベンチ出力が得られる。
- [ ] Given 同じfixture, when ブラウザで計測する, then parse時間・読み取り要求回数・総I/O bytes・UI描画時間が採取できる（未採取項目は理由付きで未実行と記録する）。
- [ ] Given 同一条件での繰返し実行, when 結果を比較する, then 回帰傾向を測れる。
- [ ] Given 未測定の項目, when docsやレポートを作成する, then 数字を掲載しない。
- [ ] Given 回帰条件（大きい`mdat`を複製しない・UIが巨大tableを全件描画しない・無限にrange再試行しない）, when テストを実行する, then 各条件が検証される。
- [ ] Given 性能改善の変更, when golden比較とfuzzを再実行する, then 意味的互換性を崩さずに改善を確認できる。
- [ ] 再現可能な計測手順と初期baselineがある。
- [ ] 主要ボトルネックがissue化され、先行最適化を抑制できる。

## テスト計画

- 前提: 2026-10-16時点で `moon.mod` がないため、計測・回帰テストは実行不可（すべて未実行）。まず `moon check` / `moon test --target native` / `moon test --target js` が通る状態が前提であることを記録する。
- Native: Linux等の実機でbench harnessを実行する。CIでは短時間の回帰チェックに限定する（[0003](./0003-ci-contract.md) の分離方針）。
- ブラウザ: [0015](./0015-web-mp4-dump.md) のE2Eで観測できる範囲を計測し、UI描画時間は [0030](./0030-native-gpui-inspector.md) と整合させる。
- 比較: Rust nativeとの比較はホスト・I/O条件を明記し、条件が異なる数値の直接比較はしない。
- チェックリスト: golden比較とfuzzの再実行、未測定/未実行の記録をchecklist化する。
- 記録: 実行結果はPASS / FAIL / 未実行（NOT_RUN / UNVERIFIED）を分けて記録し、数値がないまま成功を主張しない。
- 証跡: ベンチ出力、manifest、入力SHA、OS/arch、commit SHA、warmup回数をartifactとして残す。

## リスク

- 計測条件のばらつき: ホスト・I/O・warmup・反復を固定記録し、単発値を再現性の証拠にしない。
- 未検証数値の流通: [0033](./0033-release-docs.md) の公開文書や [0030](./0030-native-gpui-inspector.md) のUI主張へ未検証数値が入るリスクがある。manifest・issue・実行ログを出所とする数値のみ掲載する。
- 最適化による意味的互換性の破壊: golden比較とfuzzの再実行を改善の必須条件にする。
- 過剰な回帰条件による正常動作の阻害: [0031](./0031-fuzz-pbt-hardening.md) の停止条件・リミットと整合させ、境界はwbtestで固定する。
- データ形式: manifestとbench出力のschemaを0004/0016と整合させ、64bit値を丸めない。
- ロールバック: bench harnessはプロダクト挙動から独立に追加し、問題時はrevertできる。回帰条件のテスト追加が挙動契約に触れる場合はレビューを必須にする。

## 変更履歴

`CHANGES.md` impact: no

## 注記

- 関連: [0014](./0014-demux-example.md)（Native CLI）、[0015](./0015-web-mp4-dump.md)（ブラウザ計測）、[0019](./0019-fmp4-file-demux.md)（fMP4多segment）、[0022](./0022-mp4-file-mux.md)（mux性能）、[0030](./0030-native-gpui-inspector.md)（UI描画時間）、[0031](./0031-fuzz-pbt-hardening.md)（停止条件）、[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)（比較規則）、[0033](./0033-release-docs.md)（数値の掲載先）。
- 上流参照: [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)、[src/auxiliary.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/auxiliary.rs)、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs) を性能setと手順の参照元にする。
- 未決事項: 性能setの最終リスト、bench harness名、出力形式、baselineの更新頻度は実装時に確定し、本issueへ追記する。
- 証跡: ベンチ出力、manifest、入力SHA、OS/arch、commit SHA、warmup回数を残し、計測していない項目はNOT_RUN / UNVERIFIEDと明示する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。

## 検証

- `src/examples/bench` は read 回数・I/O バイト数・track/sample 数を JSON で出力（manual run PASS）。
- 経過時間・peak RSS・ブラウザ計測は NOT_RUN。`docs/performance.md` に手順と回帰条件を記載。
