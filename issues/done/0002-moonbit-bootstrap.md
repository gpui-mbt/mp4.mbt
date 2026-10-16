# [P0 / M0] MoonBitモジュール・公開APIとターゲット基盤を作る

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0002-moonbit-bootstrap
Priority: P0
Milestone: M0
Depends on: [0001](./0001-scope-upstream-license.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

初期 commit は README のみであるため、ライブラリとしてビルド・テスト可能な骨格（`moon.mod` と package directory 単位の `moon.pkg`）と、後続 Issue が並行実装できるパッケージ境界を用意する。空スタブや偽実装は置かず、core の空でない最小機能を Native と JS の両 target で動かすところまでを本 Issue の範囲とする。本 Issue は計画段階であり、未実装・未テストである。

## 背景

- 2026-10-16 時点の `main` は README のみで `moon.mod` がない（[0000](./0000-implementation-roadmap.md)）。そのため `moon check`／`moon test` を実行できず、後続 Issue（[0004](./0004-oracle-fixtures.md) 以降）の検証も開始できない。
- [0000](./0000-implementation-roadmap.md) は提案アーキテクチャとして `src/bytes`・`src/box`・`src/boxes`・`src/bitstream`・`src/demux`・`src/mux`、`examples/demux`、`examples/fmp4`、`web/`、`native/`、`tools/oracle`、`tests/fixtures` を挙げ、実際の `moon.pkg` 分割は循環依存・target 制約を検証した上で確定するとしており、その確定を本 Issue が担う。
- 上流参照（固定 SHA）: [src/lib.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/lib.rs)、[src/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux.rs)、[src/mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux.rs)、[src/codec.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs)。公開 API 名は上流の型に対応付けた命名表で統一する。
- [0001](./0001-scope-upstream-license.md) の `wire`／`semantic`／`surface` の 3 層と、core／I/O アダプタ分離の方針を、module／package 構成として最初に反映する。

## 問題

- モジュールも package もないため、ビルド・テスト・公開 API 差分（`.mbti`）のどの検証も開始できない。
- 依存方向を先に決めないと、後続 Issue が追加するファイルで循環参照や target 非対応 import が後から見つかる。
- 公開 API の命名表がないと、上流と対応しない名前が `surface`（公開関数）に固定される。
- README に成功実績のないコマンドを書くと、実行できない手順が配布物として固定される。

## 目標

- クリーン環境で `moon check`／`moon test`／`moon info`／`moon fmt` を実行でき、moon のバージョンと成否を記録できる。
- JS と Native の各 target が共通の pure package を import できる。
- core の空でない最小機能（例: FourCC 値とテスト）が 2 target で実行できる。
- 生成した `.mbti` に予定外の公開関数が含まれず、公開 API レビューの入力になる。
- 依存グラフとバージョン固定が記録され、README には実際に成功したコマンドだけが記載される。

## 対象外

- 起動だけ成功するダミー demuxer／muxer は追加しない。
- 実機能（box 解析・demux・mux・bitstream helper）は [0005](./0005-safe-bytes.md) 以降の各 Issue で実装する。本 Issue は骨格と最小の core のみを扱う。
- 配布（パッケージ公開・リリース文書）は [0033](./0033-release-docs.md) で扱う。
- WASM/WASM-GC はツールチェーンで可能性を検証してから CI へ追加する。本 Issue の最低限の target は Native と JS とする。

## 提案する方針

- `moon.mod` の name を `gpui-mbt/mp4` 相当に設定する（実際の mooncakes 名前空間と衝突を確認する）。package directory 単位に `moon.pkg` を置き、`codec`・`boxes`・`demux`・`mux`・`bitstream` の依存方向を明示する。
- `src/bytes`・`src/box`・`src/boxes`・`src/demux`・`src/mux`・`src/bitstream` を候補に、循環参照のない依存グラフを実装する。採用する package 名・ファイル名は実装時に確定し、確定内容を本 Issue へ追記する。
- 公開 API 名は上流の型に対応付けた命名表で統一し、[0001](./0001-scope-upstream-license.md) の `surface` 定義と整合させる。
- core は OS/Node/DOM を必要としない。Native と JS を最低限の target とし、CI へ載せる matrix は [0003](./0003-ci-contract.md) と一致させる。
- API ドキュメントの各例は `moon.pkg` の実パッケージ名を使い、未実装 API の空スタブや偽実装を公開しない。
- `.gitignore`、`LICENSE`、`README.mbt.md`、`CHANGES.md` と最低限のテストを追加する。`moon info` で生成した `.mbti` 差分を公開 API レビューの入力にする。
- 最初の公開 API（例: FourCC 値）の具体名と配置は実装時に確定する。上流 [src/codec.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs) 等の型との対応を命名表に記録する。

## 受け入れ条件

- [ ] Given クリーン環境, when `moon check` を実行する, then Native と JS の各 target で成功し、バージョンと成否が記録される。
- [ ] Given クリーン環境, when `moon test --target native` と `moon test --target js` を実行する, then core の最小機能（例: FourCC 値とテスト）が両 target で PASS する。
- [ ] Given JS と Native の各 target, when 共通 pure package を import する, then OS/Node/DOM 非依存の package が読み込める。
- [ ] Given `moon info` の生成物, when `.mbti` 差分をレビューする, then 予定外の公開関数が含まれない。
- [ ] Given 依存グラフ, when package 間の import を確認する, then 循環参照がなく、記録した依存方向と一致する。
- [ ] Given README, when 記載コマンドを確認する, then 実際に成功したコマンドだけが記載されている。

## テスト計画

- クリーン環境で `moon check`、`moon test`、`moon info`、`moon fmt` を実行し、バージョンと成否を記録する。現時点では `moon.mod` がないため未実行であり、本 Issue で実行可能にする。
- target 別に `moon test --target native` と `moon test --target js` を実行し、PASS／FAIL／未実行を区別して記録する。
- wbtest として core 最小機能（例: FourCC 値）の正常系・境界値を固定する。テストのファイル名・関数名は実装時に確定する。
- `.mbti` 差分のレビュー手順を記録し、公開 API の追加・削除・改名が意図どおりかを確認する。
- `moon fmt` による差分チェックが [0003](./0003-ci-contract.md) の CI と同一のコマンド・target になることを確認する（[0003](./0003-ci-contract.md) の完成後に確認する）。
- CI 上の結果（[0003](./0003-ci-contract.md) のジョブ）はローカル実行の結果とは別に、PASS／FAIL／SKIP を識別して記録する。
- クリーン環境の再現手順（install から test まで）を記録し、実行したコマンドと結果を証跡として残す（[0000](./0000-implementation-roadmap.md) §8.1）。

## リスク

- 名前空間衝突: `moon.mod` の name が mooncakes の既存名前空間と衝突すると公開・import の手順が変わる。実装開始時に確認する。
- 依存グラフの作り直し: 循環参照や target 非対応が後から判明すると package 分割の変更が大きくなる。最小 API で先に通し、確定内容を本 Issue に記録する。
- 公開 API の漏えい: `.mbti` を見ずに公開関数が増えると `surface` の判断ができない。`moon info` 差分をレビュー入力に固定する。
- 二重管理: package 名が [0001](./0001-scope-upstream-license.md) の文書や [0003](./0003-ci-contract.md) の target matrix とずれる。確定時は一箇所へ寄せて参照する。
- CI との不一致: ローカルで通る target と CI の matrix がずれると検証が空洞化する。[0003](./0003-ci-contract.md) と同時に確定する。
- target 追加の未検証: WASM/WASM-GC をツールチェーン確認なしに CI へ入れると SKIP が増える。確認できるまで追加しない。
- ロールバック: 骨格追加が中心で、問題時は該当コミットの revert で戻せる。後続 Issue は package 名・依存方向に依存するため、確定を本 Issue に記録してから着手させる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] MoonBit モジュール骨格（`moon.mod` と package 分割）と最小の core 機能（例: FourCC 値の型）を追加（内容は実装時に確定）

