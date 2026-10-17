///|
/// [ISO/IEC 14496-12] MovieBox（`moov`）(親: トップレベル)。
///
/// movie 全体のメタデータ（`mvhd`）とトラック群（`trak`）を保持する。上流
/// `MoovBox` に対応する。上流が持つ `mvex_box` は本 Issue では型付けせず、
/// `mvex` 以下のボックスは [`UnknownBox`] として `unknown_boxes` に保持する
/// （Issue 0017 で対応する）。
///
/// ```mbt check
/// test {
///   let moov = @boxes.MoovBox::new(
///     @boxes.MvhdBox::new(
///       @bytes.Mp4FileTime::from_secs(0UL),
///       @bytes.Mp4FileTime::from_secs(0UL),
///       @bytes.NonZeroU32::new(1000U).unwrap(),
///       2000UL,
///       @boxes.MvhdBox::default_rate(),
///       @boxes.MvhdBox::default_volume(),
///       @boxes.MvhdBox::default_matrix(),
///       1U,
///     ),
///     [],
///     [],
///   )
///   let bytes = @bytes.encode_to_bytes(moov)
///   let decoded : @boxes.MoovBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(bytes),
///   )
///   inspect(decoded.mvhd_box.duration, content="2000")
///   inspect(decoded.trak_boxes.length(), content="0")
///   inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
/// }
/// ```
pub struct MoovBox {
  /// movie 全体のメタデータを保持する `mvhd` ボックス
  mvhd_box : MvhdBox
  /// このムービーが持つトラック群（各トラック 1 個の `trak` ボックス）
  ///
  /// `trak` は重複してもすべて型付きで保持される（上流と同じ）。
  trak_boxes : Array[TrakBox]
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む。
  /// 本 Issue では `mvex` もここに入る）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend MoovBox with Eq::{equal, not_equal}

///|
pub extend MoovBox with Hash::{hash, hash_combine}

///|
pub extend MoovBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MoovBox::new(
  mvhd_box : MvhdBox,
  trak_boxes : Array[TrakBox],
  unknown_boxes : Array[UnknownBox],
) -> MoovBox {
  { mvhd_box, trak_boxes, unknown_boxes, }
}

///|
/// `moov` をデコードする。
///
/// `mvhd` は最初に見つかったものだけを採用し（2 個目以降は [`UnknownBox`]）、
/// `trak` はすべて型付きで保持する。`mvhd` が無い場合は
/// [`@bytes.ErrorKind::InvalidData`]（`Missing mandatory 'mvhd' box in 'moov' box`）
/// で失敗する。`mvex` は本 Issue では [`UnknownBox`] として保持する。
pub impl @bytes.Decode for MoovBox with fn decode(cursor : @bytes.ReadCursor) -> MoovBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(moov_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(moov_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut mvhd_box : MvhdBox? = None
    let trak_boxes : Array[TrakBox] = []
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == mvhd_type() && mvhd_box is None {
        mvhd_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == trak_type() {
        trak_boxes.push(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      mvhd_box: check_mandatory_box(mvhd_box, "mvhd", "moov"),
      trak_boxes,
      unknown_boxes,
    }
  })
}

///|
pub extend MoovBox with @bytes.Decode::{decode}

///|
/// `moov` を canonical な形式でエンコードする。
///
/// 子ボックスの順序は `mvhd`、`trak` 群、未知ボックス（デコード時の出現順）になる。
pub impl @bytes.Encode for MoovBox with fn encode(
  self : MoovBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, moov_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.mvhd_box, payload)
    for trak in self.trak_boxes {
      @bytes.Encode::encode(trak, payload)
    }
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend MoovBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MoovBox with fn box_type(_self) {
  moov_type()
}

///|
/// `mvhd`、`trak` 群、続いて未知ボックス（ファイル順）を返す。
pub impl @box.BaseBox for MoovBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.mvhd_box)
  for trak in self.trak_boxes {
    children.push(trak)
  }
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend MoovBox with @box.BaseBox::{box_type, is_unknown_box, children}
