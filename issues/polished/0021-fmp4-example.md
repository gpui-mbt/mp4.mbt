# [P1 / M2] 上流examples/fmp4.rsのMux/Demux統合デモを移植する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0021-fmp4-example
Priority: P1
Milestone: M2
Depends on: [0018](./0018-fmp4-segment-demux.md), [0020](./0020-fmp4-segment-mux.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

`examples/fmp4`で、疑似H.264動画とOpus音声の複数segmentを決定的に生成し、MoonBit自身とRustで読み戻して比較する実行可能なintegration exampleを作る。生成物と比較結果をartifactとして保存し、READMEに参照コマンドを載せる。

## 背景

- 現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コード・exampleはない。exampleの実行結果は0000のM2 gate（複数segmentをRust/MoonBit双方で相互読込しpayload/時間が一致）の主要証跡になる。
- 上流参照: [examples/fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/fmp4.rs)、[tests/test_mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_fmp4_segment.rs)、[tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)。
- 上流exampleはmuxとdemuxを通しで実行し、segmentとsampleの対応を確認する。本issueはそのMoonBit実行形態と、Rust側との相互運用証跡を担う。
- 前提は[0018](./0018-fmp4-segment-demux.md)（segment demux）と[0020](./0020-fmp4-segment-mux.md)（segment mux）。Rust oracle・fixtureの扱いは[0004](./0004-oracle-fixtures.md)、CI実行は[0003](./0003-ci-contract.md)に従う。

## 問題

- muxとdemuxが個別に動いても、segment間の連続性（decode timeの累積、sample entryの引継ぎ、offset基準）を一括で確認する実行可能物がない。
- 生成物をRust側で読み戻す証跡がないと、MoonBit単独の自己整合バグ（同じ実装の思い込み）を検出できない。
- 疑似コーデックのpayloadはデコード可能な実メディアとは限らず、成果を「動画が再生できた」と誤報する危険がある。

## 目標

- 固定sampleからH.264 `avc1/avcC` とOpus `Opus/dOps` のsample entryを作り、複数segmentを決定的に出力する。
- 全segmentを`Fmp4SegmentDemuxer`で読み戻し、track kind、timestamp、payload bytes、sample count、keyframe、CTTSを比較する。
- Rust oracleが同じ生成物を受け入れることを実行可能な形で示し、artifactとREADMEに参照コマンドを残す。
- 比較が壊れた入力で確実にFAILする（検証が空回りしない）ことを示す。

## 対象外

- 実エンコード・デコード、再生・映像表示。疑似payloadはraw bytesとして扱う。
- QUIC/HLS配信、通常MP4のmux（[0022](./0022-mp4-file-mux.md) / [0023](./0023-mp4-mux-example.md)）、[0029](./0029-webcodecs-transcode.md)のWebCodecs変換。
- [0020](./0020-fmp4-segment-mux.md) / [0018](./0018-fmp4-segment-demux.md)の未実装部分をexample側で代替実装すること。

## 提案する方針

- `examples/fmp4`でH.264 `avc1/avcC` とOpus `Opus/dOps` のsample entry、疑似sample bytes、duration、keyframeを決定的に生成する。乱数・時刻・map順序に依存しない固定値またはseed固定の生成器を使う。
- segmentごとにsampleをmdat payload相対位置に配置し、`create_media_segment_metadata`の後ろへpayloadを結合する。`init_segment_bytes()`は観測済みtrackから生成する。
- 全segmentを`Fmp4SegmentDemuxer`で読み戻し、track kind、timestamp、payload bytes、sample count、keyframe、CTTSをexact比較する。丸め・欠落を許さない。
- 検証用artifactに`init.mp4`、`segment-0001.m4s`等、manifest JSON、Rust側の比較結果を保存し、参照コマンドをREADMEへ載せる。出力先・ファイル名は実装時に確定して本issueへ追記する。
- 失敗時はsegment番号・sample番号・期待/実際の差分を表示して非0終了する。異なるsample順・size・offsetを与えた比較が確実にFAILすることをexampleが自己検証する。
- CLI化の要否と引数設計（0002のtarget方針に従う）は実装時に確定する。nativeで実行し、JS targetへ持ち込む場合は純粋な比較部分だけを共有する。

## 受け入れ条件

- [ ] Given `examples/fmp4`を実行する, when 疑似H.264+Opusを複数segmentに書き出す, then initとsegment群、manifest JSONが指定先に生成され成功終了する。
- [ ] Given 生成されたinit/media segment, when MoonBitの`Fmp4SegmentDemuxer`で全segmentを読み戻す, then track kind、timestamp、payload bytes、sample count、keyframe、CTTSが書き出し記録とexactに一致する。
- [ ] Given 同じ生成物, when Rust oracleでsegment群を読み込む, then 同じsample列として観測でき、比較結果がartifactに残る。
- [ ] Given sample順・size・offsetのいずれか1つを改変した比較, when exampleの比較を実行する, then 差分がsegment番号・sample番号つきで報告され非0終了する。
- [ ] Given READMEの参照コマンド, when リポジトリrootでそのまま実行する, then 追加の手動セットアップなしで再現できる。
- [ ] Given 疑似payloadに対する説明, when READMEとログを確認する, then デコード可能な実メディアと誤報しない文面になっている。

## テスト計画

- `moon check` と `moon test --target native` を実行し、PASS / FAIL / 未実行を記録する（現時点では`moon.mod`と実装がなく実行不能。0002完了後に有効化する）。
- `examples/fmp4`をCI（0003）の対象にし、exit codeとmanifestの比較結果をartifactへ保存する。nativeを先行し、JSでは比較ロジックのみを対象にする。
- Rust oracle（0004）で同じsegment群を読み、sample列の比較結果をgoldenとして記録する。oracle未整備の間は「未実行」と記録し、PASSと混同しない。
- 負例: sample順・size・offsetの改変比較をexample内で実行し、FAILが非0終了へ伝播することを確認する。
- 実行しない明記: 実コーデックでのデコード再生確認はM2の対象外とし、実施しない（疑似payloadはデコード可能とは限らない）。
- 検証状態はPASS / FAIL / 未実行を混同せず、実行コマンド・コミットSHA・OS/arch・fixture checksumとともに結果へ残す。

## リスク

- 疑似payloadを「動画の再生成功」と誤認する。READMEと出力に非デコードであることを明記する。
- 決定性の欠如（乱数・時刻・map順序）でCI差分が不安定になる。seed固定と明示ソートで固定し、CIで検出する。
- Rust oracleのpinned SHAとの不一致をcandidateのバグと誤判定する。0004の方針で再現手順を固定し、driftは[0034](./0034-upstream-drift.md)で扱う。
- artifactの肥大化。既定sample数を小さくし、CIでサイズ上限を確認する。
- ロールバック: exampleとREADMEの追加が中心で、ライブラリ公開API契約を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] 上流examples/fmp4.rs相当のMux/Demux統合exampleを追加

## 注記

- 上流参照: [examples/fmp4.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/fmp4.rs)、[tests/test_mux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_mux_fmp4_segment.rs)、[tests/test_demux_fmp4_segment.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_segment.rs)。
- 関連: [0003](./0003-ci-contract.md)（CI実行）、[0004](./0004-oracle-fixtures.md)（oracle/fixture）、[0018](./0018-fmp4-segment-demux.md)、[0020](./0020-fmp4-segment-mux.md)。
- 未決事項（実装時に確定して追記する）: output先パス、manifest JSONのスキーマ、CLI引数、Rust比較の実行形態（cargo exampleかoracleコマンドか）。
- 証跡: manifest JSONと比較ログをartifactに残し、実行環境（OS/arch、コミットSHA、fixture checksum）を記録する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
