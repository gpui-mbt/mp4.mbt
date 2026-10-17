///|
/// [<https://aomediacodec.github.io/av1-isobmff/>] AV1SampleEntry class
/// (親: [`StsdBox`])。上流 `Av01Box` に対応する。
///
/// AV1 用のサンプルエントリー。`av1C` ボックスを必須の子として持つ。
pub struct Av01Box {
  /// 映像系サンプルエントリー共通フィールド
  visual : VisualSampleEntryFields
  /// AV1 コーデック設定を保持する `av1C` ボックス
  av1c_box : Av1cBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Av01Box with Eq::{equal, not_equal}

///|
pub extend Av01Box with Hash::{hash, hash_combine}

///|
pub extend Av01Box with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Av01Box::new(
  visual : VisualSampleEntryFields,
  av1c_box : Av1cBox,
  unknown_boxes : Array[UnknownBox],
) -> Av01Box {
  { visual, av1c_box, unknown_boxes, }
}

///|
/// `av01` をデコードする。
///
/// 必須の `av1C` ボックスが無い場合は [`@bytes.ErrorKind::InvalidData`]
/// で失敗する。`av1C` が複数現れた場合は最初の 1 個だけを採用し、
/// 2 個目以降は `unknown_boxes` として保持する（上流と同じ）。
pub impl @bytes.Decode for Av01Box with fn decode(cursor : @bytes.ReadCursor) -> Av01Box raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(av01_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(av01_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let visual : VisualSampleEntryFields = @bytes.decode_from(payload_cursor)
    let mut av1c_box : Av1cBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == av1c_type() && av1c_box is None {
        av1c_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      visual,
      av1c_box: check_mandatory_box(av1c_box, "av1c", "av01"),
      unknown_boxes,
    }
  })
}

///|
pub extend Av01Box with @bytes.Decode::{decode}

///|
/// `av01` をエンコードする。
pub impl @bytes.Encode for Av01Box with fn encode(
  self : Av01Box,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, av01_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.visual, payload)
    @bytes.Encode::encode(self.av1c_box, payload)
    for b in self.unknown_boxes {
      @bytes.Encode::encode(b, payload)
    }
  })
}

///|
pub extend Av01Box with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Av01Box with fn box_type(_self) {
  av01_type()
}

///|
/// `av1C` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for Av01Box with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.av1c_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend Av01Box with @box.BaseBox::{box_type, is_unknown_box, children}
