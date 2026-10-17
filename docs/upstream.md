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
| `Either<T, U>` | 2 形態の union | `src/bytes` の `Either[A, B]`（Issue 0009、完了。`BaseBox` の転送 impl は `src/box`） |
| `FixedPointNumber` | 固定小数点数 | `src/bytes` の `FixedPointNumber`（Issue 0005、完了） |
| `Uint` / `Utf8String` / `LanguageCode` | 基本値型 | `Utf8String` / `LanguageCode` は `src/bytes`（Issue 0008、完了）。`Uint` は `src/bytes`（Issue 0010、完了。実行時フィールド化の差は補足参照） |
| `Mp4File` / `Mp4FileTime` / `TrackKind` / `SampleFlags` | 時刻・トラック・フラグ | `Mp4FileTime` / `TrackKind` は `src/bytes`（Issue 0008、完了）。`SampleFlags` は後続 Issue（0017 など）、`Mp4File` は `src/boxes`（Issue 0013） |
| `Error` / `ErrorKind` | 失敗分類 | `src/bytes` の `Mp4Error` / `ErrorKind`（Issue 0005、完了。`Either` は 0009、`Uint` は 0010 で追加済み） |
| `Decode` / `Encode` / `Result` | codec trait | `src/bytes`（Issue 0006、完了） |
| `aux::{ChunkAccessor, SampleAccessor, SampleTableAccessor, SampleTableAccessorError}` | sample table 走査 | `src/boxes`（Issue 0009、完了） |

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
| `MinfBox::stbl_box` | `MinfBox::stbl_box : StblBox` | 0008 では `stbl` を `unknown_boxes` に保持する一時差があった（`dinf` のみ必須）。0009 で `stbl_box` を追加して必須子に戻した（欠落時は `InvalidData "Missing mandatory 'stbl' box in 'minf' box"`。`MinfBox::new` も `StblBox` を必須引数にする） |
| `HdlrBox::name`（`Vec<u8>`） | `HdlrBox::name : Bytes` | 上流と同じく生バイト列として保持し、UTF-8 解釈や NUL 終端処理をしない |
| （対応型なし） | `HdlrBox::handler_type_vide()` / `handler_type_soun()` / `handler_type_subt()` / `handler_type_text()` / `track_kind()`（`src/boxes`） | 上流の `HdlrBox::HANDLER_TYPE_*` 定数と demux の `handler_type` → `TrackKind` 対応（vide/soun/subt/text → Video/Audio/Subtitle、未知は skip）をヘルパーとして公開する |
| `SmhdBox::balance`（`FixedPointNumber<u8, u8>`） | `SmhdBox::balance` + `ReadCursor::read_fixed_8_8_unsigned` / `WriteCursor::write_fixed_8_8_unsigned`（`src/bytes`） | 8.8 の整数部・小数部を符号なしバイトとして読み書きするヘルパーを追加。他の rate/volume/matrix は既存の符号付き読み書き（生ビット同一）を継続し、`FixedPointNumber` は小数部を符号なしビットで保持する |

