///|
/// [ISO/IEC 14496-15] AVCSampleEntry class (親: [`StsdBox`])。
/// 上流 `Avc1Box` に対応する。
///
/// H.264 (AVC) 用のサンプルエントリー。`avcC` ボックスを必須の子として持つ。
pub struct Avc1Box {
  /// 映像系サンプルエントリー共通フィールド
  visual : VisualSampleEntryFields
  /// H.264 デコーダー設定を保持する `avcC` ボックス
  avcc_box : AvccBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Avc1Box with Eq::{equal, not_equal}

///|
pub extend Avc1Box with Hash::{hash, hash_combine}

///|
pub extend Avc1Box with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Avc1Box::new(
  visual : VisualSampleEntryFields,
  avcc_box : AvccBox,
  unknown_boxes : Array[UnknownBox],
) -> Avc1Box {
  { visual, avcc_box, unknown_boxes, }
}

///|
/// `avc1` をデコードする。
///
/// 必須の `avcC` ボックスが無い場合は [`@bytes.ErrorKind::InvalidData`]
/// で失敗する。`avcC` が複数現れた場合は最初の 1 個だけを採用し、
/// 2 個目以降は `unknown_boxes` として保持する（上流と同じ）。
pub impl @bytes.Decode for Avc1Box with fn decode(cursor : @bytes.ReadCursor) -> Avc1Box raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(avc1_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(avc1_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let visual : VisualSampleEntryFields = @bytes.decode_from(payload_cursor)
    let mut avcc_box : AvccBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == avcc_type() && avcc_box is None {
        avcc_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      visual,
      avcc_box: check_mandatory_box(avcc_box, "avcc", "avc1"),
      unknown_boxes,
    }
  })
}

///|
pub extend Avc1Box with @bytes.Decode::{decode}

///|
/// `avc1` をエンコードする。
///
/// 共通フィールド、`avcC` ボックス、未知子ボックス群の順に書く（上流と同じ）。
pub impl @bytes.Encode for Avc1Box with fn encode(
  self : Avc1Box,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, avc1_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.visual, payload)
    @bytes.Encode::encode(self.avcc_box, payload)
    for b in self.unknown_boxes {
      @bytes.Encode::encode(b, payload)
    }
  })
}

///|
pub extend Avc1Box with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Avc1Box with fn box_type(_self) {
  avc1_type()
}

///|
/// `avcC` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序。
/// ワイヤ上の出現順ではなく、型付きボックスが先に来る）。
pub impl @box.BaseBox for Avc1Box with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.avcc_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend Avc1Box with @box.BaseBox::{box_type, is_unknown_box, children}
