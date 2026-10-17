///|
/// [ISO/IEC 14496-12] DataInformationBox（`dinf`）(親: [`MinfBox`])。
///
/// メディアデータの所在情報（`dref`）を保持する。上流 `DinfBox` に対応する。
/// `dref` は必須で、無い場合は
/// [`@bytes.ErrorKind::InvalidData`]（`Missing mandatory 'dref' box in 'dinf' box`）
/// で失敗する。
///
/// ```mbt check
/// test {
///   let box = @boxes.DinfBox::local_file()
///   let bytes = @bytes.encode_to_bytes(box)
///   let decoded : @boxes.DinfBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   inspect(decoded.dref_box.url_box is Some(_), content="true")
///   inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
/// }
/// ```
pub struct DinfBox {
  /// データ参照を保持する `dref` ボックス
  dref_box : DrefBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend DinfBox with Eq::{equal, not_equal}

///|
pub extend DinfBox with Hash::{hash, hash_combine}

///|
pub extend DinfBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn DinfBox::new(
  dref_box : DrefBox,
  unknown_boxes : Array[UnknownBox],
) -> DinfBox {
  { dref_box, unknown_boxes, }
}

///|
/// メディアデータが同じファイル内に格納されていることを示す値
/// （上流 `DinfBox::LOCAL_FILE` に対応）。
pub fn DinfBox::local_file() -> DinfBox {
  { dref_box: DrefBox::local_file(), unknown_boxes: [], }
}

///|
/// `dinf` をデコードする。
///
/// 最初に見つかった `dref` だけを型付きで採用し、2 個目以降は
/// [`UnknownBox`] として `unknown_boxes` に保持する（上流と同じ）。
pub impl @bytes.Decode for DinfBox with fn decode(cursor : @bytes.ReadCursor) -> DinfBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(dinf_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(dinf_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut dref_box : DrefBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == dref_type() && dref_box is None {
        dref_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    { dref_box: check_mandatory_box(dref_box, "dref", "dinf"), unknown_boxes, }
  })
}

///|
pub extend DinfBox with @bytes.Decode::{decode}

///|
/// `dinf` を canonical な形式でエンコードする。
pub impl @bytes.Encode for DinfBox with fn encode(
  self : DinfBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, dinf_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.dref_box, payload)
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend DinfBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for DinfBox with fn box_type(_self) {
  dinf_type()
}

///|
/// 型付きの `dref`、続いて未知ボックス（ファイル順）を返す。
pub impl @box.BaseBox for DinfBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.dref_box)
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend DinfBox with @box.BaseBox::{box_type, is_unknown_box, children}
