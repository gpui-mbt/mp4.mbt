///|
/// `stpp`（XML 字幕）サンプルエントリー。
pub struct StppBox {
  /// データ参照インデックス
  data_reference_index : @bytes.NonZeroU16
  /// 名前空間 URI のスペース区切りリスト
  namespace_uri : @bytes.Utf8String
  /// スキーマ URL のスペース区切りリスト
  schema_location : @bytes.Utf8String
  /// 補助 MIME タイプのスペース区切りリスト
  auxiliary_mime_types : @bytes.Utf8String
  /// 未知の子ボックス
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend StppBox with Eq::{equal, not_equal}

///|
pub extend StppBox with Hash::{hash, hash_combine}

///|
pub extend StppBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn StppBox::new(
  data_reference_index : @bytes.NonZeroU16,
  namespace_uri : @bytes.Utf8String,
  schema_location : @bytes.Utf8String,
  auxiliary_mime_types : @bytes.Utf8String,
  unknown_boxes : Array[UnknownBox],
) -> StppBox {
  {
    data_reference_index,
    namespace_uri,
    schema_location,
    auxiliary_mime_types,
    unknown_boxes,
  }
}

///|
/// `stpp` をデコードする。
pub impl @bytes.Decode for StppBox with fn decode(cursor : @bytes.ReadCursor) -> StppBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(stpp_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(stpp_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    payload_cursor.skip(6)
    let data_reference_index : @bytes.NonZeroU16 = @bytes.decode_from(
      payload_cursor,
    )
    let namespace_uri : @bytes.Utf8String = @bytes.decode_from(payload_cursor)
    let schema_location : @bytes.Utf8String = @bytes.decode_from(payload_cursor)
    let auxiliary_mime_types : @bytes.Utf8String = @bytes.decode_from(
      payload_cursor,
    )
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      unknown_boxes.push(@bytes.decode_from(payload_cursor))
    }
    {
      data_reference_index,
      namespace_uri,
      schema_location,
      auxiliary_mime_types,
      unknown_boxes,
    }
  })
}

///|
pub extend StppBox with @bytes.Decode::{decode}

///|
/// `stpp` をエンコードする。
pub impl @bytes.Encode for StppBox with fn encode(
  self : StppBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, stpp_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    payload.write_bytes(Bytes::make(6, b'\x00'))
    @bytes.Encode::encode(self.data_reference_index, payload)
    @bytes.Encode::encode(self.namespace_uri, payload)
    @bytes.Encode::encode(self.schema_location, payload)
    @bytes.Encode::encode(self.auxiliary_mime_types, payload)
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend StppBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for StppBox with fn box_type(_self) {
  stpp_type()
}

///|
pub impl @box.BaseBox for StppBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend StppBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// `vttC`（WebVTT 設定）ボックス。
pub struct VttCBox {
  /// WebVTT の設定テキスト
  config : String
} derive(Eq, Hash, Debug)

///|
pub extend VttCBox with Eq::{equal, not_equal}

///|
pub extend VttCBox with Hash::{hash, hash_combine}

///|
pub extend VttCBox with Debug::{to_repr}

///|
/// 設定テキストを指定して作成する。
pub fn VttCBox::new(config : String) -> VttCBox {
  { config, }
}

///|
/// `vttC` をデコードする。
pub impl @bytes.Decode for VttCBox with fn decode(cursor : @bytes.ReadCursor) -> VttCBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(vttc_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(vttc_type())
    let bytes = payload_cursor_of(cursor, payload).read_remaining()
    let config = @utf8.decode(bytes) catch {
      _ => raise @bytes.Mp4Error::invalid_input("invalid vttC config")
    }
    { config, }
  })
}

///|
pub extend VttCBox with @bytes.Decode::{decode}

///|
/// `vttC` をエンコードする。
pub impl @bytes.Encode for VttCBox with fn encode(
  self : VttCBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, vttc_type(), fn(payload) {
    payload.write_bytes(@utf8.encode(self.config))
  })
}

///|
pub extend VttCBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for VttCBox with fn box_type(_self) {
  vttc_type()
}

///|
pub impl @box.BaseBox for VttCBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend VttCBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// `wvtt`（WebVTT）サンプルエントリー。
pub struct WvttBox {
  /// データ参照インデックス
  data_reference_index : @bytes.NonZeroU16
  /// 必須の `vttC`
  vttc_box : VttCBox
  /// 未知の子ボックス
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend WvttBox with Eq::{equal, not_equal}

///|
pub extend WvttBox with Hash::{hash, hash_combine}

///|
pub extend WvttBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn WvttBox::new(
  data_reference_index : @bytes.NonZeroU16,
  vttc_box : VttCBox,
  unknown_boxes : Array[UnknownBox],
) -> WvttBox {
  { data_reference_index, vttc_box, unknown_boxes, }
}

///|
/// `wvtt` をデコードする。
pub impl @bytes.Decode for WvttBox with fn decode(cursor : @bytes.ReadCursor) -> WvttBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(wvtt_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(wvtt_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    payload_cursor.skip(6)
    let data_reference_index : @bytes.NonZeroU16 = @bytes.decode_from(
      payload_cursor,
    )
    let mut vttc : VttCBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == vttc_type() && vttc is None {
        vttc = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      data_reference_index,
      vttc_box: check_mandatory_box(vttc, "vttC", "wvtt"),
      unknown_boxes,
    }
  })
}

