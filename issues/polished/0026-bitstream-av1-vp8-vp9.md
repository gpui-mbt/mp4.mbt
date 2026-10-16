# [P2 / M4] AV1/VP8/VP9 bitstream metadataを移植する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0026-bitstream-av1-vp8-vp9
Priority: P2
Milestone: M4
Depends on: [0005](./0005-safe-bytes.md), [0010](./0010-sample-entries.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

AV1 の OBU 列と VP8 key frame / VP9 uncompressed header から解像度・profile・level・depth・キー判定の情報を取り出し、`av1C`・`vpcC` と av01/vp08/vp09 sample entry、codec string に矛盾なく供給する。AV1 では `av1C configOBUs` と sample 側の `obu_has_size_field` 条件を分けて扱う。

## 背景

- upstream（固定 SHA）の [src/bitstream/av1.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/av1.rs)、[src/bitstream/vp8.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/vp8.rs)、[src/bitstream/vp9.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/vp9.rs) が対象実装である。
- 上流の参照テストは [tests/test_bitstream_av1.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_av1.rs)、[tests/test_bitstream_vp8.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_vp8.rs)、[tests/test_bitstream_vp9.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_vp9.rs)。
- [0005](./0005-safe-bytes.md) が byte/bit reader/writer と失敗分類を提供し、[0010](./0010-sample-entries.md) が `av01/av1C`・`vp08/vp09/vpcC` sample entry を型付きで扱い、[0011](./0011-codec-strings.md) が RFC 6381 codec string を組み立てる。本 issue はその両者が参照する bitstream metadata の抽出を追加する。
- 差分判定は [0004](./0004-oracle-fixtures.md) の Rust oracle と [0016](./0016-rust-moonbit-diff.md) の canonical JSON 比較に載せる。
- [0000](./0000-implementation-roadmap.md) では bitstream helper 群を M4 に置く。2026-10-16 時点の `main` は README と `issues/` のみで、`moon.mod` も実装もない。

## 問題

- OBU / VPx header を解釈しないと、sample entry の profile・level・depth・resolution を埋められず、codec string も決められない。
- AV1 は `av1C configOBUs` と sample 内 OBU で size field の条件が異なる（`obu_has_size_field`）。混同すると sample の解釈が壊れる。
- LEB128 の長さ不足 / overflow、OBU size mismatch、reserved bit、壊れた frame header、VP9 frame marker 不正の扱いが未定義だと、部分成功の metadata を返し得る。
- codec full decoder へ範囲を広げると移植規模が膨らむ。上流の「必要欄だけ」という境界を守る必要がある。
- 未完成の codec を対応済みとして公開すると、利用側が誤った前提で組み込む。

## 目標

- AV1 の LEB128・OBU header・Sequence Header・Frame Header 先頭の必要欄を parse し、`av1C` を構築できる。
- VP8 key frame header と VP9 uncompressed header を上流の範囲だけ実装し、`vpcC` を構築できる。
- av01/vp08/vp09 sample entry 生成に必要な profile/level/depth/resolution を抽出し、codec string と矛盾しない値を返す。
- OBU size 超過・reserved bit・壊れた frame header・VP9 frame marker 不正に上限とエラーを設け、Native / JS で一致させる。
- 3 codec の対象 helper とテストを持ち、対応未完成の codec は README に partial と明示して未実装関数を公開しない。

## 対象外

- 画素の decode、色変換、圧縮率・映像品質の測定。
- codec full decoder / encoder の実装。上流の必要欄抽出を超えて復号処理に手を出さない。
- 上流が扱わない OBU 種別・frame header フィールドの網羅。
- H.264/H.265（[0024](./0024-bitstream-h264-h265.md)）、AAC/Opus（[0025](./0025-bitstream-aac-opus.md)）、字幕（[0028](./0028-subtitle-sample-entry.md)）。

## 提案する方針

- 配置は 0000 の提案パッケージに従い `src/bitstream/av1.mbt`・`src/bitstream/vp8.mbt`・`src/bitstream/vp9.mbt` を想定する。ファイル名と package 分割は [0002](./0002-moonbit-bootstrap.md) で確定し、決まり次第本 issue と README を更新する。
- AV1: LEB128、OBU header、Sequence Header、Frame Header 先頭の必要欄を parse する。`av1C configOBUs` と sample の `obu_has_size_field` 条件をコード上で分離し、取り違えをテストで検出する。
- VP8/VP9: key frame header / uncompressed header など上流の範囲だけを実装する。frame marker・reserved bit を検証し、codec full decoder には手を出さない。
- 出力: profile/level/depth/resolution 等を構造体で返し、0010 の sample entry encode と 0011 の codec string が同じ値源を使う。片側だけ変更して矛盾した場合はテストで落とす。
- エラー: 0005 の失敗分類へ写像する。OBU size 超過・reserved bit・壊れた frame header に上限を設け、LEB128 の長さ不足/overflow・OBU size mismatch・VP9 frame marker 不正を分類して返す。
- 互換性: Rust oracle の sample entry・codec string と一致することを gate とし、差分は 0016 の field path 比較で特定する。target 間（Native / JS / WASM）で同じ値とエラー分類になることを検証する。
- 実装時の未決事項: 公開 API 名、対象 OBU / frame header フィールドの正確なリストは実装時に確定する。partial の範囲は README の機能表に反映する。

## 受け入れ条件

- [ ] Given 上流 AV1 configOBUs と `black-av1-video.mp4`, when MoonBit で OBU/Sequence Header を parse する, then profile・level・depth・resolution と av1C が Rust oracle と一致する。
- [ ] Given 上流 VP8/VP9 短小 fixture, when key frame header / uncompressed header を parse する, then vpcC に必要な項目とキー判定が Rust oracle と一致する。
- [ ] Given LEB128 の長さ不足/overflow、OBU size mismatch、VP9 frame marker 不正, when parse する, then 定義済みの失敗分類でエラーになり、部分的な metadata を返さない。
- [ ] Given 同じ sample の entry 情報, when 0010 の sample entry と 0011 の codec string を構築する, then 両者が同じ profile/level/depth/resolution を参照して矛盾しない。
- [ ] Given 未実装の codec 範囲, when 公開 API と README の機能表を突き合わせる, then partial 表記と公開 API が一致し、未実装関数が公開されていない。
- [ ] Given JS と Native, when 同じ fixture を処理する, then 抽出値とエラー分類が一致する。

## テスト計画

- 現時点では `moon.mod` も実装もないため `moon check` / `moon test` を実行できない。初回実行まではすべて「未実行」と記録し、未実行を PASS / FAIL と混同しない。0000 の記録規則（PASS / FAIL / 未実行の独立記録、コマンド・commit SHA・OS/arch・fixture checksum の添付）に従う。
- 0002 の scaffold 完了後に次を実行し、結果を本 issue へ追記する。
  - `moon check --target native --deny-warn` と `moon test --target native`。
  - `moon test --target js` で抽出値とエラー分類の target 間一致を確認する。
- wbtest（package 内の white-box test）で次を固定する。
  - LEB128 の正常・長さ不足・overflow 境界。
  - OBU header / Sequence Header / configOBUs と sample の size field 条件の分岐。
  - OBU size mismatch、reserved bit、VP9 frame marker 不正の失敗分類。
  - sample entry 用 metadata と codec string 用値の同一性。
- Rust oracle: 0004 が固定した pinned checkout の shiguredo/mp4-rs で上流 AV1 configOBUs・`black-av1-video.mp4`・VP8/VP9 短小 fixture を処理し、sample entry と codec string を比較する。oracle を実行できない環境では「未実行」と記録する。
- 差分は 0016 の canonical JSON 形式で比較し、不一致は field path まで特定して記録する。
- 手動確認: 生成した av01/vp08/vp09 sample entry を [0013](./0013-mp4-file-demux.md) の demux で読み戻し、track 情報が一致することを確認する（0013 完了後）。
- 証跡: 実行コマンド、結果分類、fixture checksum、実行環境を PR または artifact に残す。

## リスク

- データ形式: configOBUs と sample の size field 条件の混同が sample 解釈の破壊につながる。条件分岐を wbtest で固定し、fixture 比較で検出する。
- 互換性: codec string の profile/level 表記が 0011 と食い違う。値源を一本化し、差分を 0016 で検出する。
- 境界: LEB128 の長い整数と JS の Number 精度の境界で値がずれ得る。0000 の 64bit 比較規則と 0005 の checked arithmetic に従う。
- スコープ拡大: 必要欄のつもりで full decoder の処理が混入する。parse 対象を上流実装とテストで列挙し、レビューで確認する。
- 公開範囲: 未完成 codec の関数を公開すると対応済みと誤解される。README の partial 表記と公開 API の一致をテストする。
- ロールバック: 追加 module のみで既存 API 契約を変えない。問題時は該当 commit の revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] AV1/VP8/VP9 bitstream metadata 補助（av1C/vpcC 構築対応）を追加

## 注記

- upstream 対応物: [src/bitstream/av1.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/av1.rs)、[src/bitstream/vp8.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/vp8.rs)、[src/bitstream/vp9.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/vp9.rs)、[tests/test_bitstream_av1.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_av1.rs)、[tests/test_bitstream_vp8.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_vp8.rs)、[tests/test_bitstream_vp9.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_vp9.rs)。
- 関連: [0005](./0005-safe-bytes.md)（byte/bit 基盤）、[0010](./0010-sample-entries.md)（av1C/vpcC）、[0011](./0011-codec-strings.md)（codec string）、[0013](./0013-mp4-file-demux.md)（読み戻し確認）、[0024](./0024-bitstream-h264-h265.md) / [0025](./0025-bitstream-aac-opus.md)（並行 helper）、[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)（検証）。
- 実装時の未決事項: ファイル名と package 分割は 0002 で確定する。対象 OBU / frame header フィールドの正確なリストと public API 名は実装時に確定し、README の partial 表記へ反映する。
- 証跡: oracle 比較ログ、fixture checksum、`moon test` の結果分類を issue または PR に添付する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
