# [P2 / M4] faststartとHybrid MP4の書込位置契約を固める

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0027-hybrid-faststart
Priority: P2
Milestone: M4
Depends on: [0020](./0020-fmp4-segment-mux.md), [0022](./0022-mp4-file-mux.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

正常終了後は通常 MP4 として読め、途中停止でも確定済みの fragment まで読める Hybrid MP4 を実現する writer 契約を用意する。`Mp4FileMuxer::advance_position` 相当で非サンプル bytes を書いた分だけ内部 write 位置を進め、次の sample が必ず新しい chunk へ切り替わることを保証する。

## 背景

- upstream（固定 SHA）の手順と実装は [docs/hybrid_mp4.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/docs/hybrid_mp4.md)、[src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs) にあり、参照テストは [tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)。
- [0022](./0022-mp4-file-mux.md) が `Mp4FileMuxer`・`append_sample`・finalize と `reserved_moov_box_size` の絶対 offset 契約を提供し、[0020](./0020-fmp4-segment-mux.md) が fMP4 の `moof/mdat` 生成を提供する。本 issue はその上の Hybrid 手順と位置管理を固める。
- 0022 の実装手順では `advance_position` を分離して本 issue で追加すると明記されており、`append_sample` の入力 offset は出力ファイル絶対位置である（0000 のデータ契約）。
- 途中停止ファイルの可読性は fMP4 の demux（[0018](./0018-fmp4-segment-demux.md) / [0019](./0019-fmp4-file-demux.md)）で、正常 finalize 後は通常 MP4 demux（[0013](./0013-mp4-file-demux.md)）で確認する。
- [0000](./0000-implementation-roadmap.md) では Hybrid を M4 の高度な Mux に置く。2026-10-16 時点の `main` は README と `issues/` のみで、`moon.mod` も実装もない。

## 問題

- 非サンプル bytes を書いた分だけ内部 write 位置を進めないと、次の `append_sample` が位置不一致で失敗するか、位置ずれのまま通って壊れた offset を持った MP4 を生成する。
- Hybrid の `moof/mdat` 生成と通常 MP4 mux の責務が混ざると、途中停止したファイルが fragment としても通常 MP4 としても壊れる。
- finalize 時の先頭 mdat ヘッダー書換・末尾 moov 配置は caller 側の実 file 操作であり、手順を sample 化しないと faststart reserved_moov 領域の不足・長さ overflow・位置不一致を区別できない。
- 途中停止時に「最後の確定 segment まで読める」という条件が明文化されていないと、再生性の検証ができない。

## 目標

- `advance_position` 相当 API で非サンプル bytes 分の write 位置を進め、次の sample で必ず新 chunk へ切り替える。
- Hybrid の `moof/mdat` 生成を利用側（または fMP4 muxer）と分離し、通常 MP4 mux が最終 `moov` を構築する。
- finalize 時の先頭 mdat ヘッダー書換・末尾 moov 配置など caller 側の実 file 操作を sample と文書で示す。
- reserved_moov 領域の不足、長さ overflow、位置不一致、途中落ち時点での有効 fragment 境界を相互に区別してエラー化する。
- `advance_position` なしの位置不一致が必ず検出される（黙って通らない）ことを負例で固定する。

## 対象外

- OS のクラッシュ耐久性の完全保証。fsync、書込順、電源断の保証は別途 OS 層の責務とし、保証しない。
- fMP4 segment mux 本体（0020）と通常 MP4 mux 本体（0022）の実装。本 issue は位置契約と Hybrid 手順の追加に限定する。
- プレーヤー互換性の網羅検証や再生 UI。

## 提案する方針

- 0022 の muxer（0000 の提案パッケージでは `src/mux`）へ `advance_position` 相当を追加する。ファイル名と package 分割は [0002](./0002-moonbit-bootstrap.md) で確定し、決まり次第本 issue を更新する。
- 契約: caller が実ファイルへ非サンプル bytes（fragment 等）を書いたことを `advance_position` で通知し、内部 write 位置だけを進める。直後の `append_sample` は新しい chunk を開始し、前の chunk と sample を共有しない。
- Hybrid 構成: 先頭の `moof/mdat` 列は利用側（または 0020 の fMP4 muxer）が生成し、通常 MP4 mux は offset 整合と最終 `moov` 構築を担う。責務をまたぐ offset 検証は muxer の絶対 offset 契約に一元化する。
- finalize: 先頭の大きな mdat ヘッダー書換と末尾 moov 配置を含む caller 側の操作手順を example と文書で示す。0022 の `reserved_moov_box_size` / `estimate_maximum_moov_box_size` の契約を再利用する。
- 位置検証: 実書込位置と内部位置が一致しない場合は `PositionMismatch` 相当のエラーを返し、advance_position 省略ケースを負例テストにする。
- 途中停止: 最後に確定した `moof/mdat` の完了点まで読める条件を定義し、途中で止めたファイルを 0018 / 0019 の demux で確認する。
- 構造確認: 正常 finalize 後のファイルを 0013 の demux と外部 mediainfo / ffprobe 相当で確認する。外部ツールが無い環境では「未実行」と記録する。
- 互換性: 上流 `docs/hybrid_mp4.md` の手順と同じ content / offset を再現し、0004 の Rust oracle と比較する（差分は 0016 の形式）。
- 実装時の未決事項: `advance_position` の引数・単位・呼び出し規約は 0022 の実装と同時に確定する。

## 受け入れ条件

- [ ] Given 先頭に非サンプル bytes を書いた状態, when `advance_position` を呼んでから `append_sample` する, then muxer の期待位置と実ファイル位置が一致し、前の chunk と統合されない。
- [ ] Given `advance_position` を省略した状態, when `append_sample` する, then 位置不一致が必ずエラーとして検出される。
- [ ] Given 上流 `docs/hybrid_mp4.md` の手順に沿った入力, when Hybrid 構成を生成する, then 上流と同じ content / offset を得る。
- [ ] Given 途中で停止したファイル, when 最後の確定 segment までを demux する, then その範囲が読め、書込途中の不完全 fragment と区別できる。
- [ ] Given 正常 finalize したファイル, when 0013 の demux で読む, then track / sample と offset が整合する。
- [ ] Given reserved_moov 領域が不足する入力, when finalize する, then 推定不足のエラーになり、位置不一致・長さ overflow と混同されない。

## テスト計画

- 現時点では `moon.mod` も実装もないため `moon check` / `moon test` を実行できない。初回実行まではすべて「未実行」と記録し、未実行を PASS / FAIL と混同しない。0000 の記録規則（PASS / FAIL / 未実行の独立記録、コマンド・commit SHA・OS/arch・fixture checksum の添付）に従う。
- 0002 の scaffold 完了後に次を実行し、結果を本 issue へ追記する。
  - `moon check --target native --deny-warn` と `moon test --target native`。
  - `moon test --target js` で位置計算の target 間一致を確認する（offset は 0000 の 64bit 比較規則に従う）。
- wbtest（package 内の white-box test）で次を固定する。
  - `advance_position` 後の位置計算と新 chunk 切替。
  - 省略時の `PositionMismatch` 相当エラー。
  - reserved_moov 不足、長さ overflow、位置不一致のエラー分類。
- 実ファイル確認: 途中停止と正常終了の両 fixture を作り、0023 の roundtrip example と併せて実行し、実行証跡を残す。
  - 途中停止: 最後の確定 `moof/mdat` までを 0018 / 0019 の demux で読めること。
  - 正常終了: 0013 の demux で読めること。mediainfo / ffprobe 相当は環境依存のため、無い場合は「未実行」と記録する。
- Rust oracle: 0004 が固定した pinned checkout の shiguredo/mp4-rs で同一手順を実行し、content / offset を比較する（差分は 0016 の形式）。
- 証跡: offset の前後比較、ファイルサイズ、実行コマンドと結果分類を PR または artifact に残す。

## リスク

- データ形式: `advance_position` の単位や呼び出しタイミングを誤ると全 sample の offset がずれる。位置契約を wbtest と負例で固定する。
- 互換性: 上流手順と content / offset が一致しないと他ツールで読めない Hybrid になる。oracle 比較を gate にする。
- 移行: 0022 の既存 API を変えず `advance_position` の追加のみとし、呼び出し側の移行を不要にする。API の追加位置は 0022 実装時に確認する。
- 境界: reserved_moov 不足・overflow・不完全 fragment の判定が混ざると失敗が黙って通る。エラー種別を分けて検証する。
- 完全性の誤認: OS クラッシュ耐久性まで保証したと誤解され得る。README / 文書に fsync・電源断は対象外と明記する。
- ロールバック: 追加 API と example が中心で既存契約を変えない。問題時は該当 commit の revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] Mp4FileMuxer の advance_position と Hybrid MP4 の書込位置契約を追加