///|
pub extend WvttBox with @bytes.Decode::{decode}

///|
/// `wvtt` をエンコードする。
pub impl @bytes.Encode for WvttBox with fn encode(
  self : WvttBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, wvtt_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    payload.write_bytes(Bytes::make(6, b'\x00'))
    @bytes.Encode::encode(self.data_reference_index, payload)
    @bytes.Encode::encode(self.vttc_box, payload)
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend WvttBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for WvttBox with fn box_type(_self) {
  wvtt_type()
}

///|
pub impl @box.BaseBox for WvttBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.vttc_box)
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend WvttBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// `tx3g` の表示矩形。
pub struct BoxRecord {
  /// top
  top : Int16
  /// left
  left : Int16
  /// bottom
  bottom : Int16
  /// right
  right : Int16
} derive(Eq, Hash, Debug)

///|
pub extend BoxRecord with Eq::{equal, not_equal}

///|
pub extend BoxRecord with Hash::{hash, hash_combine}

///|
pub extend BoxRecord with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn BoxRecord::new(
  top : Int16,
  left : Int16,
  bottom : Int16,
  right : Int16,
) -> BoxRecord {
  { top, left, bottom, right, }
}

///|
/// `tx3g` のスタイル。
pub struct StyleRecord {
  /// 開始文字インデックス
  start_char : UInt32
  /// 終了文字インデックス
  end_char : UInt32
  /// フォント ID
  font_id : UInt32
  /// face-style-flags
  face_style_flags : UInt32
  /// フォントサイズ
  font_size : UInt32
  /// テキスト色（RGBA）
  text_color_rgba : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend StyleRecord with Eq::{equal, not_equal}

///|
pub extend StyleRecord with Hash::{hash, hash_combine}

///|
pub extend StyleRecord with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn StyleRecord::new(
  start_char : UInt32,
  end_char : UInt32,
  font_id : UInt32,
  face_style_flags : UInt32,
  font_size : UInt32,
  text_color_rgba : Bytes,
) -> StyleRecord {
  {
    start_char,
    end_char,
    font_id,
    face_style_flags,
    font_size,
    text_color_rgba,
  }
}

///|
/// `tx3g` のフォントエントリー。
pub struct FontRecord {
  /// フォント ID
  font_id : UInt32
  /// フォント名
  font_name : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend FontRecord with Eq::{equal, not_equal}

///|
pub extend FontRecord with Hash::{hash, hash_combine}

///|
pub extend FontRecord with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn FontRecord::new(font_id : UInt32, font_name : Bytes) -> FontRecord {
  { font_id, font_name, }
}

///|
/// `ftab` フォントテーブル。
pub struct FtabBox {
  /// フォントエントリー列
  entries : Array[FontRecord]
} derive(Eq, Hash, Debug)

///|
pub extend FtabBox with Eq::{equal, not_equal}

///|
pub extend FtabBox with Hash::{hash, hash_combine}

///|
pub extend FtabBox with Debug::{to_repr}

///|
/// エントリー列を指定して作成する。
pub fn FtabBox::new(entries : Array[FontRecord]) -> FtabBox {
  { entries, }
}

///|
/// `ftab` をデコードする。
pub impl @bytes.Decode for FtabBox with fn decode(cursor : @bytes.ReadCursor) -> FtabBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(ftab_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(ftab_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let entry_count = payload_cursor.read_u16()
    let entries : Array[FontRecord] = []
    let mut remaining = entry_count
    while remaining > 0U {
      let font_id = payload_cursor.read_u16()
      let length = payload_cursor.read_u8()
      let name = payload_cursor.read_bytes(length.reinterpret_as_int())
      entries.push({ font_id, font_name: name, })
      remaining = remaining - 1U
    }
    { entries, }
  })
}

///|
pub extend FtabBox with @bytes.Decode::{decode}

///|
/// `ftab` をエンコードする。
pub impl @bytes.Encode for FtabBox with fn encode(
  self : FtabBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, ftab_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    payload.write_u16(self.entries.length().reinterpret_as_uint())
    for entry in self.entries {
      payload.write_u16(entry.font_id)
      if entry.font_name.length() > 255 {
        raise @bytes.Mp4Error::invalid_input("font name exceeds 255 bytes")
      }
      payload.write_u8(entry.font_name.length().reinterpret_as_uint())
      payload.write_bytes(entry.font_name)
    }
  })
}

