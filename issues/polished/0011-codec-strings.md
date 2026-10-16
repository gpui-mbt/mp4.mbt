# [P1 / M1] RFC 6381 codec stringをSampleEntryから生成する

Status: polished
Model: DeepSeek V4.1 Flash Free
Created: 2026-10-16
Updated: 2026-10-16
Branch: feat/0011-codec-strings
Priority: P1
Milestone: M1
Depends on: [0010](./0010-sample-entries.md)
Upstream baseline: [shiguredo/mp4-rs@1282b704f44184ec792e1549b5d31e0c4c54dc59](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59)

## 概要

`SampleEntry` から RFC 6381 の `codecs` パラメーター文字列（例: `avc1.640028`、`mp4a.40.2`）を生成する API を追加する。MP4 Dump の codec 列とブラウザ WebCodecs 設定に使う文字列を、ファイル名推測ではなく sample entry 由来で生成する。

## 背景

- 入力は 0010 の `SampleEntry` 型とし、0015 のブラウザ Dump と 0029 の WebCodecs 設定が生成結果を使う。
- 上流の固定基準 [`1282b704`](https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59) の [src/codec_string.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec_string.rs) の `from_sample_entry` は entry ごとに binding の表記へ変換する。`avc1` は profile / compatibility / level の 3 バイト、`hev1`/`hvc1` は ISO/IEC 14496-15 Annex E 形式、`av01` は AV1 binding、`vp08`/`vp09` は `<4CC>.PP.LL.DD`、`mp4a` は OTI（`0x40` なら AudioSpecificConfig 先頭から AOT）、`Opus`/`fLaC` は 4CC のみを返す。
- 上流のエラー条件: `SampleEntry::Unknown` は `Unsupported`、`mp4a` で `DecoderSpecificInfo` 欠落・AOT 切り詰めは `InvalidData` になる。
- 上流のテストは [tests/test_codec_string.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_codec_string.rs) にあり、同一 sample entry の golden で一致を確認できる。

## 問題

- ファイル名や拡張子から codec を推測すると、中身と食い違うファイルで誤表示する。
- 未知 entry を silent fallback で正常文字列に変換すると、誤った codec string が WebCodecs 設定など下流に流れる。
- binding ごとの表記規則（hex の桁数・大小文字、tier 文字、bit depth の 2 桁など）を誤るとブラウザ側の設定が拒否される。
- `mp4a` で OTI/AOT を読まないと AAC の profile 情報が落ち、欠落・破損を正常扱いする。
- locale 依存の数値→文字列変換を使うと JS/Native で出力が割れる。

## 目標

- `SampleEntry` から決定的な codec string を生成する公開 API（`from_sample_entry` 相当）を実装・文書化する。
- codec id 一覧・パラメーター形式・エラー分類を上流に一致させる。
- 未知 entry を `Unsupported`、`esds`/ASC の欠落・破損を `InvalidData` として区別する（silent fallback しない）。
- 文字列は canonical な小文字 hex やゼロ埋め桁数を使用し、元の 4CC 大小文字を保持する。
- parse-only codec との整合性を明示し（MoonBit の対応は parse 段階までであることを 0015 / 0016 の表示と整合させ）、WebCodecs の実機サポート判定は別レイヤーに委ねる。
- JS/Native で locale に依存しない同一文字列を返す。
- 文字列の一致を同一 sample entry の golden で確認する。

## 対象外

- コーデックのハードウェア利用可能性、エンコードや再生可否の判定。
- ブラウザ実機での `isConfigSupported` 相当の判定（0015 / 0029 の範囲）。
- codec string の解釈（文字列から entry や設定を復元する方向）。
- 字幕 entry（`stpp`/`wvtt`/`tx3g`）は 0028 で entry が入った段階で扱いを確定する。

## 提案する方針

- 対象は `src/codec_string` 相当のパッケージに置く（0002 の構成に従う）。公開関数は上流と同じ入力（`SampleEntry`）・返り値（文字列またはエラー）とし、具体名は 0002 の命名表に従い実装時に確定する。
- codec 別の規則は上流実装を正とする:
  - AVC `avc1`: 上流の `H264ProfileLevelId` 相当から `avc1.` + 3 バイト小文字 hex（例 `avc1.640028`）。
  - HEVC `hev1`/`hvc1`: Annex E 形式。`general_profile_space` を `A`/`B`/`C`、tier を `L`/`H` にし、`general_profile_compatibility_flags` は bit-reverse した大文字 hex、constraint indicator は 6 バイトの末尾ゼロを省略する（全ゼロでも 1 バイト）。
  - AV1 `av01`: `av01.<profile>.<level:02><tier>.<bitdepth:02>`。bit depth は `seq_profile`／`high_bitdepth`／`twelve_bit` から導出する。
  - VP8/VP9 `vp08`/`vp09`: `<4CC>.<profile:02>.<level:02>.<bitdepth:02>`。
  - AAC `mp4a`: `mp4a.<OTI:02x>`。OTI が `0x40` のときは続けて `.` + AOT を付ける。AOT は AudioSpecificConfig 先頭から読み、AOT 31 のエスケープ形式も扱う。
  - `Opus`/`fLaC`: 追加パラメーターが不要なため 4CC のみを返す。
