# [P2 / M5] gpui.mbt Native MP4 Inspectorを作る

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0030-native-gpui-inspector
Priority: P2
Milestone: M5
Depends on: [0013](./0013-mp4-file-demux.md), [0015](./0015-web-mp4-dump.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

同じMoonBit coreを使い、gpui.mbtでNative file viewer（MP4 Inspector）を作る。Web側で実装した解析結果と同じcanonical modelを表示し、ファイル選択・Box tree・track table・sample timeline・選択sampleのhex viewを操作対象とする。

## 背景

- 本issueは [0000](./0000-implementation-roadmap.md) のIssue一覧でM5デモ拡張に置かれている。M5のgateは「対象targetのE2E成功、未検証項目はPartial/Unverifiedと表示」である。
- 上流の参照例は [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)（CLIでの表示項目）と [examples/dump_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/index.html)（ブラウザDumpのUI構成）である。
- [0000](./0000-implementation-roadmap.md) のリスク表は「Native GUIとcoreの結合」でWeb/Nativeの挙動分岐を挙げ、対処Issueに [0002](./0002-moonbit-bootstrap.md) / [0015](./0015-web-mp4-dump.md) / 本issueを指定している。
- 解析の本体は [0013](./0013-mp4-file-demux.md)（通常MP4 demux）と [0015](./0015-web-mp4-dump.md)（canonical JSON）で確立し、本issueは表示側を担う。
- 2026-10-16時点の `mp4.mbt` はREADMEのみで `moon.mod` も実装コードもない。本issueは未実装・未テストの計画である。

## 問題

- Web Dumpはブラウザ内で解析結果を表示できるが、Nativeファイルをローカルで閲覧する経路がない。
- gpui.mbtの実公開APIと互換バージョンが未固定で、ファイル選択・Box tree・track table・sample timeline・hex viewの構成方法が決まっていない。
- NativeファイルI/Oをcoreへ直接入れると、parser/codec layerがgpuiやOS APIへ依存し、Web/JS targetとの挙動分岐を生むおそれがある。
- 500MB以上等の大型fixtureで全量読み込みが起きると、メモリと応答性が破綻する。
- Web DumpとNative Inspectorの表示が食い違った場合に、どちらを正とするか（canonical JSONの比較で判定する）が運用化されていない。

## 目標

- 同じMoonBit coreのcanonical modelを、Web側とNative側の両方で表示する。
- ファイル選択・Box tree・track table・sample timeline・選択sampleのhex viewを操作できる。
- 非同期読み込み・大容量向け仮想リスト・操作キャンセルを実装し、選択範囲だけをディスクからreadする。
- LinuxでCI/build可能な範囲を先に仕上げ、macOS Apple Siliconでは別環境で実ウィンドウの描画・入力・高DPIを検証する。
- Web Dumpとの差は同じcanonical JSONの比較で検証し、スクリーンショットはUI回帰検証として別軸で扱う。
- parser/codec layerにgpuiやOS APIへの依存を侵入させない。

## 対象外

- 初回からWindows/Intel Macのフル互換を狙わない。
- 音声/映像再生UIは後続課題とする。
- core側のdemux/mux機能そのものの追加・変更は各担当issue（0013等）で扱い、本issueは表示と操作の範囲に限定する。
- ブラウザ側Dump（[0015](./0015-web-mp4-dump.md)）のUI変更やWebCodecs変換（[0029](./0029-webcodecs-transcode.md)）との統合は含めない。

## 提案する方針

- 配置: Nativeデモは [0000](./0000-implementation-roadmap.md) の提案構成における `native/` 相当に置き、core（`src/demux` 等）との依存方向をUI→coreの一方向に固定する。実際のディレクトリ名とpackage分割は [0002](./0002-moonbit-bootstrap.md) と併せて実装時に確定する。
- gpui.mbt interop: 実公開APIと互換バージョンを最初に固定し、ファイル選択・Box tree・track table・sample timeline・選択sampleのhex viewを組む。固定したバージョンは本issueへ記録する。
- 分離: NativeファイルI/Oをadapterに閉じ込め、parser/codec layerからgpuiやOS APIを参照しない。
- 読み込み: 非同期読み込み・大容量向け仮想リスト・操作キャンセルを実装し、選択範囲だけをディスクからreadする。全量読み込みの有無を計測できるようにする。
- 環境: LinuxでCI/build可能な範囲を先に仕上げ、macOS Apple Siliconで実ウィンドウの描画・入力・高DPIを別環境で検証する。
- 比較: Web Dumpとの差は同じcanonical JSONの比較で検証する。スクリーンショットはUI回帰検証として別軸で扱う。canonical JSONのschemaは [0015](./0015-web-mp4-dump.md) / [0016](./0016-rust-moonbit-diff.md) と共有し、Native独自schemaを作らない。
- 互換性要件: coreの公開API・エラー分類・JSON schemaはWeb側と同一とし、Native側の都合でcoreへ分岐を追加しない。
- 境界条件: 未選択・巨大ファイル・破損MP4・読み込みキャンセル・ウィンドウ閉鎖・高速なファイル再選択の各状態でUIが固まらず、古い結果が残らないことを設計に含める。

## 受け入れ条件

- [ ] Given Linuxでビルド可能な環境, when Native Inspectorを起動してMP4を開く, then 画面表示・ファイル入力・トラック選択のE2Eが動作する（起動できない場合はNOT_RUNとして記録する）。
- [ ] Given Apple Silicon Macの実機, when Box tree表示・sample選択・ウィンドウ閉鎖を操作する, then 実機で動作し、高DPIと入力も確認できる。実行できない間は未実行と明示する。
- [ ] Given 同一fixture, when Web DumpとNative Inspectorのtrack/sample結果をcanonical JSONで比較する, then 一致する（不一致時はfield pathを記録する）。
- [ ] Given 500MB以上等の大型fixture, when Inspectorで開く, then 全量読み込みが起きないことを計測で確認できる。
- [ ] Given coreのソース, when 依存関係を確認する, then gpuiとOS APIの参照がUI層に限定され、coreへ侵入していない。
- [ ] Native版デモの操作方法が文書化され、実機の証拠（ログ・スクリーンショット等）が残っている。

## テスト計画

### 現時点の実行可否

- 2026-10-16時点では `moon.mod` がないため、`moon check` / `moon test --target native` / `moon test --target js` はいずれも実行できず、本issueの検証項目はすべて未実行である。実装後に実行結果（PASS / FAIL / 未実行）を記録する。

### 自動テスト（UI非依存）

- canonical modelから表示モデルへの変換、canonical JSONとの比較を純関数としてwbtestで固定する。
- core回帰: [0013](./0013-mp4-file-demux.md) のテストと [0016](./0016-rust-moonbit-diff.md) の差分レポートが引き続きPASSすることを確認する。

### 手動・環境別確認

- Linux E2E: CIまたはローカルで起動できる場合は、ファイル入力→表示→トラック選択→終了までを確認する。ヘッドレス等で起動できない場合はNOT_RUNとする（PASSと扱わない）。
- Apple Silicon実機: 実ウィンドウの描画・入力・高DPI・ウィンドウ閉鎖を確認する。物理MacがCIにない間は未実行と記録し、[0015](./0015-web-mp4-dump.md) / [0016](./0016-rust-moonbit-diff.md) の実機受入に併せて実施する。
- 大型fixture: 読み込み中に全量readが起きないことを [0032](./0032-performance-profile.md) の計測手順と整合する方法で確認する。計測していない間は「全量読み込みなし」と主張しない。
- 証跡: スクリーンショット、操作ログ、canonical JSONの比較結果（一致/不一致とfield path）をartifactとして残す。

## リスク

- gpui.mbtのAPI・互換バージョン変動: 着手時に実公開APIと互換バージョンを固定して記録し、変動時はUI層のみの修正で戻せるようにする。
- coreとUIの結合によるWeb/Native分岐: 依存方向をレビューとtarget別ビルドで確認し、adapter以外からのgpui/OS API参照をレビューで差し戻す。
- 大容量fixtureでのメモリ・応答性劣化: 仮想リストと選択範囲read、キャンセルを先に実装する。計測（[0032](./0032-performance-profile.md)）なしに改善を主張しない。
- 実機環境がないことによる未検証の放置: 未実行を明示し、完了条件に実機証拠を残す。
- データ形式: canonical JSONのschemaをNative独自に拡張しない。schema変更は [0015](./0015-web-mp4-dump.md) / [0016](./0016-rust-moonbit-diff.md) と同時に更新し、旧schemaのfixtureを暗黙に読み替えない。
- ロールバック: Nativeデモはcoreから分離されているため、問題時はデモ追加コミットのrevertで戻せる。coreの公開契約は変えない。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] gpui.mbt Native MP4 Inspector（Web Dumpと同一canonical modelのNativeファイルビューア）を追加

