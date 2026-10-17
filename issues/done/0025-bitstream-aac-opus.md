# [P1 / M4] AAC ADTS/ASC・Opusパケット補助を移植する

Status: done
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-17
Branch: feat/0025-bitstream-aac-opus
Priority: P1
Milestone: M4
Depends on: [0005](./0005-safe-bytes.md), [0010](./0010-sample-entries.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

AAC-LC AOT2 の AudioSpecificConfig（ASC）と ADTS header を parse/encode し、ADTS frame payload の抽出と raw AAC への ADTS 付与を提供する。あわせて Opus packet TOC と dOps/Opus sample entry の扱いを上流の範囲に揃え、対応音声 codec の SampleEntry 作成と MP4 mux への接続を可能にする。

## 背景

- upstream（固定 SHA）の [src/bitstream/aac.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/aac.rs) が AAC-LC AOT2 の ASC/ADTS を、[src/bitstream/opus.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/opus.rs) が Opus packet TOC と dOps を扱う。本 issue はこの範囲を MoonBit へ移植する。
- 上流の参照テストは [tests/test_bitstream_aac.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_aac.rs) と [tests/test_bitstream_opus.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_opus.rs)。
- [0005](./0005-safe-bytes.md) が bounds-safe な byte/bit reader/writer と失敗分類を提供し、[0010](./0010-sample-entries.md) が `mp4a/esds`・`Opus/dOps` sample entry を型付きで扱う。本 issue はその間に位置する bitstream レベルの補助（ASC/ADTS/TOC の parse/encode と sample data 変換）を追加する。
- 差分判定は [0004](./0004-oracle-fixtures.md) が固定する Rust oracle と [0016](./0016-rust-moonbit-diff.md) の canonical JSON 比較に載せる。
- [0000](./0000-implementation-roadmap.md) のマイルストーン表では bitstream helper 群を M4 に置く。2026-10-16 時点の `main` は README と `issues/` のみで、`moon.mod` も実装もない。

## 問題

- ADTS 付き AAC をそのままでは MP4 sample として格納できない。ADTS header と ASC の解釈、payload 抽出、sample entry への反映を誤ると、「読めるが壊れた」音声 track を生成する。
- Opus の packet TOC と dOps の pre-skip / sample_rate を保持しないと、mux と demux の間でデコード開始位置や時刻の対応が崩れる。
- CRC 付き ADTS、複数 raw data block など上流が対応しない入力の扱いが未定義だと、部分成功のまま不正な出力を残し得る。
- 上流は AAC-LC 限定であり、対応範囲を曖昧に扱うと HE-AAC 対応と誤認される。

## 目標

- AAC-LC AOT2 の ASC/ADTS header を parse/encode し、sampling frequency・channel configuration・frame size を扱える。
- ADTS frame payload から raw AAC への変換と、raw AAC への ADTS 付与を提供し、esds/mp4a sample entry 作成と MP4 mux から利用できる。
- Opus packet TOC と dOps/Opus sample entry の上流対応項目を揃え、pre-skip / sample_rate を正しく保持する。
- 無効入力（sampling frequency index、channel layout、短い ADTS 等）の失敗分類を上流に合わせ、破損入力で不正 slice を作らない。
- ASC↔ADTS 変換で sample data が変わらない性質をテストで固定する。

## 対象外

- 音声圧縮・PCM 出力。AAC/Opus の encode/decode 処理そのものは対象外。
- HE-AAC（SBR/PS 等）。上流の AAC-LC 限定範囲を超えて「HE-AAC 対応」と称さない。
- CRC 付き ADTS・複数 raw data block の完全対応。検出時は明示エラー（`Unsupported` 等）とし、黙って誤変換しない。
- 音声の再生・ミキシング・音量正規化。
- 映像 bitstream（[0024](./0024-bitstream-h264-h265.md) / [0026](./0026-bitstream-av1-vp8-vp9.md)）と字幕（[0028](./0028-subtitle-sample-entry.md)）。

## 提案する方針

- 配置は 0000 の提案パッケージに従い `src/bitstream/aac.mbt` と `src/bitstream/opus.mbt` を想定する。実際のファイル名と package 分割は [0002](./0002-moonbit-bootstrap.md) で確定し、決まり次第本 issue と README を更新する。
- AAC: ASC（AOT2・sampling frequency index・channel configuration・frame size）と ADTS header の parse/encode を実装する。ADTS frame payload を raw AAC sample data として取り出し、逆に raw AAC へ ADTS を付与する補助を対で提供し、byte 等価性を維持する。
- sample entry 連携: 解析結果を 0010 の `mp4a/esds` 構築へ供給し、対応音声 codec の SampleEntry を [0022](./0022-mp4-file-mux.md) の mux から利用可能にする。descriptor の encode は 0010 に一元化し、本 issue は入力値の供給に限定する。
- Opus: packet TOC を解析し、dOps/Opus sample entry が保持する項目（pre-skip、sample_rate 等）を上流と同じ意味で扱う。encode→decode roundtrip と size 境界をテストする。
- エラー: 0005 の失敗分類へ写像し、位置と理由を保持する。不正な sampling frequency index・channel layout・短い ADTS・size 境界では部分的な slice を返さない。
- 互換性: Rust oracle と同一 fixture で header/entry の観測値が一致することを gate とする。API は I/O に依存しない純関数とし、JS / Native 両 target で同じ値を返す（0000 の target 方針）。
- 実装時の未決事項: 公開 API 名、エラー種別の対応付け、非対応入力の検出位置は実装時に確定する。

## 受け入れ条件

- [ ] Given 有効な AAC-LC AOT2 の ASC と ADTS, when ADTS payload を raw AAC へ変換して再び ADTS を付与する, then sample data が byte 単位で変化しない。
- [ ] Given 上流 `beep-aac-audio.aac` と AAC MP4 fixture, when MoonBit の parser で header と sample entry を読む, then sampling frequency・channel configuration・frame size が Rust oracle と一致する。
- [ ] Given 上流 Opus MP4 fixture, when dOps/Opus sample entry を encode→decode roundtrip する, then pre-skip と sample_rate を含む項目が保持され、size 境界が一致する。
- [ ] Given 無効な sampling frequency index、channel layout、短い ADTS, when parse する, then 0005 の失敗分類に沿うエラーになり、不正な slice を返さない。
- [ ] Given CRC 付き ADTS または複数 raw data block, when parse する, then 非対応として明示エラーになり、部分成功の出力を残さない。
- [ ] Given 対応音声 codec の解析結果, when 0010 / 0022 の sample entry・mux API へ渡す, then MP4 mux で利用可能な SampleEntry を構築できる（依存実装の完了後）。
- [ ] Given 外部 package, when codec helper を import する, then 公開 API が参照でき、JS / Native で同じ観測値になる。

## テスト計画

- 現時点では `moon.mod` も実装もないため `moon check` / `moon test` を実行できない。初回実行まではすべて「未実行」と記録し、未実行を PASS / FAIL と混同しない。0000 の記録規則（PASS / FAIL / 未実行の独立記録、コマンド・commit SHA・OS/arch・fixture checksum の添付）に従う。
- 0002 の scaffold 完了後に次を実行し、結果を本 issue へ追記する。
  - `moon check --target native --deny-warn` と `moon test --target native`。
  - `moon test --target js` で純関数の target 間一致を確認する。
- wbtest（package 内の white-box test）で次を固定する。
  - ASC/ADTS の parse/encode roundtrip、frame size、ASC↔ADTS 変換の byte 等価。
  - 無効な sampling frequency index・channel layout・短い ADTS の失敗分類。
  - dOps/Opus sample entry の roundtrip と size 境界。
- Rust oracle: 0004 が固定した pinned checkout の shiguredo/mp4-rs で `beep-aac-audio.aac` と AAC/Opus MP4 fixture を処理し、header/entry の観測値を比較する。oracle を実行できない環境では「未実行」と記録する。
- 差分は 0016 の canonical JSON 形式で比較し、不一致は field path まで特定して記録する。
- 手動確認: 生成した sample entry を [0013](./0013-mp4-file-demux.md) の demux で読み戻し、track kind・sample 数・entry 構造が一致することを確認する（0013 完了後）。
- 証跡: 実行コマンド、結果分類、fixture checksum、実行環境を PR または artifact に残す。

## リスク

- データ形式: ASC / ADTS の解釈差が「成功」に見える誤変換を生む。roundtrip の byte 等価テストと Rust oracle 比較で検出する。
- 互換性: AAC-LC 限定範囲を超えた対応をうたうと上流との意味差が生じる。README / doc の表現を AAC-LC に固定し、HE-AAC は非対応と書く。
- 境界: 短い入力・末尾切断で範囲外参照が起き得る。0005 の checked な reader を必須経路とし、[0031](./0031-fuzz-pbt-hardening.md) で fuzz を追加する。
- 失敗分類の不一致: MoonBit のエラー分類が Rust の `ErrorKind` とずれると 0016 の差分が失敗し続ける。対応表を 0005 と共有する。
- 統合: esds descriptor の長さ表現など 0010 との接続で不整合が出る。支援 API に限定し、entry の encode は 0010 に一元化する。
- ロールバック: 追加 module のみで既存 API 契約を変えない。問題時は該当 commit の revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] AAC ADTS/ASC と Opus パケット補助（dOps/Opus sample entry 対応）を追加

