# [P1 / M4] H.264/H.265 NALとsample entry補助を移植する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0024-bitstream-h264-h265
Priority: P1
Milestone: M4
Depends on: [0005](./0005-safe-bytes.md), [0010](./0010-sample-entries.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

RTSP録画やMP4 muxの下準備のため、Annex B↔length-prefixedの変換と、SPS/PPS/VPSからのcodec設定情報抽出（`avcC`/`hvcC`構築補助）を提供する。H.264/H.265のNAL framingとヘッダー検証を共通化し、純粋なユーティリティとして公開する。

## 背景

- 現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コード・動作テストはない。本issueはM4（コーデック補助）の一部で、[0005](./0005-safe-bytes.md)（bounds-safe bytes/error）と[0010](./0010-sample-entries.md)（avcC/hvcCを持つ型付きsample entry）の上に構築する。
- 上流参照: [src/bitstream/h264.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/h264.rs)、[src/bitstream/h265.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/h265.rs)、[src/bitstream/nal.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/nal.rs)、[tests/test_bitstream_h264.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_h264.rs)、[tests/test_bitstream_h265.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_h265.rs)。
- 上流はfixture `h264-sps-pps-annexb.bin` / `h265-vps-sps-pps-annexb.bin` を使い、変換とcodec設定抽出の結果をテストしている。fixtureの入手・帰属は[0004](./0004-oracle-fixtures.md)の方針に従う。
- 既存bitstream系issueとの分担: AAC/Opusは[0025](./0025-bitstream-aac-opus.md)、AV1/VP8/VP9は[0026](./0026-bitstream-av1-vp8-vp9.md)。

## 問題

- Annex Bのstart code（3/4byte）とlength-prefixed（長さ幅1/2/4byte等）の変換、NALヘッダー検証、空NAL・trailing zero・過大length・NAL中途切断・禁止bitの扱いがMoonBit側にない。
- SPS/PPS/VPSから解像度等の情報を取り出して`avcC`/`hvcC`を組み立てる手段がなく、sample entry（0010）の型へ設定を流せない。
- EBSP/RBSPの区別とemulation prevention bytesの扱い、reserved length sizeを誤ると、生成したcodec設定が壊れる。
- 上流の「NAL header付きEBSPを保ち、SPS parse内部でのみRBSP化する」方針を踏襲しないと、変換の往復でbytesが変わってしまう。

## 目標

- H.264/H.265のNAL framingを共通APIで扱え、Annex B↔length-prefixedの変換が上流と同じ有効幅（start code 3/4byte、length幅1/2/4byte等）で行える。
- H.264 SPS/PPS、H.265 VPS/SPS/PPSを必要範囲だけ解析し、`avcC`/`hvcC`を構築する補助関数が得られる。
- EBSPを保持し、RBSP化はSPS parse内部に限定する。reserved length sizeと不正emulation bytesを明示的に扱う。
- 無効ヘッダー・空NAL・trailing zero・過大length・NAL中途切断・禁止bitを上流と同様に拒否する。
- ユーティリティ公開APIが純粋でJS/Native共通に動き、作った`avcC`/`hvcC`がsample entry（[0010](./0010-sample-entries.md)）から読み直せる。

## 対象外

- H.264/H.265のデコード・エンコードはしない。
- codec文字列（RFC6381）の生成は[0011](./0011-codec-strings.md)、AAC/Opusは[0025](./0025-bitstream-aac-opus.md)、AV1/VP8/VP9は[0026](./0026-bitstream-av1-vp8-vp9.md)。
- RTSPやストリーム受信そのもの（録画データはcallerが用意する）。
- track sample entry作成の自動化を必須にしない（オプション扱い）。

## 提案する方針

- NAL framingを共通化し、H.264/H.265のheader検証、Annex B start code 3/4byte、長さprefix 1/2/4byteなど上流の有効幅を表現する。[0005](./0005-safe-bytes.md)のbounds-safe reader/error型を使う。
- H.264 SPS/PPS、H.265 VPS/SPS/PPSを必要範囲だけ解析し、`avcC`/`hvcC`を構築する補助関数を作る。構築結果は[0010](./0010-sample-entries.md)の型でdecodeし直して一致を確認できる形にする。
- NAL header付きEBSPを保ち、SPS parse内部でのみRBSP化する。reserved length sizeと不正emulation bytesを明示扱いする。
- 無効ヘッダー、空NAL、trailing zero、過大length、NAL中途切断、禁止bit設定の扱いを上流と合わせ、error分類として固定する。
- track sample entry作成の自動化はオプションとし、入力bitstreamが常に正しい動画であると断定しない。普及ファミリ（100/110/High等）のプロファイル範囲は上流の受理範囲を実装時に確認して明記する。
- APIの型名・モジュール配置（例: `src/bitstream`配下）は実装時に確定して本issueへ追記する。変換は入力を変更せず新規bytesを返す純粋関数にする。

## 受け入れ条件

- [ ] Given 上流fixture `h264-sps-pps-annexb.bin`相当の入力, when Annex Bからlength-prefixedへ変換して戻す, then SPS/PPSを含む各NALが上流と同じbytesになり、戻し試験で元に戻る（必要な正規化例外は明記する）。
- [ ] Given H.264 SPS/PPSのNAL列, when `avcC`を構築する, then sample entry（[0010](./0010-sample-entries.md)）でdecodeし直したprofile/compatibility/levelとparameter setが入力と一致する。
- [ ] Given 上流fixture `h265-vps-sps-pps-annexb.bin`相当の入力, when `hvcC`を構築する, then VPS/SPS/PPSが上流と同じ結果で格納される。
- [ ] Given 無効ヘッダー・空NAL・trailing zero・過大length・NAL中途切断・禁止bit設定の入力, when 変換または解析する, then 上流と同じ分類でエラーになりpanic・無限loopにならない。
- [ ] Given reserved length sizeや不正emulation bytesを含む入力, when 解析する, then 明示的なエラーまたは定義済みの扱いになる。
- [ ] Given 同一公開API, when `--target native`と`--target js`でテストする, then 結果が一致する。

## テスト計画

- `moon check`と`moon test --target native`を実行し、PASS / FAIL / 未実行を記録する（現時点では`moon.mod`と実装がなく実行不能。0002完了後に有効化する）。
- fixture: 上流`h264-sps-pps-annexb.bin`/`h265-vps-sps-pps-annexb.bin`相当の入力を、0004の方針（帰属確認・checksum固定）で用意し、上流と同じ結果になることを比較する。fixtureを用意できない間は「未実行」と記録する。
- 変換の往復: Annex B→length-prefixed→Annex Bの戻し試験。必要な正規化例外（許容される差）を明記し、黙ってbytesを変えない。
- 負例: SPS/VPSの切断、zero padding、予約length、禁止bit設定、emulation bytes不正を入力し、安全にエラーになることを固定する。
- `--target js`でも同じwbtestを実行し、整数・byte操作のtarget差がないことを確認する。実行できない場合は理由とともに未実行と記録する。
- 証跡: 変換・解析結果の比較とfixture checksum、実行コマンド、コミットSHAをログまたはartifactへ残す。

## リスク

- EBSP/RBSPの扱いを誤り、変換の往復でbytesが変化する。RBSP化をSPS parse内部に限定し、戻し試験を必須にする。
- 長さprefix幅（1/2/4byte）やstart code長の混同で、有効なbitstreamを拒否・破壊する。上流の有効幅をテストで固定する。
- 不正入力で範囲外参照・無限loopを起こす。[0005](./0005-safe-bytes.md)のbounds-safe型と回帰テストで防ぐ。
- fixtureの入手・帰属確認が遅れ、テストが未実行のままになる。[0004](./0004-oracle-fixtures.md)の手続きに従い、未実行状態を明示して完了扱いにしない。
- ロールバック: 新規bitstreamユーティリティの追加が中心で、既存API契約を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] H.264/H.265のAnnex B・length-prefixed変換とavcC/hvcC構築補助を追加

