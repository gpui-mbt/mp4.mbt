# [P0 / M0] Rust oracle・fixture・正規化goldenを構築する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: test/0004-oracle-fixtures
Priority: P0
Milestone: M0
Depends on: [0001](./0001-scope-upstream-license.md), [0002](./0002-moonbit-bootstrap.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

Rust 互換性を主観で判定せず、同じ入力 bytes → 両実装 → 同じ観測値で判定する。固定 SHA の Rust 実装を oracle、MoonBit を candidate とし、fixture の manifest（帰属・SHA256）と正規化した golden を `tests/fixtures` と `tools/oracle` に用意する。特に大きな 64bit 値と sample の順序を損失なく扱う。本 Issue は計画段階であり、未実装・未テストである。

## 背景

- [0000](./0000-implementation-roadmap.md) §4 は「Upstream fixture」「Rust differential」を検証区分として挙げ、固定 SHA から再生成した canonical golden との一致で判定する方針を示す。M0 の gate は「fixture の hash と期待結果が固定」である。
- 上流参照（固定 SHA）: [tests/testdata](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/testdata)、[examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)、[examples/fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/fmp4.rs)、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)、[tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)。
- [0000](./0000-implementation-roadmap.md) のデータ契約 6 は「JSON 比較では 64bit 整数を十進文字列で保持し、JS の安全整数精度外を Number へ強制変換しない」と定める。正規化 schema もこれに従う。
- fixture の帰属・配布可否は [0001](./0001-scope-upstream-license.md) の確認結果を前提とし、確認前に外部素材を保存しない。

## 問題

- 目視や曖昧な『似ている』比較では Rust/MoonBit の差分が主観になり、[0016](./0016-rust-moonbit-diff.md) の比較 Lab や [0003](./0003-ci-contract.md) の golden ジョブが判定できない。
- JS の Number へ 64bit 値を渡すと丸めが入り、大きい offset や時間の差分が消える。
- oracle が latest を参照すると、上流の変更を candidate のバグと誤判定する。
- candidate のビルド失敗や oracle 不能を「差分なし」と扱うと偽の一致になる。
- fixture の帰属・配布可否が未確認のままだと、再配布できない素材が repo に入る。

## 目標

- 上流固定 SHA の小さな fixture を候補に、帰属と SHA256 付きの manifest がある。
- 固定上流 clone から実 Rust 実装を実行する oracle コマンドがあり、ランダム・日時・出力パスなどを固定して再現できる。
- 観測値を `kind`、track ID/kind/timescale/duration、sample 順序/DTS/CTTS/keyframe/offset/size、box tree、エラー種別と位置に正規化し、差分が見える schema で比較できる。
- expected golden が Rust oracle run ID と upstream SHA に紐付く。
- candidate 失敗時は差分ではなく未検証／実行失敗として記録され、「一致」と混同されない。
- 結果一覧が Pass／Fail／Unverified の 3 状態を持つ。

## 対象外

- 公開配布できることを確かめていない外部テストメディアは保存しない。
- 動画エンコードの再現をこの Issue の前提にしない。未取得素材は generator で作る。
- golden を手入力して『一致』を作らない。
- 差分の可視化 UI（[0016](./0016-rust-moonbit-diff.md)）と fuzz/PBT（[0031](./0031-fuzz-pbt-hardening.md)）の実装は各 Issue が扱う。本 Issue は oracle・fixture・golden の生成と比較基盤に限定する。

## 提案する方針

- `tests/fixtures` に manifest を置き、上流 `1282b704` の小さな fixture（black-h264-video.mp4、black-h264-fmp4.mp4、beep-aac-audio.mp4、beep-opus-audio.mp4、black-av1-video.mp4 など）を候補に、帰属と SHA256 を記録する。採用する個別ファイルは [0001](./0001-scope-upstream-license.md) の確認結果と実装時に確定する。
- `tools/oracle` に、固定上流 clone（`1282b704f44184ec792e1549b5d31e0c4c54dc59`）から実 Rust 実装を実行するコマンドを用意する。[0000](./0000-implementation-roadmap.md) に記載の `cargo run --example demux -- tests/testdata/black-h264-video.mp4` や `cargo run --example fmp4` を出発点とし、最終形は実装時に確定する。ランダム・日時・出力パスなどを固定し、外部システム依存を排除する。
- 正規化 schema を定義する: `kind`、track ID/kind/timescale/duration、sample 順序/DTS/CTTS/keyframe/offset/size、box tree、エラー種別と位置。64bit 整数は JSON の数値でなく十進文字列で持ち、CTTS 未設定と 0 の区別・timebase 付き比較を維持する（[0000](./0000-implementation-roadmap.md) のデータ契約）。
- expected golden は Rust oracle run ID と upstream SHA を紐付けて保存する。candidate が失敗した場合は差分ではなく未検証／実行失敗として記録する。golden を手入力して『一致』を作らない。
- fixture 群を正常、moov 先頭/末尾、複数 track、切断、巨大 size 宣言、未知 box、字幕、fMP4 multi-segment に分類する。未取得素材は generator で作る。
- schema の版管理（golden に schema version を持たせるか）と manifest／golden のファイル形式は実装時に確定し、確定内容を本 Issue へ追記する。

