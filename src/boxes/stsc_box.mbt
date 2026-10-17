///|
/// [`StscBox`] が保持するエントリー。
pub struct StscEntry {
  /// この設定が始まる最初のチャンク番号（1 始まり）
  first_chunk : @bytes.NonZeroU32
  /// 該当区間の 1 チャンク当たりのサンプル数
  sample_per_chunk : UInt32
  /// 該当区間のサンプルが参照する [`StsdBox::entries`] のインデックス（1 始まり）
  sample_description_index : @bytes.NonZeroU32
} derive(Eq, Hash, Debug)

///|
pub extend StscEntry with Eq::{equal, not_equal}

///|
pub extend StscEntry with Hash::{hash, hash_combine}

///|
pub extend StscEntry with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn StscEntry::new(
  first_chunk : @bytes.NonZeroU32,
  sample_per_chunk : UInt32,
  sample_description_index : @bytes.NonZeroU32,
) -> StscEntry {
  { first_chunk, sample_per_chunk, sample_description_index, }
}

///|
/// [ISO/IEC 14496-12] SampleToChunkBox（`stsc`）(親: [`StblBox`])。
///
/// サンプルからチャンクへのマッピングを run-length 表現で保持する。上流
/// `StscBox` に対応する。
///
/// ```mbt check
/// test {
///   let box = @boxes.StscBox::new([
///     @boxes.StscEntry::new(
///       @bytes.NonZeroU32::one(),
///       2U,
///       @bytes.NonZeroU32::one(),
///     ),
///   ])
///   let decoded : @boxes.StscBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.entries.length(), content="1")
///   inspect(decoded.entries[0].sample_per_chunk, content="2")
/// }
/// ```
pub struct StscBox {
  /// (開始チャンク, チャンク当たりサンプル数, サンプル記述子インデックス) の
  /// run-length 表現によるエントリー列
  entries : Array[StscEntry]
} derive(Eq, Hash, Debug)

///|
pub extend StscBox with Eq::{equal, not_equal}

///|
pub extend StscBox with Hash::{hash, hash_combine}

///|
pub extend StscBox with Debug::{to_repr}

///|
/// エントリー列を指定して作成する。
pub fn StscBox::new(entries : Array[StscEntry]) -> StscBox {
  { entries, }
}

///|
/// `stsc` をデコードする。
///
/// `first_chunk` / `sample_description_index` が 0 の場合は
/// [`@bytes.NonZeroU32`] のデコードが失敗する（上流と同じ理由文字列）。
pub impl @bytes.Decode for StscBox with fn decode(cursor : @bytes.ReadCursor) -> StscBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stsc_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stsc_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let count = payload_cursor.read_u32()
    let entries : Array[StscEntry] = []
    let mut remaining = count
    while remaining > 0 {
      let first_chunk : @bytes.NonZeroU32 = @bytes.decode_from(payload_cursor)
      let sample_per_chunk = payload_cursor.read_u32()
      let sample_description_index : @bytes.NonZeroU32 = @bytes.decode_from(
        payload_cursor,
      )
      entries.push(
        StscEntry::new(first_chunk, sample_per_chunk, sample_description_index),
      )
      remaining = remaining - 1
    }
    { entries, }
  })
}

///|
pub extend StscBox with @bytes.Decode::{decode}

///|
/// `stsc` を canonical な形式でエンコードする。
pub impl @bytes.Encode for StscBox with fn encode(
  self : StscBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stsc_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.entries.length().reinterpret_as_uint())
    for entry in self.entries {
      @bytes.Encode::encode(entry.first_chunk, payload)
      payload.write_u32(entry.sample_per_chunk)
      @bytes.Encode::encode(entry.sample_description_index, payload)
    }
  })
}

///|
pub extend StscBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for StscBox with fn box_type(_self) {
  stsc_type()
}

///|
pub impl @box.BaseBox for StscBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend StscBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for StscBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for StscBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend StscBox with @box.FullBox::{full_box_version, full_box_flags}
