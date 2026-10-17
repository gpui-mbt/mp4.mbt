///|
/// [ISO/IEC 14496-12] HandlerBox（`hdlr`）(親: [`MdiaBox`])。
///
/// メディアハンドラー種別とハンドラ名を保持する。上流 `HdlrBox` に対応する。
///
/// ISO の仕様書上は `name` は null 終端の UTF-8 文字列であるべきだが、中身が
/// UTF-8 ではなかったり、null 終端文字列ではなく先頭にサイズバイトを格納する形式で
/// MP4 ファイルを作成する実装が普通に存在するため、ここでは単なるバイト列として
/// 扱う（上流と同じ）。NUL 終端の有無も解釈しない。
///
/// ```mbt check
/// test {
///   let box = @boxes.HdlrBox::new(
///     @boxes.HdlrBox::handler_type_vide(),
///     b"VideoHandler",
///   )
///   let decoded : @boxes.HdlrBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.handler_type.to_string(), content="vide")
///   inspect(decoded.track_kind() is Some(@bytes.TrackKind::Video), content="true")
///   inspect(decoded.name == b"VideoHandler", content="true")
/// }
/// ```
pub struct HdlrBox {
  /// ハンドラー種別（`soun` / `vide` / `subt` / `text` などの 4 バイトコード）
  handler_type : @bytes.FourCC
  /// ハンドラ名（生バイト列。NUL 終端やサイズ前置は解釈しない）
  name : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend HdlrBox with Eq::{equal, not_equal}

///|
pub extend HdlrBox with Hash::{hash, hash_combine}

///|
pub extend HdlrBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn HdlrBox::new(handler_type : @bytes.FourCC, name : Bytes) -> HdlrBox {
  { handler_type, name, }
}

///|
/// 音声用のハンドラー種別（`soun`）。
pub fn HdlrBox::handler_type_soun() -> @bytes.FourCC {
  fourcc_literal(b"soun")
}

///|
/// 映像用のハンドラー種別（`vide`）。
pub fn HdlrBox::handler_type_vide() -> @bytes.FourCC {
  fourcc_literal(b"vide")
}

///|
/// 字幕用のハンドラー種別（`subt`）。
pub fn HdlrBox::handler_type_subt() -> @bytes.FourCC {
  fourcc_literal(b"subt")
}

///|
/// 字幕テキスト系トラック用のハンドラー種別（`text`）。
pub fn HdlrBox::handler_type_text() -> @bytes.FourCC {
  fourcc_literal(b"text")
}

///|
/// ハンドラー種別からトラックの種類を求める。
///
/// `vide` は [`@bytes.TrackKind::Video`]、`soun` は [`@bytes.TrackKind::Audio`]、
/// `subt` と `text` は [`@bytes.TrackKind::Subtitle`] に対応する。それ以外の
/// handler は `None` になり、映像などへは丸めない（上流の demux と同じ扱い）。
pub fn HdlrBox::track_kind(self : HdlrBox) -> @bytes.TrackKind? {
  let bytes = self.handler_type.as_bytes()
  if bytes == b"vide" {
    Some(@bytes.TrackKind::Video)
  } else if bytes == b"soun" {
    Some(@bytes.TrackKind::Audio)
  } else if bytes == b"subt" || bytes == b"text" {
    Some(@bytes.TrackKind::Subtitle)
  } else {
    None
  }
}

///|
/// `hdlr` をデコードする。
///
/// version / flags / `pre_defined` は保持しない（上流と同じ）。`name` は
/// 固定フィールドの後ろからボックス末尾までの生バイト列である。
pub impl @bytes.Decode for HdlrBox with fn decode(cursor : @bytes.ReadCursor) -> HdlrBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(hdlr_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(hdlr_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    // pre_defined（4 バイト）
    payload_cursor.skip(4)
    let handler_type = payload_cursor.read_fourcc()
    // reserved（12 バイト）
    payload_cursor.skip(4 * 3)
    let name = payload_cursor.read_remaining()
    { handler_type, name, }
  })
}

///|
pub extend HdlrBox with @bytes.Decode::{decode}

///|
/// `hdlr` をエンコードする。
///
/// version 0 / flags 0 / `pre_defined` 0 の固定値と、`handler_type`、
/// 3 つの予約 `u32`、`name` の生バイト列を順に書く（上流と同じ）。
/// デコード時に入力が持っていた version / flags / `pre_defined` は再現されない。
pub impl @bytes.Encode for HdlrBox with fn encode(
  self : HdlrBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, hdlr_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    payload.write_u32(0)
    payload.write_fourcc(self.handler_type)
    payload.write_u32(0)
    payload.write_u32(0)
    payload.write_u32(0)
    payload.write_bytes(self.name)
  })
}

///|
pub extend HdlrBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for HdlrBox with fn box_type(_self) {
  hdlr_type()
}

///|
pub impl @box.BaseBox for HdlrBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend HdlrBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ。デコード時の version は保持しない）。
pub impl @box.FullBox for HdlrBox with fn full_box_version(_self) {
  0U
}

///|
/// 常に flags 0（上流と同じ。デコード時の flags は保持しない）。
pub impl @box.FullBox for HdlrBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend HdlrBox with @box.FullBox::{full_box_version, full_box_flags}
