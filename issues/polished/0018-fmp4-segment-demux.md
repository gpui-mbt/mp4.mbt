# [P1 / M2] 初期化＋メディアセグメントのSans I/O demuxerを作る

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0018-fmp4-segment-demux
Priority: P1
Milestone: M2
Depends on: [0010](./0010-sample-entries.md), [0017](./0017-fmp4-boxes.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

init segment（`ftyp` + `moov`/`mvex`）と後続の `moof`/`mdat` 列からsample metadataとpayload位置を取り出す `Fmp4SegmentDemuxer` 相当をSans I/Oで実装する。返す `data_offset` は `handle_media_segment()` へ渡したバッファ先頭からの相対位置であり、ファイル絶対位置と混同しない。

## 背景

- 上流参照: [src/demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_fmp4_segment.rs)、[tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)。
- 上流API（固定コミットで確認できる範囲）: `handle_init_segment(data)` がトラック情報とtrex既定値を初期化し（2回目はInvalidState）、`tracks()` が `&[TrackInfo]` を返し、`handle_media_segment(data)` が `Vec<Sample>` を返す。1回の呼び出しで扱えるのは単一の `moof`+`mdat` ペアのみである。
- 上流の `Sample.data_offset` は渡したデータスライス先頭からの相対位置で、読み飛ばしたboxの分は加算しない。通常MP4 demuxer（[0013](./0013-mp4-file-demux.md)）のファイル絶対位置とは基準が異なる（0000のデータ契約2）。
- [0017](./0017-fmp4-boxes.md)（box型）と[0010](./0010-sample-entries.md)（sample entry）を入力に、[0019](./0019-fmp4-file-demux.md)と[0020](./0020-fmp4-segment-mux.md)が本issueのAPI・offset契約を共有する。現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コードはない。

## 問題

- fMP4のinit/mediaの状態遷移と相対offsetの契約が実装されておらず、segment単位のdemuxができない。
- skip対象トラック・複数traf・default値継承・sample entry変更通知の扱いが未定義だと、正しいセグメントを誤って失敗させる。
- 相対offsetと絶対offsetを混同すると、payloadが別範囲を指す（0000の代表的リスク。0013/0018/0020/0022の横断リスク）。

## 目標

- `handle_init_segment` / `tracks` / `handle_media_segment` 相当のAPIで、上流のsegment demuxと同じ観測値を返す。
- `data_offset` は常に当該 `handle_media_segment()` 入力バッファ先頭からの相対位置とし、ファイル絶対位置と混同しない。
- sample entryの最初の通知と変更時通知、keyframe、DTS/CTTS/timescaleを再現する。
- 初期化なしメディア投入、segment内broken offset、multiple traf、不明track IDといった失敗を分類して返す。
- sample payloadを正確にsliceして取り出せる。

## 対象外

- 単一巨大ファイルのincremental demux（[0019](./0019-fmp4-file-demux.md)で実装する）。
- segmentの生成・mux（[0020](./0020-fmp4-segment-mux.md)）。
- codec payloadのdecodeと再生。
- HLS/DASH等の配信層。

## 提案する方針

- 状態は「未初期化 / 初期化済み」の2状態とし、初期化前の `tracks()`・`handle_media_segment()` はInvalidState相当のエラーにする。`handle_init_segment` の2回目も同様とする（上流と同じ）。
- init segment: `ftyp` は任意（あれば読み飛ばす）、`moov` 必須、`mvex` 必須。handler typeがvide/soun/subt/textのtrackを登録し、それ以外はsampleを返さないskip対象としてtrack_idとtrex（欠落許容）を記録し、そのtrafを安全に読み飛ばす。登録対象trackでtrex欠落はエラー、`stsd` のentriesが空もエラー（上流の検証に対応）。登録失敗時に部分状態を残さない。
- media segment: `moof` までtop-level boxを種別を問わず読み飛ばし（先頭の `ftyp`/`moov`/`mdat` も読み飛ばし対象）、`moof` が見つからないまま末尾へ達したらエラー。`moof` より前にsize=0のbox（32bitのsize=0、またはsize=1+largesize=0）があればエラー。`moof` の後も `mdat` まで同様に読み飛ばし、`mdat` より先に別の `moof` が出た場合はエラー。`mdat` の後は入力末尾まで読み飛ばし、後続 `moof` はエラー、32bitのsize=0は末尾まで続くboxとして受け付ける（上流仕様）。
- offset継承: tfhdにbase_data_offsetがあればその値（入力先頭基準の相対）、`default_base_is_moof=true` ならmoof先頭、どちらでもなければ直前trafのデータ末尾（最初のtrafはmoof先頭）を基準にする。trunのdata_offsetは基準位置への加算、2番目以降のtrunでdata_offsetがなければ直前trunのデータ末尾から継続する。
- sample値の継承: sizeはtrun → tfhd.default_sample_size → trex.default_sample_size、durationも同様、flagsはrun先頭サンプルでfirst_sample_flagsを優先し、それ以外はtrun_sample.flags → tfhd.default_sample_flags → trex.default_sample_flags。keyframeはnon-syncフラグの否定とする。sample_description_indexはtfhd → trex.default_sample_description_indexの順で、0や範囲外はエラー。
- sample entryは「各トラックの最初のサンプル」と「sample_description_indexが変わったサンプル」にのみ `Some` を付ける。同一 `moof` 内に同じtrackのtrafが複数ある場合は呼び出し内の直前trafと比較する。
- sample範囲がmdat境界を越える場合はエラー。エラーを返した場合は内部状態を進めず、同じインスタンスで処理を継続できるようにする（上流契約）。API名・エラー型・ファイル配置は実装時に確定し、本issueへ追記する。

## 受け入れ条件

- [ ] Given 上流black-h264-fmp4 fixtureと生成init/media群, when initを処理してからmediaを渡す, then 全sampleのoffset/size/DTSがRust oracleと一致する。
- [ ] Given moof/mdatの周辺にstyp/sidx/freeがあるセグメント, when 処理する, then 相対data_offsetがbox挿入の影響を受けずに一致する。
- [ ] Given 初期化なしでmediaを渡す、mdatが存在しない、trun範囲がmdat外、空payload, when 処理する, then それぞれ定義済みエラーで拒否される。
- [ ] Given 複数セグメントを連続処理する, when decode timeとentry変更を追跡する, then entry通知が変更時のみになり、DTS/timescaleが上流と同じ値で継続する。
- [ ] Given skip対象トラックのtrafを含むsegment, when 処理する, then 登録対象のsampleだけが返り、読み飛ばしが後続trafの基準位置計算を壊さない。
- [ ] Given エラーを返した呼び出しの後, when 同じインスタンスへ再びmediaを渡す, then 内部状態が変わっておらず、entry通知の結果が正常時と同じになる。
- [ ] Given 複数traf・data_offsetの有無が混在するsegment, when 処理する, then sample payloadを呼出側が正確にsliceして取り出せる。

## テスト計画

- 現時点では `moon.mod` がなく、以下は0002・0004・0017完了後に実行する。PASS / FAIL / 未実行を混同せず記録する。
  - `moon check --target native --deny-warn` と `moon test --target native`（および `--target js`）を実行し、結果とツールチェーンのバージョンを記録する。
  - wbtest: offset継承の3モード（明示base_data_offset / default_base_is_moof / 直前traf末尾）、trun data_offsetの連続、sample entry通知条件、エラー時に状態を進めないことを固定バイト列で検証する。
- [0004](./0004-oracle-fixtures.md)のoracleで、[tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)に対応するfixture（上流black-h264-fmp4と生成init/media群）を処理し、sampleのoffset/size/DTS/keyframe/CTOを全件比較する。
- 負例（initなし/mdatなし/範囲外trun/空payload/size=0/後続moof/不明track_id）を固定バイト列のテストとして追加し、エラー分類の一致を確認する。
- 大容量mdatはsegmentとして受け取った範囲だけを扱う契約を確認し、file全体の読込を要求しないことを固定する。
- 現時点では上記いずれも実行できない。fixtureは帰属確認済みのものに限定し、未確認素材では「未実行」と理由を記録する（0001/0004）。

## リスク

- 相対/絶対offsetの混同。戻り値の基準をdoc commentとテストで固定し、[0019](./0019-fmp4-file-demux.md)の絶対offset変換と関数を分けて扱う。
- skip対象trafのデータ末尾計算を誤ると、後続trafの基準位置がずれる。trex欠落時は必要な場面でエラーにし、testsで固定する。
- 読み飛ばし範囲を仕様より広く/狭く取ると、正しいファイルを拒否するか壊れたファイルを通す。size=0・largesize=0・moof重複の境界をwbtestで固定する。
- 複数traf・複数trunの並びでDTSがずれる。継承順を一元化した関数で計算し、oracle全件比較で検出する。
- ロールバック: 新規demuxerの追加が中心で、[0013](./0013-mp4-file-demux.md)の公開API契約を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] fMP4のinit/mediaセグメントSans I/O demuxer（相対data_offset・skip track対応）

## 注記

- 上流参照: [src/demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_fmp4_segment.rs)、[tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)。
- 関連: [0010](./0010-sample-entries.md)、[0013](./0013-mp4-file-demux.md)、[0017](./0017-fmp4-boxes.md)、[0019](./0019-fmp4-file-demux.md)、[0020](./0020-fmp4-segment-mux.md)。
- 運用: fixture checksum・upstream SHA・実行コマンドを証跡に残す。エラー分類の一致はPASS/FAILで記録し、未実行は理由付きで残す。
- 未決事項（実装時に確定して追記する）: API名・エラー型・ファイル配置、読み飛ばしで許容するbox種別の最終範囲。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
