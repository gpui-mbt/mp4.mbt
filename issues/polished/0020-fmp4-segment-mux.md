# [P1 / M2] Fmp4SegmentMuxerのinit/media生成とオフセット管理

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0020-fmp4-segment-mux
Priority: P1
Milestone: M2
Depends on: [0010](./0010-sample-entries.md), [0017](./0017-fmp4-boxes.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

fMP4の初期化segment（`ftyp+moov/mvex`）とメディアsegment（`moof+mdat`）を生成する`SegmentMuxerOptions` / `Fmp4SegmentMuxer`を移植する。callerがpayloadを配置できるよう、返却値はbox bytesと`Sample.data_offset`（当該mdat payload先頭からの相対位置）に限定する。

## 背景

- 現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コード・動作テストはない。本issueはM2（fMP4）のmux側の主力で、[0017](./0017-fmp4-boxes.md)（fMP4 box）と[0010](./0010-sample-entries.md)（sample entry）の上に構築する。
- 上流参照: [src/mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_fmp4_segment.rs)、[tests/test_mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_fmp4_segment.rs)。
- データ契約（0000の変更できないデータ契約3）: `Fmp4SegmentMuxer.create_media_segment_metadata`の入力offsetは当該mdat payload先頭からの相対位置とし、返り値にpayloadを含めずcallerが連結する。Mp4FileMuxerのファイル絶対位置（[0022](./0022-mp4-file-mux.md)）と取り違えない。
- 上流はRust例（0021）とテストでmux→demuxのroundtripを検証している。本issueはその生成側を担う。

## 問題

- MoonBit側にfMP4 segment muxerがないため、0021の統合exampleとM2のmux→demux相互読込（0000のM2 gate）が成立しない。
- fMP4のoffset基準は複数ある（trafのbase-data-offset、trunのdata-offset、caller配置位置）。相対位置の契約を固定しないと、生成物が構造的に正常に見えたままpayloadを別範囲へ指す事故が起きる。
- 最初のsampleからtrack kind/timescale/sample entryを学習する契約、segment間のdecode time・sequence number・sample entry indexの更新規則（[0017](./0017-fmp4-boxes.md)）が未定義。
- CTTSはfMP4ではsigned i32基準で、通常MP4の広いunsigned範囲と混同すると値域を誤る。

## 目標

- `Fmp4SegmentMuxer`がinit segmentを発行し、`create_media_segment_metadata(samples)`がmoof/mdatヘッダーを返し、各sampleの`data_offset`がmdat payload先頭からの相対位置として復元可能である。
- 複数segment・複数track（Audio/Video/Subtitle各1）でdecode timeの累積、sequence number、sample entry index、`trun` flags、`tfdt`が上流規則どおりに更新される。
- optionalな`sidx`/`mfra`を段階的に生成できる。
- Rust oracleとのroundtrip比較で、MoonBit生成のsegmentを0018のdemuxerおよびRustで読み戻せる。

## 対象外

- 実コーデックのエンコード、QUIC/HLS配信はしない。
- 通常MP4のmux（0022）とHybrid MP4の`advance_position`（0027）。
- セグメントdemux（0018）とfMP4 file demux（0019）の再実装。
- sample payloadの生成・加工。payloadはraw bytesとして呼出側が渡す。

## 提案する方針

- upstream互換のAPIを`SegmentMuxerOptions` / `Fmp4SegmentMuxer`として実装する。最初のsampleからtrack kind、timescale、sample entryを学習し、`init_segment_bytes()`は観測済みの内容だけを出す。
- `create_media_segment_metadata(samples)`は`moof`と`mdat` headerだけを返す。payload本体は呼出側に配置を要求し、`sample.data_offset`は当該mdat payload先頭からの相対位置として検証する。
- trackごとにdecode_time、sequence number、sample entry index、`trun` flags、`tfdt`を段階的に生成する。optionalな`sidx`/`mfra`は上流のオプションに合わせて実装時に有効化条件を確定する。
- 同一TrackKindは現状1トラック（Audio/Video/Subtitle各1）。同一segment・同一track内でsample entryが混在するケースは上流互換の制約を検証し、許否をテストで固定する（暫定は明示エラー）。
- CTTSの書込範囲はfMP4ではsigned i32を基準とし、通常MP4（[0022](./0022-mp4-file-mux.md)）の広いunsigned CTTS範囲と混同しない。境界値は[0017](./0017-fmp4-boxes.md)のbox契約と整合させる。
- offsetの定義が混ざる余地を減らすため、`data_offset`の基準をAPIドキュメントと型コメントに明記する。ファイル名・モジュール名（例: `src/mux`配下）は0002のパッケージ確定に合わせ、実装時に確定して本issueへ追記する。

## 受け入れ条件

- [ ] Given 学習用の最初のsampleと`SegmentMuxerOptions`, when `Fmp4SegmentMuxer`を構築して`init_segment_bytes()`を呼ぶ, then 観測済みtrackのsample entry・timescaleを含むinit segmentが得られ、未観測trackは含まれない。
- [ ] Given 複数segmentのsample列, when `create_media_segment_metadata(samples)`を呼ぶ, then 返却bytesにpayloadが含まれず、各sampleの`data_offset`がmdat payload先頭からの相対位置を指す。
- [ ] Given 生成したinit+media segment, when MoonBitのsegment demuxer（0018）で読み戻す, then 各sampleのbytesとtimestampが元の入力と一致する。
- [ ] Given AVC1+Opusの複数segment, when segment間でdecode timeを継続する, then sequence number・`tfdt`・sample entry indexが上流規則どおりに更新される。
- [ ] Given EmptyTracks/EmptySamples、timescale mismatch、sample length不一致、offset gap/overlap, when muxする, then 部分的に壊れたsegmentを出さず明示エラーで拒否する。
- [ ] Given `sidx`/`mfra`を有効にしたsegment, when 索引からsample位置を解決する, then moofのoffsetとpayload位置が一致する。
- [ ] Given fMP4でCTTSを書くsample, when 値がsigned i32の境界域にある, then 通常MP4と異なるsigned i32基準の規則で受理・拒否が固定される。

## テスト計画

- `moon check` と `moon test --target native` を実行し、PASS / FAIL / 未実行を記録する（現時点では`moon.mod`と実装がなく実行不能。0002完了後に有効化する）。
- unit/wbtest: sample列からmoof/mdatを生成した結果のoffset、`trun` flags、`tfdt`、sequence number、sample entry indexの継続更新を固定する。負例（EmptyTracks、EmptySamples、timescale mismatch、length不一致、offset gap/overlap）のerror種別を固定する。
- roundtrip: 生成init+mediaをself-hostの`Fmp4SegmentDemuxer`（[0018](./0018-fmp4-segment-demux.md)）で読み戻し、bytes・timestamp・keyframeを比較する。Rust oracle（[0004](./0004-oracle-fixtures.md)）でも同じsegment群を読み、両経路の観測値を比較する。oracle未整備の間は「未実行」と記録する。
- 相互運用の証跡として、Rust側の生成したsegmentをMoonBitで読み、MoonBit生成のsegmentをRustで読む両方向をCI（[0003](./0003-ci-contract.md)）で確認する。実行できない環境では未実行理由つきで記録する。
- 検証状態はPASS / FAIL / 未実行を混同せず、実行コマンド・OS/arch・コミットSHA・fixture checksumとともに結果へ残す。
- 生成した一時ファイルはworkspace内（例: `target/`配下）に限定し、fixtureを上書きしない。

## リスク

- offset基準の混同により、構造は妥当に見えるがpayload位置だけ誤ったsegmentを生成する。相対位置契約をテストとドキュメントで固定し、Rust oracleとのroundtripで検出する。
- CTTSの値域を通常MP4と共通型で扱い誤る。fMP4はsigned i32基準の境界値をwbtestで固定し、[0022](./0022-mp4-file-mux.md)と別契約であることを明記する。
- sample entryの混在・変更の扱いが上流と分岐する。M2では明示エラーに倒し、受理が必要になった時点で別issueに切り出す。
- `sidx`/`mfra`の索引がmoofとずれる。索引から解決したoffsetを必ずmoof/mdat実体と突き合わせる検証を置く。
- ロールバック: muxの新規コード追加が中心で、既存のread-only API契約（M1のdemux系）を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] fMP4 segment muxer（init/media生成とoffset管理）を追加

## 注記

- 上流参照: [src/mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_fmp4_segment.rs)、[tests/test_mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_fmp4_segment.rs)。
- 関連: [0010](./0010-sample-entries.md)（sample entry）、[0017](./0017-fmp4-boxes.md)（moof/traf/trun/tfdt）、[0018](./0018-fmp4-segment-demux.md)（roundtrip相手）、[0021](./0021-fmp4-example.md)（統合example）、[0022](./0022-mp4-file-mux.md)（通常MP4、CTTS境界の対照元）。
- 未決事項（実装時に確定して追記する）: モジュール/ファイル名、`sidx`/`mfra`の既定有効条件、sample entry混在時の扱い。
- 証跡: roundtripの比較結果と使用fixtureのchecksumをログまたはartifactに残し、失敗はoffsetの差分が追える形で記録する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
