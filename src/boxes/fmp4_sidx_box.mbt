///|
/// [ISO/IEC 14496-12] SegmentIndexBox（`sidx`）。
///
/// メディアセグメントへの参照情報を保持する。上流 `SidxBox` に対応する。
/// version 0 は 32-bit、version 1 は 64-bit の presentation time / offset を持つ。
pub struct SidxBox {
  /// 参照対象のストリーム識別子（通常は track_id）
  reference_id : UInt32
  /// この sidx が定めるタイムスケール
  timescale : UInt32
  /// 最初のサブセグメントの earliest presentation time
  earliest_presentation_time : UInt64
  /// この sidx 直後から最初のサブセグメント先頭までのバイト数
  first_offset : UInt64
  /// サブセグメント参照列
  references : Array[SidxReference]
} derive(Eq, Hash, Debug)

///|
pub extend SidxBox with Eq::{equal, not_equal}

///|
pub extend SidxBox with Hash::{hash, hash_combine}

///|
pub extend SidxBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn SidxBox::new(
  reference_id : UInt32,
  timescale : UInt32,
  earliest_presentation_time : UInt64,
  first_offset : UInt64,
  references : Array[SidxReference],
) -> SidxBox {
  {
    reference_id,
    timescale,
    earliest_presentation_time,
    first_offset,
    references,
  }
}

///|
/// `sidx` をデコードする。
pub impl @bytes.Decode for SidxBox with fn decode(cursor : @bytes.ReadCursor) -> SidxBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(sidx_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(sidx_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let version = full_header.version()
    let reference_id = payload_cursor.read_u32()
    let timescale = payload_cursor.read_u32()
    let earliest_presentation_time : UInt64 = if version == 1 {
      payload_cursor.read_u64()
    } else {
      payload_cursor.read_u32().to_uint64()
    }
    let first_offset : UInt64 = if version == 1 {
      payload_cursor.read_u64()
    } else {
      payload_cursor.read_u32().to_uint64()
    }
    let _reserved = payload_cursor.read_u16()
    let reference_count = payload_cursor.read_u16()
    let required_bytes = reference_count.reinterpret_as_int() * 12
    if required_bytes > payload_cursor.remaining() {
      raise @bytes.Mp4Error::invalid_data(
        "SidxBox reference_count exceeds remaining payload",
      )
    }
    let references : Array[SidxReference] = []
    let mut remaining = reference_count
    while remaining > 0U {
      let first_word = payload_cursor.read_u32()
      let reference_type = first_word >> 31 != 0U
      let referenced_size = first_word & 0x7FFFFFFFU
      let subsegment_duration = payload_cursor.read_u32()
      let third_word = payload_cursor.read_u32()
      let starts_with_sap = third_word >> 31 != 0U
      let sap_type = (third_word >> 28) & 0b111U
      let sap_delta_time = third_word & 0x0FFFFFFFU
      references.push(
        SidxReference::new(
          reference_type, referenced_size, subsegment_duration, starts_with_sap,
          sap_type, sap_delta_time,
        ),
      )
      remaining = remaining - 1U
    }
    {
      reference_id,
      timescale,
      earliest_presentation_time,
      first_offset,
      references,
    }
  })
}

///|
pub extend SidxBox with @bytes.Decode::{decode}

///|
/// `sidx` をエンコードする。
pub impl @bytes.Encode for SidxBox with fn encode(
  self : SidxBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  if self.references.length() > 65535 {
    raise @bytes.Mp4Error::invalid_data(
      "SidxBox reference count exceeds u16::MAX",
    )
  }
  write_box_with_payload(cursor, sidx_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    let version = full_header.version()
    @bytes.Encode::encode(full_header, payload)
    payload.write_u32(self.reference_id)
    payload.write_u32(self.timescale)
    if version == 1 {
      payload.write_u64(self.earliest_presentation_time)
      payload.write_u64(self.first_offset)
    } else {
      if self.earliest_presentation_time > 0xFFFFFFFFUL ||
        self.first_offset > 0xFFFFFFFFUL {
        raise @bytes.Mp4Error::invalid_data(
          "SidxBox version 0 requires 32-bit presentation time and first_offset",
        )
      }
      payload.write_u32(self.earliest_presentation_time.to_uint())
      payload.write_u32(self.first_offset.to_uint())
    }
    payload.write_u16(0U)
    payload.write_u16(self.references.length().reinterpret_as_uint())
    for reference in self.references {
      let type_bit : UInt32 = if reference.reference_type { 1U } else { 0U }
      payload.write_u32(
        (type_bit << 31) | (reference.referenced_size & 0x7FFFFFFFU),
      )
      payload.write_u32(reference.subsegment_duration)
      let sap_bit : UInt32 = if reference.starts_with_sap { 1U } else { 0U }
      payload.write_u32(
        (sap_bit << 31) |
        ((reference.sap_type & 0b111U) << 28) |
        (reference.sap_delta_time & 0x0FFFFFFFU),
      )
    }
  })
}

///|
pub extend SidxBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for SidxBox with fn box_type(_self) {
  sidx_type()
}

///|
pub impl @box.BaseBox for SidxBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend SidxBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for SidxBox with fn full_box_version(self) {
  if self.earliest_presentation_time > 0xFFFFFFFFUL ||
    self.first_offset > 0xFFFFFFFFUL {
    1U
  } else {
    0U
  }
}

///|
pub impl @box.FullBox for SidxBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::empty()
}

///|
pub extend SidxBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [`SidxBox`] の 1 サブセグメント参照。
pub struct SidxReference {
  /// true なら sidx への参照、false ならメディアセグメントへの参照
  reference_type : Bool
  /// 参照先のサイズ（バイト）
  referenced_size : UInt32
  /// サブセグメントの継続時間（sidx timescale 単位）
  subsegment_duration : UInt32
  /// SAP で始まるかどうか
  starts_with_sap : Bool
  /// SAP の種類（0-7）
  sap_type : UInt32
  /// SAP までのデルタ時間
  sap_delta_time : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend SidxReference with Eq::{equal, not_equal}

///|
pub extend SidxReference with Hash::{hash, hash_combine}

///|
pub extend SidxReference with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn SidxReference::new(
  reference_type : Bool,
  referenced_size : UInt32,
  subsegment_duration : UInt32,
  starts_with_sap : Bool,
  sap_type : UInt32,
  sap_delta_time : UInt32,
) -> SidxReference {
  {
    reference_type,
    referenced_size,
    subsegment_duration,
    starts_with_sap,
    sap_type,
    sap_delta_time,
  }
}
