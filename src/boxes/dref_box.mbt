///|
/// [ISO/IEC 14496-12] DataReferenceBox（`dref`）(親: [`DinfBox`])。
///
/// メディアデータのデータ参照を保持する。上流 `DrefBox` に対応する。
/// `entry_count` はエンコード時に `url ` + 未知ボックスの個数から計算する。
///
/// ```mbt check
/// test {
///   let box = @boxes.DrefBox::local_file()
///   let bytes = @bytes.encode_to_bytes(box)
///   let decoded : @boxes.DrefBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   inspect(decoded.url_box is Some(_), content="true")
///   inspect(decoded.unknown_boxes.length(), content="0")
///   inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
/// }
/// ```
pub struct DrefBox {
  /// URL 形式のデータ参照を保持する `url ` ボックス（省略可）
  url_box : UrlBox?
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend DrefBox with Eq::{equal, not_equal}

///|
pub extend DrefBox with Hash::{hash, hash_combine}

///|
pub extend DrefBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn DrefBox::new(
  url_box : UrlBox?,
  unknown_boxes : Array[UnknownBox],
) -> DrefBox {
  { url_box, unknown_boxes, }
}

///|
/// メディアデータが同じファイル内に格納されていることを示す値
/// （上流 `DrefBox::LOCAL_FILE` に対応）。
pub fn DrefBox::local_file() -> DrefBox {
  { url_box: Some(UrlBox::local_file()), unknown_boxes: [], }
}

///|
/// `dref` をデコードする。
///
/// `entry_count` 個の子ボックスだけを読む。`entry_count` を超えて末尾に続く
/// バイト列は無視する（上流と同じ）。最初の `url ` だけを型付きで採用し、
/// 2 個目以降は [`UnknownBox`] として保持する。
pub impl @bytes.Decode for DrefBox with fn decode(cursor : @bytes.ReadCursor) -> DrefBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(dref_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(dref_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let entry_count = payload_cursor.read_u32()
    let mut url_box : UrlBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    let mut remaining = entry_count
    while remaining > 0 {
      let child_type = peek_box_type(payload_cursor)
      if child_type == url_type() && url_box is None {
        url_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
      remaining = remaining - 1
    }
    { url_box, unknown_boxes, }
  })
}

///|
pub extend DrefBox with @bytes.Decode::{decode}

///|
/// `dref` を canonical な形式でエンコードする。
///
/// `entry_count` には `url `（あれば 1）と未知ボックスの個数の合計を書く。
pub impl @bytes.Encode for DrefBox with fn encode(
  self : DrefBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, dref_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    let url_count : UInt32 = if self.url_box is Some(_) { 1U } else { 0U }
    payload.write_u32(
      url_count + self.unknown_boxes.length().reinterpret_as_uint(),
    )
    match self.url_box {
      Some(url_box) => @bytes.Encode::encode(url_box, payload)
      None => ()
    }
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend DrefBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for DrefBox with fn box_type(_self) {
  dref_type()
}

///|
/// 型付きの `url `、続いて未知ボックス（ファイル順）を返す。
pub impl @box.BaseBox for DrefBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  match self.url_box {
    Some(url_box) => children.push(url_box)
    None => ()
  }
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend DrefBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 常に version 0（上流と同じ）。
pub impl @box.FullBox for DrefBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for DrefBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend DrefBox with @box.FullBox::{full_box_version, full_box_flags}
