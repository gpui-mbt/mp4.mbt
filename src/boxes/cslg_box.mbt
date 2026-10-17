///|
/// [ISO/IEC 14496-12] CompositionToDecodeBox（`cslg`）(親: [`StblBox`])。
///
/// composition と decode の時刻関係を要約する。上流 `CslgBox` に対応する。
/// 全時刻フィールドは media timescale 単位（[`MdhdBox::timescale`]）で表す。
///
/// ```mbt check
/// test {
///   let box = @boxes.CslgBox::new(0U, 1L, -2L, 3L, -4L, 5L)
///   let decoded : @boxes.CslgBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.version, content="0")
///   inspect(decoded.least_decode_to_display_delta, content="-2")
/// }
/// ```
pub struct CslgBox {
  /// FullBox バージョン（0 または 1）
  ///
  /// version 1 では各フィールドが 64-bit、version 0 では 32-bit で符号化される。
  /// ラウンドトリップ時に元のバージョンを保つため独立フィールドとして持つ。
  version : UInt32
  /// composition から decode への時刻シフト量（media timescale 単位）
  composition_to_dts_shift : Int64
  /// decode から display への最小差分（media timescale 単位）
  least_decode_to_display_delta : Int64
  /// decode から display への最大差分（media timescale 単位）
  greatest_decode_to_display_delta : Int64
  /// このトラックの composition（表示）開始時刻（media timescale 単位）
  composition_start_time : Int64
  /// このトラックの composition（表示）終了時刻（media timescale 単位）
  composition_end_time : Int64
} derive(Eq, Hash, Debug)

///|
pub extend CslgBox with Eq::{equal, not_equal}

///|
pub extend CslgBox with Hash::{hash, hash_combine}

///|
pub extend CslgBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn CslgBox::new(
  version : UInt32,
  composition_to_dts_shift : Int64,
  least_decode_to_display_delta : Int64,
  greatest_decode_to_display_delta : Int64,
  composition_start_time : Int64,
  composition_end_time : Int64,
) -> CslgBox {
  {
    version,
    composition_to_dts_shift,
    least_decode_to_display_delta,
    greatest_decode_to_display_delta,
    composition_start_time,
    composition_end_time,
  }
}

///|
/// `cslg` をデコードする。
///
/// version が 2 以上の場合は [`@bytes.ErrorKind::InvalidData`]
/// （`"Invalid cslg box version: {v}"`）で失敗する（上流と同じ理由文字列）。
pub impl @bytes.Decode for CslgBox with fn decode(cursor : @bytes.ReadCursor) -> CslgBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(cslg_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(cslg_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let version = full_header.version()
    if version > 1U {
      raise @bytes.Mp4Error::invalid_data(
        "Invalid cslg box version: \{version}",
      )
    }
    let (
      composition_to_dts_shift,
      least_decode_to_display_delta,
      greatest_decode_to_display_delta,
      composition_start_time,
      composition_end_time,
    ) = if version == 1U {
      (
        payload_cursor.read_i64(),
        payload_cursor.read_i64(),
        payload_cursor.read_i64(),
        payload_cursor.read_i64(),
        payload_cursor.read_i64(),
      )
    } else {
      (
        payload_cursor.read_i32().to_int64(),
        payload_cursor.read_i32().to_int64(),
        payload_cursor.read_i32().to_int64(),
        payload_cursor.read_i32().to_int64(),
        payload_cursor.read_i32().to_int64(),
      )
    }
    {
      version,
      composition_to_dts_shift,
      least_decode_to_display_delta,
      greatest_decode_to_display_delta,
      composition_start_time,
      composition_end_time,
    }
  })
}

///|
pub extend CslgBox with @bytes.Decode::{decode}

///|
/// `cslg` を canonical な形式でエンコードする。
///
/// version 0 / 1 以外や、version 0 で i32 に収まらないフィールドは
/// [`@bytes.ErrorKind::InvalidInput`] で失敗する（上流と同じ理由文字列）。
pub impl @bytes.Encode for CslgBox with fn encode(
  self : CslgBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  let version = self.version
  if version > 1U {
    raise @bytes.Mp4Error::invalid_input("Invalid cslg box version: \{version}")
  }
  write_box_with_payload(cursor, cslg_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    if version == 1U {
      payload.write_i64(self.composition_to_dts_shift)
      payload.write_i64(self.least_decode_to_display_delta)
      payload.write_i64(self.greatest_decode_to_display_delta)
      payload.write_i64(self.composition_start_time)
      payload.write_i64(self.composition_end_time)
    } else {
      write_cslg_v0_field(
        payload,
        self.composition_to_dts_shift,
        "composition_to_dts_shift",
      )
      write_cslg_v0_field(
        payload,
        self.least_decode_to_display_delta,
        "least_decode_to_display_delta",
      )
      write_cslg_v0_field(
        payload,
        self.greatest_decode_to_display_delta,
        "greatest_decode_to_display_delta",
      )
      write_cslg_v0_field(
        payload,
        self.composition_start_time,
        "composition_start_time",
      )
      write_cslg_v0_field(
        payload,
        self.composition_end_time,
        "composition_end_time",
      )
    }
  })
}

///|
/// version 0 の `cslg` フィールドを i32 に収まることを検査して書く。
fn write_cslg_v0_field(
  payload : @bytes.WriteCursor,
  value : Int64,
  name : StringView,
) -> Unit raise @bytes.Mp4Error {
  if value > 0x7FFFFFFFL || value < -0x80000000L {
    raise @bytes.Mp4Error::invalid_input(
      "cslg version 0 requires \{name} to be in i32 range, got \{value}",
    )
  }
  payload.write_i32(value.to_int())
}

///|
pub extend CslgBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for CslgBox with fn box_type(_self) {
  cslg_type()
}

///|
pub impl @box.BaseBox for CslgBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend CslgBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for CslgBox with fn full_box_version(self) {
  self.version
}

///|
pub impl @box.FullBox for CslgBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend CslgBox with @box.FullBox::{full_box_version, full_box_flags}