### Issue 0009 で確定した対応の補足

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `basic_types::Either<T, U>` | `Either[A, B]`（`src/bytes`） | `A`/`B` の 2 variant。上流の `BaseBox` 転送は `pub impl[A : BaseBox, B : BaseBox] BaseBox for @bytes.Either[A, B]`（`src/box`）で行う。`pub extend @bytes.Either with BaseBox` はコンパイルエラー 4059（型とトレイトが別 package）のため使えない。`Either` へのトレイト呼び出しは `@box.BaseBox::box_type(either)` と書く（メソッド記法不可。意図的な差） |
| `boxes_moov_tree::{StblBox, StsdBox, SttsBox, CttsBox, CslgBox, SdtpBox, StscBox, StszBox, StcoBox, Co64Box, StssBox}` | 同名（`src/boxes`） | 必須子の欠落は上流と同じ "Missing mandatory '...' box in 'stbl' box"（`stco`/`co64` は `"stco' or 'co64"`）。`stco` と `co64` が両方あるときは両方 decode してから `stco` を採用（`Either::A`）。重複 box は最初の 1 個を採用し、以降は `unknown_boxes`。`ctts`/`cslg` は version 0/1、`sdtp` は version 0 のみ |
| `SampleEntry`（型付き variant 群） | `SampleEntry::{Avc1, Hev1, Hvc1, Vp08, Vp09, Av01, Opus, Mp4a, Flac, Unknown}`（`src/boxes`） | Issue 0010 で型付き variant を追加（詳細は「Issue 0010 で確定した対応の補足」）。`Stpp`/`Wvtt`/`Tx3g` は 0028 まで `Unknown` 分類 |
| `SttsBox::from_sample_deltas` | `SttsBox::from_sample_deltas(Iter[UInt])`（`src/boxes`） | 連続する同値を run-length 集約する。`sample_count` の u32 合計が溢れると `InvalidData "stts sample_count overflow"` |
| `SdtpSampleFlags` | `SdtpSampleFlags { value : Byte }`（`src/boxes`） | `from_fields(is_leading, sample_depends_on, sample_is_depended_on, sample_has_redundancy)` / `get` と 4 つの 2-bit accessor。2-bit を超える入力はマスクする |
| `MinfBox::stbl_box` | `MinfBox::stbl_box : StblBox`（`src/boxes`） | 0008 の一時差を解消し、`stbl` を `minf` の必須子に戻した。`MinfBox::new(media_header?, dinf_box, stbl_box, unknown_boxes)` |
| `auxiliary::{SampleTableAccessor, SampleAccessor, ChunkAccessor}` | 同名（`src/boxes`） | 上流の `T: AsRef<StblBox>` ジェネリクスと `AsRef` impl は移植しない（上流の唯一の利用者は所有 `StblBox` を渡す）。`SampleTableAccessor::new(StblBox)` が値を受け取り、accessor は `StblBox` をコピー保持する（値セマンティクス。意図的な差）。`samples()`/`chunks()` は `Iter` を返し、per-sample の計算は O(1)（全 sample 配列は生成しない。run-length prefix table のみ box の entry 数に比例）。`get_sample`/`get_chunk`/`get_sample_by_timestamp` は範囲外・該当なしで `None` |
| `auxiliary::SampleTableAccessorError` | `SampleTableAccessorError`（`suberror`、`src/boxes`） | 上流と同じ 8 variant・フィールド名・`Display` 文言（`to_string`）を持ち、`raise` で返す。`sample_entry_count` は `UInt`、`stsc_entry_index` は `Int` で保持する |
| （アクセスの端境界） | `chunk()` は `partition_point(\|x\| x <= index) - 1`、`get_sample_by_timestamp` は上流と同じ binary search | ゼロ件 `stts`/`ctts` が異なる値で並ぶ場合、上流 `binary_search` のどちらの重複キーを返すかは未規定。MoonBit 側は決定的（leftmost）に実装し、この形の入力は oracle 差分から除外して unit test のみで固定する |
| （対応型なし） | oracle `sample-tables` / `sample-tables-cases` / `sample-tables-fixtures`（`tools/oracle`） | `moov-tree` と同じ正規化 JSON / `--moonbit` 生成。`input` は絶対 path ではなく `name`/`size`/`sha256`、`moov_error` で `moov` 抽出・decode 失敗を表す（リポジトリの再現性ルール）。golden は `src/boxes/sample_table_oracle_*.mbt` と差分比較 |