## 注記

- 上流参照（固定 SHA）: [src/lib.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/lib.rs)、[src/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux.rs)、[src/mux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux.rs)、[src/codec.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs)。
- 関連: [0001](./0001-scope-upstream-license.md)（対象・責務・ライセンス）、[0003](./0003-ci-contract.md)（CI matrix）、[0004](./0004-oracle-fixtures.md)（oracle のビルド基盤）、[0005](./0005-safe-bytes.md)（最初の実装 Issue）、[0033](./0033-release-docs.md)（配布）。
- 未決事項: package 名、最初の公開 API の具体名、命名表の配置は実装時に確定し、確定内容を本 Issue へ追記する。
- 証跡: moon のバージョン、実行コマンド、target 別の PASS／FAIL／未実行を記録する（[0000](./0000-implementation-roadmap.md) §4・§8.1）。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
- 2026-10-17: 実装に着手
- 2026-10-17: moon.mod(source=src, name=gpui-mbt/mp4)・src/bytes package・FourCC・black-boxテスト・README.mbt.md・CHANGES.md・.gitignore を追加。証跡: moon 0.1.20261012/moonc v0.10.15 で moon check --target native/js 成功、moon test --target native 7件PASS、--target js 7件PASS、moon fmt差分なし、moon infoレビュー済み。registry に gpui-mbt/mp4 が存在しないことを確認
