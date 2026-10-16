# [P0 / M0] 継続的チェック・変更管理の品質ゲートを作る

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: chore/0003-ci-contract
Priority: P0
Milestone: M0
Depends on: [0002](./0002-moonbit-bootstrap.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

後続 30 件の Issue を安全に進めるため、MoonBit の品質ゲート（`moon check`／`moon test`／`moon fmt` の差分チェック／`moon info` 公開 API 差分）と、Rust oracle との差分報告の置き場所を先に整備する。CI を green にするためのテスト無効化、固定値 assert、未検証結果の PASS 表示は行わない。本 Issue は計画段階であり、未実装・未テストである。

## 背景

- 2026-10-16 時点では CI が存在せず、[0002](./0002-moonbit-bootstrap.md) で追加するモジュールの品質を継続的に確認する手段がない。[0000](./0000-implementation-roadmap.md) はマージの標準条件を「CI Green かつ独立レビュー Approve 相当／P1 なし」とし、評価対象 commit を明示することを求めている。
- 上流参照（固定 SHA）: [.github/workflows/ci.yml](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/.github/workflows/ci.yml)、[Cargo.toml](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/Cargo.toml)。
- Rust oracle 本体（固定 SHA・cargo toolchain・検証用スクリプト）は [0004](./0004-oracle-fixtures.md) が構築し、本 Issue はその実行を CI に載せる側を担う。
- [0000](./0000-implementation-roadmap.md) §4 は検証状態を PASS／FAIL／UNVERIFIED／NOT_RUN と分けて記録し、実行コマンド・commit SHA・OS/arch・fixture checksum・日時を結果に含める方針を示している。

## 問題

- 品質ゲートがないまま後続 Issue が増えると、target 不足・整形差分・公開 API の意図しない追加がマージまで検出されない。
- Rust oracle が latest を参照したり、上流 testdata や Rust build を毎ジョブ無制限に clone すると、CI が非再現・長時間化する。
- target 未対応などの SKIP を PASS と同じ表示で集計すると、未検証が成功として扱われる。
- GitHub Pages へ `main` の全内容をコピーする手順は、公開範囲の制御にならない。
- レビュー時に再現コマンドがなく、どの commit を評価したか特定できない。

## 目標

- CI で `moon check`／`moon test`／`moon fmt` の差分チェック／`moon info` 公開 API 差分を実行し、実際に対応する Native／JS を matrix 化する。
- Rust oracle を固定 SHA・cargo toolchain・検証用スクリプトで再現可能にし、毎ジョブの無制限 clone をしない。
- unit・fixture・golden・E2E・fuzz・performance を分離し、各 PR で必要な最小チェックを定義する。
- GitHub Pages は CI green の成果物だけを別 workflow で公開し、出力ディレクトリを限定する。
- 必須チェックは実施したコマンド／target／commit SHA／PASS・FAIL・SKIP を識別できる。
- 独立レビューは Approve 相当・P1 なしをマージ判定に使える。

## 対象外

- CI を green にするためのテスト無効化、固定値 assert、未検証結果の PASS 表示をしない。
- 機能テストの中身（box 解析・demux 等）と用例は各 Issue（[0005](./0005-safe-bytes.md) 以降）が追加する。本 Issue はジョブ構成と判定規則を用意する。
- Rust oracle 本体・fixture の内容・golden schema は [0004](./0004-oracle-fixtures.md) の範囲とする。
- Pages のデモ実装そのものは [0015](./0015-web-mp4-dump.md) の範囲とする。

## 提案する方針

- `.github/workflows/` に CI workflow を追加し、`moon check`／`moon test`／`moon fmt` の差分チェック／`moon info` 公開 API 差分をジョブ化する。target は実際に対応する Native／JS で matrix 化し、[0002](./0002-moonbit-bootstrap.md) が確定する package 構成を入力にする。ジョブ名・workflow ファイル名は実装時に確定する。
- Rust oracle のジョブは固定 SHA（`1282b704f44184ec792e1549b5d31e0c4c54dc59`）、cargo toolchain、検証用スクリプトを明示し、上流 testdata や Rust build を毎ジョブ無制限に clone しない（キャッシュまたは限定 checkout を使う）。
- unit・fixture・golden・E2E・fuzz・performance を分離したジョブとして定義し、各 PR が必要とする最小チェックを選択できるようにする。大きな E2E も失敗を隠さず報告できるようにする。
- GitHub Pages は `main` の全内容をコピーせず、CI green の成果物を別 workflow で公開し、出力ディレクトリを限定する。
- 必須チェックの集計は、実施したコマンド／target／commit SHA／PASS・FAIL・SKIP を識別する形にし、SKIP を PASS に含めない。マージ判定は独立レビュー Approve 相当・P1 なしを条件にする。
- 再現コマンド（依存の導入、チェック実行、oracle 実行）をドキュメント化し、レビュー担当が同じ手順を実行できるようにする。成果物（ログ・レポート）の保存先は [0016](./0016-rust-moonbit-diff.md) の差分レポートと整合させる。
- 必須チェックの一覧・branch protection の設定は実装時に確定し、確定内容を本 Issue へ追記する。

## 受け入れ条件

- [ ] Given 意図的に構文エラーを注入した変更, when CI を実行する, then `moon check` のジョブが FAIL する。
- [ ] Given fixture の期待値を改変した変更, when golden 比較ジョブが完成している, then そのジョブが FAIL する。
- [ ] Given target 未対応による SKIP, when CI の結果を集計する, then SKIP は PASS として集計されず、別状態で表示される。
- [ ] Given core のテスト失敗, when Pages deploy workflow の起動条件を評価する, then deploy は実行されない。
- [ ] Given レビュー依頼, when ドキュメント化された再現コマンドを実行する, then 実施したコマンド／target／commit SHA を特定できる。
- [ ] Given 固定 SHA の Rust oracle, when 検証用スクリプトを実行する, then toolchain と手順が記録され、同じ結果を再現できる。
- [ ] Given CI の実行ログ, when target 別の結果を確認する, then target ごとに PASS／FAIL／SKIP が識別できる。

## テスト計画

- CI 設定自体を故障注入で検証する。いずれも現時点では workflow が未作成のため未実行であり、実施時に結果を記録する。
  - 構文エラーを注入した PR で `moon check` ジョブが赤くなること（[0002](./0002-moonbit-bootstrap.md) の完了後に実施可能）。
  - fixture 期待値の改変で golden 比較ジョブが赤くなること（ジョブ完成時に実施）。
  - target 未対応の SKIP が PASS として集計されないこと（ジョブ完成時に実施）。
- ローカルで `moon check`／`moon test`／`moon info`／`moon fmt` を実行し、CI と同一のコマンド・target になることを確認する（`moon.mod` がないため現時点では未実行）。
- Rust oracle ジョブは実装後に 2 回実行し、同一 commit・同一 fixture で結果が一致することを確認する（未実施）。
- 検証状態は PASS／FAIL／SKIP（未実行）を混同せず記録し、実行できなかった項目は「未実行」と明記する（[0000](./0000-implementation-roadmap.md) §4・§8.1）。
- 証跡として CI 実行ログへのリンク、実行日時、commit SHA、target 名を PR に残す。

## リスク

- CI green を優先して検査を弱める誘因: テスト無効化・固定値 assert を禁止し、レビューで差分を確認する。
- oracle の非再現: latest 追従や無制限 clone を避け、固定 SHA と限定的な checkout を使う。上流差分の監査は [0034](./0034-upstream-drift.md) に接続する。
- SKIP の PASS 混入: 集計表示で状態を分離し、対象 target ごとの実行有無を明示する。
- Pages の公開範囲: 出力ディレクトリを限定し、`main` 全内容のコピー手順を使わない。core テスト失敗時は deploy しない。
- 移行時の混乱: 必須チェックの名前・対象 target が変わるとブランチ保護の設定がずれる。初回設定時に一覧を文書化する。
- ロールバック: workflow と設定の追加が中心で、問題時は該当コミットの revert で戻せる。

## 変更履歴

`CHANGES.md` impact: no

判断理由: CI と運用の整備が中心で、利用者に見える API・挙動を変えない。

## 注記

- 上流参照: [.github/workflows/ci.yml](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/.github/workflows/ci.yml)、[Cargo.toml](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/Cargo.toml)（固定 SHA）。
- 関連: [0002](./0002-moonbit-bootstrap.md)（matrix の入力）、[0004](./0004-oracle-fixtures.md)（oracle ジョブ）、[0015](./0015-web-mp4-dump.md)（Pages 対象）、[0016](./0016-rust-moonbit-diff.md)（差分レポートの artifact 化）、[0031](./0031-fuzz-pbt-hardening.md)（fuzz ジョブ）、[0034](./0034-upstream-drift.md)（上流追従監査）。
- 未決事項: ジョブ名、matrix の最終形、required checks と branch protection の一覧は実装時に確定し、確定内容を本 Issue へ追記する。
- 証跡ルール: PASS／FAIL／SKIP（未実行）を混同せず、実行ログ・commit SHA・target・日時を残す（[0000](./0000-implementation-roadmap.md) §8.1）。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