### Issue 0010 で確定した対応の補足

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `basic_types::Uint<T, BITS, OFFSET>` | `Uint { value : UInt64, bits : Int, offset : Int }`（`src/bytes`） | コンパイル時ジェネリクスのビット幅・オフセットを実行時フィールドに写像した（意図的な差）。`new` は値が `bits` に収まらない場合 `None`、`from_bits` は格納幅の全ビットから同じ幅・オフセットの部分ビットを切り出す。`get`/`to_bits`/`as_bool` は上流と同じ意味 |
| `basic_types::NonZeroU16` | `NonZeroU16`（`src/bytes`） | `NonZeroU32` と同じ構成。`NonZeroU16::MIN` は `one()`、decode で 0 は `invalid_input "Expected a non-zero integer, but got 0"` |
| `FixedPointNumber<u16, u16>` の読み書き | `ReadCursor::read_fixed_16_16_unsigned` / `WriteCursor::write_fixed_16_16_unsigned`（`src/bytes`） | 整数部・小数部とも符号なし u16 として読み書きする。`audio_sample_rate`（u16.u16）と映像 `horizresolution`/`vertresolution` で使用 |
| `boxes_sample_entry::{VisualSampleEntryFields, AudioSampleEntryFields}` | 同名（`src/boxes`） | 上流と同じ 78/28 バイトレイアウトと reserved/pre_defined フィールド破棄。`compressorname` は生の 32 バイトを保持し、`depth`/`pre_defined` 末尾は定数化しない（値を保持して再エンコードする） |
| `SampleEntry::{Avc1, Hev1, Hvc1, Vp08, Vp09, Av01, Opus, Mp4a, Flac, Unknown}` | 同名 variant（`src/boxes`） | FourCC で dispatch する `Decode` と variant 委譲の `Encode`/`BaseBox`。`Stpp`/`Wvtt`/`Tx3g` は 0028 まで `Unknown` に分類される（字幕 entry は上流と異なり型付き variant を持たない一時差）。各 entry の必須設定 box（`avcC`/`hvcC`/`vpcC`/`av1C`/`dOps`/`esds`/`dfLa`）の欠落・重複・未知子の扱いは上流と同じ |
| `SampleEntry::{audio_channel_count, audio_sample_rate, audio_sample_size, video_resolution}` | 同名メソッド（`src/boxes`） | `audio_channel_count` は `channelcount` の下位 8 ビット（上流の `as u8` 相当）、`audio_sample_rate` は整数部のみ（上流 `u16` と同じ切り捨て） |
| `boxes_sample_entry::{Avc1Box, AvccBox, Hev1Box, Hvc1Box, HvccBox, HvccNalUintArray, Vp08Box, Vp09Box, VpccBox, Av01Box, Av1cBox, OpusBox, DopsBox, Mp4aBox, FlacBox, DflaBox, FlacMetadataBlock}` | 同名（`src/boxes`） | `Hev1Box`/`Hvc1Box` と `Vp08Box`/`Vp09Box` は decode/encode 共有の内部ヘルパー経由。上流の `impl` 内 `const TYPE`/`VERSION`/`CONFIGURATION_VERSION` は `support.mbt` の box_type ヘルパーと各ファイル内定数に対応する |
| `descriptors::{EsDescriptor, DecoderConfigDescriptor, DecoderSpecificInfo, SlConfigDescriptor}` | 同名（`src/boxes`） | 上流と同じ tag/size（拡張 size バイト対応）の decode/encode。`SlConfigDescriptor` は `predefined==2` のみ受理し、それ以外は `unsupported "Unsupported `SLConfigDescriptor.predefined` value: {n}"`。descriptor の tag 不一致・サイズ超過は上流と同じ `invalid_data` 分類 |
| `EsdsBox` | 同名（`src/boxes`） | `es : EsDescriptor` のみを持つ FullBox（version 0） |
| （上流の decode と encode の非対称） | `avcC` profile が 66/77/88 以外で拡張フィールドなし → decode 成功・encode は `invalid_input "Missing 'chroma_format' field in 'avcC' box"` | oracle ケース `avc1_profile100_no_tail` で凍結。`Encode` でも `Mp4Error` を返すため同じ分類で再現する |
| （対応型なし） | oracle `sample-entries` / `sample-entries-cases` / `sample-entries-fixtures`（`tools/oracle`） | 各 `stsd` entry を上流で再エンコードした `input` と凍結 snapshot を生成する。decode 成功・encode 失敗の組合せは `encode_error_kind`/`encode_error_reason` で表す。golden は `src/boxes/sample_entry_oracle_*.mbt` と差分比較 |

