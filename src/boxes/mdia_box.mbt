///|
/// [ISO/IEC 14496-12] MediaBox（`mdia`）(親: [`TrakBox`])。
///
/// メディア固有のヘッダー（`mdhd`）、ハンドラー（`hdlr`）、メディア情報（`minf`）を
/// 保持する。上流 `MdiaBox` に対応する。3 つとも必須で、無い場合は
/// [`@bytes.ErrorKind::InvalidData`]（`Missing mandatory '...' box in 'mdia' box`）
/// で失敗する。
///
/// ```mbt check
/// test {
///   let box = @boxes.MdiaBox::new(
///     @boxes.MdhdBox::new(
///       @bytes.Mp4FileTime::from_secs(0UL),
///       @bytes.Mp4FileTime::from_secs(0UL),
///       @bytes.NonZeroU32::new(48000U).unwrap(),
///       96000UL,
///       @bytes.LanguageCode::undefined(),
///     ),
///     @boxes.HdlrBox::new(@boxes.HdlrBox::handler_type_vide(), b""),
///     @boxes.MinfBox::new(None, @boxes.DinfBox::local_file(), []),
///     [],
///   )
///   let bytes = @bytes.encode_to_bytes(box)
///   let decoded : @boxes.MdiaBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   inspect(decoded.mdhd_box.timescale.get(), content="48000")
///   inspect(
///     decoded.hdlr_box.track_kind() is Some(@bytes.TrackKind::Video),
///     content="true",
///   )
///   inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
/// }
/// ```
pub struct MdiaBox {
  /// メディア固有のヘッダー情報を保持する `mdhd` ボックス
  mdhd_box : MdhdBox
  /// メディアハンドラー種別を保持する `hdlr` ボックス
  hdlr_box : HdlrBox
  /// メディア情報を保持する `minf` ボックス
  minf_box : MinfBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend MdiaBox with Eq::{equal, not_equal}

///|
pub extend MdiaBox with Hash::{hash, hash_combine}

///|
pub extend MdiaBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MdiaBox::new(
  mdhd_box : MdhdBox,
  hdlr_box : HdlrBox,
  minf_box : MinfBox,
  unknown_boxes : Array[UnknownBox],
) -> MdiaBox {
  { mdhd_box, hdlr_box, minf_box, unknown_boxes, }
}

///|
/// `mdia` をデコードする。
///
/// `mdhd` / `hdlr` / `minf` はそれぞれ最初に見つかったものを採用し、2 個目以降は
/// [`UnknownBox`] として保持する（上流と同じ）。
pub impl @bytes.Decode for MdiaBox with fn decode(cursor : @bytes.ReadCursor) -> MdiaBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mdia_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mdia_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut mdhd_box : MdhdBox? = None
    let mut hdlr_box : HdlrBox? = None
    let mut minf_box : MinfBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == mdhd_type() && mdhd_box is None {
        mdhd_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == hdlr_type() && hdlr_box is None {
        hdlr_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == minf_type() && minf_box is None {
        minf_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      mdhd_box: check_mandatory_box(mdhd_box, "mdhd", "mdia"),
      hdlr_box: check_mandatory_box(hdlr_box, "hdlr", "mdia"),
      minf_box: check_mandatory_box(minf_box, "minf", "mdia"),
      unknown_boxes,
    }
  })
}

///|
pub extend MdiaBox with @bytes.Decode::{decode}

///|
/// `mdia` を canonical な形式でエンコードする。
pub impl @bytes.Encode for MdiaBox with fn encode(
  self : MdiaBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mdia_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.mdhd_box, payload)
    @bytes.Encode::encode(self.hdlr_box, payload)
    @bytes.Encode::encode(self.minf_box, payload)
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend MdiaBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MdiaBox with fn box_type(_self) {
  mdia_type()
}

///|
/// `mdhd`、`hdlr`、`minf`、続いて未知ボックス（ファイル順）を返す。
pub impl @box.BaseBox for MdiaBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.mdhd_box)
  children.push(self.hdlr_box)
  children.push(self.minf_box)
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend MdiaBox with @box.BaseBox::{box_type, is_unknown_box, children}
