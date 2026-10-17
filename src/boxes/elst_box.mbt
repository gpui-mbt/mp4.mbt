///|
/// [`ElstBox`] に含まれるエントリー。
///
/// 同一 struct 内で [`ElstEntry::edit_duration`] は movie timescale 単位、
/// [`ElstEntry::media_time`] は media timescale 単位という二重 timescale に
/// なっている。取り違えると再生範囲がずれるため注意する。
pub struct ElstEntry {
  /// このエントリーの継続時間（[`MvhdBox::timescale`] 単位、すなわち
  /// movie timescale 単位で表す）
  edit_duration : UInt64
  /// このエントリーに対応するメディア側の開始時刻（そのトラックの
  /// [`MdhdBox::timescale`] 単位、すなわち media timescale 単位で表す。
  /// 負値は「メディア無し（空白）」を意味する）
  media_time : Int64
  /// このエントリーの再生レート（1.0 が通常速度）
  media_rate : @bytes.FixedPointNumber
} derive(Eq, Hash, Debug)

///|
pub extend ElstEntry with Eq::{equal, not_equal}

///|
pub extend ElstEntry with Hash::{hash, hash_combine}

///|
pub extend ElstEntry with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn ElstEntry::new(
  edit_duration : UInt64,
  media_time : Int64,
  media_rate : @bytes.FixedPointNumber,
) -> ElstEntry {
  { edit_duration, media_time, media_rate, }
}

///|
/// [ISO/IEC 14496-12] EditListBox（`elst`）(親: [`EdtsBox`])。
///
/// 編集リスト（empty edit を含む）をそのまま保持する。上流 `ElstBox` に対応する。
/// 再生時刻の補正は行わない（上流がしない補正を追加しない）。
///
/// ```mbt check
/// test {
///   let box = @boxes.ElstBox::new([
///     @boxes.ElstEntry::new(1000UL, -1L, @bytes.FixedPointNumber::new(1, 0)),
///   ])
///   let decoded : @boxes.ElstBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.entries.length(), content="1")
///   inspect(decoded.entries[0].media_time, content="-1")
///   inspect(decoded.entries[0].media_rate.integer(), content="1")
/// }
/// ```
pub struct ElstBox {
  /// 編集リストのエントリー列
  entries : Array[ElstEntry]
} derive(Eq, Hash, Debug)

///|
pub extend ElstBox with Eq::{equal, not_equal}

///|
pub extend ElstBox with Hash::{hash, hash_combine}

///|
pub extend ElstBox with Debug::{to_repr}

///|
/// エントリー列を指定して作成する。
pub fn ElstBox::new(entries : Array[ElstEntry]) -> ElstBox {
  { entries, }
}

///|
/// `elst` をデコードする。
///
/// version 0 では `edit_duration` を 32-bit、`media_time` を 32-bit（符号拡張）で
/// 読み、version 1 ではそれぞれ 64-bit で読む。どちらも [`ElstEntry`] の
/// `UInt64` / `Int64` にそのまま保持する。
pub impl @bytes.Decode for ElstBox with fn decode(cursor : @bytes.ReadCursor) -> ElstBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(elst_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(elst_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let count = payload_cursor.read_u32()
    let entries : Array[ElstEntry] = []
    let mut remaining = count
    while remaining > 0 {
      let edit_duration : UInt64 = if full_header.version() == 1 {
        payload_cursor.read_u64()
      } else {
        payload_cursor.read_u32().to_uint64()
      }
      let media_time : Int64 = if full_header.version() == 1 {
        payload_cursor.read_i64()
      } else {
        payload_cursor.read_i32().to_int64()
      }
      let media_rate = payload_cursor.read_fixed_16_16()
      entries.push(ElstEntry::new(edit_duration, media_time, media_rate))
      remaining = remaining - 1
    }
    { entries, }
  })
}

///|
pub extend ElstBox with @bytes.Decode::{decode}

///|
/// `elst` を canonical な形式でエンコードする。
///
/// version は [`@box.FullBox`] の実装が決める。version 0 で書く場合は
/// 32-bit へ切り詰めた値が書かれる（version 0 を選ぶ条件により値は収まっている）。
pub impl @bytes.Encode for ElstBox with fn encode(
  self : ElstBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, elst_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    payload.write_u32(self.entries.length().reinterpret_as_uint())
    for entry in self.entries {
      if full_header.version() == 1 {
        payload.write_u64(entry.edit_duration)
        payload.write_i64(entry.media_time)
      } else {
        payload.write_u32(entry.edit_duration.to_uint())
        payload.write_i32(entry.media_time.to_int())
      }
      payload.write_fixed_16_16(entry.media_rate)
    }
  })
}

///|
pub extend ElstBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for ElstBox with fn box_type(_self) {
  elst_type()
}

///|
pub impl @box.BaseBox for ElstBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend ElstBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// `edit_duration` が 32-bit に収まらない、または `media_time` が 32-bit の
/// 符号付き範囲に収まらないエントリーがある場合は version 1 を使う
/// （上流と同じ判定）。
pub impl @box.FullBox for ElstBox with fn full_box_version(self) {
  let mut large = false
  for entry in self.entries {
    if entry.edit_duration > 0xFFFFFFFFUL ||
      entry.media_time > 0x7FFFFFFFL ||
      entry.media_time < -0x80000000L {
      large = true
    }
  }
  if large {
    1U
  } else {
    0U
  }
}

///|
pub impl @box.FullBox for ElstBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend ElstBox with @box.FullBox::{full_box_version, full_box_flags}