### Issue 0011 で確定した対応の補足

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `codec_string::from_sample_entry` | `from_sample_entry`（`src/codec_string`） | `SampleEntry` を受け取り `String` または `Mp4Error` を返す同名の自由関数。`Avc1`/`Hev1`/`Hvc1`/`Vp08`/`Vp09`/`Av01`/`Mp4a` は各 binding 形、`Opus`/`Flac` は 4CC のみを返す。`Unknown` は `unsupported "codec string is unsupported for unknown sample entry type `{4CC}`"`（上流文言を保持）。字幕系 `stpp`/`wvtt`/`tx3g` は 0028 まで `Unknown` 分類のため unsupported になる一時差 |
| `codec_string` の書式規則 | 同名の内部 helper（`src/codec_string`） | `avc1` は 3 バイト小文字 hex（上流 `H264ProfileLevelId::to_hex` 相当をインライン化）、HEVC Annex E（profile space の `A`/`B`/`C`、compat の bit-reverse 大文字 hex 先頭ゼロ省略、tier `L`/`H`、48bit constraint の末尾ゼロ省略・最低 1 バイト）、AV1（`av01.<profile>.<level:02><tier>.<bitdepth:02>`、bit depth の `seq_profile`/`high_bitdepth`/`twelve_bit` 分岐）、VP（`<4CC>.PP.LL.DD` 十進 2 桁）、`mp4a.<OTI:02x>`（OTI `0x40` で AOT 追記、AOT 31 のエスケープ形式対応）。数値書式はすべて手続き的な固定桁 hex/dec で locale 非依存 |
| `audio_object_type_from_asc` | 同名（`src/codec_string`、非公開） | ASC 先頭の `audioObjectType` のみ読む。空 ASC・AOT 31 の切り詰めは上流と同じ `invalid_data` 文言 |
| `H264ProfileLevelId::to_hex` | `avc1_codec_string` 内の `hex_lower_padded` ×3（`src/codec_string`） | `H264ProfileLevelId` 自体は `src/bitstream`（Issue 0024）の範囲のため未移植。codec string に必要な `{:02x}{:02x}{:02x}` 部分だけを再現 |
| （対応型なし） | oracle `codec-strings-cases`（`tools/oracle`） | 0010 の `sample_entry_cases` 全件 + 全 fixture entry を入力に、上流の `from_sample_entry` 出力（成功文字列または kind/reason）を凍結。`decode_ok=false` の行はエントリーの decode エラーを記録する。golden は `src/codec_string/codec_string_oracle_cases_test.mbt` と差分比較 |

### `boxes` / `codec_string` / `descriptors`

| 上流 | 概要 | MoonBit 側の対応（予定） |
| --- | --- | --- |
| `RootBox::{FtypBox, FreeBox, MdatBox, UnknownBox}` | ルート直下の box | `src/boxes`（Issue 0007、完了。`moof` / `mfra` / `sidx` の variant は 0017。`moov` は 0008 で `RootBox::Moov` として追加済み） |
| moov tree 群（`MoovBox` 〜 `TrexBox`） | movie/track/media/table box | `src/boxes`（`MoovBox` / `MvhdBox` / `TrakBox` / `TkhdBox` / `EdtsBox` / `ElstBox` / `MdiaBox` / `MdhdBox` / `HdlrBox` / `MinfBox` / `MediaHeader` / `DinfBox` / `DrefBox` / `UrlBox` は Issue 0008、`stbl` 配下の table 群は Issue 0009、いずれも完了。`mvex` / `mehd` / `trex` は 0017） |
| sample entry 群（`SampleEntry`, `Avc1Box`, `Hvc1Box`, `Hev1Box`, `Vp08Box`, `Vp09Box`, `Av01Box`, `OpusBox`, `Mp4aBox`, `FlacBox`, `StppBox`, `WvttBox`, `Tx3gBox` ほか） | コーデック別 entry | `src/boxes`（映像・音声の型付き entry は Issue 0010 で完了。字幕系 `StppBox`/`WvttBox`/`Tx3gBox` は Issue 0028。それまでは `SampleEntry::Unknown` に分類される） |
| fMP4 群（`MoofBox`, `TfhdBox`, `TrunBox`, `SidxBox`, `MfraBox` ほか） | fragment box | `src/boxes`（Issue 0017） |
| `codec_string::from_sample_entry` | RFC 6381 codecs 文字列 | `src/codec_string`（Issue 0011、完了。字幕系は 0028 まで `Unknown` 経由で unsupported） |
| `descriptors::{EsDescriptor, DecoderConfigDescriptor, DecoderSpecificInfo, SlConfigDescriptor}` | MPEG-4 descriptor | `src/boxes`（Issue 0010 で `esds` とともに実装済み、0025 でも利用） |

