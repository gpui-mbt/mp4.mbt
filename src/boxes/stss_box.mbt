///|
/// [ISO/IEC 14496-12] SyncSampleBox（`stss`）(親: [`StblBox`])。
///
/// 同期サンプル（キーフレーム）のサンプル番号列（1 始まり）を保持する。上流
/// `StssBox` に対応する。0 が現れると [`@bytes.NonZeroU32`] のデコードが失敗する。
///
/// ```mbt check
/// test {
///   let box = @boxes.StssBox::new([
///     @bytes.NonZeroU32::one(),
///     @bytes.NonZeroU32::new(3U).unwrap(),
///   ])
///   let decoded : @boxes.StssBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.sample_numbers.length(), content="2")
///   inspect(decoded.sample_numbers[1].get(), content="3")
/// }
/// ```
pub struct StssBox {
  /// 同期サンプル（キーフレーム）のサンプル番号列（1 始まり）
  sample_numbers : Array[@bytes.NonZeroU32]
} derive(Eq, Hash, Debug)

///|
pub extend StssBox with Eq::{equal, not_equal}

///|
pub extend StssBox with Hash::{hash, hash_combine}

///|
pub extend StssBox with Debug::{to_repr}

///|
/// サンプル番号列を指定して作成する。
pub fn StssBox::new(sample_numbers : Array[@bytes.NonZeroU32]) -> StssBox {
  { sample_numbers, }
}

///|
/// `stss` をデコードする。
pub impl @bytes.Decode for StssBox with fn decode(cursor : @bytes.ReadCursor) -> StssBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stss_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stss_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let count = payload_cursor.read_u32()
    let sample_numbers : Array[@bytes.NonZeroU32] = []
    let mut remaining = count
    while remaining > 0 {
      sample_numbers.push(@bytes.decode_from(payload_cursor))
      remaining = remaining - 1
    }
    { sample_numbers, }
  })
}

///|
pub extend StssBox with @bytes.Decode::{decode}

///|
/// `stss` を canonical な形式でエンコードする。
pub impl @bytes.Encode for StssBox with fn encode(
  self : StssBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stss_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.sample_numbers.length().reinterpret_as_uint())
    for sample_number in self.sample_numbers {
      @bytes.Encode::encode(sample_number, payload)
    }
  })
}

///|
pub extend StssBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for StssBox with fn box_type(_self) {
  stss_type()
}

///|
pub impl @box.BaseBox for StssBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend StssBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for StssBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for StssBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend StssBox with @box.FullBox::{full_box_version, full_box_flags}
