///|
/// [ISO/IEC 14496-12] MovieExtendsBox（`mvex`）(親: `moov`)。
///
/// フラグメント化されたムービーの既定値を持つ。上流 `MvexBox` に対応する。
///
/// ```mbt check
/// test {
///   let mvex = @boxes.MvexBox::new(
///     Some(@boxes.MehdBox::new(0UL)),
///     [@boxes.TrexBox::new(1U, 1U, 0U, 0U, @boxes.SampleFlags::empty())],
///     [],
///   )
///   let decoded : @boxes.MvexBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(mvex)),
///   )
///   inspect(decoded.trex_boxes.length(), content="1")
///   inspect(decoded.trex_boxes[0].track_id, content="1")
/// }
/// ```
pub struct MvexBox {
  /// フラグメント化されたムービー全体の尺を保持する `mehd`（省略可）
  mehd_box : MehdBox?
  /// 各トラックのフラグメント既定値を保持する `trex` 列
  trex_boxes : Array[TrexBox]
  /// 未知の子ボックス
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend MvexBox with Eq::{equal, not_equal}

///|
pub extend MvexBox with Hash::{hash, hash_combine}

///|
pub extend MvexBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MvexBox::new(
  mehd_box : MehdBox?,
  trex_boxes : Array[TrexBox],
  unknown_boxes : Array[UnknownBox],
) -> MvexBox {
  { mehd_box, trex_boxes, unknown_boxes, }
}

///|
/// `mvex` をデコードする。
pub impl @bytes.Decode for MvexBox with fn decode(cursor : @bytes.ReadCursor) -> MvexBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mvex_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mvex_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut mehd_box : MehdBox? = None
    let trex_boxes : Array[TrexBox] = []
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == mehd_type() && mehd_box is None {
        mehd_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == trex_type() {
        trex_boxes.push(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    { mehd_box, trex_boxes, unknown_boxes, }
  })
}

///|
pub extend MvexBox with @bytes.Decode::{decode}

///|
/// `mvex` を canonical な形式でエンコードする。
pub impl @bytes.Encode for MvexBox with fn encode(
  self : MvexBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mvex_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    match self.mehd_box {
      Some(mehd) => @bytes.Encode::encode(mehd, payload)
      None => ()
    }
    for trex in self.trex_boxes {
      @bytes.Encode::encode(trex, payload)
    }
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend MvexBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MvexBox with fn box_type(_self) {
  mvex_type()
}

///|
pub impl @box.BaseBox for MvexBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  match self.mehd_box {
    Some(mehd) => children.push(mehd)
    None => ()
  }
  for trex in self.trex_boxes {
    children.push(trex)
  }
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend MvexBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// [ISO/IEC 14496-12] MovieExtendsHeaderBox（`mehd`）(親: [`MvexBox`])。
///
/// フラグメント化されたムービー全体の尺を保持する。上流 `MehdBox` に対応する。
pub struct MehdBox {
  /// 全フラグメントを結合した後のムービー全体の尺（movie timescale 単位）
  fragment_duration : UInt64
} derive(Eq, Hash, Debug)

///|
pub extend MehdBox with Eq::{equal, not_equal}

///|
pub extend MehdBox with Hash::{hash, hash_combine}

///|
pub extend MehdBox with Debug::{to_repr}

///|
/// 継続時間を指定して作成する。
pub fn MehdBox::new(fragment_duration : UInt64) -> MehdBox {
  { fragment_duration, }
}

///|
/// `mehd` をデコードする。
pub impl @bytes.Decode for MehdBox with fn decode(cursor : @bytes.ReadCursor) -> MehdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mehd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mehd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let fragment_duration : UInt64 = if full_header.version() == 1 {
      payload_cursor.read_u64()
    } else {
      payload_cursor.read_u32().to_uint64()
    }
    { fragment_duration, }
  })
}

///|
pub extend MehdBox with @bytes.Decode::{decode}

///|
/// `mehd` をエンコードする。値が 32-bit に収まらない場合は version 1 になる。
pub impl @bytes.Encode for MehdBox with fn encode(
  self : MehdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mehd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    if full_header.version() == 1 {
      payload.write_u64(self.fragment_duration)
    } else {
      payload.write_u32(self.fragment_duration.to_uint())
    }
  })
}

///|
pub extend MehdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MehdBox with fn box_type(_self) {
  mehd_type()
}

///|
pub impl @box.BaseBox for MehdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend MehdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for MehdBox with fn full_box_version(self) {
  if self.fragment_duration > 0xFFFFFFFFUL {
    1U
  } else {
    0U
  }
}

///|
pub impl @box.FullBox for MehdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::empty()
}

///|
pub extend MehdBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] TrackExtendsBox（`trex`）(親: [`MvexBox`])。
///
/// トラックフラグメントの既定値を保持する。上流 `TrexBox` に対応する。
pub struct TrexBox {
  /// この既定値が適用される `tkhd` の track_id
  track_id : UInt32
  /// 既定の sample_description_index（1 始まり）
  default_sample_description_index : UInt32
  /// 既定のサンプル尺（media timescale 単位）
  default_sample_duration : UInt32
  /// 既定のサンプルサイズ（バイト）
  default_sample_size : UInt32
  /// 既定のサンプルフラグ
  default_sample_flags : SampleFlags
} derive(Eq, Hash, Debug)

///|
pub extend TrexBox with Eq::{equal, not_equal}

///|
pub extend TrexBox with Hash::{hash, hash_combine}

///|
pub extend TrexBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TrexBox::new(
  track_id : UInt32,
  default_sample_description_index : UInt32,
  default_sample_duration : UInt32,
  default_sample_size : UInt32,
  default_sample_flags : SampleFlags,
) -> TrexBox {
  {
    track_id,
    default_sample_description_index,
    default_sample_duration,
    default_sample_size,
    default_sample_flags,
  }
}

///|
/// `trex` をデコードする。
pub impl @bytes.Decode for TrexBox with fn decode(cursor : @bytes.ReadCursor) -> TrexBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(trex_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(trex_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    {
      track_id: payload_cursor.read_u32(),
      default_sample_description_index: payload_cursor.read_u32(),
      default_sample_duration: payload_cursor.read_u32(),
      default_sample_size: payload_cursor.read_u32(),
      default_sample_flags: @bytes.decode_from(payload_cursor),
    }
  })
}

///|
pub extend TrexBox with @bytes.Decode::{decode}

///|
/// `trex` をエンコードする。
pub impl @bytes.Encode for TrexBox with fn encode(
  self : TrexBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, trex_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.track_id)
    payload.write_u32(self.default_sample_description_index)
    payload.write_u32(self.default_sample_duration)
    payload.write_u32(self.default_sample_size)
    @bytes.Encode::encode(self.default_sample_flags, payload)
  })
}

///|
pub extend TrexBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TrexBox with fn box_type(_self) {
  trex_type()
}

///|
pub impl @box.BaseBox for TrexBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend TrexBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for TrexBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for TrexBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::empty()
}

///|
pub extend TrexBox with @box.FullBox::{full_box_version, full_box_flags}