### Issue 0012 で確定した対応の補足

| 上流 | MoonBit 側 | 備考 |
| --- | --- | --- |
| `demux::Mp4FileKind` | `Mp4FileKind::{Mp4, FragmentedMp4}`（`src/demux`） | `moov` 内の `mvex` の有無のみで判定する。現行の `MoovBox` は `mvex` を型付き field で持たないため `unknown_boxes` を走査する（`mvex`/`mehd`/`trex` の型付けは Issue 0017 で差し替える） |
| `demux::Mp4FileKindDetector` | `Mp4FileKindDetector`（`src/demux`） | `new()` / `required_input()` / `handle_input(Input)` / `file_kind()` の同名 API。`required_input()` は検出後・エラー保持後に `None` を返す。`file_kind()` は `Mp4FileKind?` を返し、保持したエラーは `DemuxError` として raise する |
| `demux::{RequiredInput, Input}` | 同名（`src/demux`） | `RequiredInput::{position : UInt64, size : UInt64?}`（`size=None` は EOF まで）、`Input::{position : UInt64, data : BytesView}`。`usize` を `UInt64` に写像した。`is_satisfied_by` / `to_input` / `Input::slice_range` も同名で移植。上流と同じく「要求位置を含み、要求終端（あれば）を含む」満足規則 |
| `demux::DemuxError` | 同名（`src/demux`） | `DecodeError(@bytes.Mp4Error)` / `SampleTableError(@boxes.SampleTableAccessorError)` / `InvalidState(String)` / `InputRequired(RequiredInput)`。`input_required` helper と `to_string`（上流 `Display` 相当）も同名。上流は `From<Error>` で `Mp4Error` を自動変換するが、MoonBit 側は decode 呼び出しを `wrap_decode` で明示的に `DecodeError` に包む |
| `usize::try_from(box_size)` 検査 | `max_usable_size`（`src/demux`） | Rust では `usize` 変換失敗時に `"ftyp box size exceeds usize::MAX"` / `"moov box size exceeds usize::MAX"`。MoonBit ではバッファ長が `Int` なので `Int` 最大値（0x7FFFFFFF）を上限として同じエラーを raise する（32bit 環境の上流と同じ意味） |
| `MoovBox::mvex_box.is_some()` | `moov_box.unknown_boxes` 内の `mvex` box_type 走査（`src/demux`） | 判定論理は同一。`MoovBox` の `mvex` 型付けが入った時点で置き換える |
| （対応型なし） | oracle `kind-detector-cases --moonbit`（`tools/oracle`） | 9 fixture + 合成ケース（non-faststart、未知 box、largesize、size=0、`moov` 未発見、offset オーバーフロー、ftyp 種別/サイズ異常）を上流検出器に通し、`required_input()` の要求列と最終結果（kind または classification/kind/box_type/reason）を凍結。golden は `src/demux/kind_detector_oracle_cases_test.mbt` と差分比較。`moov` より前の `mdat` payload を要求しないことも要求列で検証する |

### Issue 0013 で確定した対応の補足

