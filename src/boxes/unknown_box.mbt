///|
/// ペイロードの解釈方法が不明なボックス。
///
/// ペイロードを保持し、デコード時のサイズ形式（`size==0` の可変長を含む）のまま
/// 再エンコードする（wire-preserving）。
///
/// [`UnknownBox::decode`] は、0 埋めされた不正な入力を可変長ボックスと誤解釈しない
/// ように `size==0` を拒否する。ファイル末尾のトップレベルボックスだけが
/// [`UnknownBox::decode_top_level`] で可変長を受理できる（上流と同じ分担）。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x0Azzzz\xAA\xBB")
///   let box : @boxes.UnknownBox = @bytes.decode_from(cursor)
///   inspect(box.box_type.to_string(), content="zzzz")
///   inspect(box.payload.length(), content="2")
/// }
/// ```
pub struct UnknownBox {
  /// ボックス種別
  box_type : @bytes.BoxType
  /// デコード時のサイズ（再エンコードで保持する）
  box_size : @box.BoxSize
  /// ペイロード
  payload : Bytes
} derive(Eq, Debug)

///|
pub extend UnknownBox with Eq::{equal, not_equal}

///|
pub extend UnknownBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する（デコード時のサイズ形式を保つ）。
pub fn UnknownBox::new(
  box_type : @bytes.BoxType,
  box_size : @box.BoxSize,
  payload : Bytes,
) -> UnknownBox {
  { box_type, box_size, payload, }
}

///|
/// トップレベルの未知ボックスをデコードする。
///
/// [`UnknownBox::decode`] と異なり、可変長サイズ（`size==0`）をファイル末尾まで
/// として受理する。ペイロードはコピーして保持し、確保量はカーソルの
/// [`@bytes.ParseLimits`] で制限される。
///
/// 失敗した場合はカーソル位置を開始位置へ戻す。
pub fn UnknownBox::decode_top_level(
  cursor : @bytes.ReadCursor,
) -> UnknownBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  @bytes.with_box_type(header.box_type(), fn() raise @bytes.Mp4Error {
    {
      box_type: header.box_type(),
      box_size: header.box_size(),
      payload: payload_cursor_of(cursor, payload).read_remaining(),
    }
  })
}

///|
/// 入れ子の未知ボックスをデコードする。`size==0` は拒否する。
pub impl @bytes.Decode for UnknownBox with fn decode(cursor : @bytes.ReadCursor) -> UnknownBox raise @bytes.Mp4Error {
  let start = cursor.position()
  let start_offset = cursor.offset()
  errdefer cursor.rewind_to(start)
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  if header.box_size() == @box.BoxSize::variable_size() {
    raise @bytes.Mp4Error::invalid_data("UnknownBox does not accept size=0")
      .with_offset(start_offset)
      .with_box_type(header.box_type())
  }
  @bytes.with_box_type(header.box_type(), fn() raise @bytes.Mp4Error {
    {
      box_type: header.box_type(),
      box_size: header.box_size(),
      payload: payload_cursor_of(cursor, payload).read_remaining(),
    }
  })
}

///|
pub extend UnknownBox with @bytes.Decode::{decode}

///|
/// デコード時のサイズ形式を保ったままエンコードする。
///
/// 末尾まで可変長だった入力（`size==0`）は `size==0` のまま書き戻される。
pub impl @bytes.Encode for UnknownBox with fn encode(
  self : UnknownBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  @bytes.Encode::encode(
    @box.BoxHeader::new(self.box_type, self.box_size),
    cursor,
  )
  cursor.write_bytes(self.payload)
}

///|
pub extend UnknownBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for UnknownBox with fn box_type(self) {
  self.box_type
}

///|
pub impl @box.BaseBox for UnknownBox with fn is_unknown_box(_self) {
  true
}

///|
pub impl @box.BaseBox for UnknownBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend UnknownBox with @box.BaseBox::{box_type, is_unknown_box, children}
