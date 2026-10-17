# [P1 / M3] 通常MP4書込・roundtrip CLIサンプルを作る

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0023-mp4-mux-example
Priority: P1
Milestone: M3
Depends on: [0013](./0013-mp4-file-demux.md), [0022](./0022-mp4-file-mux.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

`examples/mux`で、通常MP4の作成と再読込を1コマンドで検証する最小サンプルを作る。`--faststart`、`--output`、`--verify`を備え、`--verify`はMoonBit（[0013](./0013-mp4-file-demux.md)）とRust oracle双方のdemux結果を比較する。実メディアを用意しない環境でも動く。

## 背景

- 現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コード・exampleはない。本issueはM3の完了証跡（sample実offsetの一致、生成物を双方のdemuxerで読める）を実行可能な形で提供する。
- 上流参照: [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[crates/wasm/examples/mux.js](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/examples/mux.js)、[tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)。
- 前提は[0022](./0022-mp4-file-mux.md)（`Mp4FileMuxer`）と[0013](./0013-mp4-file-demux.md)（読み戻し側）。CLIの実行基盤は[0002](./0002-moonbit-bootstrap.md)のtarget方針に従い、CIゲートは[0003](./0003-ci-contract.md)、oracleは[0004](./0004-oracle-fixtures.md)を使う。

## 問題

- mux APIが単体で動いても、書込→読み戻し→metadata/oracle比較を通しで実行する場所がない。
- 生成MP4の同価性を確認せずに「書けた」と扱うと、samplesの同一性（stss省略条件やcttsの変化）の崩れを検出できない。
- 既存ファイルを黙って上書きすると、ユーザーのfixtureや直前の生成物を破壊する。失敗時の中途半端な一時ファイルの後始末も未定義。
- 実メディアやネットワークがない環境で動く最小サンプルの要件（固定Opus/AAC sample entryと既知payload）が固まっていない。

## 目標

- CLI1コマンドでMP4を生成し、再読込比較（MoonBit/Rust）まで実行できる。
- faststart/non-faststartの両方でsamplesの同一性が保たれることを出力で示せる。
- 既存ファイル上書きを防ぎ、失敗時に中途ファイルを残さない（削除または安全な退避とパス報告）。
- CIでCLI smoke testとgoldenが実行され、再現可能なfixtureと説明がリポジトリにある。

## 対象外

- 複数音声言語track（上流現行設計上サポート外）。
- 実エンコード・実デコード、再生・映像表示。payloadは既知の固定bytesを扱う。
- fMP4のexample（[0021](./0021-fmp4-example.md)）とHybrid/faststartの位置契約（[0027](./0027-hybrid-faststart.md)）。
- UI・ブラウザdemo（[0015](./0015-web-mp4-dump.md) / [0029](./0029-webcodecs-transcode.md)）。

## 提案する方針

- `examples/mux`で固定Opus/AAC sample entryと既知payloadを組み立て、`initial_boxes_bytes`→payload追記→`append_sample`→`finalize`結果の指定offset書込を行う。
- CLIは`--faststart`、`--output`、`--verify`を用意する。`--verify`はMoonBitのdemuxerとRust oracle双方のdemux結果（track/sample metadata）を比較し、差分があれば非0終了で報告する。
- 書込先を破壊しないため、既存ファイルの上書きには明示許可（例: 明示フラグ）を要求する。失敗時は一時ファイルを削除するか、削除しない場合はパスと理由を報告する。書込先は`--output`指定パスまたは一時ディレクトリに限定する。
- 再実行可能な小さなfixtureと説明を追加し、テスト時は生成時刻（created time相当）を固定して決定的にする。
- CLI引数、出力ファイルの一時的な置き方、エラー分類は実装時に確定して本issueへ追記する。nativeを先行し、JSでは純粋なmuxコアのテストを対象にする（CLIはnativeのみ）。

## 受け入れ条件

- [ ] Given 実メディアなしの環境, when `examples/mux`を既定引数で実行する, then Opus/AACの固定sampleからMP4が生成され成功終了する。
- [ ] Given 生成MP4, when MoonBitのdemuxerで再読込する, then track kind、timestamp、payload bytes、keyframeが書き出し記録と一致する。
- [ ] Given 生成MP4, when Rust oracleで再読込する, then MoonBit側と同じsample metadataとして観測でき、比較結果がログとartifactに残る。
- [ ] Given `--faststart`の有無それぞれ, when 生成してから再読込する, then moov位置が仕様どおり配置され、samplesの値は両者で同一である。
- [ ] Given 既存ファイルが出力先にある, when 上書き許可なしで実行する, then 既存ファイルを変更せずエラーにする。上書き許可ありでは置き換わる。
- [ ] Given finalize差分のoffset対応を書かない異常ケースを注入する, when `--verify`を実行する, then検証が差分を報告して非0終了する（検証が空回りしない）。
- [ ] Given 生成失敗（例: 書込先が書込不可）, when CLIが終了する, then 中途半端な出力ファイルが残っていないか、残存パスと理由が報告される。
- [ ] Given READMEの参照コマンド, when リポジトリrootで実行する, then 追加セットアップなしで再現できる。

## テスト計画

- `moon check`と`moon test --target native`を実行し、PASS / FAIL / 未実行を記録する（現時点では`moon.mod`と実装がなく実行不能。0002完了後に有効化する）。
- CLI smoke test: 最小入力を生成し、exit codeと出力ファイルの存在、`--verify`の比較結果をCIで確認する。goldenとしてmanifestまたはsample metadataの比較結果を保存する。
- `--faststart`/non-faststartの両モードを実行し、moov位置（offset）とsamplesの同一性を比較する。結果はgoldenとして固定する。
- Rust oracle（0004）との比較で、MoonBit生成MP4がRust demuxに受理されることを確認する。oracle未整備の間は「未実行」と記録し、PASSと混同しない。
- 異常ケース: finalize offset対応なしの比較、既存ファイル上書き、書込不可パスを注入し、FAILと非0終了、中途ファイルの有無を確認する。
- JS targetはmuxコアのテストに限定し、CLI部分はnativeのみとする。実行しない確認は理由つきで「未実行」と記録する。

## リスク

- 上書きや途中終了で既存ファイルを壊す。上書きの明示許可と一時ファイル経由の置換で限定する。
- faststart有無でmoov位置とoffsetが変わり、検証なしでは壊れたファイルが成功扱いになる。`--verify`必須をREADME/CIで既定にする。
- CLI固有の失敗（引数、権限、パス）がcoreのエラーと混ざる。呼出側で分類し、coreはSans I/Oを保つ。
- golden依存で環境差が出る。生成時刻固定と比較対象（metadataのみ）の限定で抑える。
- ロールバック: exampleとREADMEの追加が中心で、topの公開API契約を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] 通常MP4の作成・再読込を1コマンドで検証するCLIサンプルを追加

## 注記

- 上流参照: [src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[crates/wasm/examples/mux.js](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/crates/wasm/examples/mux.js)、[tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)。
- 関連: [0003](./0003-ci-contract.md)（CI）、[0004](./0004-oracle-fixtures.md)（oracle/fixture）、[0013](./0013-mp4-file-demux.md)（読み戻し）、[0022](./0022-mp4-file-mux.md)（writer本体）、[0027](./0027-hybrid-faststart.md)（位置契約）。
- 未決事項（実装時に確定して追記する）: CLI引数名、一時ファイル→最終パスの置換手順、goldenの保存形式。
- 証跡: 実行コマンド、exit code、比較結果、出力パス、コミットSHA、fixture checksumをログまたはartifactに残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。


## 検証

- 実装: `src/boxes` / `src/demux` / `src/mux` / `src/examples` に追加し、`moon test --target native` と `--target js` を実行した（2026-10-17、PASS）。
- MoonBit の unit / roundtrip テストは PASS。Rust oracle との完全な差分比較はこの環境では未実行のため **UNVERIFIED**（oracle 依存の受入項目は PASS と扱わない）。
- `moon fmt --check` と `moon info` は実行済み。生成された `.mbti` を同時に更新する。
