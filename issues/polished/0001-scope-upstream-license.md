# [P0 / M0] 上流互換の対象・責務・ライセンスを固定する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: docs/0001-scope-upstream-license
Priority: P0
Milestone: M0
Depends on: なし
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

単なる README の『port』から、Rust 版との互換性を検証できる独立 MoonBit ライブラリへ進める。その最初の工程として、上流の固定コミット・ライセンス・参照 API・対応 RFC/ISO 規格、および移植対象の境界（v0.1/v0.2 以降）を `docs/upstream.md` と `docs/scope.md` に固定する。進め方は、最初に通常 MP4 demux ＋ Dump デモ、次に通常 MP4 mux ／ fMP4、最後に拡張コーデック・GUI とし、移植成功とソースコピーを混同しない。

## 背景

- 本 Issue は計画段階であり、未実装・未テストである。2026-10-16 時点の `main` は README のみで、`moon.mod`・実装コード・CI はない（[0000](./0000-implementation-roadmap.md)）。
- 上流固定基準は [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)（調査時の `develop` HEAD）。上流参照として [README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.md)、[AGENTS.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/AGENTS.md)、[src/lib.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/lib.rs)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md) を確認対象にする。
- [0000](./0000-implementation-roadmap.md) では上流ライセンスを Apache-2.0 と整理しているが、著作権告知、上流由来 fixture の配布可否と帰属は本 Issue で個別に確認する。確認前に上流コードや素材をコピーしない。
- 後続 Issue は並行して実装を始めるため、互換性の意味と対象境界を先に固定しないと、各 Issue の『一致』基準と同梱素材の可否が揃わない。

## 問題

- 互換性の意味が `wire`／`semantic`／`surface` の 3 層に整理されておらず、各 Issue の『一致』の判定基準が揃わない。
- 対象・非対象の境界がなく、libwebrtc やコーデック本体まで巻き込むか、逆に M1 で未対応の機能を supported と誤表記する余地がある。
- 上流固定コミットとの差分を評価する手順がなく、暗黙に latest へ追従すると Rust oracle（[0004](./0004-oracle-fixtures.md)）の比較が誤判定になる。
- ライセンス・帰属・fixture 配布可否が未確認のままだと、後続 Issue で未確認素材が同梱され得る。
- 下位 I/O と core の責務分離が文書化されておらず、純粋部分へファイル・ネットワーク・DOM 依存が混入する余地がある。

## 目標

- 上流 SHA・ライセンス・参照 API・対応規格の一覧をドキュメントから追跡できる。
- 互換性を `wire`（MP4 bytes）／`semantic`（track/sample 等）／`surface`（公開関数）の 3 層で説明でき、M1 は `semantic` 一致を基本とすることを明記する。
- 下位 I/O と core の責務を説明する設計例があり、ライブラリの純粋部分からファイル・ネットワーク・DOM を参照しないことをレビューできる。
- 外部 fixture・コードのライセンス／帰属が確認され、未確認素材を同梱しない。
- `docs/upstream.md` と `docs/scope.md` に v0.1/v0.2 以降の境界があり、M1 で未対応の機能が supported と誤表記されない。

## 対象外

- libwebrtc、H.264/H.265/AV1 エンコーダーやデコーダー本体、C ABI 完全互換、リアルタイム再生は core の対象外とする。
- Rust 実装をラップするだけの FFI を『MoonBit port』と称さない。
- 個別 API の実装（[0005](./0005-safe-bytes.md) 以降）と Rust oracle の構築（[0004](./0004-oracle-fixtures.md)）は本 Issue では扱わない。本 Issue は対象・責務・ライセンスの文書化に限定する。

## 提案する方針

- `docs/upstream.md` に上流の固定コミット、ライセンス、参照 API 一覧、対応 RFC/ISO 規格、上流参照 URL を記録する。上流との差分は commit SHA 更新時に評価し、暗黙の latest 追従を禁止する（追従の監査は [0034](./0034-upstream-drift.md)）。
- `docs/scope.md` に `wire`／`semantic`／`surface` の 3 層定義を書く。M1 では `semantic` 一致を基本とし、厳密なバイト一致は該当箇所だけ明示する。
- 依存方向を文書化する。非 I/O の MP4 core（提案: `src/bytes`・`src/box`・`src/boxes`・`src/demux`・`src/mux`・`src/bitstream`。確定は [0002](./0002-moonbit-bootstrap.md)）と `native file`／`browser File` アダプタを分離し、core からファイル・ネットワーク・DOM を参照しない。
- ライセンス表記、著作権告知、上流由来 fixture の配布可否と帰属を確認し、文書へ記録する。README には原著作者と独立移植である旨を明示する。
- 仕様範囲表に `Mp4FileKindDetector`、3 種類の demuxer、2 種類の muxer、Box/codec string、bitstream helper、C/WASM の対応可否を列挙する。
- 上流 fixture の個別ファイル名・配布条件は実装（[0004](./0004-oracle-fixtures.md)）時に確定し、確認結果を本 Issue の文書へ反映する。文書の章立て・ファイル形式は実装時に確定する。

