# [P1 / M1] 同一MP4でRust/WASMとMoonBitの差分を可視化する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-18
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

- [x] Given 0004のmanifestにある少なくとも3つのfixture, when 同一bytesを両実装へ与える, then Rust/MoonBitの比較レポートが保存され、一致項目と不一致のfield pathが列挙される。 → manifest 全 9 fixture を `web/run_lab.mjs` で比較し `web/lab-out/<fixture>.report.json` + `summary.json` に保存（全 fixture verdict=pass。例: opus は pass=3438 項目）。CI の `diff-lab` job が artifact 化。
- [x] Given 正常なfixture, when candidate側の1 sampleのdurationだけを意図的に変える, then 該当sample indexのdurationフィールドに不一致が出る。 → `run_lab.mjs` 内蔵の故障注入 self-test が `samples[0].duration` を +1 改竄し、該当 path のみ FAIL を全サンプル保持 fixture で検出（`fault_injection=detected`、`<fixture>.fault-report.json` も保存）。ブラウザ UI にも故障注入ボタンがあり E2E で検証。
- [x] Given oracle側のRust実装/版が異なる, when 比較する, then source commitの差がレポートに書き出され、candidateの不一致と混同されない。 → レポート `meta.upstream_sha` に固定 SHA `1282b704…` を必ず記録（UI のメタ表示 + レポート JSON）。CI 上で wasm oracle は Cargo.lock + git rev 固定で再現ビルドされる。
- [x] Given candidateのビルド失敗またはoracle不能, when 実行する, then 結果はUnverifiedとして表示され、PASSにならない。 → `mp4lab_unverified_json` が理由付き UNVERIFIED レポートを生成（`lab.js` は oracle.wasm 取得失敗・candidate セッション失敗時にこれを使用）。`run_lab.mjs` は実行基盤エラーを exit 2、UNVERIFIED/FAIL 残存を exit 1 で区別。wbtest で「比較不能は pass にならない」を固定。
- [x] Given 64bit offsetとCTTS未設定を含むfixture, when 比較する, then 数値文字列とNone/0の区別が保たれ、JS数値精度の丸めによる不一致が出ない。 → `Json::Number` の `repr` で十進文字列として厳密比較（BigInt 経由・Number 変換なし）。`composition_time_offset` は `none` と `"0"` を区別する wbtest を実装。
- [x] Given Browser E2E, when ページを操作する, then 両ロジックが実際に起動していることをログ/実行トレースで確認できる。 → `web/lab.html` の実行エンジンログに `[oracle] dump ok`（wasm 実行）と `[candidate] … N range reads`（MoonBit 実行）の双方を記録し、E2E で両方の存在を assert（スクリーンショット成果物付き、20/20 pass）。
- [x] Given 比較レポート, when CIが終了する, then PASS / FAIL / Unverifiedが区別され、差分レポートと実行証跡がartifactとして保存される。 → CI `diff-lab` job が `node web/run_lab.mjs` を実行し `web/lab-out/` を `actions/upload-artifact` で保存。レポートは `stats` で PASS/FAIL/UNVERIFIED/NOT_RUN を独立計数。

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
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。

## 実装時に確定した事項

- レポート形式: `{"meta": {...}, "verdict": "pass|fail|unverified|not_run", "stats": {...}, "entries": [{"path","verdict","expected","actual","note"}], "excluded": [{"path","reason"}]}`。`meta` に upstream SHA・fixture 名/SHA-256/file size・両エンジン識別・ツールチェーンを含める。
- 差分判定コードの配置: `tools/oracle` ではなく **pure MoonBit 側**（`src/difflab`）に置いた。理由: ブラウザ上の wasm oracle と同一バンドル内で比較を完結させるには JS 実行側に comparator が必要なため。`src/webdump` から `mp4lab_compare_json` / `mp4lab_unverified_json` として ESM export。
- box tree 正規化: preorder の `(depth, type, start)` 列で比較するが、candidate が観測しなかったノード（例: `moof`/`traf`/`mfra` 配下は candidate の box walker が未展開）は「coverage 差」として `excluded` に記録し、`box_tree.order` は両側で実際に観測されたノードのみで比較する（coverage 差を順序差と誤判定しない）。
- Rust/WASM 側は上流 `crates/wasm` を移植するのではなく、固定コミットの Rust 実装を wasm32-unknown-unknown cdylib（`tools/lab-oracle`、上流 `allocate_vec` 規約の `lab_alloc`/`lab_vec_*` ABI）としてブラウザ/Node で直接実行する構成。これにより「参照実装そのもの」を回せる。
- JSON emitter は `tools/oracle/src/oracle_json.rs` に抽出し、native oracle バイナリと wasm cdylib が同一 emit コードを共有（golden schema とのドリフトを構造的に防ぐ）。抽出は golden 再生成一致で検証済み。

## 検証証跡（2026-10-18）

- `moon fmt` / `moon info`: clean（`.mbti` 差分は `mp4lab_compare_json` / `mp4lab_unverified_json` の 2 export 追加のみ）。
- `moon check` / `moon check --target js`: clean（警告なし）。
- `moon test`: 423/423（default）、423/423（js）、439/439（native）pass。difflab wbtest 11 件（ゼロ埋め拒否・64bit 文字列厳密比較・null vs 0・field path 生成・verdict 遷移・順序非依存 box tree・oracle-only ノードの coverage 分離・UNVERIFIED 遷移等）を含む。
- `sh web/build.sh`: `mp4.js`（ESM, difflab 込み）+ `oracle.wasm`（`tools/lab-oracle`、rust-toolchain.toml で 1.94.0 + wasm32 target 固定）を `web/dist/` へ出力。
- `node web/run_lab.mjs`: manifest 全 9 fixture で verdict=pass（合計 pass 項目: 5,489）。故障注入 self-test はサンプル保持全 fixture で `samples[0].duration` の FAIL を検出。fMP4 fixture は `moof`/`traf`/`mfra` 配下未展開のため excluded=9 を記録しつつ pass（coverage 差として正しく分離）。
- Playwright E2E（`web/e2e/e2e.mjs`、headless Chromium）20/20 pass: lab ページの PASS 判定表示、両エンジン実行ログ、meta の upstream SHA、故障注入 → FAIL at `samples[0].duration`、スクリーンショット成果物。
- CI: `diff-lab` job（build + run_lab + `actions/upload-artifact` で `web/lab-out/` 保存）。pages.yml は既存の `sh web/build.sh` 経由で wasm oracle も Pages に同梱。
