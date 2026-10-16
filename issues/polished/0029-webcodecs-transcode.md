# [P2 / M5] WebCodecsでローカルMP4変換デモを作る

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0029-webcodecs-transcode
Priority: P2
Milestone: M5
Depends on: [0015](./0015-web-mp4-dump.md), [0022](./0022-mp4-file-mux.md), [0024](./0024-bitstream-h264-h265.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

『MoonBitのdemux/mux + ブラウザのWebCodecs』で、ローカルの H.264 映像から新しい MP4 を生成し、メタデータを双方の表示画面で調べられるデモを作る。入力の parse と sample 列抽出、出力 MP4 の構成は MoonBit core、codec 変換はブラウザ提供の `VideoDecoder` / `VideoEncoder` に分離する。

## 背景

- upstream（固定 SHA）の参照実装は [examples/transcode_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/transcode_wasm/index.html) と [examples/transcode_wasm/transcode.js](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/transcode_wasm/transcode.js)。上流デモは edit list（edts）を考慮せず AV sync がずれ得る点を参照する。
- [0015](./0015-web-mp4-dump.md) がブラウザ MP4 Dump（File API・Range I/O・表示 UI・canonical JSON export）を提供し、[0022](./0022-mp4-file-mux.md) が通常 MP4 muxer、[0024](./0024-bitstream-h264-h265.md) が H.264 sample entry 補助を提供する。本 issue はそれらを組み合わせ、デモを追加する。
- [0000](./0000-implementation-roadmap.md) では M5 のうち本 issue だけが WebCodecs へ依存し、codec 未対応ブラウザは機能を無効化する方針とする。MoonBit core は JS target で動作し、DOM 依存は UI アダプタに隔離する（0000 / [0002](./0002-moonbit-bootstrap.md)）。
- 2026-10-16 時点の `main` は README と `issues/` のみで、`moon.mod` も実装もデモもない。

## 問題

- MoonBit 側の demux/mux だけではブラウザで codec 変換ができない。WebCodecs との責務分離を定めないと、core へ DOM / ブラウザ依存が混入する。
- DTS/PTS/CTTS と edit list、キーフレーム境界の扱いを誤ると AV sync がずれる。上流デモも edts 未考慮でずれ得ることを参照しており、デモ側の前提を明示する必要がある。
- 巨大ファイルを一括でメモリへ載せるとタブが落ちる。分割処理とキャンセルの設計が要る。
- ブラウザごとの codec サポート差を実測なしに表明すると、虚偽の対応表示になる。

## 目標

- ローカル File API 入力 → MoonBit core での MP4 parse / sample 抽出 → WebCodecs の `VideoDecoder` / `VideoEncoder` → MoonBit core で出力 MP4 構成、という責務分離を実装する。
- H.264 input から H.264 出力（ブラウザが対応する場合）を最小ゴールとし、AV1/HEVC/VP9 の選択肢は `isConfigSupported()` で実機判定し、不可は Disabled にする。
- DTS/PTS/CTTS・edit list・キーフレーム境界と音声トラックの保持 / 除外をデモ仕様として明示し、当初は映像単一 track の file に限定する。
- 全ファイルを一括保持しない分割処理を優先し、不可ならサイズ上限を明示する。キャンセル・異常系・出力 download を実装する。
- 公開デモの README にブラウザ別の実測サポート結果と制限を載せる。

## 対象外

- MoonBit 製の H.264/AV1 エンコーダー・デコーダーの実装。codec 変換は WebCodecs が担い、MoonBit 製エンコーダーとは呼ばない。
- Safari / Chrome の全機能対応の表明。証拠のない対応を表明しない。
- 音声の変換・再エンコード、音声付き複数 track の同時変換（当初は映像単一 track に限定）。
- サーバ / クラウド変換。ファイルは外部アップロードしない（0015 と同じ方針）。

## 提案する方針

- 配置は 0000 の提案に従い `web/` または `examples/` 配下のデモとして追加する。パッケージ構成は 0002 で確定し、決まり次第本 issue を更新する。core 側は 0013 / 0022 / 0024 の既存 API のみを使い、WebCodecs 依存を core へ持ち込まない。
- 入力: File API の slice を Range I/O アダプタ経由で core へ供給し、全量の ArrayBuffer 化を避ける。分割処理が不可の環境では UI にサイズ上限を明示する。
- 変換: `VideoDecoder` で sample を decode し、`VideoEncoder` で encode する。出力 sample 列は 0022 の Mp4FileMuxer、sample entry は 0024（必要なら 0010）を使って MP4 へ構成する。
- codec 選択: H.264 を最小ゴールとし、AV1/HEVC/VP9 は `isConfigSupported()` の実行時判定に従う。不可は Disabled として理由を表示し、判定結果を環境ごとに記録する。
- 時刻: DTS/PTS/CTTS・edit list・キーフレーム境界の保持 / 除去規則をデモ仕様に明記する。edts 未考慮の AV sync ずれリスクを上流デモ同様に扱い、当初は映像単一 track に限定して複雑化を避ける。
- 失敗系: キャンセル（decode/encode の中断、古い結果を残さない）、不正 input、巨大 file で UI が固まらないことを実装する。出力は download API で取得する。
- 互換性: 出力 MP4 を MoonBit demux（0013）と Rust demux の双方で解析し、track / sample を比較する。ブラウザ別の実測結果は実行できた環境だけを README に記録し、未検証は UNVERIFIED と明記する（[0033](./0033-release-docs.md) の公開文書と整合させる）。
- 実装時の未決事項: デモの配置パス、初期対象ブラウザ、サイズ上限値、音声 track を扱う将来手順は実装時に確定する。

## 受け入れ条件

- [ ] Given H.264 の短い fixture と WebCodecs 対応ブラウザ, when デモで変換する, then 入力から出力 MP4 が生成され、MoonBit demux で track / sample を再解析できる。
- [ ] Given codec 非対応ブラウザ, when 変換を開始する, then クラッシュせず当該 codec が Disabled として明示され、理由が表示される。
- [ ] Given 映像単一 track の入力と一括処理が困難なサイズ, when 変換する, then 分割処理または明示したサイズ上限のいずれかで動作し、UI が応答し続ける。
- [ ] Given 変換の進行中, when キャンセルする, then decode / encode が停止し、古い結果が画面に残らない。
- [ ] Given 出力 MP4, when MoonBit / Rust demux で解析する, then DTS / PTS / キーフレーム境界の扱いが仕様どおりで、仕様外の保持 / 除外がない。
- [ ] Given README のブラウザ別サポート表, when 結果を確認する, then 実測した環境と未検証項目（UNVERIFIED）が混同されずに記載されている。
- [ ] Given ローカルの入力ファイル, when デモを実行する, then ファイルが外部へアップロードされない。

## テスト計画

- 現時点では `moon.mod` も実装もデモもないため、core の `moon check` / `moon test` とブラウザ E2E のどちらも実行できない。初回実行まではすべて「未実行」と記録し、未実行を PASS / FAIL と混同しない。0000 の記録規則（PASS / FAIL / UNVERIFIED / 未実行の独立記録、コマンド・commit SHA・OS/arch・fixture checksum の添付）に従う。
- 0002 の scaffold 完了後に core 側で次を実行し、結果を本 issue へ追記する。
  - `moon check --target native --deny-warn` と `moon test --target native`。
  - `moon test --target js`（デモが使う core 部分の target 間一致）。
- ブラウザ E2E: 0015 で整備する実ブラウザ操作テストの仕組みを再利用し、次を実行する。
  - H.264 の短い fixture を変換し、出力 MP4 を MoonBit demux と Rust demux（0004 の oracle）で解析して track / sample を比較する。
  - codec 非対応環境を模したケースで Disabled 表示になり、クラッシュしないこと。
  - 映像のみ入力、巨大 file（分割処理または上限表示）、キャンセル、不正 input の各ケース。
- 実測表: 実行できたブラウザとバージョンだけを README に記録し、実行できなかった環境は未実行 / UNVERIFIED として区別する。対応を推測で書かない。
- 手動確認: 変換前後のメタデータ表示（0015 の Dump 画面相当）を目視で確認し、スクリーンショットを残す。
- 証跡: 実行環境、入力 fixture の checksum、変換ログ、出力 MP4 の解析 JSON、画面と結果分類を artifact に残す。入力ファイルの中身をリポジトリへコミットしない。

## リスク

- ブラウザ差: 同じ codec でもブラウザ / バージョンで可否が異なる。`isConfigSupported()` の実行時判定と実測表で吸収し、未検証を隠さない。
- AV sync: edts 未考慮の上流例と同様に DTS / PTS 変換でずれ得る。当初は映像単一 track に限定し、DTS / PTS の契約テストと出力の demux 比較を行う。
- メモリ: 一括保持で OOM になる。Range I/O と分割処理を優先し、上限を UI に明示する。
- 出力不正: sample entry や offset を誤ると読めない MP4 になる。0022 / 0024 の承認済み API のみを使い、roundtrip で検証する。
- 誇大表明: 実測なしの対応表明が公開文書へ流れる。README の UNVERIFIED 表記と 0033 の公開方針で抑える。
- ロールバック: デモは core から分離して追加するため、問題時はデモを外すか該当 commit を revert できる。core の既存契約は変えない。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] WebCodecs によるローカル MP4 変換デモを追加

## 注記

- upstream 対応物: [examples/transcode_wasm/index.html](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/transcode_wasm/index.html)、[examples/transcode_wasm/transcode.js](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/examples/transcode_wasm/transcode.js)。
- 関連: [0015](./0015-web-mp4-dump.md)（File API・表示 UI）、[0022](./0022-mp4-file-mux.md)（出力 mux）、[0024](./0024-bitstream-h264-h265.md)（H.264 sample entry）、[0013](./0013-mp4-file-demux.md)（出力の再解析）、[0004](./0004-oracle-fixtures.md) / [0016](./0016-rust-moonbit-diff.md)（oracle 差分）、[0033](./0033-release-docs.md)（公開文書の制限表記）、[0000](./0000-implementation-roadmap.md)（M5 位置づけ）。
- 実装時の未決事項: デモの配置パス、初期対象ブラウザ、サイズ上限値、音声 track を含む変換の将来手順は実装時に確定し、本 issue と README に反映する。
- 運用・証跡: 実測表は実行できた環境と未実行を区別して記録する。入力ファイルはローカル処理のみとし、外部送信しない。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
