///|
/// [<https://gitlab.xiph.org/xiph/opus/-/blob/main/doc/opus_in_isobmff.html>]
/// OpusSampleEntry class (親: [`StsdBox`])。上流 `OpusBox` に対応する。
///
/// Opus 音声用のサンプルエントリー。`dOps` ボックスを必須の子として持つ。
pub struct OpusBox {
  /// 音声系サンプルエントリー共通フィールド
  audio : AudioSampleEntryFields
  /// Opus のデコーダー設定を保持する `dOps` ボックス
  dops_box : DopsBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend OpusBox with Eq::{equal, not_equal}

///|
pub extend OpusBox with Hash::{hash, hash_combine}

///|
pub extend OpusBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn OpusBox::new(
  audio : AudioSampleEntryFields,
  dops_box : DopsBox,
  unknown_boxes : Array[UnknownBox],
) -> OpusBox {
  { audio, dops_box, unknown_boxes, }
}

///|
/// `Opus` をデコードする。
///
/// 必須の `dOps` ボックスが無い場合は [`@bytes.ErrorKind::InvalidData`]
/// で失敗する。`dOps` が複数現れた場合は最初の 1 個だけを採用し、
/// 2 個目以降は `unknown_boxes` として保持する（上流と同じ）。
pub impl @bytes.Decode for OpusBox with fn decode(cursor : @bytes.ReadCursor) -> OpusBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(opus_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(opus_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let audio : AudioSampleEntryFields = @bytes.decode_from(payload_cursor)
    let mut dops_box : DopsBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == dops_type() && dops_box is None {
        dops_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      audio,
      dops_box: check_mandatory_box(dops_box, "dops", "Opus"),
      unknown_boxes,
    }
  })
}

///|
pub extend OpusBox with @bytes.Decode::{decode}

///|
/// `Opus` をエンコードする。
pub impl @bytes.Encode for OpusBox with fn encode(
  self : OpusBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, opus_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.audio, payload)
    @bytes.Encode::encode(self.dops_box, payload)
    for b in self.unknown_boxes {
      @bytes.Encode::encode(b, payload)
    }
  })
}

///|
pub extend OpusBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for OpusBox with fn box_type(_self) {
  opus_type()
}

///|
/// `dOps` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for OpusBox with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.dops_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend OpusBox with @box.BaseBox::{box_type, is_unknown_box, children}