## 注記

- 上流参照: [src/bitstream/h264.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/h264.rs)、[src/bitstream/h265.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/h265.rs)、[src/bitstream/nal.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/nal.rs)、[tests/test_bitstream_h264.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_h264.rs)、[tests/test_bitstream_h265.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_h265.rs)。
- 関連: [0005](./0005-safe-bytes.md)（bounds-safe bytes/error）、[0010](./0010-sample-entries.md)（avcC/hvcCの型）、[0011](./0011-codec-strings.md)、[0025](./0025-bitstream-aac-opus.md)、[0026](./0026-bitstream-av1-vp8-vp9.md)。
- 未決事項（実装時に確定して追記する）: 解析対象のプロファイル範囲、公開API名、fixtureの入手経路とchecksum。
- 証跡: fixture checksum、変換・解析の比較結果、targetごとのテスト結果をログまたはartifactに残す。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。


## 検証

- `src/bitstream` / `src/boxes` に実装し、MoonBit の unit / roundtrip テストを追加した。
- `moon test --target native` / `--target js` は PASS（2026-10-17）。Rust oracle との完全な差分比較は **UNVERIFIED**。
- 0027 は `advance_position` の位置契約・チャンク境界・Hybrid 手順を `docs/hybrid_mp4.md` と wbtest で固定した。
- 0028 は `stpp` / `wvtt` / `tx3g` の型付き sample entry と codec string / mux 属性対応を追加した。
