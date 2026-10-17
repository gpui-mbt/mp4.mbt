///|
/// [`CttsBox`] が保持するエントリー。
pub struct CttsEntry {
  /// このエントリーが適用されるサンプル数
  sample_count : UInt32
  /// 合成時刻オフセット（[`MdhdBox::timescale`] 単位、すなわち media timescale 単位）
  ///
  /// version 0 では非負値、version 1 では負値も許容される。
  sample_offset : Int64
} derive(Eq, Hash, Debug)

///|
pub extend CttsEntry with Eq::{equal, not_equal}

///|
pub extend CttsEntry with Hash::{hash, hash_combine}

///|
pub extend CttsEntry with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn CttsEntry::new(
  sample_count : UInt32,
  sample_offset : Int64,
) -> CttsEntry {
  { sample_count, sample_offset, }
}

///|
/// [ISO/IEC 14496-12] CompositionOffsetBox（`ctts`）(親: [`StblBox`])。
///
/// composition time offset（CTS - DTS）を保持する。上流 `CttsBox` に対応する。
/// version 1 では [`CttsEntry::sample_offset`] に負値が使える。ラウンドトリップ時に
/// 元のバージョンを保つため独立フィールドとして持つ。
///
/// ```mbt check
/// test {
///   let box = @boxes.CttsBox::new(1U, [@boxes.CttsEntry::new(1U, -2L)])
///   let decoded : @boxes.CttsBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.version, content="1")
///   inspect(decoded.entries[0].sample_offset, content="-2")
/// }
/// ```
pub struct CttsBox {
  /// FullBox バージョン（0 または 1）
  version : UInt32
  /// エントリー列
  entries : Array[CttsEntry]
} derive(Eq, Hash, Debug)

///|
pub extend CttsBox with Eq::{equal, not_equal}

///|
pub extend CttsBox with Hash::{hash, hash_combine}

///|
pub extend CttsBox with Debug::{to_repr}

///|
/// version とエントリー列を指定して作成する。
pub fn CttsBox::new(version : UInt32, entries : Array[CttsEntry]) -> CttsBox {
  { version, entries, }
}

///|
/// `ctts` をデコードする。
///
/// version が 2 以上の場合は [`@bytes.ErrorKind::InvalidData`]
/// （`"Invalid ctts box version: {v}"`）で失敗する（上流と同じ理由文字列）。
pub impl @bytes.Decode for CttsBox with fn decode(cursor : @bytes.ReadCursor) -> CttsBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(ctts_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(ctts_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let version = full_header.version()
    if version > 1U {
      raise @bytes.Mp4Error::invalid_data(
        "Invalid ctts box version: \{version}",
      )
    }
    let count = payload_cursor.read_u32()
    let entries : Array[CttsEntry] = []
    let mut remaining = count
    while remaining > 0 {
      let sample_count = payload_cursor.read_u32()
      let sample_offset : Int64 = if version == 1U {
        payload_cursor.read_i32().to_int64()
      } else {
        payload_cursor.read_u32().to_uint64().reinterpret_as_int64()
      }
      entries.push(CttsEntry::new(sample_count, sample_offset))
      remaining = remaining - 1
    }
    { version, entries, }
  })
}

///|
pub extend CttsBox with @bytes.Decode::{decode}

///|
/// `ctts` を canonical な形式でエンコードする。
///
/// version 0 / 1 以外や、各 version で表現できない `sample_offset` は
/// [`@bytes.ErrorKind::InvalidInput`] で失敗する（上流と同じ理由文字列）。
pub impl @bytes.Encode for CttsBox with fn encode(
  self : CttsBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  let version = self.version
  if version > 1U {
    raise @bytes.Mp4Error::invalid_input("Invalid ctts box version: \{version}")
  }
  write_box_with_payload(cursor, ctts_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.entries.length().reinterpret_as_uint())
    for entry in self.entries {
      payload.write_u32(entry.sample_count)
      if version == 1U {
        if entry.sample_offset > 0x7FFFFFFFL ||
          entry.sample_offset < -0x80000000L {
          raise @bytes.Mp4Error::invalid_input(
            "ctts version 1 requires sample_offset to be in i32 range, got \{entry.sample_offset}",
          )
        }
        payload.write_i32(entry.sample_offset.to_int())
      } else {
        if entry.sample_offset < 0L || entry.sample_offset > 0xFFFFFFFFL {
          raise @bytes.Mp4Error::invalid_input(
            "ctts version 0 requires non-negative sample_offset, got \{entry.sample_offset}",
          )
        }
        payload.write_u32(entry.sample_offset.reinterpret_as_uint64().to_uint())
      }
    }
  })
}

///|
pub extend CttsBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for CttsBox with fn box_type(_self) {
  ctts_type()
}

///|
pub impl @box.BaseBox for CttsBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend CttsBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for CttsBox with fn full_box_version(self) {
  self.version
}

///|
pub impl @box.FullBox for CttsBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend CttsBox with @box.FullBox::{full_box_version, full_box_flags}
