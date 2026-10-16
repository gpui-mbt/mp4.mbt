# [P1 / M5] README・API・example・配布とversionを整備する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: docs/0033-release-docs
Priority: P1
Milestone: M5
Depends on: [0003](./0003-ci-contract.md), [0013](./0013-mp4-file-demux.md), [0014](./0014-demux-example.md), [0015](./0015-web-mp4-dump.md), [0016](./0016-rust-moonbit-diff.md), [0031](./0031-fuzz-pbt-hardening.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

使う人がdemoからAPI、テスト、制限、移植元まで到達できるようにし、達成済み機能だけを段階的に配布する。README、API example、互換性matrix、release checklist、version/タグとgit SHAの対応を整備し、`moon publish`可能な体裁にする。実際のpublishは別途明示承認があるまで行わない。

## 背景

- 上流の参照元は [README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.md)、[README.en.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.en.md)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)、[AGENTS.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/AGENTS.md) である。
- [0000](./0000-implementation-roadmap.md) のM5 gateは「対象targetのE2E成功、未検証項目はPartial/Unverifiedと表示」である。§8はPRに上流SHA、予定/実装API差分、コマンド＋結果、fixture/CI link、既知limitationsを載せることと、M1 gate後に読取版をalpha相当とすることを定める。
- 記載対象は [0013](./0013-mp4-file-demux.md)（demux）、[0014](./0014-demux-example.md)（Native CLI）、[0015](./0015-web-mp4-dump.md)（ブラウザDump）、[0016](./0016-rust-moonbit-diff.md)（Rust比較）の成果である。証跡の前提は [0003](./0003-ci-contract.md) の品質ゲートと [0031](./0031-fuzz-pbt-hardening.md) の残余リスク記載とする。
- 2026-10-16時点のリポジトリはREADME.md（2行）のみで `moon.mod` も実装コードもない。本issueは未実装・未テストの計画である。

## 問題

- 公開ドキュメント・install手順・API example・version/タグ対応が未整備で、demoと移植元（上流の位置付け）の間が遠い。
- 対応表がないと未実装機能を実装済みと誤読させる。C API/WASM APIの完全互換と誤認させるおそれがある。
- リリース基準（M1読取版alpha / M2 fMP4 / M3通常mux / M4 codec拡張）が分けて記録されていない。
- mooncakesで利用できる公開モジュール名・version・ライセンスの体裁が未整備である。
- docsのsample outputと実結果、タグversionとsource SHAの一致を検証する手順がない。

## 目標

- README.mbt.mdと短いREADME.mdへ、対応表、現在のphase、install、Native CLI、ブラウザDemo、Rust比較結果を記載する。
- mooncakesで利用できる公開モジュール名、version、ライセンス、リリースタグとgit SHAの対応を整備し、`moon publish`可能な体裁にする。実際のpublishは別途明示承認があるまでしない。
- 対応表は`Implemented / Partial / Not started / Blocked`と`verified targets`を分離する。C API/WASM APIの完全互換は約束しない。
- API exampleは実行可能コードを載せ、`moon check/test/fmt/info`の成功証跡とRust oracle SHAをrelease checklistに追加する。
- M1読取版をalphaとして、M2 fMP4、M3通常mux、M4 codec拡張のリリース基準を分けて記録する。
- 適正なライセンス・上流クレジット・fixture帰属を行い、publish可否と実施状況を明示する。

## 対象外

- この計画へのcommitではタグ作成・mooncakes公開・GitHub Releaseは行わない。
- C API/WASM APIの完全互換は約束しない（対応表でPartial / Not started / Blockedを分離するに留める）。
- Rust比較・性能数値の再計測は [0016](./0016-rust-moonbit-diff.md) / [0032](./0032-performance-profile.md) の範囲とし、本issueは証跡の引用と掲載のみを行う。
- 文書はREADME 2種・release checklist・互換性matrixを中心とし、それを超える大規模なチュートリアル体系は後続とする。

## 提案する方針

- 文書セット: README.mbt.md と短い README.md、release checklist、互換性matrixを作る。現状はREADME.mdのみのため、ファイル名と分割は実装時に確定する。
- 対応表: `Implemented / Partial / Not started / Blocked` と `verified targets` を分離した表にし、各行を機能Issueと検証状態（0000 §8のPASS / FAIL / UNVERIFIED / NOT_RUN）へリンクする。
- install: クリーンなNative/JS環境を前提にした手順を書く。mooncakes利用時の公開モジュール名、version、ライセンスを明記する。
- version/タグ: リリースタグとgit SHAの対応表を作り、タグのversionとsource SHAが一致することを検証手順に含める。`moon publish`可能な体裁は整えるが、publish・タグ作成・GitHub Releaseは別途明示承認があるまで行わない。
- example: API exampleは実行可能コードのみを載せ、未対応APIを利用する例を実行可能と書かない。`moon check/test/fmt/info`の成功証跡とRust oracle SHAをrelease checklistに追加する。
- リリース基準: M1読取版alpha、M2 fMP4、M3通常mux、M4 codec拡張を分けて記録し、未検証項目はPartial/Unverifiedと表示する（[0000](./0000-implementation-roadmap.md) のM5 gate）。
- 互換性要件: Rust/WASM比較は [0016](./0016-rust-moonbit-diff.md) の差分レポート、性能数値は [0032](./0032-performance-profile.md) の計測結果、fuzz残余リスクは [0031](./0031-fuzz-pbt-hardening.md) のREADME記載を引用元とし、独自数値を作らない。
- 権利: ライセンス表記・上流クレジット・fixture帰属は0001/0004の確認結果に従う。確認できない素材をREADMEへ載せない。
- 境界条件: docsのsample outputは実行ログから転記し、実結果と異なる場合はdocsを修正する（実結果をdocsに合わせない）。

