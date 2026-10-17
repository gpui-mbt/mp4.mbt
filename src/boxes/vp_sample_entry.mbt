///|
/// VP サンプルエントリー（`vp08` / `vp09`）のデコード共通処理。
///
/// `vp08` と `vp09` の内部構造は同一であるため、ボックス種別と
/// 必須ボックス欠落時の親名（エラーメッセージ用）だけを引数で受け取る
/// （上流の各 `Decode` 実装と同じ構造を共通化したもの）。
fn decode_vp_sample_entry(
  payload_cursor : @bytes.ReadCursor,
  parent_name : StringView,
) -> (VpccBox, Array[UnknownBox]) raise @bytes.Mp4Error {
  let mut vpcc_box : VpccBox? = None
  let unknown_boxes : Array[UnknownBox] = []
  while !payload_cursor.is_empty() {
    let child_type = peek_box_type(payload_cursor)
    if child_type == vpcc_type() && vpcc_box is None {
      vpcc_box = Some(@bytes.decode_from(payload_cursor))
    } else {
      unknown_boxes.push(@bytes.decode_from(payload_cursor))
    }
  }
  (check_mandatory_box(vpcc_box, "vpcC", parent_name), unknown_boxes)
}

///|
/// VP サンプルエントリー（`vp08` / `vp09`）のエンコード共通処理。
fn encode_vp_sample_entry(
  cursor : @bytes.WriteCursor,
  box_type : @bytes.BoxType,
  visual : VisualSampleEntryFields,
  vpcc_box : VpccBox,
  unknown_boxes : Array[UnknownBox],
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, box_type, fn(payload) raise @bytes.Mp4Error {
    @bytes.Encode::encode(visual, payload)
    @bytes.Encode::encode(vpcc_box, payload)
    for b in unknown_boxes {
      @bytes.Encode::encode(b, payload)
    }
  })
}

///|
/// [<https://www.webmproject.org/vp9/mp4/>] VP8SampleEntry class
/// (親: [`StsdBox`])。上流 `Vp08Box` に対応する。
///
/// VP8 用のサンプルエントリー。`vpcC` ボックスを必須の子として持つ。
pub struct Vp08Box {
  /// 映像系サンプルエントリー共通フィールド
  visual : VisualSampleEntryFields
  /// VP コーデック設定を保持する `vpcC` ボックス
  vpcc_box : VpccBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Vp08Box with Eq::{equal, not_equal}

///|
pub extend Vp08Box with Hash::{hash, hash_combine}

///|
pub extend Vp08Box with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Vp08Box::new(
  visual : VisualSampleEntryFields,
  vpcc_box : VpccBox,
  unknown_boxes : Array[UnknownBox],
) -> Vp08Box {
  { visual, vpcc_box, unknown_boxes, }
}

///|
/// `vp08` をデコードする。
///
/// 必須の `vpcC` ボックスが無い場合は [`@bytes.ErrorKind::InvalidData`]
/// で失敗する。`vpcC` が複数現れた場合は最初の 1 個だけを採用し、
/// 2 個目以降は `unknown_boxes` として保持する（上流と同じ）。
pub impl @bytes.Decode for Vp08Box with fn decode(cursor : @bytes.ReadCursor) -> Vp08Box raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(vp08_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(vp08_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let visual : VisualSampleEntryFields = @bytes.decode_from(payload_cursor)
    let (vpcc_box, unknown_boxes) = decode_vp_sample_entry(
      payload_cursor, "vp08",
    )
    { visual, vpcc_box, unknown_boxes, }
  })
}

///|
pub extend Vp08Box with @bytes.Decode::{decode}

///|
/// `vp08` をエンコードする。
pub impl @bytes.Encode for Vp08Box with fn encode(
  self : Vp08Box,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  encode_vp_sample_entry(
    cursor,
    vp08_type(),
    self.visual,
    self.vpcc_box,
    self.unknown_boxes,
  )
}

///|
pub extend Vp08Box with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Vp08Box with fn box_type(_self) {
  vp08_type()
}

///|
/// `vpcC` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for Vp08Box with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.vpcc_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend Vp08Box with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// [<https://www.webmproject.org/vp9/mp4/>] VP9SampleEntry class
/// (親: [`StsdBox`])。上流 `Vp09Box` に対応する。
///
/// VP9 用のサンプルエントリー。`vpcC` ボックスを必須の子として持つ。
pub struct Vp09Box {
  /// 映像系サンプルエントリー共通フィールド
  visual : VisualSampleEntryFields
  /// VP コーデック設定を保持する `vpcC` ボックス
  vpcc_box : VpccBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Vp09Box with Eq::{equal, not_equal}

///|
pub extend Vp09Box with Hash::{hash, hash_combine}

///|
pub extend Vp09Box with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Vp09Box::new(
  visual : VisualSampleEntryFields,
  vpcc_box : VpccBox,
  unknown_boxes : Array[UnknownBox],
) -> Vp09Box {
  { visual, vpcc_box, unknown_boxes, }
}

///|
/// `vp09` をデコードする。必須の `vpcC` ボックスが無い場合は
/// [`@bytes.ErrorKind::InvalidData`] で失敗する（[`Vp08Box`] と同じ規則）。
pub impl @bytes.Decode for Vp09Box with fn decode(cursor : @bytes.ReadCursor) -> Vp09Box raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(vp09_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(vp09_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let visual : VisualSampleEntryFields = @bytes.decode_from(payload_cursor)
    let (vpcc_box, unknown_boxes) = decode_vp_sample_entry(
      payload_cursor, "vp09",
    )
    { visual, vpcc_box, unknown_boxes, }
  })
}

///|
pub extend Vp09Box with @bytes.Decode::{decode}

///|
/// `vp09` をエンコードする。
pub impl @bytes.Encode for Vp09Box with fn encode(
  self : Vp09Box,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  encode_vp_sample_entry(
    cursor,
    vp09_type(),
    self.visual,
    self.vpcc_box,
    self.unknown_boxes,
  )
}

///|
pub extend Vp09Box with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Vp09Box with fn box_type(_self) {
  vp09_type()
}

///|
/// `vpcC` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for Vp09Box with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.vpcc_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend Vp09Box with @box.BaseBox::{box_type, is_unknown_box, children}
