///|
/// [Encapsulation of FLAC in ISO Base Media File Format] FLACSampleEntry class
/// (親: [`StsdBox`])。上流 `FlacBox` に対応する。
///
/// <https://github.com/xiph/flac/blob/master/doc/isoflac.txt>
///
/// FLAC 音声用のサンプルエントリー。`dfLa` ボックスを必須の子として持つ。
pub struct FlacBox {
  /// 音声系サンプルエントリー共通フィールド
  audio : AudioSampleEntryFields
  /// FLAC のデコーダー設定を保持する `dfLa` ボックス
  dfla_box : DflaBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend FlacBox with Eq::{equal, not_equal}

///|
pub extend FlacBox with Hash::{hash, hash_combine}

///|
pub extend FlacBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn FlacBox::new(
  audio : AudioSampleEntryFields,
  dfla_box : DflaBox,
  unknown_boxes : Array[UnknownBox],
) -> FlacBox {
  { audio, dfla_box, unknown_boxes, }
}

///|
/// `fLaC` をデコードする。
///
/// 必須の `dfLa` ボックスが無い場合は [`@bytes.ErrorKind::InvalidData`]
/// で失敗する。`dfLa` が複数現れた場合は最初の 1 個だけを採用し、
/// 2 個目以降は `unknown_boxes` として保持する（上流と同じ）。
pub impl @bytes.Decode for FlacBox with fn decode(cursor : @bytes.ReadCursor) -> FlacBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(flac_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(flac_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let audio : AudioSampleEntryFields = @bytes.decode_from(payload_cursor)
    let mut dfla_box : DflaBox? = None
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == dfla_type() && dfla_box is None {
        dfla_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      audio,
      dfla_box: check_mandatory_box(dfla_box, "dfLa", "fLaC"),
      unknown_boxes,
    }
  })
}

///|
pub extend FlacBox with @bytes.Decode::{decode}

///|
/// `fLaC` をエンコードする。
pub impl @bytes.Encode for FlacBox with fn encode(
  self : FlacBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, flac_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.audio, payload)
    @bytes.Encode::encode(self.dfla_box, payload)
    for b in self.unknown_boxes {
      @bytes.Encode::encode(b, payload)
    }
  })
}

///|
pub extend FlacBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for FlacBox with fn box_type(_self) {
  flac_type()
}

///|
/// `dfLa` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for FlacBox with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.dfla_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend FlacBox with @box.BaseBox::{box_type, is_unknown_box, children}