- 互換性要件: 返り値は JS/Native 共通の文字列型とし、数値→文字列変換は locale 非依存の固定書式で行う。比較は 0016 の差分 Lab と同じ field path に載る形にする。
- 境界条件: entry に必要な設定が入っていない場合は 0010 の decode エラーになる前提とし、本関数は「導出不能なら `Unsupported`（未知 entry）/ `InvalidData`（`esds`・ASC の欠落や破損）」の 2 分類だけを担う。
- 実装時に確定する点: HEVC の compat / constraint 省略規則と AV1 の bit depth 分岐を上流実装と照合し、golden で固定する。

## 受け入れ条件

- [ ] Given AVC High Profile Level 4.0 の `avc1` entry, when codec string を生成する, then `avc1.640028` が返る。
- [ ] Given AAC-LC（OTI `0x40`、AOT 2）の `mp4a` entry, when 生成する, then `mp4a.40.2` が返る。
- [ ] Given AV1 entry, when 生成する, then `av01.0.01M.08` 形式（profile / level / tier / bit depth）が golden と一致する。
- [ ] Given HEVC・VP8/VP9・Opus・FLAC entry, when 生成する, then 上流 golden（`hev1.1.6.L93.B0`、`vp09.00.31.08`、4CC 等）と一致する。
- [ ] Given `SampleEntry::Unknown`, when 生成する, then `Unsupported` 相当のエラーになり、正常文字列へ fallback しない。
- [ ] Given `mp4a` で `DecoderSpecificInfo` 欠落または AOT 切り詰め, when 生成する, then `InvalidData` 相当のエラーになる。
- [ ] Given 同一 entry, when JS と Native で生成する, then バイト単位で同一の文字列になる（locale 非依存）。
- [ ] Given 同一 sample entry の golden, when 再生成する, then 実行ごとに同一の文字列になる（決定性）。

## テスト計画

- `moon.mod` とパッケージが 0002 で整備された後に `moon check`、`moon test --target native`、`moon test --target js` を実行し、PASS / FAIL / 未実行を記録する。現時点で `moon.mod` も実装コードもないため、実行できない確認はすべて未実行として扱い PASS と混同しない。
- wbtest: 全 codec 分岐の文字列生成、エラー 2 分類、4CC 大小文字の保持、AOT 31 の境界を手作り entry で固定する。
- golden 比較: 0010 の entry を入力に、Rust oracle（0004）の `from_sample_entry` 相当の出力と全 fixture で一致を確認する。golden は Rust 実行の証跡付きで作り、手入力しない。
- JS / Native 同一性: 同じ golden を両 target で再生成し、文字列のバイト一致を確認する。
- 手動確認: 0015 の Dump の codec 列に本関数の出力が出ること、0029 では実機サポート判定を別レイヤーで行うことを確認する。
- 実装詳細（公開関数名・配置）は実装時に確定し、確定内容を本 issue へ追記する。

## リスク

- binding 表記の誤り（桁数・大小文字・tier）で WebCodecs 設定が拒否される。上流 golden との全件比較で固定する。
- HEVC の compat bit-reverse と constraint 末尾ゼロ省略の解釈差。上流実装を正とし、ゼロ埋めケースを境界テストにする。
- エラー分類の混同（`Unsupported` と `InvalidData`）で呼び出し側の分岐が壊れる。上流と同じ分類をテストで固定する。
- ファイル名推測の用途が残ると誤表示が再発する。0015 / 0016 の表示経路から本関数だけを使う。
- ロールバック: 純粋な関数追加で既存 API を変えない。問題時は該当コミットの revert で戻せる。

## 変更履歴

`CHANGES.md` impact: yes

項目案:

- [ADD] SampleEntry からの RFC 6381 codec string 生成 API

## 注記

- upstream の対応物: [src/codec_string.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec_string.rs)、[tests/test_codec_string.rs](https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/test_codec_string.rs)。
- 関連: [0010](./0010-sample-entries.md)（入力型）、[0015](./0015-web-mp4-dump.md)（表示）、[0029](./0029-webcodecs-transcode.md)（WebCodecs 設定）、[0028](./0028-subtitle-sample-entry.md)（字幕 entry 追加時に 4CC 扱いを突き合わせる）。
- 関連ロードマップ: [0000](./0000-implementation-roadmap.md) の M1。codec 表示を使う 0015 / 0016 の前提になる。
- 証跡ルール: checkbox は実際に実行した証拠がある項目だけ完了にする（0000 の進捗更新の規則 1）。
- 実装時の未決事項: 公開関数名、字幕 entry（0028）の取り込み可否、golden の生成時期は 0004 と調整して確定する。
- 2026-10-16: 本文を実装可能な形式へ整備し、実装に着手可能なため polished へ更新。