| 上流（`demux_mp4_file.rs`） | MoonBit | 備考 |
| --- | --- | --- |
| `demux::Mp4FileDemuxer` | `Mp4FileDemuxer`（`src/demux`） | `new()` / `required_input()` / `handle_input(Input)` / `tracks()` / `next_sample()` / `prev_sample()` / `seek(Duration)` の同名 API。状態機械（`ReadFtypBoxHeader → ReadFtypBox → ReadMoovBoxHeader → ReadMoovBox → Initialized`）と、各フェーズ末尾で次フェーズへ連鎖する上流の再帰呼び出しもそのまま移植 |
| `demux::TrackInfo` | `TrackInfo`（`src/demux`） | `track_id : UInt` / `kind : @bytes.TrackKind` / `duration : UInt64` / `timescale : @bytes.NonZeroU32`。`u32` → `UInt`、`u64` → `UInt64` の写像 |
| `demux::Sample<'a>` | `Sample`（`src/demux`） | `track` / `sample_entry` は上流では demuxer 内部への参照だが、MoonBit 側は値として保持する（`TrackInfo` は不変、`SampleEntry` はデコード済み共有値）。`sample_entry` は sample entry index が変わり内容も異なる場合だけ `Some`（上流の最適化と同じく、index が同じなら内容比較しない） |
| `core::time::Duration` | `Duration`（`src/demux`） | `seek` の引数用に `secs : UInt64` + `nanos : UInt`（< 1e9）の不変型として移植。`new` / `from_secs` / `from_millis` / `as_secs` / `subsec_nanos` を提供 |
| `Duration::from_secs(timestamp) / timescale` 比較 | `timestamp_key`（`src/demux`） | サンプル順の比較は `(secs, nanos)` の辞書順キーで行う（secs = `t / ts`、nanos = `(t % ts) * 1_000_000_000 / ts`）。浮動小数を経由しないため精度劣化はなく、同時刻 tie-break は上流と同じく走査順で先のトラックが残る |
| `duration_to_timestamp` | 同名（`src/demux`、package 内部） | `seek` 用の `Duration` → track timescale 変換。`secs * timescale` / 加算のオーバーフローは上流と同じ `"timestamp overflow"` の `DecodeError` |
| `handle_input_error.take()` | `ensure_initialized`（`src/demux`、package 内部） | 保持したエラーは `tracks` / `next_sample` / `prev_sample` / `seek` のいずれかが一度だけ取り出し、以後は `required_input()` の状態から `InputRequired` が返る。エラー保持中 `required_input()` は `None` |
| `SampleTableAccessorError → DemuxError` 変換 | `wrap_sample_table`（`src/demux`、package 内部） | 上流の `From` 実装相当。`stbl` 不整合は `SampleTableError` として raise する |
| 非 `moov` size 0 box | `read_moov_box_header` 内の `"moov box not found"` | 上流と同じ。size 0 の非 `moov` ボックスは「ファイル末尾まで」と解釈されるため moov は存在しないと判定する |
| box offset の加算 | `offset + box_size` の前に上限検査（`src/demux`） | 破損入力で `UInt64` が回り込まないよう防御する点だけ上流より厳しい（上流は `usize` で表せない巨大 size を先に拒否するため到達不能） |
| `handler_type` → `TrackKind` | `HdlrBox::track_kind()`（`src/boxes`） | `vide` / `soun` / `subt` / `text` → `Video` / `Audio` / `Subtitle`、それ以外は `None` でトラックを skip（上流と同じく panic しない） |
| （対応型なし） | oracle `demux-cases --moonbit`（`tools/oracle`） | 9 fixture + 上流 `Mp4FileMuxer` で生成した合成ファイル（video+audio の timescale 跨ぎ、audio 先頭 tie-break、`ctts` v0/v1、字幕 `stpp`、未知 `hdlr`、faststart、空 `moov`、`stsz` 不整合、`moov` 欠落、size 0 `ftyp`、先頭非 `ftyp`）を上流 demuxer に通し、要求列・track 行・前後両方向の sample 行・`seek` プローブ結果・エラー分類を凍結。golden は `src/demux/mp4_file_demux_oracle_cases_test.mbt`、driver は `mp4_file_demux_oracle_test.mbt`。上流 `Error` の `reason` が常に空の `insufficient_buffer` だけ比較時に正規化する（MoonBit 側は診断文を持つ） |

