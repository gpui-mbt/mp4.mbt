///|
/// FLAC メタデータブロック。上流 `FlacMetadataBlock` に対応する。
///
/// FLAC 仕様の METADATA_BLOCK 構造を表現する
/// （<https://xiph.org/flac/format.html>）。
pub struct FlacMetadataBlock {
  /// 最後のメタデータブロックかどうかを示すフラグ（1 ビット）
  last_metadata_block_flag : @bytes.Uint
  /// ブロックタイプ（7 ビット。
  /// 0: STREAMINFO, 1: PADDING, 2: APPLICATION, 3: SEEKTABLE,
  /// 4: VORBIS_COMMENT, 5: CUESHEET, 6: PICTURE）
  block_type : @bytes.Uint
  /// ブロックデータ
  block_data : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend FlacMetadataBlock with Eq::{equal, not_equal}

///|
pub extend FlacMetadataBlock with Hash::{hash, hash_combine}

///|
pub extend FlacMetadataBlock with Debug::{to_repr}

///|
/// ブロックタイプ: STREAMINFO。上流 `BLOCK_TYPE_STREAMINFO`。
pub fn FlacMetadataBlock::block_type_streaminfo() -> @bytes.Uint {
  @bytes.Uint::new(0UL, bits=7, offset=0).unwrap()
}

///|
/// ブロックタイプ: PADDING。上流 `BLOCK_TYPE_PADDING`。
pub fn FlacMetadataBlock::block_type_padding() -> @bytes.Uint {
  @bytes.Uint::new(1UL, bits=7, offset=0).unwrap()
}

///|
/// ブロックタイプ: APPLICATION。上流 `BLOCK_TYPE_APPLICATION`。
pub fn FlacMetadataBlock::block_type_application() -> @bytes.Uint {
  @bytes.Uint::new(2UL, bits=7, offset=0).unwrap()
}

///|
/// ブロックタイプ: SEEK TABLE。上流 `BLOCK_TYPE_SEEKTABLE`。
pub fn FlacMetadataBlock::block_type_seektable() -> @bytes.Uint {
  @bytes.Uint::new(3UL, bits=7, offset=0).unwrap()
}

///|
/// ブロックタイプ: VORBIS COMMENT。上流 `BLOCK_TYPE_VORBIS_COMMENT`。
pub fn FlacMetadataBlock::block_type_vorbis_comment() -> @bytes.Uint {
  @bytes.Uint::new(4UL, bits=7, offset=0).unwrap()
}

///|
/// ブロックタイプ: CUESHEET。上流 `BLOCK_TYPE_CUESHEET`。
pub fn FlacMetadataBlock::block_type_cuesheet() -> @bytes.Uint {
  @bytes.Uint::new(5UL, bits=7, offset=0).unwrap()
}

///|
/// ブロックタイプ: PICTURE。上流 `BLOCK_TYPE_PICTURE`。
pub fn FlacMetadataBlock::block_type_picture() -> @bytes.Uint {
  @bytes.Uint::new(6UL, bits=7, offset=0).unwrap()
}

///|
/// 各フィールドを指定して作成する。
///
/// `last_metadata_block_flag` / `block_type` はそれぞれ 1 ビット / 7 ビットの
/// [`@bytes.Uint`] で指定する（上流と同じ型レベルの制約を値で表したもの）。
pub fn FlacMetadataBlock::new(
  last_metadata_block_flag : @bytes.Uint,
  block_type : @bytes.Uint,
  block_data : Bytes,
) -> FlacMetadataBlock {
  { last_metadata_block_flag, block_type, block_data, }
}

///|
/// メタデータブロックをデコードする（ボックスではなくブロック列 1 要素分）。
///
/// ヘッダーは `last-metadata-block-flag(1) | block_type(7)` の 1 バイトと
/// `length`(u24) で構成される。
pub impl @bytes.Decode for FlacMetadataBlock with fn decode(
  cursor : @bytes.ReadCursor,
) -> FlacMetadataBlock raise @bytes.Mp4Error {
  let b = cursor.read_u8().to_uint64()
  let last_metadata_block_flag = @bytes.Uint::from_bits(b, bits=1, offset=7)
  let block_type = @bytes.Uint::from_bits(b, bits=7, offset=0)
  let length = cursor.read_u24()
  // `length` が残りを超える場合は read_bytes が InsufficientBuffer で失敗する
  // （上流 `check_buffer_size` と同じ分類）
  let block_data = cursor.read_bytes(length.reinterpret_as_int())
  { last_metadata_block_flag, block_type, block_data, }
}

///|
pub extend FlacMetadataBlock with @bytes.Decode::{decode}

///|
/// メタデータブロックをエンコードする。
///
/// `block_data` が 24 ビット長（最大 16777215 バイト）を超える場合は
/// [`@bytes.ErrorKind::InvalidInput`] で失敗する。
pub impl @bytes.Encode for FlacMetadataBlock with fn encode(
  self : FlacMetadataBlock,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  let length = self.block_data.length()
  if length > 0xFF_FFFF {
    raise @bytes.Mp4Error::invalid_input(
      "FLAC metadata block data is too large (max 16777215 bytes)",
    )
  }
  cursor.write_u8(
    (self.last_metadata_block_flag.to_bits() | self.block_type.to_bits()).to_uint(),
  )
  cursor.write_u24(length.reinterpret_as_uint())
  cursor.write_bytes(self.block_data)
}

///|
pub extend FlacMetadataBlock with @bytes.Encode::{encode}

///|
/// [Encapsulation of FLAC in ISO Base Media File Format] FLACSpecificBox class
/// (親: [`FlacBox`])。上流 `DflaBox` に対応する。
///
/// <https://github.com/xiph/flac/blob/master/doc/isoflac.txt>
pub struct DflaBox {
  /// FLAC メタデータブロックのリスト。
  /// 最初のブロックは必ず STREAMINFO (block_type=0) でなければならない
  metadata_blocks : Array[FlacMetadataBlock]
} derive(Eq, Hash, Debug)

///|
pub extend DflaBox with Eq::{equal, not_equal}

///|
pub extend DflaBox with Hash::{hash, hash_combine}

///|
pub extend DflaBox with Debug::{to_repr}

///|
/// メタデータブロック列を指定して作成する。
pub fn DflaBox::new(metadata_blocks : Array[FlacMetadataBlock]) -> DflaBox {
  { metadata_blocks, }
}

///|
/// `dfLa` をデコードする。
///
/// version が 0 でない場合、ブロックが 1 つも無い場合、先頭ブロックが
/// STREAMINFO でない場合、または最終ブロックの後にデータが残っている場合は
/// [`@bytes.ErrorKind::InvalidData`] で失敗する。
pub impl @bytes.Decode for DflaBox with fn decode(cursor : @bytes.ReadCursor) -> DflaBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(dfla_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(dfla_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    if full_header.version() != 0U {
      raise @bytes.Mp4Error::invalid_data(
        "Unsupported dfLa version: \{full_header.version()}",
      )
    }
    let metadata_blocks : Array[FlacMetadataBlock] = []
    while !payload_cursor.is_empty() {
      let block : FlacMetadataBlock = @bytes.decode_from(payload_cursor)
      let is_last = block.last_metadata_block_flag.as_bool()
      metadata_blocks.push(block)
      if is_last {
        break
      }
    }
    if !payload_cursor.is_empty() {
      raise @bytes.Mp4Error::invalid_data(
        "Unexpected data after last metadata block (\{payload_cursor.remaining()} bytes remaining)",
      )
    }
    if metadata_blocks.is_empty() {
      raise @bytes.Mp4Error::invalid_data(
        "dfLa box must contain at least one metadata block (STREAMINFO)",
      )
    }
    if metadata_blocks[0].block_type !=
      FlacMetadataBlock::block_type_streaminfo() {
      raise @bytes.Mp4Error::invalid_data(
        "First metadata block in dfLa must be STREAMINFO (block_type=0)",
      )
    }
    { metadata_blocks, }
  })
}

///|
pub extend DflaBox with @bytes.Decode::{decode}

///|
/// `dfLa` をエンコードする。version 0 / flags 0 の固定値で書く（上流と同じ）。
pub impl @bytes.Encode for DflaBox with fn encode(
  self : DflaBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, dfla_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    for block in self.metadata_blocks {
      @bytes.Encode::encode(block, payload)
    }
  })
}

///|
pub extend DflaBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for DflaBox with fn box_type(_self) {
  dfla_type()
}

///|
pub impl @box.BaseBox for DflaBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend DflaBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ）。
pub impl @box.FullBox for DflaBox with fn full_box_version(_self) {
  0U
}

///|
/// 常に flags 0（上流と同じ。デコード時の flags は保持しない）。
pub impl @box.FullBox for DflaBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend DflaBox with @box.FullBox::{full_box_version, full_box_flags}