## 注記

- 関連: [0013](./0013-mp4-file-demux.md)（demux API）、[0015](./0015-web-mp4-dump.md)（Web Dumpとcanonical JSON）、[0016](./0016-rust-moonbit-diff.md)（差分比較）、[0002](./0002-moonbit-bootstrap.md)（package分割・target）、[0032](./0032-performance-profile.md)（読み込み計測）、[0029](./0029-webcodecs-transcode.md)（M5のWeb側デモ）。
- 上流参照: 本issue専用の上流exampleはなく、[examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs) と [examples/dump_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm/index.html) は表示項目とUI構成の参照元として使う。
- 未決事項: gpui.mbtの互換バージョン、Nativeデモのpackage名・配置、LinuxでのCI起動可否は実装時に確定し、本issueへ追記する。
- 証跡: 実機のスクリーンショットと操作ログ、canonical JSON比較の一致/不一致とfield path、読み込み計測の条件（host・fixture）を残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。

## 進捗

- `src/inspect` に gpui/OS 非依存の portable view model（box tree rows / track rows /
  仮想 sample window / hex dump）を追加し、unit test を追加した。
- gpui native host・ファイル選択・ウィンドウ E2E・大容量 read 計測は **NOT_RUN**。
  本 issue は未完了のため `issues/polished/` に残す。