## 受け入れ条件

- [ ] Given クリーンなNative/JS環境, when READMEのコマンドを順番に実行する, then 記載どおりに成功する（未対応targetは未対応と明記されている）。
- [ ] Given 未対応API, when exampleへ掲載する, then 実行可能と誤記されず、Partial / Not started / Blockedのいずれかに分類されている。
- [ ] Given docsのsample output, when 実結果と比較する, then 一致する。
- [ ] Given リリースタグ, when versionとsource SHAの対応を確認する, then 一致する。
- [ ] リリース文書と互換性matrixが作成され、verified targetsと未検証状態（UNVERIFIED / NOT_RUN）が区別されている。
- [ ] ライセンス・上流クレジット・fixture帰属が適正である。
- [ ] publish可否と実施状況（未実施を含む）が明示されている。
- [ ] release checklistに `moon check/test/fmt/info` の成功証跡とRust oracle SHAの記録項目がある。

## テスト計画

- 現時点: README以外の実装がなく `moon.mod` もないため、READMEに載せる実行例は未検証であり、本issueの検証はすべて未実行である。実装後にクリーン環境で順に実行して記録する。
- 実行予定コマンド: `moon check`、`moon test --target native`、`moon test --target js`、`moon fmt`（差分なしの確認）、`moon info`（公開API差分）。結果にはcommit SHA・OS/arch・日時を付す。
- docs突合: sample outputは実行ログから転記する。手書きの期待値を載せない。
- タグ検証: タグとSHAの対応確認をchecklist化する。タグ作成・publishは明示承認後にのみ実施する。
- example検査: 例のコンパイル・実行可否で対応表との矛盾を検査する。実行していない例は「未検証」と表示し、PASSと混同しない。
- 集計規則: PASS / FAIL / 未実行（NOT_RUN / UNVERIFIED）を分けて記録する（[0000](./0000-implementation-roadmap.md) §8・[0003](./0003-ci-contract.md)）。
- 手動確認: 対応表の各行に機能Issueと検証状態のリンクがあること、release checklistの全項目が埋まっていることをレビューで確認する。

## リスク

- 誇大表示: 未実装機能やC ABI互換の誤表記は、対応表のPartial / Not started / Blocked分離とレビューで防ぐ（[0000](./0000-implementation-roadmap.md) リスク表の「リリース誇大表示」）。
- 出所不明の数値・比較: [0016](./0016-rust-moonbit-diff.md) / [0032](./0032-performance-profile.md) の証跡がない数値を掲載しない。
- ライセンス・帰属漏れ: 0001/0004の確認なしにコード・fixtureを転載しない。
- version/タグ不一致: checklistで機械的に照合する。不一致時は記録を止め、タグやversionの解釈をその場で変えない。
- ロールバック: 文書変更はrevert可能。タグ・publishは明示承認制のため、手続きで誤公開を防ぐ。
- データ形式: 対応表・checklistは更新漏れを検出できる表形式にし、項目の追加・変更をreviewableにする（具体形式は実装時に確定）。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] README・互換性matrix・API example・release checklist（version/タグとgit SHAの対応含む）を整備

## 注記

- 関連: [0001](./0001-scope-upstream-license.md)（対象・ライセンス）、[0003](./0003-ci-contract.md)（証跡と必須チェック）、[0004](./0004-oracle-fixtures.md)（fixture帰属）、[0013](./0013-mp4-file-demux.md) / [0014](./0014-demux-example.md) / [0015](./0015-web-mp4-dump.md)（記載対象）、[0016](./0016-rust-moonbit-diff.md)（比較結果）、[0029](./0029-webcodecs-transcode.md)（デモの制約表示）、[0031](./0031-fuzz-pbt-hardening.md)（残余リスク）、[0032](./0032-performance-profile.md)（性能数値）、[0034](./0034-upstream-drift.md)（固定参照の表示）。
- 上流参照: [README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.md)、[README.en.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.en.md)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)、[AGENTS.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/AGENTS.md) を文書構成の参照元にする。
- 運用: publish・タグ作成・GitHub Releaseは別途の明示承認があるまで実施しない。`moon publish`可能な体裁の整備までで止める。
- 未決事項: 公開モジュール名、version規則、README.mbt.mdの分割、checklistの保存場所は実装時に確定し、本issueへ追記する。
- 証跡: `moon check/test/fmt/info`の実行ログ、Rust oracle SHA、sample outputの突合結果をrelease checklistに残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
