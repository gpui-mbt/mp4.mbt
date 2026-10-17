# [P1 / M4] stpp/wvtt/tx3g字幕trackを移植する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0028-subtitle-sample-entry
Priority: P1
Milestone: M4
Depends on: [0008](./0008-movie-track-boxes.md), [0010](./0010-sample-entries.md), [0018](./0018-fmp4-segment-demux.md), [0022](./0022-mp4-file-mux.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

上流が対応する 3 種の字幕 track（`stpp` = TTML/IMSC、`wvtt` = WebVTT cue boxes、`tx3g` = 3GPP Timed Text）を読取・書込の両方で扱い、表示 UI では subtitle として列挙できるようにする。sample entry と上流が扱う子 box を型付きで parse/encode し、track handler / media header の対応と metadata を保持する。

## 背景

- upstream（固定 SHA）では [docs/subtitle.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/docs/subtitle.md) が字幕対応の仕様を示し、[src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs) に字幕 sample entry が、[src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs) / [src/mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_fmp4_segment.rs) に mux 側の扱いがある。
- [0008](./0008-movie-track-boxes.md) が track / handler / media header を、[0010](./0010-sample-entries.md) が sample entry 基盤を提供する。0010 の非対象に「字幕 sample-entry は 0028 で独立拡張」と明記されており、本 issue がその拡張を担う。
- mux / demux の利用側は [0022](./0022-mp4-file-mux.md)（通常 MP4）と [0018](./0018-fmp4-segment-demux.md)（fMP4 segment）、mux 側の fMP4 は 0020 が担う。sample payload は raw bytes のまま、時系列 metadata は既存の track / sample 契約で扱う。
- 0000 のデータ契約では同一 TrackKind は 1 トラックまでであり、字幕もこの制約に含まれる。
- [0000](./0000-implementation-roadmap.md) では字幕を M4 の補助機能に置く。2026-10-16 時点の `main` は README と `issues/` のみで、`moon.mod` も実装もない。

## 問題

- 字幕 sample entry がないと、字幕 track は unknown entry の raw 保持に留まり、track kind の識別・metadata の型付き参照・mux ができない。
- handler / media header の対応（stpp=subt/sthd、wvtt=text/sthd、tx3g=text/nmhd）を誤ると、上流 fixture や他ツールとの互換が崩れる。
- 同一 track に非両立形式を混ぜた場合の拒否（`MixedSampleEntries` 相当）が未定義だと、壊れた track を受理し得る。
- language / name 等の metadata を保持しないと、表示 UI の subtitle 列挙で情報が欠落する。
- 字幕も含めた「同一 TrackKind 1 トラック」制約を README に明記しないと、多言語字幕 mux への対応と誤解される。

## 目標

- `stpp`・`wvtt`・`tx3g` の sample entry と、上流が扱う子 box（wvtt の cue boxes 等）を型付きで parse/encode できる。
- track handler と media header の対応（stpp=subt/sthd、wvtt=text/sthd、tx3g=text/nmhd）を維持する。
- 1 つの字幕 track に非両立形式を混ぜた場合は `MixedSampleEntries` 相当で拒否し、同一 handler / media_header の合法変種は受け入れる。
- language / name 等の metadata と、字幕 sample の DTS/duration/keyframe/payload bytes を mux / demux で保存する。
- M4 字幕機能表に対応 3 形式と制限（1 トラック制約、raw payload 扱い）を明示する。

## 対象外

- wvtt cue / TTML XML / tx3g style の描画パーサ。sample payload は raw bytes のままとし、描画パーサを実装に含めない。
- 字幕テキストの意味解釈・字幕レンダリング・多言語字幕の同時 Mux。
- 字幕の表示時間編集やタイミング補正（parse / 保存のみ）。
- 映像・音声 bitstream helper（[0024](./0024-bitstream-h264-h265.md) / [0025](./0025-bitstream-aac-opus.md) / [0026](./0026-bitstream-av1-vp8-vp9.md)）。

## 提案する方針

- 配置は 0000 の提案パッケージに従い `src/boxes`（sample entry、upstream `src/boxes_sample_entry.rs` 相当）と `src/demux` / `src/mux` の該当モジュールへ追加する。ファイル名と分割は [0002](./0002-moonbit-bootstrap.md) で確定し、決まり次第本 issue を更新する。
- sample entry: `stpp`（TTML/IMSC 用）・`wvtt`（WebVTT cue boxes 用）・`tx3g`（3GPP Timed Text 用）の型と子 box を parser/encoder に追加する。形式ごとのフィールドと子 box の対応範囲は upstream 実装と `docs/subtitle.md` を基に実装時に確定する。
- track 対応: 0008 の TrackKind へ接続し、handler / media header の組（stpp=subt/sthd、wvtt=text/sthd、tx3g=text/nmhd）を維持する。未知 handler の扱いは既存方針を変えない。
- 混在拒否: 1 track 内で非両立形式を検出したら `MixedSampleEntries` 相当のエラーを返す。同一 handler / media_header の合法変種は拒否しない。
- metadata / payload: language / name 等を保持し、sample payload は raw bytes のまま mux / demux 間で保存する。sample entry 変更の通知契約は 0010 / 0018 / 0022 と整合させる。
- 制限の明示: 同一 TrackKind 1 トラック（字幕も含む）と raw payload 扱いを README の M4 字幕機能表に記載する。
- 互換性: 上流 `docs/subtitle.md` に整合する fixture / テストを用意し、[0016](./0016-rust-moonbit-diff.md) の差分比較で既知 / 未知判定と metadata を照合する。
- 実装時の未決事項: 各形式の子 box の対応範囲と metadata 項目、public API 名は実装時に確定する。

## 受け入れ条件

- [ ] Given `stpp`/`wvtt`/`tx3g` の sample entry 入力, when encode→decode する, then 型・子 box 構造・language/name 等の metadata が保持される。
- [ ] Given stpp=subt/sthd、wvtt=text/sthd、tx3g=text/nmhd の組, when track を parse する, then TrackKind が subtitle として識別される。
- [ ] Given 1 つの字幕 track に stpp と tx3g の非両立混在, when parse する, then `MixedSampleEntries` 相当のエラーで拒否される。
- [ ] Given 同一 handler / media_header の合法変種, when parse する, then 拒否されず受理される。
- [ ] Given 字幕 sample の DTS/duration/keyframe/payload bytes, when 0022 / 0018 の mux→demux roundtrip する, then 値が保存される（依存実装の完了後）。
- [ ] Given README の M4 字幕機能表, when 対応形式と制限を確認する, then 3 形式・1 トラック制約・raw payload 扱いと非対象が明示されている。

## テスト計画

- 現時点では `moon.mod` も実装もないため `moon check` / `moon test` を実行できない。初回実行まではすべて「未実行」と記録し、未実行を PASS / FAIL と混同しない。0000 の記録規則（PASS / FAIL / 未実行の独立記録、コマンド・commit SHA・OS/arch・fixture checksum の添付）に従う。
- 0002 の scaffold 完了後に次を実行し、結果を本 issue へ追記する。
  - `moon check --target native --deny-warn` と `moon test --target native`。
  - `moon test --target js` で sample entry の parse/encode が target 間で一致することを確認する。
- wbtest（package 内の white-box test）で次を固定する。
  - 3 形式の sample entry encode/decode と子 box 構造。
  - handler / media header 対応と TrackKind 識別。
  - 非両立混在の拒否、合法変種の受理。
  - language / name metadata の保持、未知 subtype の raw 保持（0010 の既存挙動）に回帰がないこと。
- 上流整合: 0004 が固定した fixture と `docs/subtitle.md` の記述を基に、encode/decode と track kind の観測値を比較する。fixture は帰属を確認してから追加する。
- Rust oracle / 差分: 0016 の canonical JSON 形式で sample entry・metadata・失敗分類を照合する。oracle を実行できない環境では「未実行」と記録する。
- 手動確認: [0015](./0015-web-mp4-dump.md) の Browser MP4 Dump で字幕 track が subtitle として列挙されることを確認する（0015 完了後）。
- 証跡: 実行コマンド、結果分類、fixture checksum、実行環境を PR または artifact に残す。

## リスク

- データ形式: 子 box 構造や sample entry の解釈差で roundtrip が崩れる。encode/decode の対テストと oracle 比較で検出する。
- 互換性: handler / media header の対応を誤ると他ツールで読めない。`docs/subtitle.md` と 0016 の差分で固定する。
- 境界: 混在拒否を厳しくしすぎると合法変種を拒否し、緩すぎると壊れた track を受理する。両方向のテストを置く。
- 移行: 0010 の unknown entry raw 保持を変えると既存 fixture の読みに回帰し得る。既存挙動を維持し、回帰テストを追加する。
- 期待値のずれ: 多言語字幕 mux に対応したと誤解される。README / UI の文言で 1 トラック制約を明示する。
- ロールバック: 追加の box 型中心で既存 API 契約を変えない。README の機能表更新は独立 commit にすると戻しやすい。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] stpp/wvtt/tx3g 字幕 sample entry と字幕 track 対応を追加

