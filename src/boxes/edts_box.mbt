///|
/// [ISO/IEC 14496-12] EditBox（`edts`）(親: [`TrakBox`])。
///
/// 編集リストを保持する `elst` を `Option` で持つ。上流 `EdtsBox` に対応する。
/// `elst` は必須ではないため、`edts` が空でもデコードは成功する。
///
/// ```mbt check
/// test {
///   let box = @boxes.EdtsBox::new(None, [])
///   let bytes = @bytes.encode_to_bytes(box)
///   let decoded : @boxes.EdtsBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   inspect(decoded.elst_box is None, content="true")
///   inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
/// }
/// ```
pub struct EdtsBox {
  /// 編集リストを保持する `elst` ボックス（省略可）
  elst_box : ElstBox?
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend EdtsBox with Eq::{equal, not_equal}

///|
pub extend EdtsBox with Hash::{hash, hash_combine}

///|
pub extend EdtsBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn EdtsBox::new(
  elst_box : ElstBox?,
  unknown_boxes : Array[UnknownBox],
) -> EdtsBox {
  { elst_box, unknown_boxes, }
}

///|
/// `edts` をデコードする。
///
/// 最初に見つかった `elst` だけを型付きで採用し、2 個目以降は
/// [`UnknownBox`] として `unknown_boxes` に保持する（上流と同じ）。
pub impl @bytes.Decode for EdtsBox with fn decode(cursor : @bytes.ReadCursor) -> EdtsBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(edts_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(edts_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut elst_box : ElstBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == elst_type() && elst_box is None {
        elst_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    { elst_box, unknown_boxes, }
  })
}

///|
pub extend EdtsBox with @bytes.Decode::{decode}

///|
/// `edts` を canonical な形式でエンコードする。
pub impl @bytes.Encode for EdtsBox with fn encode(
  self : EdtsBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, edts_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    match self.elst_box {
      Some(elst) => @bytes.Encode::encode(elst, payload)
      None => ()
    }
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend EdtsBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for EdtsBox with fn box_type(_self) {
  edts_type()
}

///|
/// 型付きの `elst`、続いて未知ボックス（ファイル順）を返す。
pub impl @box.BaseBox for EdtsBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  match self.elst_box {
    Some(elst) => children.push(elst)
    None => ()
  }
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend EdtsBox with @box.BaseBox::{box_type, is_unknown_box, children}
