# [P1 / M2] fMP4ファイル全体のincremental demuxerを作る

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0019-fmp4-file-demux
Priority: P1
Milestone: M2
Depends on: [0012](./0012-file-kind-detector.md), [0017](./0017-fmp4-boxes.md), [0018](./0018-fmp4-segment-demux.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

`moof`/`mdat`が複数並んだ単一のfMP4ファイルに対し、必要な範囲を段階的に読みながら全sampleを返す `Fmp4FileDemuxer` 相当を実装する。`required_input` / `handle_input` / `tracks` / `next_sample` を通常MP4 demuxerと整合する形で提供し、sampleの `data_offset` はファイル絶対位置とする。

## 背景

- 上流参照: [src/demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_fmp4_file.rs)、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)。
- 上流API（固定コミットで確認できる範囲）: `required_input() -> Option<RequiredInput>`、`handle_input(Input)`、`tracks() -> Result<&[TrackInfo]>`、`next_sample() -> Result<Option<Sample>>`。内部で[0018](./0018-fmp4-segment-demux.md)相当のsegment demuxerへ委譲し、segment側の相対 `data_offset` にmoof位置を加算してファイル絶対位置にする。
- 上流の制限: `tfhd.base_data_offset` がファイル絶対位置を指す形式には非対応で、そのtrafを含むmoofを明示エラーにする。`moof` と `mdat` の間の `free` 等のtop-level boxは種別を問わず読み飛ばす。
- 上流の境界の扱い: top-level走査で32bitのsize=0が来た場合はファイル終端（EndOfFile）として扱われ、`moof` と `mdat` の間のsize=0はエラーになる。詳細境界は実装時に上流と突き合わせて固定する。
- [0012](./0012-file-kind-detector.md)がfMP4を判定して本demuxerへ振り分け、[0021](./0021-fmp4-example.md)が成果物を読み戻しに使う。現時点のrepoはREADMEとissuesのみで、`moon.mod`・実装コードはない。

## 問題

- 複数fragmentを持つfMP4を全量メモリへ載せずに読むdemuxerがない。
- phase管理（ftyp→moov→境界走査→moof→mdat→media segment）と `RequiredInput` の契約が未実装だと、巨大ファイルや途中入力で破綻する。
- sample順序（DTS順、同時刻はtrack/data位置で安定）とファイル全体でのsample entry変更通知が未定義だと、Rust oracleと比較できない。
- 仕様外のtfhd形式を暗黙に読み替えると、offsetを静かに誤って解釈し得る。

## 目標

- `required_input` / `handle_input` / `tracks` / `next_sample` を通常版（[0013](./0013-mp4-file-demux.md)）と整合する形で実装する。
- 初期化→segment境界走査→sample出力→次のsegmentの要求をphaseとして管理し、要求rangeのみを読む。
- sample順序はDTS順、同時刻はtrackとdata位置で安定化する。
- sample entry変更通知をファイル全体の取り出し順で維持する。
- 未対応形式（`tfhd.base_data_offset` の絶対位置形式）を読み替えず、ユーザー向けエラーにする。

## 対象外

- segment単位の単発demux（[0018](./0018-fmp4-segment-demux.md)）。
- mux（[0020](./0020-fmp4-segment-mux.md) / [0021](./0021-fmp4-example.md)）。
- 仕様外のtfhd形式の暗黙の読み替え・不一致の推測修正。
- codec payloadのdecode・再生。

## 提案する方針

- phaseは上流同様に「初期化→segment境界走査→sample出力→次のsegmentの要求」として段階化する。`moof` と `mdat` の間に `free` 等のtop-level boxを許容し、`mdat` より先に次の `moof` が出る場合は失敗とする。top-level走査での32bit size=0はファイル終端、`moof` と `mdat` の間のsize=0は失敗とし、上流の分岐をwbtestで固定する（境界は実装時に確定して本issueへ追記する）。
- `required_input` はphaseごとにpositionとsizeを返す（box headerは `BoxHeader::MAX_SIZE` 相当、`moov`/`moof`/media segmentはそのサイズ、mdatはsegment全体）。`handle_input` は要求位置を含まない入力をエラー状態にし、以降の `tracks()` / `next_sample()` がそのエラーを返す扱いにする。要求より多いデータは許容するが、`next_sample` にサンプルが残っている間は `handle_input` を呼ばない前提をdoc commentとREADMEに明記する（entry変更判定が取り出し順の状態を使うため）。
- 入力が要求範囲の終端より手前で終わる場合は入力終端をファイル終端とみなす（上流契約）。途中で切れた入力では切れた位置までだけを処理する。
- 絶対offset: segment demuxerが返す相対 `data_offset` に `moof` のファイル位置を加算して絶対位置へ変換する。`tfhd.base_data_offset` が設定されたtrafを含むmoofは非対応としてエラーにし、読み替えない。
- 順序: segment内のサンプルはDTS順に並べ替える。timescaleをまたぐ比較は整数積で行い、float丸めを使わない。同時刻はtrack index、次にdata位置で安定順にする。
- sample entryはファイル全体の取り出し順で各トラック最初のサンプルと、直前サンプル（前segmentの最後を含む）からentryが変わったサンプルにのみ付与する。
- `mdat` のsize=0（末尾まで続く）の場合は次segmentなしとしてEOFへ遷移する。一度取得したsampleを全件queueに保持せず、offsetに基づく段階処理とEOFを管理し、pendingは現segment分に限定する。
- 通常demuxとは別のpublic typeとし、[0012](./0012-file-kind-detector.md)のkindから振り分け可能にする。API名・ファイル配置・phaseの分割粒度は実装時に確定し、本issueへ追記する。

