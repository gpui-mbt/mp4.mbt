///|
/// [ISO/IEC 14496-12] TrackBox（`trak`）(親: [`MoovBox`])。
///
/// 1 トラックのヘッダー（`tkhd`）、編集リスト（`edts`、省略可）、メディア情報
/// （`mdia`）を保持する。上流 `TrakBox` に対応する。`tkhd` と `mdia` は必須で、
/// 無い場合は [`@bytes.ErrorKind::InvalidData`]
/// （`Missing mandatory '...' box in 'trak' box`）で失敗する。
///
/// ```mbt check
/// test {
///   let box = @boxes.TrakBox::new(
///     @boxes.TkhdBox::new(
///       true,
///       true,
///       false,
///       false,
///       @bytes.Mp4FileTime::from_secs(0UL),
///       @bytes.Mp4FileTime::from_secs(0UL),
///       1U,
///       1000UL,
///       @boxes.TkhdBox::default_layer(),
///       @boxes.TkhdBox::default_alternate_group(),
///       @boxes.TkhdBox::default_video_volume(),
///       @boxes.TkhdBox::default_matrix(),
///       @bytes.FixedPointNumber::new(1920, 0),
///       @bytes.FixedPointNumber::new(1080, 0),
///     ),
///     None,
///     @boxes.MdiaBox::new(
///       @boxes.MdhdBox::new(
///         @bytes.Mp4FileTime::from_secs(0UL),
///         @bytes.Mp4FileTime::from_secs(0UL),
///         @bytes.NonZeroU32::new(30000U).unwrap(),
///         30000UL,
///         @bytes.LanguageCode::undefined(),
///       ),
///       @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_vide(), b""),
///       @boxes.MinfBox::new(None, @boxes.DinfBox::local_file(), []),
///       [],
///     ),
///     [],
///   )
///   let bytes = @bytes.encode_to_bytes(box)
///   let decoded : @boxes.TrakBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   inspect(decoded.tkhd_box.track_id, content="1")
///   inspect(decoded.edts_box is None, content="true")
///   inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
/// }
/// ```
pub struct TrakBox {
  /// このトラックの `tkhd` ボックス
  tkhd_box : TkhdBox
  /// 編集リストを保持する `edts` ボックス（省略可）
  edts_box : EdtsBox?
  /// このトラックの `mdia` ボックス（メディア情報を保持する）
  mdia_box : MdiaBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend TrakBox with Eq::{equal, not_equal}

///|
pub extend TrakBox with Hash::{hash, hash_combine}

///|
pub extend TrakBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TrakBox::new(
  tkhd_box : TkhdBox,
  edts_box : EdtsBox?,
  mdia_box : MdiaBox,
  unknown_boxes : Array[UnknownBox],
) -> TrakBox {
  { tkhd_box, edts_box, mdia_box, unknown_boxes, }
}

///|
/// `trak` をデコードする。
///
/// `tkhd` / `edts` / `mdia` はそれぞれ最初に見つかったものを採用し、2 個目以降は
/// [`UnknownBox`] として保持する（上流と同じ）。
pub impl @bytes.Decode for TrakBox with fn decode(cursor : @bytes.ReadCursor) -> TrakBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(trak_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(trak_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut tkhd_box : TkhdBox? = None
    let mut edts_box : EdtsBox? = None
    let mut mdia_box : MdiaBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == tkhd_type() && tkhd_box is None {
        tkhd_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == edts_type() && edts_box is None {
        edts_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == mdia_type() && mdia_box is None {
        mdia_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      tkhd_box: check_mandatory_box(tkhd_box, "tkhd", "trak"),
      edts_box,
      mdia_box: check_mandatory_box(mdia_box, "mdia", "trak"),
      unknown_boxes,
    }
  })
}

///|
pub extend TrakBox with @bytes.Decode::{decode}

///|
/// `trak` を canonical な形式でエンコードする。
pub impl @bytes.Encode for TrakBox with fn encode(
  self : TrakBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, trak_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.tkhd_box, payload)
    match self.edts_box {
      Some(edts_box) => @bytes.Encode::encode(edts_box, payload)
      None => ()
    }
    @bytes.Encode::encode(self.mdia_box, payload)
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend TrakBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TrakBox with fn box_type(_self) {
  trak_type()
}

///|
/// `tkhd`、`edts`（あれば）、`mdia`、続いて未知ボックス（ファイル順）を返す。
pub impl @box.BaseBox for TrakBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.tkhd_box)
  match self.edts_box {
    Some(edts_box) => children.push(edts_box)
    None => ()
  }
  children.push(self.mdia_box)
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend TrakBox with @box.BaseBox::{box_type, is_unknown_box, children}
