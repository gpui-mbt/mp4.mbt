///|
/// [ISO/IEC 14496-14] MP4AudioSampleEntry class (親: [`StsdBox`])。
/// 上流 `Mp4aBox` に対応する。
///
/// MPEG-4 音声（主に AAC）用のサンプルエントリー。`esds` ボックスを
/// 必須の子として持つ。
pub struct Mp4aBox {
  /// 音声系サンプルエントリー共通フィールド
  audio : AudioSampleEntryFields
  /// MPEG-4 コーデック設定（ES 記述子）を保持する `esds` ボックス
  esds_box : EsdsBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Mp4aBox with Eq::{equal, not_equal}

///|
pub extend Mp4aBox with Hash::{hash, hash_combine}

///|
pub extend Mp4aBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Mp4aBox::new(
  audio : AudioSampleEntryFields,
  esds_box : EsdsBox,
  unknown_boxes : Array[UnknownBox],
) -> Mp4aBox {
  { audio, esds_box, unknown_boxes, }
}

///|
/// `mp4a` をデコードする。
///
/// 必須の `esds` ボックスが無い場合は [`@bytes.ErrorKind::InvalidData`]
/// で失敗する。`esds` が複数現れた場合は最初の 1 個だけを採用し、
/// 2 個目以降は `unknown_boxes` として保持する（上流と同じ）。
pub impl @bytes.Decode for Mp4aBox with fn decode(cursor : @bytes.ReadCursor) -> Mp4aBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mp4a_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mp4a_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let audio : AudioSampleEntryFields = @bytes.decode_from(payload_cursor)
    let mut esds_box : EsdsBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == esds_type() && esds_box is None {
        esds_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      audio,
      esds_box: check_mandatory_box(esds_box, "esds", "mp4a"),
      unknown_boxes,
    }
  })
}

///|
pub extend Mp4aBox with @bytes.Decode::{decode}

///|
/// `mp4a` をエンコードする。
pub impl @bytes.Encode for Mp4aBox with fn encode(
  self : Mp4aBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mp4a_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.audio, payload)
    @bytes.Encode::encode(self.esds_box, payload)
    for b in self.unknown_boxes {
      @bytes.Encode::encode(b, payload)
    }
  })
}

///|
pub extend Mp4aBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Mp4aBox with fn box_type(_self) {
  mp4a_type()
}

///|
/// `esds` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for Mp4aBox with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.esds_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend Mp4aBox with @box.BaseBox::{box_type, is_unknown_box, children}
