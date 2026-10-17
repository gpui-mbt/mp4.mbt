///|
/// [ISO/IEC 14496-12] ChunkOffsetBox（`stco`）(親: [`StblBox`])。
///
/// 各チャンクのファイル先頭からの絶対バイトオフセット（32-bit）を保持する。
/// 上流 `StcoBox` に対応する。値域が 32-bit に収まらない場合は [`Co64Box`] を使う。
///
/// ```mbt check
/// test {
///   let box = @boxes.StcoBox::new([0xFFFFFFFFU, 8U])
///   let decoded : @boxes.StcoBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.chunk_offsets.length(), content="2")
///   inspect(decoded.chunk_offsets[0], content="4294967295")
/// }
/// ```
pub struct StcoBox {
  /// 各チャンクのファイル先頭からの絶対バイトオフセット（32-bit）
  chunk_offsets : Array[UInt32]
} derive(Eq, Hash, Debug)

///|
pub extend StcoBox with Eq::{equal, not_equal}

///|
pub extend StcoBox with Hash::{hash, hash_combine}

///|
pub extend StcoBox with Debug::{to_repr}

///|
/// チャンクオフセット列を指定して作成する。
pub fn StcoBox::new(chunk_offsets : Array[UInt32]) -> StcoBox {
  { chunk_offsets, }
}

///|
/// `stco` をデコードする。
pub impl @bytes.Decode for StcoBox with fn decode(cursor : @bytes.ReadCursor) -> StcoBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stco_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stco_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let count = payload_cursor.read_u32()
    let chunk_offsets : Array[UInt32] = []
    let mut remaining = count
    while remaining > 0 {
      chunk_offsets.push(payload_cursor.read_u32())
      remaining = remaining - 1
    }
    { chunk_offsets, }
  })
}

///|
pub extend StcoBox with @bytes.Decode::{decode}

///|
/// `stco` を canonical な形式でエンコードする。
pub impl @bytes.Encode for StcoBox with fn encode(
  self : StcoBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stco_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.chunk_offsets.length().reinterpret_as_uint())
    for offset in self.chunk_offsets {
      payload.write_u32(offset)
    }
  })
}

///|
pub extend StcoBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for StcoBox with fn box_type(_self) {
  stco_type()
}

///|
pub impl @box.BaseBox for StcoBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend StcoBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for StcoBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for StcoBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend StcoBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] ChunkLargeOffsetBox（`co64`）(親: [`StblBox`])。
///
/// 各チャンクのファイル先頭からの絶対バイトオフセット（64-bit）を保持する。
/// 上流 `Co64Box` に対応する。
///
/// ```mbt check
/// test {
///   let box = @boxes.Co64Box::new([0x100000000UL, 8UL])
///   let decoded : @boxes.Co64Box = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.chunk_offsets.length(), content="2")
///   inspect(decoded.chunk_offsets[0], content="4294967296")
/// }
/// ```
pub struct Co64Box {
  /// 各チャンクのファイル先頭からの絶対バイトオフセット（64-bit）
  chunk_offsets : Array[UInt64]
} derive(Eq, Hash, Debug)

///|
pub extend Co64Box with Eq::{equal, not_equal}

///|
pub extend Co64Box with Hash::{hash, hash_combine}

///|
pub extend Co64Box with Debug::{to_repr}

///|
/// チャンクオフセット列を指定して作成する。
pub fn Co64Box::new(chunk_offsets : Array[UInt64]) -> Co64Box {
  { chunk_offsets, }
}

///|
/// `co64` をデコードする。
pub impl @bytes.Decode for Co64Box with fn decode(cursor : @bytes.ReadCursor) -> Co64Box raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(co64_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(co64_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let count = payload_cursor.read_u32()
    let chunk_offsets : Array[UInt64] = []
    let mut remaining = count
    while remaining > 0 {
      chunk_offsets.push(payload_cursor.read_u64())
      remaining = remaining - 1
    }
    { chunk_offsets, }
  })
}

///|
pub extend Co64Box with @bytes.Decode::{decode}

///|
/// `co64` を canonical な形式でエンコードする。
pub impl @bytes.Encode for Co64Box with fn encode(
  self : Co64Box,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, co64_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.chunk_offsets.length().reinterpret_as_uint())
    for offset in self.chunk_offsets {
      payload.write_u64(offset)
    }
  })
}

///|
pub extend Co64Box with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Co64Box with fn box_type(_self) {
  co64_type()
}

///|
pub impl @box.BaseBox for Co64Box with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend Co64Box with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for Co64Box with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for Co64Box with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend Co64Box with @box.FullBox::{full_box_version, full_box_flags}
