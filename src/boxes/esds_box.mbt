///|
/// [ISO/IEC 14496-14] ESDBox class (親: [`Mp4aBox`] などの音声サンプルエントリー)。
///
/// ElementaryStream の設定を保持する [`EsDescriptor`] を格納する FullBox。
/// 上流 `EsdsBox` に対応する。
///
/// ```mbt check
/// test {
///   let box = @boxes.EsdsBox::new(
///     @boxes.EsDescriptor::new(
///       1U,
///       @bytes.Uint::new(0UL, bits=5, offset=0).unwrap(),
///       None,
///       None,
///       None,
///       @boxes.DecoderConfigDescriptor::new(
///         @boxes.DecoderConfigDescriptor::object_type_indication_audio_iso_iec_14496_3(),
///         @boxes.DecoderConfigDescriptor::stream_type_audio(),
///         @boxes.DecoderConfigDescriptor::up_stream_false(),
///         @bytes.Uint::new(0UL, bits=24, offset=0).unwrap(),
///         0U,
///         0U,
///         None,
///       ),
///       @boxes.SlConfigDescriptor::new(),
///     ),
///   )
///   let decoded : @boxes.EsdsBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded == box, content="true")
/// }
/// ```
pub struct EsdsBox {
  /// このエントリー配下の ElementaryStream 記述子
  es : EsDescriptor
} derive(Eq, Hash, Debug)

///|
pub extend EsdsBox with Eq::{equal, not_equal}

///|
pub extend EsdsBox with Hash::{hash, hash_combine}

///|
pub extend EsdsBox with Debug::{to_repr}

///|
/// [`EsDescriptor`] を指定して作成する。
pub fn EsdsBox::new(es : EsDescriptor) -> EsdsBox {
  { es, }
}

///|
/// `esds` をデコードする。
///
/// 上流と同じく FullBox ヘッダー（version / flags）は読み飛ばすだけで保持しない。
pub impl @bytes.Decode for EsdsBox with fn decode(cursor : @bytes.ReadCursor) -> EsdsBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(esds_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(esds_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let es : EsDescriptor = @bytes.decode_from(payload_cursor)
    { es, }
  })
}

///|
pub extend EsdsBox with @bytes.Decode::{decode}

///|
/// `esds` をエンコードする。version 0 / flags 0 の固定値で書く（上流と同じ）。
pub impl @bytes.Encode for EsdsBox with fn encode(
  self : EsdsBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, esds_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    @bytes.Encode::encode(self.es, payload)
  })
}

///|
pub extend EsdsBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for EsdsBox with fn box_type(_self) {
  esds_type()
}

///|
pub impl @box.BaseBox for EsdsBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend EsdsBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ。デコード時の version は保持しない）。
pub impl @box.FullBox for EsdsBox with fn full_box_version(_self) {
  0U
}

///|
/// 常に flags 0（上流と同じ。デコード時の flags は保持しない）。
pub impl @box.FullBox for EsdsBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend EsdsBox with @box.FullBox::{full_box_version, full_box_flags}
