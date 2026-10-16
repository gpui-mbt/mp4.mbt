# [P0 / M1] 上流demux.rs相当のCLIサンプルを作る

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0014-demux-example
Priority: P0
Milestone: M1
Depends on: [0013](./0013-mp4-file-demux.md), [0004](./0004-oracle-fixtures.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

`moon run` でファイルを指定するとトラック一覧と先頭 N サンプルを表示する Native CLI サンプルを作る。目で見て試せる最初の成果物とし、0015 / 0016 の表示経路の基準出力を与える。

## 背景

- 上流の固定基準 [`1282b704`](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59) の [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs) は 1MB バッファで `required_input` に応じ seek/read し、トラックの id / duration / timescale と先頭 10 サンプルの track id / timestamp / data offset / data size を標準出力に出す。
- 上流 example の `read_from_file` は要求サイズをバッファ長に切り詰めて返すため、1MB を超える要求では `handle_input` の契約（要求範囲を一度に満たす）を満たさない可能性がある。MoonBit 側はこの点を明示的に扱う。
- 0004 の fixture / oracle と 0013 の demuxer を入力にし、出力は 0000 の「変更できないデータ契約」6（JSON の 64bit は十進文字列）に従う。
- 現時点で `moon.mod` も CLI もないため、本 issue は 0002 と 0013 の後に着手する。

## 問題

- 要求範囲が 1MB を超える場合をそのまま上流 example の実装で写すと、`handle_input` の契約違反（不足入力）になる。
- 64bit offset を JSON の Number にすると JS 側で精度が落ち、0016 の比較が成立しない。
- 誤ったパス・非 MP4・途中切断で exit code とエラー表示が不統一だと、CI smoke test や人手の確認が安定しない。
- 実行例が README にないと第三者が再現できない。

## 目標

- `examples/demux` 相当のコマンドを Native target で実装し、file path と `--max-samples`、`--json` を公開する。
- `required_input` に応じた seek / read、`size=None` の場合の読み方、1MB 上限の分割 I/O と要求範囲の蓄積を明確にする。
- 要求範囲が 1MB より大きい場合は、安全に結合できる範囲だけ受け入れ、上限超過なら明示エラーにする（上流契約違反にしない）。
- 通常 MP4 から track ID/kind、duration/timescale、sample DTS/CTTS/keyframe/offset/size を表示する。JSON は 64bit 整数を文字列にする。
- 誤ったパス、非 MP4、途中で切れたファイルの exit code とエラー表示を統一する。
- README に実際の MoonBit CLI に基づく実行例と代表出力を記載する（`moon run ... -- file.mp4` の形式は 0002 の package 構成に合わせて確定する）。
- CLI 実行と出力を CI smoke test に追加する（0003 の CI 完成後）。
- 入力読取の最大メモリを設定可能にする。

## 対象外

- GUI と Web ブラウザ（0015 で扱う）。
- 入力のメディアデコード（0013 と同じく sample payload は raw bytes のまま扱う）。
- 上流 example にない表示オプションの拡充（必要になった時点で別 issue にする）。

## 提案する方針

- `examples/demux` 相当を 0002 で確定する package 構成の下に Native target で実装する。引数は file path（必須）、`--max-samples <N>`、`--json` とする。`--max-samples` 未指定時の件数と正確なコマンド形は実装時に確定し、README に反映する。
- I/O アダプタ: `required_input` の `position` へ seek し、`size` 指定時はその範囲を、`size=None` のときは EOF までを上限付きで読む。読み取った範囲が要求に届かない場合は同一位置から再読込し、安全に結合できる範囲だけ結合する。上限（1MB 基準）を超える要求は「上限超過」の明示エラーにして demuxer へ不足入力を渡さない。
- 出力（テキスト）: 上流 example と同じ意味の項目（track id / duration / timescale、sample の track id / timestamp / data offset / data size、先頭 N 件の打ち切り表示）を出し、加えて kind / CTTS / keyframe を出して 0013 の `Sample` フィールドを隠さない。
- 出力（`--json`）: 64bit 整数（offset 等）は十進文字列にする。schema は 0015 / 0016 の JSON と共通化できる形にし、確定した schema を本 issue に記録する。
- エラー処理: 引数不正・ファイル不在・I/O 失敗・demux エラーを区別し、usage は stderr、成功出力は stdout、失敗は非ゼロ exit とする。exit code の具体値は実装時に確定して README と smoke test に固定する。
- 境界条件: `--max-samples 0` はサンプルを出力せず正常終了、全件指定は全サンプル、空ファイル・途中切断は demux エラーとして非ゼロ exit にする。パスに依存しない再現コマンドを README に書く。
- CI: 0003 の CI に smoke test（小さな fixture での実行と出力確認）を追加する。fixture は 0004 の manifest のものを使い、実行できない環境では SKIP を PASS と数えない。

## 受け入れ条件

- [ ] Given 0004 の fixture, when CLI を実行する, then track 一覧と先頭 N サンプルが上流 example 相当の情報で表示され、0013 の結果と一致する。
- [ ] Given 先頭 10 件 / 全件 / `--max-samples 0`, when 実行する, then それぞれ表示数が期待どおりで exit code 0 になる。
- [ ] Given `--json`, when 実行する, then 64bit offset が十進文字列で出力され、値が丸められない。
- [ ] Given 存在しないパス, when 実行する, then 非ゼロ exit で stderr に統一形式のエラーを出す（panic しない）。
- [ ] Given 非 MP4・空・途中切断のファイル, when 実行する, then 統一されたエラー表示と非ゼロ exit になる。
- [ ] Given 要求範囲が 1MB を超える fixture, when 実行する, then `handle_input` 契約違反にならず、明示エラー（または上限内の結合）で処理が終わる。
- [ ] Given README の再現コマンド, when そのまま実行する, then 代表出力が得られる。
- [ ] Given CI smoke test, when CLI を実行する, then 出力検証が PASS / FAIL / SKIP を区別して記録される。
- [ ] Given 入力の最大メモリ設定, when 大きな fixture を実行する, then 設定上限を超える保持をしない（読取量の証跡）。

## テスト計画

- `moon.mod` と 0013 が整備された後に `moon check`、`moon test --target native` を実行し、PASS / FAIL / 未実行を記録する。CLI は Native 専用のため、JS target は core 側の `moon test --target js` だけを対象にする。
- CLI 実行テスト: fixture ごとにテキスト出力と `--json` 出力を golden 化し、`--max-samples` の 0 / 10 / 全件で表示数と exit code を検証する。
- 上流比較: pinned SHA の `cargo run --example demux -- <fixture>` の出力と意味（track / sample の項目対応）を突き合わせる。表示形式の完全一致ではなく項目対応を golden で管理する。
- 手動確認: 大きめの MP4 で起動・表示・終了を確認し、途中で中断しても入力ファイルを変更しないことを確認する。
- CI smoke: 0003 の CI に追加し、実行できない環境の結果は未実行 / SKIP として記録して PASS と混同しない（0000 のテスト分類）。
- 現時点で `moon.mod` も CLI もないため、上記はすべて未実行として記録する。実行できない確認を PASS と混同しない。

## リスク

- 1MB 超の要求範囲を切り詰めて渡すと demuxer がエラー状態に遷移し、以後の実行が失敗する。上限判定を I/O アダプタに閉じ、wbtest で固定する。
- JSON の 64bit 精度を Number で失う。文字列固定をテストし、0016 の比較 schema と合わせる。
- 出力形式と README のドリフト。実行証跡のある代表出力だけを README に載せ、smoke test で検出する。
- exit code の具体値が環境のシェル規約と衝突する。値は実装時に確定し、テストで固定する。
- ロールバック: 新規 example と README 追加が中心で、コア API を変えない。問題時は該当コミットの revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] Native demux CLI サンプルと README 実行例

## 注記

- upstream の対応物: [examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)。
- 関連: [0003](./0003-ci-contract.md)（CI smoke）、[0004](./0004-oracle-fixtures.md)（fixture / oracle）、[0013](./0013-mp4-file-demux.md)（demuxer）、[0015](./0015-web-mp4-dump.md)（Web Dump との JSON 共通化）、[0016](./0016-rust-moonbit-diff.md)（差分 Lab の基準出力）。
- 関連ロードマップ: [0000](./0000-implementation-roadmap.md) の M1 とテスト分類（PASS / FAIL / UNVERIFIED / NOT_RUN）。
- 証跡ルール: checkbox は実際に実行した証拠がある項目だけ完了にする。CLI 出力と exit code を smoke test の artifact に残す。
- 実装時の未決事項: コマンド形（package 構成）、`--max-samples` の既定値、exit code の具体値、JSON schema の確定は実装時に決めて本 issue へ追記する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
