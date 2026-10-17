///|
/// [ISO/IEC 14496-12] DataEntryUrlBox（`url `）(親: [`DrefBox`])。
///
/// メディアデータの所在を表す。上流 `UrlBox` に対応する。flags の bit 0
/// （self-contained）が立っている場合はメディアデータがこのファイル内に
/// 格納されていることを意味し、[`UrlBox::location`] は `None` になる。
///
/// ```mbt check
/// test {
///   // self-contained（flags bit 0 セット）の `url `
///   let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x0Curl \x00\x00\x00\x01")
///   let box : @boxes.UrlBox = @bytes.decode_from(cursor)
///   inspect(box.location is None, content="true")
///   inspect(
///     @bytes.encode_to_bytes(box) == cursor.data().to_owned(),
///     content="true",
///   )
/// }
/// ```
pub struct UrlBox {
  /// メディアデータの所在を表す URL 文字列
  ///
  /// `None` の場合はメディアデータがこのファイル内に格納されていること
  /// （FullBox の flags の `self-contained` ビットが立っている状態）を表す。
  location : @bytes.Utf8String?
} derive(Eq, Hash, Debug)

///|
pub extend UrlBox with Eq::{equal, not_equal}

///|
pub extend UrlBox with Hash::{hash, hash_combine}

///|
pub extend UrlBox with Debug::{to_repr}

///|
/// 所在（`None` ならこのファイル内）を指定して作成する。
pub fn UrlBox::new(location : @bytes.Utf8String?) -> UrlBox {
  { location, }
}

///|
/// メディアデータが同じファイル内に格納されていることを示す値
/// （上流 `UrlBox::LOCAL_FILE` に対応）。
pub fn UrlBox::local_file() -> UrlBox {
  { location: None, }
}

///|
/// `url ` をデコードする。
///
/// flags の bit 0 が立っている場合は [`UrlBox::location`] を読まずに `None` にし、
/// 立っていない場合だけ NUL 終端の UTF-8 文字列として読む。
pub impl @bytes.Decode for UrlBox with fn decode(cursor : @bytes.ReadCursor) -> UrlBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(url_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(url_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let location = if full_header.flags().is_set(0) {
      None
    } else {
      Some(@bytes.decode_from(payload_cursor))
    }
    { location, }
  })
}

///|
pub extend UrlBox with @bytes.Decode::{decode}

///|
/// `url ` をエンコードする。
///
/// [`UrlBox::location`] が `None` のときは flags の bit 0（self-contained）を立て、
/// `Some` のときは 0 にして URL 文字列と NUL 終端を書く。
pub impl @bytes.Encode for UrlBox with fn encode(
  self : UrlBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, url_type(), fn(payload) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    match self.location {
      Some(location) => @bytes.Encode::encode(location, payload)
      None => ()
    }
  })
}

///|
pub extend UrlBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for UrlBox with fn box_type(_self) {
  url_type()
}

///|
pub impl @box.BaseBox for UrlBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend UrlBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ）。
pub impl @box.FullBox for UrlBox with fn full_box_version(_self) {
  0U
}

///|
/// [`UrlBox::location`] が `None` のときだけ bit 0（self-contained）を立てる。
pub impl @box.FullBox for UrlBox with fn full_box_flags(self) {
  @box.FullBoxFlags::new(if self.location is None { 1U } else { 0U })
}

///|
pub extend UrlBox with @box.FullBox::{full_box_version, full_box_flags}