### `demux` / `mux` / `bitstream`

| 上流 | 概要 | MoonBit 側の対応（予定） |
| --- | --- | --- |
| `demux::{Mp4FileKind, Mp4FileKindDetector}` | MP4/fMP4 種別検出 | `src/demux`（Issue 0012、完了） |
| `demux::{Input, RequiredInput, DemuxError}` | 共有の入力契約 | `src/demux`（Issue 0012、完了。0013 の `Mp4FileDemuxer` と共用する） |
| `demux::{Mp4FileDemuxer, Input, RequiredInput, Sample, TrackInfo, DemuxError}` | 通常 MP4 の Sans I/O demux | `src/demux`（Issue 0013、完了。`prev_sample` / `seek` / `Duration` も同名で移植） |
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

- 2026-10-18: Issue 0013（通常 MP4 demuxer）の対応表を追記。`Mp4FileDemuxer` の同名 API（`prev_sample` / `seek` / `Duration` 含む）、`TrackInfo` / `Sample`、`(secs, nanos)` 辞書順の整数タイムスタンプ比較、エラー保持の take セマンティクス、未知 `hdlr` の skip、offset 加算の防御検査、oracle `demux-cases`（muxer 生成の合成入力を含む）を記録。
- 2026-10-17: Issue 0011（codec string）の対応表を追記。`codec_string::from_sample_entry` → `src/codec_string` の同名関数、各 binding の書式規則（HEVC Annex E の bit-reverse / constraint 末尾省略、AV1 bit depth 分岐、AOT 31 エスケープ）、`H264ProfileLevelId` の未移植部分、字幕 entry の一時差（unsupported）、oracle `codec-strings-cases` を記録。
- 2026-10-17: Issue 0010（型付き video/audio sample entry）の対応表を追記。`Uint<T,BITS,OFFSET>` の実行時フィールド化、`NonZeroU16`、u16.u16 unsigned ヘルパー、`Visual`/`AudioSampleEntryFields`、9 つの型付き `SampleEntry` variant と設定 box 群、descriptor/`EsdsBox`、字幕 entry の `Unknown` 継続（0028 までの一時差）、`avcC` decode/encode 非対称、oracle `sample-entries` 系モードを記録。
- 2026-10-17: Issue 0009（stbl と SampleTableAccessor）の対応表を追記。`Either` と `src/box` の `BaseBox` 転送 impl（`pub extend` 不可の理由）、`SampleEntry` の unknown-only（0010 で型付き化）、`MinfBox::stbl_box` の必須化（0008 の一時差の解消）、非ジェネリック accessor（`AsRef` を移植しない意図的な差）、`SampleTableAccessorError` の対応、未規定の重複キー探索を差分対象外にして leftmost 固定する方針、oracle `sample-tables` 系モードを記録。
- 2026-10-17: Issue 0008（moov tree と時刻情報）の対応表を追記。`Mp4FileTime` の秒保持、`Utf8String`/`LanguageCode`/`TrackKind`/`NonZeroU32` の対応、`mvex`/`stbl` の一時的な未知 box 扱い（`minf` が `stbl` を必須にしない一時差）、`HdlrBox::name` の生バイト保持、`track_kind()` ヘルパーと 8.8 unsigned ヘルパーを記録。`Mp4File` の追加先を 0013 に修正。
- 2026-10-17: Issue 0007（ルート box と box tree 走査）の対応表を追記。`Brand` → `FourCC`、`MdatBox` の範囲保持（意図的な差）、`RootBox` の variant 追加予定、独自の box tree API を記録。
- 2026-10-16: 初版（Issue 0001）。固定 SHA、ライセンス、API 対応表、規格一覧、更新手順を記録。
