# 上流参照と互換性の基準

この文書は mp4.mbt が参照する上流実装・ライセンス・API 対応・対応規格・上流更新手順を固定する。
対象と責務の境界は [`scope.md`](./scope.md) を参照。

## 1. 固定参照（上流 baseline）

| 項目 | 値 |
| --- | --- |
| リポジトリ | [shiguredo/mp4-rs](https://github.com/shiguredo/mp4-rs) |
| 固定コミット | `1282b704f44184ec792e1549b5d31e0c4c54dc59` |
| コミット確定日 | 2026-10-16（調査時の `develop` HEAD） |
| クレート名 / バージョン | `shiguredo_mp4` / `2026.6.0-canary.2` |
| Rust edition / MSRV | 2024 / 1.93 |
| 性質 | 依存ゼロ・Sans I/O・`no_std` 対応 MP4 mux/demux ライブラリ |

- 上流を参照するときは常に固定 SHA の URL を使う。`main` / `develop` や latest を暗黙に参照しない。
- 上流 SHA を更新するときは §5 の手順で差分を評価し、この表と oracle（[`../tools/oracle`](../tools/oracle)）・golden を同じ変更で更新する。追従監査は Issue 0034 の範囲。
- 本リポジトリの `moon.mod` が上流クレートへ依存することはない（実装の移植であり、FFI ラッパーではない）。

## 2. ライセンスと帰属

| 対象 | 内容 | 状態 |
| --- | --- | --- |
| 上流コード | Apache License 2.0（`LICENSE`、著作権表示は Apache-2.0 標準本文のみで個別 copyright 行なし） | 確認済み（2026-10-16、固定 SHA の `LICENSE` を確認） |
| 本リポジトリ | Apache License 2.0（ルート `LICENSE`）。独立移植であり、原著作者とは別のプロジェクト | 設定済み |
| 帰属表示 | ルート `NOTICE` と `README.md` に上流リポジトリと固定 SHA を明記 | 設定済み |
| 上流 testdata | Apache-2.0 リポジトリに含まれる小さな生成素材（生成手順は非公開だが、リポジトリのライセンスに従う）。利用する fixture は manifest に SHA256・出所 URL・取得日を記録する | 確認済み・条件付き |
| 再配布が確認できない素材 | 同梱しない。generator で再生成するかテストを Unverified とする | 運用ルール |

- Apache-2.0 の条件（ライセンス全文の同梱、変更告知、NOTICE の保持）を満たす。派生実装であることと独自の実装変更を含むことを README / NOTICE に明示する。
- 上流由来 fixture は `tests/fixtures/manifest.json` に帰属・SHA256 を記録したものだけを `tests/fixtures/` に置く。記録のない素材を追加しない（Issue 0004）。
- ライセンス表示のレビューは Issue 0033（公開文書）と Issue 0034（追従監査）で再確認する。

## 3. 上流公開 API と MoonBit 対応

上流の公開 API（固定 SHA の `src/lib.rs` と各 `pub use`）を移植の対応表とする。
MoonBit 側の最終的な package / 公開名は Issue 0002 で確定し、本書の表を更新する。

### ルート (`lib.rs`)

| 上流 | 概要 | MoonBit 側の対応 |
| --- | --- | --- |
| `BaseBox` / `BoxHeader` / `BoxSize` / `BoxType` / `FullBox` / `FullBoxFlags` / `FullBoxHeader` | box envelope と共通ヘッダ | `src/box`（Issue 0006、完了） |
| `Either<T, U>` | 2 形態の union | `src/bytes`（後続 Issue で追加。利用は 0009 以降） |
| `FixedPointNumber` | 固定小数点数 | `src/bytes` の `FixedPointNumber`（Issue 0005、完了） |
| `Uint` / `Utf8String` / `LanguageCode` | 基本値型 | `Utf8String` / `LanguageCode` は `src/bytes`（Issue 0008、完了）。`Uint` は後続 Issue |
| `Mp4File` / `Mp4FileTime` / `TrackKind` / `SampleFlags` | 時刻・トラック・フラグ | `Mp4FileTime` / `TrackKind` は `src/bytes`（Issue 0008、完了）。`SampleFlags` は後続 Issue（0017 など）、`Mp4File` は `src/boxes`（Issue 0013） |
| `Error` / `ErrorKind` | 失敗分類 | `src/bytes` の `Mp4Error` / `ErrorKind`（Issue 0005、完了。`Either`/`Uint` 等は後続） |
| `Decode` / `Encode` / `Result` | codec trait | `src/bytes`（Issue 0006、完了） |
| `aux::{ChunkAccessor, SampleAccessor, SampleTableAccessor, SampleTableAccessorError}` | sample table 走査 | `src/boxes`（Issue 0009） |

Issue 0005 で確定した対応の補足:

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `Result<T>` | `T raise Mp4Error` | MoonBit のエラー機構（`raise`/`catch`）で表現する |
| `codec::Error` | `Mp4Error` | `Error` は MoonBit の予約型名のため改名。`kind` / `reason` / `loc`（`SourceLoc`）に加え `offset: UInt64?` と `box_type: BoxType?` を持つ |
| 長さ付き入力の読み取り | `ReadCursor`（`src/bytes`） | Big Endian、位置は成功時のみ前進、確保量は `ParseLimits` で制限 |
| 長さ付き出力の書き込み | `WriteCursor`（`src/bytes`） | 伸長バッファへ Big Endian 書き込み |
| Rust の無制限 allocation/nesting | `ParseLimits`（`src/bytes`） | 既定値 `DEFAULT_MAX_ALLOCATION_SIZE` = 1 GiB、`DEFAULT_MAX_NESTING_DEPTH` = 64、上限は `ParseLimits::new` で変更 |
| u64 → JS Number / index 変換 | `uint64_to_index` / `uint64_to_exact_double`（`src/bytes`） | 2^31-1 超の index、2^53 超の `Double` 化を暗黙に丸めず `InvalidInput` で拒否 |
| 上流 `bitstream` のビット読み | `BitReader` / `BitWriter`（`src/bitstream`） | MSB 先。終端超過は `InvalidInput`。本格的な NAL/AAC/AV1 解析は M4（0024–0026） |

Issue 0006 で確定した対応の補足:

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `BoxType::{Normal([u8; 4]), Uuid([u8; 16])}` | `BoxType::{Normal(FourCC), Uuid(Uuid)}`（`src/bytes`） | 生 4 バイト / 16 バイトを保持。表示のみ差異: 上流は UTF-8 可なら生文字列、不可ならバイト列の Debug（十進）。MoonBit は printable のとき生文字列、非 printable は hex、uuid は 8-4-4-4-12 の hex |
| `Uuid`（上流は `BoxType::Uuid([u8; 16])`） | `Uuid`（`src/bytes`） | 16 バイト固定の派生型。`from_bytes` は長さ不一致を `InvalidInput`（"uuid box type must be 16 bytes, but got N"） |
| `BoxSize` | `BoxSize::{U32, U64}`（`src/box`） | `size==1` + `largesize` は `U64`。`U32(0)` は「EOF まで」、`U64(0)` はエンコード用プレースホルダでデコードでは不正 |
| `BoxHeader::decode_header_and_payload` | `BoxHeader::decode_header_and_payload(ReadCursor)`（`src/box`） | `size==0` は渡されたカーソル末尾までをペイロードにする（トップレベル専用。入れ子の `size==0` 拒否は Issue 0007 の box tree 方針） |
| `BoxHeader::decode` の再エンコード | `Encode for BoxHeader`（`src/box`） | デコード時の `BoxSize` variant を保持する（wire-preserving）。同一ペイロードで最小幅へ畳むのは `BoxSize::to_canonical` / `BoxHeader::to_canonical` |
| `BoxHeader::MIN_SIZE` / `MAX_SIZE` | `MIN_BOX_HEADER_SIZE` / `MAX_BOX_HEADER_SIZE`（`src/box`） | associated const を持たないため package 定数（8 / 32） |
| `BoxHeader::new` / `new_variable_size`（`pub(crate)`） | `BoxHeader::new` / `new_variable_size`（`pub`） | 後続 Issue の構築とテストのために公開する |
| `BoxHeader::finalize_box_size`（`pub(crate)`、mux 用） | 未実装 | mux（Issue 0022）で必要になった時点で追加する |
| `BoxSize::with_payload_size` | `BoxSize::with_payload_size`（`src/box`） | 4 + 種別長 + payload が 32-bit 超なら largesize（+8）。u64 overflow は上流と異なり明示的に `InvalidInput` |
| `FullBoxFlags` | `FullBoxFlags`（`src/box`） | 24-bit を `UInt32` で保持。`new` は値をそのまま保持し、encode は下位 24-bit |
| `FullBoxFlags::is_set` / `from_flags` のビット位置 | `Int32` | 呼び出し側の変換を避ける。負値と 32 以上は `false` / 無視（上流の usize と同様） |
| `FullBoxHeader` / `FullBox` / `BaseBox` | 同名 trait / struct（`src/box`） | `BaseBox` は `box_type` / `is_unknown_box`（既定 `false`）/ `children`。`FullBoxHeader::from_box[F : FullBox]` |
| `Decode` / `Encode` trait | `Decode` / `Encode`（`src/bytes`） | `decode(ReadCursor) -> Self raise Mp4Error` / `encode(Self, WriteCursor) raise Mp4Error`。失敗時に位置を巻き戻す `decode_from[T]`、バイト列化する `encode_to_bytes[T]` を併設 |
| `Mp4Error` の box 情報 | `Mp4Error::with_box_type` / `box_type` フィールド（`src/bytes`） | `with_offset` と同様に初回設定のみを残し、`to_string` は `[種別] 分類: 理由 offset=N (at loc)` 形式 |

Issue 0007 で確定した対応の補足:

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `Brand`（4 バイトのブランド型） | `@bytes.FourCC` | `Brand` 型は作らず 4 バイトコードを直接使う。上流の定数（`ISOM` 等）は必要になった Issue で追加する |
| `FtypBox` / `FreeBox` / `MdatBox` / `UnknownBox` / `RootBox` | 同名（`src/boxes`）。ただし `RootBox` の variant は `Free` / `Mdat` / `Moov` / `Unknown` | `Moof` / `Mfra` / `Sidx` の variant は Issue 0017 で追加する。それまでの間、`moof` 等は `Unknown` として保持され、`RootBox::Unknown` の `is_unknown_box` は `true` になる（`Moov` は 0008 で追加済み） |
| `FtypBox::TYPE` などの associated const | 非公開ヘルパー（`ftyp_type()` 等、`src/boxes`） | `FourCC` を const 構築できないため、`normal_box_type("ftyp")` で都度作る。公開 TYPE アクセサは後続 Issue で検討する |
| `FtypBox`（`major_brand` / `minor_version` / `compatible_brands`） | `FtypBox`（`src/boxes`） | フィールドは同じ。`Encode` は canonical（最小幅、`size==0` を使わない） |
| `MdatBox::{payload: Vec<u8>}` | `MdatBox::{data_offset, data_size}`（`src/boxes`） | 意図的な差: ペイロードをコピーせず範囲だけ保持する（大容量 fixture でもメモリがファイルサイズに比例しない）。このため `Encode` は実装せず、`RootBox::encode` の `Mdat` は `Unsupported`。書き出しは `BoxHeader` を直接使う |
| `UnknownBox::decode` / `decode_top_level` / `Encode` | 同名（`src/boxes`） | `decode` は `size==0` を `InvalidData`（上流と同じ理由メッセージ "UnknownBox does not accept size=0"）、`decode_top_level` は末尾までとして受理。`Encode` はデコード時のサイズ形式を保つ（wire-preserving、`size==0` を含む） |
| （対応型なし） | `BoxNode` / `BoxTreeOptions` / `build_box_tree` / `flatten_box_tree` / `is_plain_container_box_type`（`src/boxes`） | 本リポジトリ独自。位置・サイズと FourCC を保持するヘッダーレベルの box tree 走査。上流は box 構造体に位置を保持しない。入れ子の `size==0` を拒否し、深さ・ノード数上限で `Unsupported`、payload は保持しない |
| `Mp4File`（`basic_types`） | 未実装 | Issue 0013（通常 MP4 demux）で追加する。0008 では `moov` 以下を型付き box として移植し、集約型 `Mp4File` は作らない |

### Issue 0008 で確定した対応の補足

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `Mp4FileTime`（`Duration` を保持、`from_unix_duration` / `as_duration`） | `Mp4FileTime`（`src/bytes`） | 秒 `UInt64` のみを保持する（1904-01-01 起点）。`from_secs` / `as_secs` / `from_unix_seconds`。上流のナノ秒精度 `Duration` 受け渡しは移植せず、秒未満の丸めは呼び出し側の責務とする（意図的な差） |
| `Utf8String` | `Utf8String`（`src/bytes`） | `new` は NUL を含む文字列を `None`。`Encode`/`Decode` は上流どおり NUL 終端必須（"Null-terminated string not found"）で、不正 UTF-8 を拒否する。失敗分類は上流の `Error::invalid_input` に合わせ `InvalidInput` |
| `LanguageCode` | `LanguageCode`（`src/bytes`） | 3 バイト（各 `0x60..=0x7F`）保持。`from_packed` / `to_packed` を MdhdBox の 5-bit packing に使う。未定義値は `undefined()`（`0x55C4`） |
| `TrackKind` | `TrackKind::{Audio, Video, Subtitle}`（`src/bytes`） | 上流と同じ 3 種。未知 handler を丸めない（`HdlrBox::track_kind() -> TrackKind?` が `None`） |
| `NonZeroU32` | `NonZeroU32`（`src/bytes`） | `new` は 0 で `None`。`Decode` は上流と同じ "Expected a non-zero integer, but got 0"（`InvalidInput`）。`timescale` に使う |
| `MoovBox` / `MvhdBox` / `TrakBox` / `TkhdBox` / `EdtsBox` / `ElstBox` / `MdiaBox` / `MdhdBox` / `HdlrBox` / `MinfBox` / `MediaHeader` / `DinfBox` / `DrefBox` / `UrlBox` | 同名（`src/boxes`） | 必須子 box の欠落は上流と同じ "Missing mandatory '...' box in '...' box"（`InvalidData`）。重複は最初の 1 個のみ採用し、以降は `unknown_boxes` に保持 |
| `MoovBox::mvex_box` | 未実装 | `mvex` / `mehd` / `trex` は Issue 0017 まで `unknown_boxes` に保持する（`MoovBox` は `mvhd_box` / `trak_boxes` / `unknown_boxes`） |
| `MinfBox::stbl_box` | 未実装 | `stbl` は Issue 0009 まで `unknown_boxes` に保持する。上流は `minf` の必須子に `stbl` を要求するが、0008 では `dinf` のみ必須（設計どおりの一時差。0009 で `stbl_box` を追加して必須に戻す） |
| `HdlrBox::name`（`Vec<u8>`） | `HdlrBox::name : Bytes` | 上流と同じく生バイト列として保持し、UTF-8 解釈や NUL 終端処理をしない |
| （対応型なし） | `HdlrBox::handler_type_vide()` / `handler_type_soun()` / `handler_type_subt()` / `handler_type_text()` / `track_kind()`（`src/boxes`） | 上流の `HdlrBox::HANDLER_TYPE_*` 定数と demux の `handler_type` → `TrackKind` 対応（vide/soun/subt/text → Video/Audio/Subtitle、未知は skip）をヘルパーとして公開する |
| `SmhdBox::balance`（`FixedPointNumber<u8, u8>`） | `SmhdBox::balance` + `ReadCursor::read_fixed_8_8_unsigned` / `WriteCursor::write_fixed_8_8_unsigned`（`src/bytes`） | 8.8 の整数部・小数部を符号なしバイトとして読み書きするヘルパーを追加。他の rate/volume/matrix は既存の符号付き読み書き（生ビット同一）を継続し、`FixedPointNumber` は小数部を符号なしビットで保持する |

### `boxes` / `codec_string` / `descriptors`

| 上流 | 概要 | MoonBit 側の対応（予定） |
| --- | --- | --- |
| `RootBox::{FtypBox, FreeBox, MdatBox, UnknownBox}` | ルート直下の box | `src/boxes`（Issue 0007、完了。`moof` / `mfra` / `sidx` の variant は 0017。`moov` は 0008 で `RootBox::Moov` として追加済み） |
| moov tree 群（`MoovBox` 〜 `TrexBox`） | movie/track/media/table box | `src/boxes`（`MoovBox` / `MvhdBox` / `TrakBox` / `TkhdBox` / `EdtsBox` / `ElstBox` / `MdiaBox` / `MdhdBox` / `HdlrBox` / `MinfBox` / `MediaHeader` / `DinfBox` / `DrefBox` / `UrlBox` は Issue 0008、完了。`stbl` は 0009、`mvex` / `mehd` / `trex` は 0017） |
| sample entry 群（`SampleEntry`, `Avc1Box`, `Hvc1Box`, `Hev1Box`, `Vp08Box`, `Vp09Box`, `Av01Box`, `OpusBox`, `Mp4aBox`, `FlacBox`, `StppBox`, `WvttBox`, `Tx3gBox` ほか） | コーデック別 entry | `src/boxes`（Issue 0010/0028） |
| fMP4 群（`MoofBox`, `TfhdBox`, `TrunBox`, `SidxBox`, `MfraBox` ほか） | fragment box | `src/boxes`（Issue 0017） |
| `codec_string::generate_codecs_string` | RFC 6381 codecs 文字列 | `src/boxes`（Issue 0011） |
| `descriptors::{EsDescriptor, DecoderConfigDescriptor, DecoderSpecificInfo, SlConfigDescriptor}` | MPEG-4 descriptor | `src/boxes`（Issue 0025 で利用） |

### `demux` / `mux` / `bitstream`

| 上流 | 概要 | MoonBit 側の対応（予定） |
| --- | --- | --- |
| `demux::{Mp4FileKind, Mp4FileKindDetector}` | MP4/fMP4 種別検出 | `src/demux`（Issue 0012） |
| `demux::{Mp4FileDemuxer, Input, RequiredInput, Sample, TrackInfo, DemuxError}` | 通常 MP4 の Sans I/O demux | `src/demux`（Issue 0013） |
| `demux::{Fmp4SegmentDemuxer, Fmp4FileDemuxer}` | fMP4 の demux | `src/demux`（Issue 0018/0019） |
| `mux::{Mp4FileMuxer, Mp4FileMuxerOptions, Sample, TrackMetadata, FinalizedBoxes, MuxError, estimate_maximum_moov_box_size}` | 通常 MP4 の mux | `src/mux`（Issue 0022） |
| `mux::{Fmp4SegmentMuxer, SegmentMuxerOptions}` | fMP4 segment の mux | `src/mux`（Issue 0020） |
| `bitstream::{aac, av1, h264, h265, opus, vp8, vp9}` | コーデック補助（sample entry 構築・NAL/ADTS 解析） | `src/bitstream`（Issue 0024–0026） |
| `docs::{hybrid_mp4, subtitle}` | 話題別補足ドキュメント | `docs/`（Issue 0027/0028/0033） |

### 上流の別クレート（本リポジトリの対象外）

- `crates/c-api`（C ABI）、`crates/wasm`（WASM バインディング）、`examples/dump_wasm`、`examples/transcode_wasm`、`fuzz`、`pbt` は移植対象ではない。互換性を主張しない。
- ブラウザ向けの出力は本リポジトリの MoonBit/JS ビルドとして独自に提供する（Issue 0015/0016）。

## 4. 対応規格

移植で参照する規格・文書の一覧。解釈が食い違う場合は本書の固定 SHA の上流実装を優先し、差分は Issue 0016 の比較で確認する。

| 規格・文書 | 対象 |
| --- | --- |
| ISO/IEC 14496-12 (ISOBMFF) | box 構造、`moov`/`trak`/`stbl`、fragment、`sidx`、`mfra` |
| ISO/IEC 14496-15 | AVC/HEVC の sample entry と設定 box（`avcC`/`hvcC`） |
| ISO/IEC 14496-30 | `wvtt` / `stpp` 字幕 |
| 3GPP TS 26.245 | `tx3g` 字幕 |
| RFC 6381 | `codecs` パラメーター文字列 |
| RFC 6716 / RFC 7845 | Opus（`Opus` sample entry と `dOps`） |
| RFC 9639 | FLAC（`fLaC` sample entry と `dfLa`） |
| VP Codec ISO Media File Format Binding | `vp08` / `vp09` と `vpcC` |
| AV1 Codec ISO Media File Format Binding | `av01` と `av1C` |
| MPEG-4 Audio (ISO/IEC 14496-3) | AAC の AudioSpecificConfig と ADTS |
| ISO/IEC 13818-7 / MPEG-H | 補助コードコード（必要になった時点で追記） |

## 5. 上流 SHA の更新手順

1. 新しい SHA を決定し、`docs/upstream.md`（本書）と oracle の固定値を同じ変更で更新する。
2. `git log <旧SHA>..<新SHA> -- src tests` で変更ファイル一覧を取得し、影響する移植 package を特定する。
3. `tools/oracle` で新 SHA の oracle を実行し、golden を再生成する（Issue 0004）。
4. golden 差分を確認し、意図した仕様変更かどうかを分類する。分類できない差分を candidate のバグと決めつけない。
5. `tests/fixtures/manifest.json` の fixture に変更があれば SHA256 と出所を更新する。
6. Issue 0034 の監査記録に、旧/新 SHA・差分分類・未追従項目を残す。

## 6. 参照 URL（すべて固定 SHA）

- README: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/README.md>
- AGENTS.md: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/AGENTS.md>
- lib.rs: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/lib.rs>
- codec.rs: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/codec.rs>
- basic_types.rs: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/basic_types.rs>
- demux_mp4_file.rs: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/demux_mp4_file.rs>
- mux_mp4_file.rs: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/src/mux_mp4_file.rs>
- testdata: <https://github.com/shiguredo/mp4-rs/tree/1282b704f44184ec792e1549b5d31e0c4c54dc59/tests/testdata>
- CI: <https://github.com/shiguredo/mp4-rs/blob/1282b704f44184ec792e1549b5d31e0c4c54dc59/.github/workflows/ci.yml>

## 7. 更新履歴

- 2026-10-17: Issue 0008（moov tree と時刻情報）の対応表を追記。`Mp4FileTime` の秒保持、`Utf8String`/`LanguageCode`/`TrackKind`/`NonZeroU32` の対応、`mvex`/`stbl` の一時的な未知 box 扱い（`minf` が `stbl` を必須にしない一時差）、`HdlrBox::name` の生バイト保持、`track_kind()` ヘルパーと 8.8 unsigned ヘルパーを記録。`Mp4File` の追加先を 0013 に修正。
- 2026-10-17: Issue 0007（ルート box と box tree 走査）の対応表を追記。`Brand` → `FourCC`、`MdatBox` の範囲保持（意図的な差）、`RootBox` の variant 追加予定、独自の box tree API を記録。
- 2026-10-16: 初版（Issue 0001）。固定 SHA、ライセンス、API 対応表、規格一覧、更新手順を記録。
