///|
/// [ISO/IEC 14496-12] SampleDescriptionBox（`stsd`）(親: [`StblBox`])。
///
/// サンプルエントリー列（コーデックごとの記述）を保持する。上流 `StsdBox` に
/// 対応する。version / flags は 0 固定で、デコード時は入力の FullBox ヘッダーを
/// 読み飛ばす（上流と同じ）。
///
/// ```mbt check
/// test {
///   let box = @boxes.StsdBox::new([
///     @boxes.SampleEntry::Unknown(
///       @boxes.UnknownBox::new(
///         @bytes.BoxType::Normal(
///           @bytes.FourCC::from_bytes(b"test") catch {
///             _ => abort("4 bytes")
///           },
///         ),
///         @box.BoxSize::U32(10),
///         b"\xAA\xBB",
///       ),
///     ),
///   ])
///   let bytes = @bytes.encode_to_bytes(box)
///   // stsd header (8) + full header (4) + entry_count (4) + entry (10)
///   inspect(bytes.length(), content="26")
///   let decoded : @boxes.StsdBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   inspect(decoded.entries.length(), content="1")
/// }
/// ```
pub struct StsdBox {
  /// サンプルエントリー列（コーデックごとの記述）
  entries : Array[SampleEntry]
} derive(Eq, Hash, Debug)

///|
pub extend StsdBox with Eq::{equal, not_equal}

///|
pub extend StsdBox with Hash::{hash, hash_combine}

///|
pub extend StsdBox with Debug::{to_repr}

///|
/// エントリー列を指定して作成する。
pub fn StsdBox::new(entries : Array[SampleEntry]) -> StsdBox {
  { entries, }
}

///|
/// `stsd` をデコードする。
///
/// FullBox ヘッダーは version / flags を検証せず読み飛ばし、`entry_count` 個の
/// エントリーだけを読む（上流と同じ。余りは読まない）。
pub impl @bytes.Decode for StsdBox with fn decode(cursor : @bytes.ReadCursor) -> StsdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stsd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stsd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let entry_count = payload_cursor.read_u32()
    let entries : Array[SampleEntry] = []
    let mut remaining = entry_count
    while remaining > 0 {
      entries.push(@bytes.decode_from(payload_cursor))
      remaining = remaining - 1
    }
    { entries, }
  })
}

///|
pub extend StsdBox with @bytes.Decode::{decode}

///|
/// `stsd` を canonical な形式でエンコードする。
///
/// `entry_count` は [`StsdBox::entries`] の長さから書く。FullBox ヘッダーは
/// version 0 / flags 0 になる。
pub impl @bytes.Encode for StsdBox with fn encode(
  self : StsdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stsd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.entries.length().reinterpret_as_uint())
    for entry in self.entries {
      @bytes.Encode::encode(entry, payload)
    }
  })
}

///|
pub extend StsdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for StsdBox with fn box_type(_self) {
  stsd_type()
}

///|
pub impl @box.BaseBox for StsdBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  for entry in self.entries {
    children.push(entry)
  }
  children
}

///|
pub extend StsdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for StsdBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for StsdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend StsdBox with @box.FullBox::{full_box_version, full_box_flags}