## 受け入れ条件

- [ ] Given 複数fragment・複数track・CTTS付きfixture, when 全sampleを列挙する, then sample順序とファイル絶対data_offsetがRust oracleと一致する。
- [ ] Given segmentを跨ぐsample entry変更とfreeを挟む構造, when 処理する, then entry通知がファイル全体の取り出し順で変化時のみ付き、空segmentの扱いも上流と一致する。
- [ ] Given `tfhd` の絶対base_data_offset、二つ続くmoof、mdat欠落, when 処理する, then 想定どおりのエラーで失敗し、暗黙に読み替えない。
- [ ] Given 大きいmdat, when `required_input` を観測する, then 全読込を要求せず、Rust oracleと要求rangeが一致する。
- [ ] Given 途中まで切れた入力, when `handle_input` へ渡す, then 入力終端をファイル終端として扱い、`next_sample` / `tracks` の応答が上流契約と一致する。
- [ ] Given [0012](./0012-file-kind-detector.md)でfMP4と判定したファイル, when 振り分ける, then 通常demuxとは別のpublic typeとして扱える。
- [ ] Given fragment単位とfile単位の比較, when Rust oracleと照合する, then 両方でsemantic parityが示される。

## テスト計画

- 現時点では `moon.mod` がなく、以下は0002・0004・0012・0017・0018完了後に実行する。PASS / FAIL / 未実行を混同せず記録する。
  - `moon check --target native --deny-warn` と `moon test --target native`（および `--target js`）を実行し、結果とツールチェーンのバージョンを記録する。
  - wbtest: phase遷移（ftyp→moov→top-level→moof→mdat→segment要求）、要求rangeの決定、絶対offset変換、並べ替えのtie-break、entry通知条件、エラー状態の伝播を固定する。
- [0004](./0004-oracle-fixtures.md)のoracleで、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)のfixture群を処理し、fragment単位・file単位の両方でsample metadataと要求rangeを比較する。
- 要求rangeの比較は、oracle側とcandidate側で `required_input` のposition/size列をログに取り、差をfield単位で出す。
- 負例（絶対base_data_offset、二つ続くmoof、mdat欠落、途中切断、moof/mdat間のsize=0）を固定バイト列のテストで追加し、エラー分類の一致を確認する。
- 現時点では上記いずれも実行できない。fixtureは帰属確認済みのものに限定し、未確認素材では「未実行」と理由を記録する（0001/0004）。

## リスク

- 相対offsetへの加算漏れ・二重加算。[0018](./0018-fmp4-segment-demux.md)の相対offsetから絶対offsetへの変換を一元化し、oracle比較で検出する。
- phaseとpendingの管理ミスでsample順序・entry通知が壊れる。u128相当の整数積比較とtie-break、entry通知条件をwbtestで固定する。
- size=0 boxの解釈差で無限loop・早期終了になる。上流の分岐（top-levelはEOF許容、moof/mdat間はエラー）をテストで固定する。
- media segment全体を要求するため、非常に大きいmdatで呼出側のメモリを圧迫する。要求rangeの上限・分割受入の扱いを[0013](./0013-mp4-file-demux.md)/[0014](./0014-demux-example.md)と揃えて文書化する。
- ロールバック: 新規demuxerの追加が中心で、[0013](./0013-mp4-file-demux.md)の公開API契約を変えない。問題時は該当コミットのrevertで戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] fMP4ファイル全体のincremental demuxer（要求rangeベース・ファイル絶対offset）

## 注記

- 上流参照: [src/demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_fmp4_file.rs)、[tests/test_demux_fmp4_file.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_demux_fmp4_file.rs)。
- 関連: [0012](./0012-file-kind-detector.md)（kind判定）、[0013](./0013-mp4-file-demux.md)（通常demux）、[0017](./0017-fmp4-boxes.md)、[0018](./0018-fmp4-segment-demux.md)、[0021](./0021-fmp4-example.md)（roundtrip example）。
- 運用: upstream SHA・fixture checksum・要求range列・実行コマンドを証跡に残す（0004/0034の方針）。
- 未決事項（実装時に確定して追記する）: public type名、`RequiredInput` を[0013](./0013-mp4-file-demux.md)と共有するか別型にするか、size=0 boxの最終的な扱い。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