## 注記

- upstream 対応物: [docs/subtitle.md](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/docs/subtitle.md)、[src/boxes_sample_entry.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/boxes_sample_entry.rs)、[src/mux_mp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs)、[src/mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_fmp4_segment.rs)。
- 関連: [0008](./0008-movie-track-boxes.md)（track/handler）、[0010](./0010-sample-entries.md)（sample entry 基盤）、[0018](./0018-fmp4-segment-demux.md) / [0022](./0022-mp4-file-mux.md)（利用側）、[0020](./0020-fmp4-segment-mux.md)（fMP4 mux）、[0015](./0015-web-mp4-dump.md)（表示確認）、[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)（検証）。
- 実装時の未決事項: 各形式の子 box の対応範囲と metadata 項目、public API 名、ファイル分割は実装時に確定し、確定後に本 issue と README を更新する。
- 証跡: sample entry の encode/decode ログ、track kind 一覧、fixture checksum、`moon test` の結果分類を残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。


## 検証

- `src/bitstream` / `src/boxes` に実装し、MoonBit の unit / roundtrip テストを追加した。
- `moon test --target native` / `--target js` は PASS（2026-10-17）。Rust oracle との完全な差分比較は **UNVERIFIED**。
- 0027 は `advance_position` の位置契約・チャンク境界・Hybrid 手順を `docs/hybrid_mp4.md` と wbtest で固定した。
- 0028 は `stpp` / `wvtt` / `tx3g` の型付き sample entry と codec string / mux 属性対応を追加した。