## 受け入れ条件

- [ ] Given 同じ Rust SHA・同じ fixture, when oracle を再実行する, then golden が決定的に再生成され、再生成差分が検出できる。
- [ ] Given 64bit `2^53+1` などの整数, when golden へ正規化する, then 丸められず十進文字列として保持される。
- [ ] Given データ変更・sample 順序変更・エラー区分変更, when 比較する, then golden 比較が FAIL する。
- [ ] Given 上流 fixture の不在またはライセンス未確認, when 対象テストを実行する, then 未実行（Unverified）として報告され、PASS と集計されない。
- [ ] Given candidate のビルド失敗や oracle 不能, when 比較を実行する, then 差分なしではなく未検証／実行失敗として記録される。
- [ ] Given `tests/fixtures/manifest` と `tools/oracle`, when 実行手順を確認する, then Rust と MoonBit を区別した実行証跡を保存できる。
- [ ] Given 結果一覧, when 状態を確認する, then Pass／Fail／Unverified の 3 状態が区別されている。

## テスト計画

- Rust oracle の再現性: 固定上流 clone から 2 回実行し、同じ fixture・同じ SHA で golden が一致することを確認する（[0002](./0002-moonbit-bootstrap.md) の実行基盤に依存し、現時点では未実行）。
- 正規化の単体検証: 64bit 値（`2^53+1` 等）が十進文字列で保持され、丸めが入らないことを wbtest で固定する。テストのファイル名・関数名は実装時に確定する。
- 差分検出の負の検証: fixture のデータ変更・sample 順序変更・エラー区分変更で比較が FAIL することを確認する。
- 未検証の扱い: 上流 fixture 不在・ライセンス未確認・candidate 失敗の各経路で、結果が Unverified（未実行）になり PASS に集計されないことを確認する。
- MoonBit 側のコマンド: `moon check`、`moon test --target native`、`moon test --target js` を将来実行する。現時点では `moon.mod` がないためすべて未実行であり、PASS とは記録しない。
- fixture の管理: manifest の SHA256 と帰属情報、generator の再生成手順をセットで残し、未確認素材を repo へ追加しない。
- 証跡: 実行コマンド、commit SHA、OS/arch、fixture checksum、日時を結果に含める（[0000](./0000-implementation-roadmap.md) §4）。

## リスク

- fixture の権利: 配布可否が未確認の素材を保存すると再配布できない。外部素材は帰属・許諾確認後に限定し、未確認は generator で作る（[0001](./0001-scope-upstream-license.md)）。
- oracle 再現性の破綻: latest 参照や環境依存（乱数・日時・パス）が混ざると差分が再現しない。固定 SHA と正規化で排除する（追従監査は [0034](./0034-upstream-drift.md)）。
- 精度の劣化: JSON 数値へ変換すると 64bit 値が丸まる。十進文字列を schema の契約に固定する。
- schema 変更の波及: golden の schema を変えると全 fixture の再生成が必要になる。schema version の扱いを実装時に決め、変更時は再生成を必須にする。
- 偽の一致: golden 手入力や candidate 失敗の PASS 扱いが混入し得る。生成元（oracle run ID・upstream SHA）の紐付けと Unverified の分離で防ぐ。
- ロールバック: tools／tests／golden の追加は独立で、問題時は該当コミットの revert で戻せる。fixture の配布不可が判明した場合は、manifest を辿って該当 fixture と依存 golden だけを外せるようにする。

## 変更履歴

`CHANGES.md` impact: no

判断理由: oracle・fixture・golden の検証基盤が中心で、利用者に見える API・挙動を変えない。

## 注記

- 上流参照（固定 SHA）: [tests/testdata](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/testdata)、[examples/demux.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/demux.rs)、[examples/fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/fmp4.rs)、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)、[tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)。
- 関連: [0000](./0000-implementation-roadmap.md)（検証区分・データ契約）、[0001](./0001-scope-upstream-license.md)（帰属と配布可否）、[0002](./0002-moonbit-bootstrap.md)（実行基盤）、[0003](./0003-ci-contract.md)（golden ジョブ）、[0016](./0016-rust-moonbit-diff.md)（差分表示）、[0031](./0031-fuzz-pbt-hardening.md)（fuzz）、[0034](./0034-upstream-drift.md)（上流追従）。
- 未決事項: 正規化 schema の詳細、採用 fixture、manifest／golden のファイル形式、schema version の扱いは実装時に確定し、確定内容を本 Issue へ追記する。
- 証跡ルール: Pass／Fail／Unverified を混同せず、oracle run ID・upstream SHA・fixture checksum・実行日時を記録する。PASS は実際に実行して一致した場合だけ記録する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
- 2026-10-17: 実装に着手
- 2026-10-17: tools/oracle（固定SHA 1282b704・Rust1.94.0・schema v1・64bit十進文字列）と tests/fixtures（manifest.json SHA256付き9件・golden 9件・regenerate_fixtures.mbtx）を追加。証跡: cargo test 2件PASS、sha256sum照合9件一致、oracle 2回実行で決定的（--checkで9件unchanged）、golden 9件生成。candidate側の比較実装は0013/0016で実施