///|
pub extend FtabBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for FtabBox with fn box_type(_self) {
  ftab_type()
}

///|
pub impl @box.BaseBox for FtabBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend FtabBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// `tx3g`（3GPP Timed Text）サンプルエントリー。
pub struct Tx3gBox {
  /// データ参照インデックス
  data_reference_index : @bytes.NonZeroU16
  /// display flags
  display_flags : UInt32
  /// 水平ジャスティフィケーション
  horizontal_justification : Int32
  /// 垂直ジャスティフィケーション
  vertical_justification : Int32
  /// 背景色 RGBA
  background_color_rgba : Bytes
  /// 既定の表示矩形
  default_text_box : BoxRecord
  /// 既定のスタイル
  default_style : StyleRecord
  /// 必須のフォントテーブル
  ftab_box : FtabBox
  /// 未知の子ボックス
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Tx3gBox with Eq::{equal, not_equal}

///|
pub extend Tx3gBox with Hash::{hash, hash_combine}

///|
pub extend Tx3gBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Tx3gBox::new(
  data_reference_index : @bytes.NonZeroU16,
  display_flags : UInt32,
  horizontal_justification : Int32,
  vertical_justification : Int32,
  background_color_rgba : Bytes,
  default_text_box : BoxRecord,
  default_style : StyleRecord,
  ftab_box : FtabBox,
  unknown_boxes : Array[UnknownBox],
) -> Tx3gBox {
  {
    data_reference_index,
    display_flags,
    horizontal_justification,
    vertical_justification,
    background_color_rgba,
    default_text_box,
    default_style,
    ftab_box,
    unknown_boxes,
  }
}

///|
/// `tx3g` をデコードする。
pub impl @bytes.Decode for Tx3gBox with fn decode(cursor : @bytes.ReadCursor) -> Tx3gBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(tx3g_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(tx3g_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    payload_cursor.skip(6)
    let data_reference_index : @bytes.NonZeroU16 = @bytes.decode_from(
      payload_cursor,
    )
    let display_flags = payload_cursor.read_u32()
    let horizontal_justification = payload_cursor.read_i8()
    let vertical_justification = payload_cursor.read_i8()
    let background_color_rgba = payload_cursor.read_bytes(4)
    let default_text_box = {
      top: Int16::from_int(payload_cursor.read_i16()),
      left: Int16::from_int(payload_cursor.read_i16()),
      bottom: Int16::from_int(payload_cursor.read_i16()),
      right: Int16::from_int(payload_cursor.read_i16()),
    }
    let default_style = {
      start_char: payload_cursor.read_u16(),
      end_char: payload_cursor.read_u16(),
      font_id: payload_cursor.read_u16(),
      face_style_flags: payload_cursor.read_u8(),
      font_size: payload_cursor.read_u8(),
      text_color_rgba: payload_cursor.read_bytes(4),
    }
    let mut ftab : FtabBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == ftab_type() && ftab is None {
        ftab = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      data_reference_index,
      display_flags,
      horizontal_justification,
      vertical_justification,
      background_color_rgba,
      default_text_box,
      default_style,
      ftab_box: check_mandatory_box(ftab, "ftab", "tx3g"),
      unknown_boxes,
    }
  })
}

///|
pub extend Tx3gBox with @bytes.Decode::{decode}

///|
/// `tx3g` をエンコードする。
pub impl @bytes.Encode for Tx3gBox with fn encode(
  self : Tx3gBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, tx3g_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    payload.write_bytes(Bytes::make(6, b'\x00'))
    @bytes.Encode::encode(self.data_reference_index, payload)
    payload.write_u32(self.display_flags)
    payload.write_i8(self.horizontal_justification)
    payload.write_i8(self.vertical_justification)
    payload.write_bytes(self.background_color_rgba)
    payload.write_i16(self.default_text_box.top.to_int())
    payload.write_i16(self.default_text_box.left.to_int())
    payload.write_i16(self.default_text_box.bottom.to_int())
    payload.write_i16(self.default_text_box.right.to_int())
    payload.write_u16(self.default_style.start_char)
    payload.write_u16(self.default_style.end_char)
    payload.write_u16(self.default_style.font_id)
    payload.write_u8(self.default_style.face_style_flags)
    payload.write_u8(self.default_style.font_size)
    payload.write_bytes(self.default_style.text_color_rgba)
    @bytes.Encode::encode(self.ftab_box, payload)
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend Tx3gBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Tx3gBox with fn box_type(_self) {
  tx3g_type()
}

///|
pub impl @box.BaseBox for Tx3gBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.ftab_box)
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend Tx3gBox with @box.BaseBox::{box_type, is_unknown_box, children}
