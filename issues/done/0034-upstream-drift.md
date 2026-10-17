# [P2 / M5] 上流追従と互換性監査を継続可能にする

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: docs/0034-upstream-drift
Priority: P2
Milestone: M5
Depends on: [0004](./0004-oracle-fixtures.md), [0016](./0016-rust-moonbit-diff.md), [0022](./0022-mp4-file-mux.md), [0033](./0033-release-docs.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

固定SHAの上流から将来のdevelopへ更新するとき、API互換・意味互換・規格変更を混同せず段階的に判断できる運用を作る。baseline更新PRごとに`source diff`と`contract delta`を生成し、旧baseline / 新baseline / MoonBit candidateの三者比較、goldenのレビュー承認更新、リリースmatrixへの固定参照表示を手順化する。

## 背景

- 上流の参照元は [CHANGES.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/CHANGES.md)、[src/demux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file.rs)、[src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs) である。
- [0000](./0000-implementation-roadmap.md) のリスク表は「oracle再現性」として「Rustの新HEADとの差分をcandidateバグと誤判定」を挙げ、対処Issueに [0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md) / 本issueを指定している。
- 前提: [0004](./0004-oracle-fixtures.md) のgolden・manifest、[0016](./0016-rust-moonbit-diff.md) の差分lab、[0022](./0022-mp4-file-mux.md) 等の実装、[0033](./0033-release-docs.md) のリリースmatrixが揃っていることを前提とする。
- 2026-10-16時点で `moon.mod` も実装コードもなく、baselineは上記SHAのままである。本issueは未実装・未テストの計画である。

## 問題

- baseline SHA更新時に何を比較し、どこへ記録し、誰が承認するかの手順が未定義である。
- 上流の仕様変更による差分とMoonBitの未実装・候補バグを分けるラベルがない。
- goldenの自動上書きの危険がある（変更が「一致」に見える）。
- upstream SHAが進んでも既存のMoonBit実装が自動的に互換と宣言され得る。
- Rust oracleが取得できない場合の記録方法が決まっていない。

## 目標

- baseline更新PRごとに`CHANGES.md`・API一覧・対象filesを比較し、`source diff`と`contract delta`を生成する。
- 新たなRust oracle outputを生成して旧baseline / new baseline / MoonBit candidateの三者を比較し、上流の仕様変更による差分とMoonBitの未実装を別ラベルにする。
- codec追加や規格改定、box構造追加などを機能Issueに分解し、既存の対応範囲を明示し続ける。
- goldenは自動上書きせずレビュー承認でbaselineを更新し、元fixture/hashと変更理由を残す。
- upstream SHAが進んでも既存実装が自動的に互換と宣言されないよう、リリースmatrixに固定参照を表示する。
- 追従時に対象Issue・テスト・実行結果をリンク可能にする。

## 対象外

- 上流の更新を無確認で直接取り込む自動マージはしない。
- 新機能の実装・codec追加そのものは各機能Issueで扱い、本issueは差分の検出・記録・承認の運用に限定する。
- 上流の開発速度に合わせた追従期限は設けない（目的は監査可能性の維持である）。
- fixtureの新規取得・ライセンス確認そのものは [0001](./0001-scope-upstream-license.md) / [0004](./0004-oracle-fixtures.md) の範囲とする。

## 提案する方針

- 手順: baseline SHA更新PRテンプレートに、比較対象（`CHANGES.md`・API一覧・対象files）、生成物（`source diff`・`contract delta`）、三者比較レポート、fixture/hashと変更理由、レビュー承認、リリースmatrix更新を項目として含める。テンプレートの配置とフォーマットは実装時に確定する。
- 定義: `source diff`は上流ソースの変更点、`contract delta`は公開API・意味論の差分を指す作業定義とする。具体的な出力形式は [0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md) のschemaと整合させ、実装時に確定する。
- ラベル: 「上流仕様変更」「MoonBit未実装」「候補バグ」「Unverified（oracle不能）」を分離し、[0016](./0016-rust-moonbit-diff.md) のPass / Fail / Unverified区分と揃える。
- golden更新: 自動上書きを禁止し、元fixture/hash・変更理由・oracle run IDを記録した上でレビュー承認により更新する。新baselineは旧baselineとの差分レポートとともに保存する。
- 分解: codec追加、規格改定、box構造追加などは機能Issueへ分解し、既存の対応範囲と未対応範囲を常に明示する。
- 互換性要件: upstream SHAの前進と「互換宣言」を切り離す。リリースmatrix（[0033](./0033-release-docs.md)）は固定参照SHAを表示し、更新は本issueの手順を経たものだけとする。
- 境界条件: Rust oracleが取得できない場合はUnverifiedとして記録し、一致と扱わない。fixtureライセンスが未確認の素材は監査対象に含めない（0001/0004）。

## 受け入れ条件

- [ ] Given 上流APIに仮の追加を入れた監査リハーサル, when 差分監査を実行する, then 新旧の差分が正しく検出される。
- [ ] Given 候補版, when 旧goldenと新goldenで比較する, then 旧goldenにはPASS、新goldenにはFAILという区別が示される。
- [ ] Given Rust oracleが取得できない検証, when 結果を記録する, then Unverifiedとして記録され、一致と扱われない。
- [ ] Given baseline更新PR, when テンプレートに沿って提出する, then source diff・contract delta・fixture/hash・変更理由が記録されている。
- [ ] Given goldenの変更提案, when レビューする, then 自動上書きではなく承認の記録がある。
- [ ] Given upstream SHAが進んだ状態, when リリースmatrixを確認する, then 固定参照が表示され、既存実装が自動的に互換と宣言されていない。
- [ ] 追従時に対象Issue・テスト・実行結果をリンクできる。

## テスト計画

- 現時点: `moon.mod` も実装もなく、[0004](./0004-oracle-fixtures.md) のgolden再生成手順と [0016](./0016-rust-moonbit-diff.md) の差分labも未実装のため、監査リハーサルは実行不可である（NOT_RUNと記録する）。
- 0004 / 0016の完了後、上流APIへの仮の追加を含む監査リハーサルを実施し、旧/新goldenのPASS/FAILの区別とUnverifiedの記録を確認する。
- レビュー手順として、goldenの自動上書きがないこと・承認が記録されていることを確認する。
- 記録項目: upstream SHA、oracle run ID、対象fixture hash、実行コマンド、結果（PASS / FAIL / UNVERIFIED / NOT_RUN）を残す。
- 手動確認: baseline更新PRテンプレートの各項目が埋まっていること、リリースmatrixに固定参照が表示されていることを確認する。
- 実行できない検証を「一致」やPASSとして扱わない（[0000](./0000-implementation-roadmap.md) §8）。

## リスク

- 上流仕様変更をMoonBitのバグと誤判定: 旧/新baselineとcandidateの三者比較とラベル分離で防ぐ（[0000](./0000-implementation-roadmap.md) の「oracle再現性」への対処）。
- goldenの暗黙変更: 自動上書き禁止と承認記録で防ぐ。
- 比較漏れ: `CHANGES.md`・API一覧・対象filesのチェックリスト化で防ぐ。
- 運用の形骸化: 追従PRの受入条件にリンク（対象Issue・テスト・実行結果）を要求し、空欄のままのbaseline更新を認めない。
- ライセンス: 確認できないfixture・素材は監査に含めない（[0001](./0001-scope-upstream-license.md) / [0004](./0004-oracle-fixtures.md)）。
- データ形式: source diff・contract delta・goldenは0004/0016のschemaと比較規則（64bit値の文字列化等）を再利用し、独自形式を作らない。形式変更は両issueと同時に更新する。
- ロールバック: 運用文書とテンプレートの変更はrevert可能。golden更新を伴う場合はfixture/hashと承認記録から旧baselineへ戻せるようにする。

## 変更履歴

`CHANGES.md` impact: no

## 注記

- 関連: [0004](./0004-oracle-fixtures.md)（golden/manifest）、[0016](./0016-rust-moonbit-diff.md)（差分lab）、[0022](./0022-mp4-file-mux.md)（対象実装の一例）、[0033](./0033-release-docs.md)（リリースmatrixへの固定参照表示）、[0000](./0000-implementation-roadmap.md)（リスク表と検証状態の規則）、[0001](./0001-scope-upstream-license.md)（対象範囲・ライセンス）。
- 上流参照: [CHANGES.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/CHANGES.md)、[src/demux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file.rs)、[src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs) を差分監査の対象例とする。
- 運用: baselineの更新はレビュー承認経由のみとし、上流の更新を無確認で自動マージしない。
- 未決事項: source diff / contract deltaの出力形式、PRテンプレートの配置（リポジトリ内ファイル）、監査リハーサルの実施手順は実装時に確定し、本issueへ追記する。
- 証跡: upstream SHA、oracle run ID、fixture hash、実行コマンド、差分ラベル、承認記録をartifactとして残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。

## 検証

- `tools/upstream-drift/audit.py` と `docs/upstream-drift.md`、PR テンプレートを追加。
- 監査リハーサルは未実行（NOT_RUN）。golden の自動上書きは行わない。
