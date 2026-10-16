# [P1 / M1] 同一MP4でRust/WASMとMoonBitの差分を可視化する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0016-rust-moonbit-diff
Priority: P1
Milestone: M1
Depends on: [0004](./0004-oracle-fixtures.md), [0015](./0015-web-mp4-dump.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

同一入力に対して固定コミットのRust/WASM（参照実装）とMoonBit/JS（candidate）を別々に実行し、「似ている」ではなく一致した項目・不一致の箇所が分かるconformance labにする。差分はfield path・expected/actual・対象sample index・source commitとして表示し、判定状態をPASS / FAIL / Unverifiedで区別する。

## 背景

- 上流参照: [examples/dump_wasm](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)、[tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)。
- 上流wasm APIは `mp4_demux_sample_to_json` / `mp4_demux_track_info_to_json` でsample/trackをJSON化する。sample/trackの観測値をJSONで突き合わせる土台が上流にある。
- [0004](./0004-oracle-fixtures.md)がoracleの固定・正規化JSON schema・64bit十進文字列の契約を定め、[0015](./0015-web-mp4-dump.md)がMoonBit/JS側のcanonical JSON exportを提供する。本issueは両者を接続する。
- Rust側oracleの再現性は[0034](./0034-upstream-drift.md)（上流変更追従）と整合させる。現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コードはない。

## 問題

- 目視の左右比較では一致/不一致の判定が主観になり、64bit値・CTTSの有無・timebaseの差を見落とす。
- candidateが起動しなかった場合やoracleが取得できなかった場合を「差分なし」と扱うと、偽のPASSが生じる。
- Rust実装のバージョン差による差分をcandidateのバグと誤判定し得る。

## 目標

- 同一File bytesへの両実装の観測値を、field path・expected/actual・対象sample index・source commit付きで表示する。
- 64bit数値は文字列、CTTS未設定と0を区別し、timebase付きで比較する。
- candidateのビルド失敗・oracle不能をUnverifiedとして扱い、差分なし=PASSと混同しない。
- 実行証跡（差分レポートとログ）をCI artifactとして保存し、両実装の独立性をレビュー可能にする。

## 対象外

- Rustの解析結果をMoonBit側に埋め込んで「一致」させること。
- gpui-conformanceの画面比較との統合（任意の後続作業）。
- 新規codec/box対応の実装（既知の対応範囲のみ比較する）。
- oracle側を意図的に変更する作業（[0034](./0034-upstream-drift.md)へ回す）。

## 提案する方針

- 参照実装は固定コミット `1282b704` のRust/WASMをビルドしたもの、candidateはMoonBit/JS（[0015](./0015-web-mp4-dump.md)の出力）とする。両方へ同じFile bytesを与え、コードパスは別々に維持する。Rustの解析結果をcandidateへ流し込む経路を作らない。
- Rust側のJSONは `mp4_demux_sample_to_json` / `mp4_demux_track_info_to_json` 等の公開関数から取得し、candidateの出力を[0004](./0004-oracle-fixtures.md)の共通JSON schemaへ変換する。未知項目をゼロ埋め・既定値埋めする変換は禁止する（変換は許可リスト方式とし、対象外キーは比較対象から外したこともレポートに残す）。
- UI/レポートは左/右のtrack list・sample list・box treeを並置する。box treeは上流index.htmlの注意どおり出現順が入力順と一致しない場合があるため、順序に依存しない正規化で比較し、順序自体の差は別フィールドとして扱う（正規化方式は実装時に確定し、本issueへ追記する）。
- 比較の保証対象を固定する: 64bit数値の文字列化、CTTS未設定（`None`）と0の区別、timebase付き時刻比較、sample entry変更条件、エラー型一致。DTSの全track統合はfloat丸めなしで比較する（0000のデータ契約）。
- 判定状態はPASS / FAIL / UNVERIFIED / NOT_RUNを独立に記録し（0000の方針）、candidate未起動やoracle失敗はUnverifiedとしてUIとCI判定へ反映する。
- レポートには固定commit SHA・fixture checksum・実行日時・OS/arch・ツールチェーン版を埋め込む。レポートのファイル形式とUI/CI共通判定コードの置き場所は実装時に確定する。

## 受け入れ条件

- [ ] Given 0004のmanifestにある少なくとも3つのfixture, when 同一bytesを両実装へ与える, then Rust/MoonBitの比較レポートが保存され、一致項目と不一致のfield pathが列挙される。
- [ ] Given 正常なfixture, when candidate側の1 sampleのdurationだけを意図的に変える, then 該当sample indexのdurationフィールドに不一致が出る。
- [ ] Given oracle側のRust実装/版が異なる, when 比較する, then source commitの差がレポートに書き出され、candidateの不一致と混同されない。
- [ ] Given candidateのビルド失敗またはoracle不能, when 実行する, then 結果はUnverifiedとして表示され、PASSにならない。
- [ ] Given 64bit offsetとCTTS未設定を含むfixture, when 比較する, then 数値文字列とNone/0の区別が保たれ、JS数値精度の丸めによる不一致が出ない。
- [ ] Given Browser E2E, when ページを操作する, then 両ロジックが実際に起動していることをログ/実行トレースで確認できる。
- [ ] Given 比較レポート, when CIが終了する, then PASS / FAIL / Unverifiedが区別され、差分レポートと実行証跡がartifactとして保存される。

## テスト計画

- 現時点では `moon.mod` がなく、以下は0002・0004・0015完了後に実行する。PASS / FAIL / 未実行を混同せず記録する。
  - `moon check --target js` と `moon test --target js` を実行し、結果とツールチェーンのバージョンを記録する。
  - wbtest: JSON正規化で未知項目をゼロ埋めしないこと、64bit文字列とNone/0の区別、差分のfield path生成、判定状態遷移（PASS / FAIL / UNVERIFIED / NOT_RUN）を固定する。box treeの順序非依存比較は境界ケースを含める。
- Rust/WASM oracleは固定commitのcloneからビルドし、oracle run IDとupstream SHAをgoldenに紐付ける（0004）。同じSHA・同じfixtureから決定的に再生成できることを確認する。
- 故障注入: fixtureのコピーで1 sampleのdurationを書き換え、該当fieldへの不一致を確認する（実メディアの再エンコードは行わない）。
- Browser E2E（Playwright等）で両ロジックの起動を確認し、レポート・ログ・スクリーンショットをCI artifactに保存する。
- fixtureは0004のmanifest（SHA256付き）を使い、ライセンス未確認素材は使わない。oracle未整備・candidate未ビルドの間は「未実行」と理由を記録する。

## リスク

- 上流の新HEADとの差分をcandidateバグと誤判定する。source commit比較を必須表示とし、固定SHA以外は比較対象から外す（[0034](./0034-upstream-drift.md)と連携）。
- JSON変換で未知項目をゼロ埋めすると偽PASSになる。許可リスト方式の正規化とwbtestで拒否を固定する。
- UIの左右表示が「似ているだけ」の比較に戻る。field path・expected/actualを必須出力とし、E2Eで欠落を検出する。
- JS実行環境とRust oracleの環境差で64bit値・時刻の表現が分かれる。文字列保持の契約を両実装で共有し、比較前に共通schemaへ正規化する。
- ロールバック: 比較ツールとレポート生成の追加に限定し、coreの公開API契約を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] Rust/WASMとMoonBit/JSの同一入力差分レポート（PASS / FAIL / Unverifiedを区別）

## 注記

- 上流参照: [examples/dump_wasm](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/dump_wasm)、[crates/wasm/README.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/README.md)、[tests/test_decode_encode.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_decode_encode.rs)。
- 関連: [0004](./0004-oracle-fixtures.md)（oracle/fixture）、[0015](./0015-web-mp4-dump.md)（candidate側UI）、[0031](./0031-fuzz-pbt-hardening.md)（不正入力の回帰）、[0034](./0034-upstream-drift.md)（上流追従）。
- 運用: 比較レポートとログをCI artifact化し、candidateとoracleのどちらが失敗したかを区別して記録する。未検証項目はPartial/Unverifiedと明示し、diffなしと混同しない。
- 未決事項（実装時に確定して追記する）: レポート形式、差分判定コードの配置（`tools/oracle` 候補）、box tree正規化の具体規則。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