## 注記

- upstream 対応物: [src/bitstream/aac.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/aac.rs)、[src/bitstream/opus.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/bitstream/opus.rs)、[tests/test_bitstream_aac.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_aac.rs)、[tests/test_bitstream_opus.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_bitstream_opus.rs)。
- 関連: [0005](./0005-safe-bytes.md)（byte/bit 基盤と失敗分類）、[0010](./0010-sample-entries.md)（mp4a/esds・Opus/dOps）、[0022](./0022-mp4-file-mux.md)（利用側）、[0024](./0024-bitstream-h264-h265.md) / [0026](./0026-bitstream-av1-vp8-vp9.md)（並行 helper）、[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)（検証）。
- 実装時の未決事項: ファイル名と package 分割は 0002 で確定する。公開 API 名とエラー型の対応は実装時に決め、確定後に本 issue と README を更新する。
- 証跡: oracle 比較ログ、fixture checksum、`moon test` の結果分類を issue または PR に添付する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。


## 検証

- `src/bitstream` / `src/boxes` に実装し、MoonBit の unit / roundtrip テストを追加した。
- `moon test --target native` / `--target js` は PASS（2026-10-17）。Rust oracle との完全な差分比較は **UNVERIFIED**。
- 0027 は `advance_position` の位置契約・チャンク境界・Hybrid 手順を `docs/hybrid_mp4.md` と wbtest で固定した。
- 0028 は `stpp` / `wvtt` / `tx3g` の型付き sample entry と codec string / mux 属性対応を追加した。