## 受け入れ条件

- [ ] Given 上流固定コミット, when `docs/upstream.md` を参照する, then 固定 SHA・ライセンス・参照 API・対応規格の一覧が追跡できる。
- [ ] Given `wire`／`semantic`／`surface` の 3 層定義, when 後続 Issue の『一致』主張を確認する, then どの層の一致かを分類できる。
- [ ] Given 下位 I/O と core の分離, when `docs/scope.md` の設計例をレビューする, then 純粋部分がファイル・ネットワーク・DOM を参照しないことを説明できる。
- [ ] Given 外部 fixture やコード, when 同梱可否を確認する, then ライセンス／帰属が確認済みの素材だけが同梱され、未確認素材は含まれない。
- [ ] Given `docs/upstream.md` と `docs/scope.md`, when 独立レビューする, then 上流参照と法的表示の欠落がない。
- [ ] Given M1 の仕様範囲表, when 未対応機能の記述を確認する, then supported と誤表記されていない。
- [ ] Given 上流 SHA の更新, when 差分評価の手順を確認する, then 暗黙の latest 追従が残っていない。

## テスト計画

- 文書 Issue のため自動テストはない。作成した文書のレビューと参照確認で検証し、実施した確認と未実施の確認を区別して記録する。
- `docs/upstream.md` の URL・SHA が解決すること、`docs/scope.md` の範囲表と 3 層定義が後続 Issue と整合することを手動確認する（文書は未作成のため、現時点では未実行）。
- ライセンス確認は上流のライセンス表示・帰属・fixture の出所を一次情報で行う。確認できない素材は「未確認」のままにし、PASS と集計しない。
- このリポジトリにはまだ `moon.mod` がなく、`moon check`／`moon test --target native`／`moon test --target js` は実行できない（未実行と記録する）。本 Issue の完了判定をコマンドの合否と混同しない。
- 証跡として、確認した URL・commit SHA・確認日を Issue または PR に残す（[0000](./0000-implementation-roadmap.md) §8.1 の規則: checkbox は実際に実行した証拠がある項目だけ完了にする）。

## リスク

- ライセンス確認不足: 上流由来素材の配布条件を誤ると再配布できない。確認前にコピーせず、未確認素材は同梱しない。
- スコープ膨張: コーデック本体・libwebrtc・リアルタイム再生まで対象が広がる。3 層定義と範囲表で境界を固定する。
- 誤表記: 境界が曖昧なまま README で対応をうたうと supported 誤表記になる。範囲表と README の突き合わせをレビューで行う。
- 上流追従の混入: latest 参照が混ざると [0004](./0004-oracle-fixtures.md) の oracle が非再現になる。参照は固定 SHA に限定する。
- ロールバック: 変更は Markdown のみで、問題時は該当コミットの revert で戻せる。後続への影響は [0002](./0002-moonbit-bootstrap.md) と [0004](./0004-oracle-fixtures.md) が参照する前提文書に限られる。

## 変更履歴

`CHANGES.md` impact: no

判断理由: 対象・責務・ライセンスの文書化と README の帰属表示が中心で、利用者に見える API・挙動を変えない。

## 注記

- 上流参照: [README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.md)、[AGENTS.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/AGENTS.md)、[src/lib.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/lib.rs)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)（すべて固定 SHA）。
- 関連: [0000](./0000-implementation-roadmap.md)（全体計画）、[0002](./0002-moonbit-bootstrap.md)（モジュール骨格）、[0004](./0004-oracle-fixtures.md)（fixture の帰属）、[0033](./0033-release-docs.md)（公開文書）、[0034](./0034-upstream-drift.md)（上流追従監査）。
- 未決事項: `docs/upstream.md`／`docs/scope.md` の章立て、上流 fixture の個別ファイルと配布可否は実装時に確定し、確定内容を本 Issue へ追記する。
- 証跡ルール: ライセンス・帰属の確認記録（URL・SHA・確認日）を残し、未確認を PASS と混同しない。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
