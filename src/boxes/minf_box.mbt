///|
/// [ISO/IEC 14496-12] MediaInformationBox（`minf`）(親: [`MdiaBox`])。
///
/// メディアヘッダーとデータ情報を保持する。上流 `MinfBox` に対応する。
/// 上流が持つ `stbl_box` は本 Issue では型付けせず、`stbl` は
/// [`UnknownBox`] として `unknown_boxes` に保持する（Issue 0009 で対応する）。
///
/// ```mbt check
/// test {
///   let box = @boxes.MinfBox::new(
///     Some(@boxes.MediaHeader::Nmhd(@boxes.NmhdBox::new())),
///     @boxes.DinfBox::local_file(),
///     [],
///   )
///   let bytes = @bytes.encode_to_bytes(box)
///   let decoded : @boxes.MinfBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   match decoded.media_header {
///     Some(@boxes.MediaHeader::Nmhd(_)) => ()
///     _ => fail("nmhd が得られるはず")
///   }
///   inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
/// }
/// ```
pub struct MinfBox {
  /// [`MediaHeader`] を保持する
  ///
  /// 仕様上 `minf` 直下にメディアヘッダーは 1 種類しか出ないため `Option` で
  /// ラップする。メディアトラック以外を含む MP4 で `minf` を持てるよう `None` も
  /// 許容する。
  media_header : MediaHeader?
  /// メディアデータの所在情報を保持する `dinf` ボックス
  dinf_box : DinfBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む。
  /// 本 Issue では `stbl` もここに入る）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend MinfBox with Eq::{equal, not_equal}

///|
pub extend MinfBox with Hash::{hash, hash_combine}

///|
pub extend MinfBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MinfBox::new(
  media_header : MediaHeader?,
  dinf_box : DinfBox,
  unknown_boxes : Array[UnknownBox],
) -> MinfBox {
  { media_header, dinf_box, unknown_boxes, }
}

///|
/// `minf` をデコードする。
///
/// メディアヘッダー系（`smhd` / `vmhd` / `sthd` / `nmhd`）は最初に見つかった
/// 1 種類だけを採用し、2 個目以降は [`UnknownBox`] へ落とす。`dinf` は必須で、
/// 無い場合は [`@bytes.ErrorKind::InvalidData`] で失敗する。`stbl` は本 Issue
/// では型付けせず [`UnknownBox`] として保持する。
pub impl @bytes.Decode for MinfBox with fn decode(cursor : @bytes.ReadCursor) -> MinfBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(minf_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(minf_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut media_header : MediaHeader? = None
    let mut dinf_box : DinfBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if (
          child_type == smhd_type() ||
          child_type == vmhd_type() ||
          child_type == sthd_type() ||
          child_type == nmhd_type()
        ) &&
        media_header is None {
        media_header = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == dinf_type() && dinf_box is None {
        dinf_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      media_header,
      dinf_box: check_mandatory_box(dinf_box, "dinf", "minf"),
      unknown_boxes,
    }
  })
}

///|
pub extend MinfBox with @bytes.Decode::{decode}

///|
/// `minf` を canonical な形式でエンコードする。
pub impl @bytes.Encode for MinfBox with fn encode(
  self : MinfBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, minf_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    match self.media_header {
      Some(media_header) => @bytes.Encode::encode(media_header, payload)
      None => ()
    }
    @bytes.Encode::encode(self.dinf_box, payload)
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend MinfBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MinfBox with fn box_type(_self) {
  minf_type()
}

///|
/// メディアヘッダー（あれば）、`dinf`、続いて未知ボックス（ファイル順）を返す。
pub impl @box.BaseBox for MinfBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  match self.media_header {
    Some(media_header) => children.push(media_header)
    None => ()
  }
  children.push(self.dinf_box)
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend MinfBox with @box.BaseBox::{box_type, is_unknown_box, children}