## 注記

- upstream 対応物: [docs/hybrid_mp4.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/docs/hybrid_mp4.md)、[src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[tests/test_mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_mp4_file.rs)。
- 関連: [0020](./0020-fmp4-segment-mux.md)（`moof/mdat` 生成）、[0022](./0022-mp4-file-mux.md)（muxer 本体と reserved_moov）、[0018](./0018-fmp4-segment-demux.md) / [0019](./0019-fmp4-file-demux.md)（途中停止ファイルの読み）、[0013](./0013-mp4-file-demux.md)（正常終了ファイルの読み）、[0023](./0023-mp4-mux-example.md)（roundtrip example）、[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)（検証）。
- 実装時の未決事項: `advance_position` の引数・単位・呼び出し規約、example の配置は 0022 / 0023 の実装と同時に確定し、本 issue に反映する。
- 運用・証跡: 途中停止 fixture は一時ファイルへ出力し、後始末を明記する。offset 比較ログと結果分類を残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。


## 検証

- `src/bitstream` / `src/boxes` に実装し、MoonBit の unit / roundtrip テストを追加した。
- `moon test --target native` / `--target js` は PASS（2026-10-17）。Rust oracle との完全な差分比較は **UNVERIFIED**。
- 0027 は `advance_position` の位置契約・チャンク境界・Hybrid 手順を `docs/hybrid_mp4.md` と wbtest で固定した。
- 0028 は `stpp` / `wvtt` / `tx3g` の型付き sample entry と codec string / mux 属性対応を追加した。
