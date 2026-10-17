///|
/// HEVC サンプルエントリー（`hev1` / `hvc1`）のデコード共通処理。
///
/// ISO/IEC 14496-15 上、`hev1` と `hvc1` の内部構造は同一であるため、
/// ボックス種別と必須ボックス欠落時の親名（エラーメッセージ用）だけを
/// 引数で受け取る（上流 `decode_hevc_sample_entry` に対応）。
fn decode_hevc_sample_entry(
  cursor : @bytes.ReadCursor,
  expected_type : @bytes.BoxType,
  parent_name : StringView,
) -> (VisualSampleEntryFields, HvccBox, Array[UnknownBox]) raise @bytes.Mp4Error {
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  header.box_type().expect(expected_type)
  let payload_cursor = payload_cursor_of(cursor, payload)
  let visual : VisualSampleEntryFields = @bytes.decode_from(payload_cursor)
  let mut hvcc_box : HvccBox? = None
  let unknown_boxes : Array[UnknownBox] = []
  while !payload_cursor.is_empty() {
    let child_type = peek_box_type(payload_cursor)
    if child_type == hvcc_type() && hvcc_box is None {
      hvcc_box = Some(@bytes.decode_from(payload_cursor))
    } else {
      unknown_boxes.push(@bytes.decode_from(payload_cursor))
    }
  }
  (visual, check_mandatory_box(hvcc_box, "hvcc", parent_name), unknown_boxes)
}

///|
/// HEVC サンプルエントリー（`hev1` / `hvc1`）のエンコード共通処理
/// （上流 `encode_hevc_sample_entry` に対応）。
fn encode_hevc_sample_entry(
  cursor : @bytes.WriteCursor,
  box_type : @bytes.BoxType,
  visual : VisualSampleEntryFields,
  hvcc_box : HvccBox,
  unknown_boxes : Array[UnknownBox],
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, box_type, fn(payload) raise @bytes.Mp4Error {
    @bytes.Encode::encode(visual, payload)
    @bytes.Encode::encode(hvcc_box, payload)
    for b in unknown_boxes {
      @bytes.Encode::encode(b, payload)
    }
  })
}

///|
/// [ISO/IEC 14496-15] HEVCSampleEntry class (親: [`StsdBox`])。
/// 上流 `Hev1Box` に対応する。
///
/// `hev1` はパラメータセット（VPS / SPS / PPS）がサンプル中に in-band で
/// 現れうる場合に使う。
pub struct Hev1Box {
  /// 映像系サンプルエントリー共通フィールド
  visual : VisualSampleEntryFields
  /// H.265 デコーダー設定を保持する `hvcC` ボックス
  hvcc_box : HvccBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Hev1Box with Eq::{equal, not_equal}

///|
pub extend Hev1Box with Hash::{hash, hash_combine}

///|
pub extend Hev1Box with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Hev1Box::new(
  visual : VisualSampleEntryFields,
  hvcc_box : HvccBox,
  unknown_boxes : Array[UnknownBox],
) -> Hev1Box {
  { visual, hvcc_box, unknown_boxes, }
}

///|
/// `hev1` をデコードする。
///
/// 必須の `hvcC` ボックスが無い場合は [`@bytes.ErrorKind::InvalidData`]
/// で失敗する。`hvcC` が複数現れた場合は最初の 1 個だけを採用し、
/// 2 個目以降は `unknown_boxes` として保持する（上流と同じ）。
pub impl @bytes.Decode for Hev1Box with fn decode(cursor : @bytes.ReadCursor) -> Hev1Box raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(hev1_type(), fn() raise @bytes.Mp4Error {
    let (visual, hvcc_box, unknown_boxes) = decode_hevc_sample_entry(
      cursor,
      hev1_type(),
      "hev1",
    )
    { visual, hvcc_box, unknown_boxes, }
  })
}

///|
pub extend Hev1Box with @bytes.Decode::{decode}

///|
/// `hev1` をエンコードする。
pub impl @bytes.Encode for Hev1Box with fn encode(
  self : Hev1Box,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  encode_hevc_sample_entry(
    cursor,
    hev1_type(),
    self.visual,
    self.hvcc_box,
    self.unknown_boxes,
  )
}

///|
pub extend Hev1Box with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Hev1Box with fn box_type(_self) {
  hev1_type()
}

///|
/// `hvcC` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for Hev1Box with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.hvcc_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend Hev1Box with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// [ISO/IEC 14496-15] HEVCSampleEntry class (親: [`StsdBox`])。
/// 上流 `Hvc1Box` に対応する。
///
/// `hvc1` はパラメータセット（VPS / SPS / PPS）が全て `hvcC` の
/// out-of-band に格納される場合に使う。
pub struct Hvc1Box {
  /// 映像系サンプルエントリー共通フィールド
  visual : VisualSampleEntryFields
  /// H.265 デコーダー設定を保持する `hvcC` ボックス
  hvcc_box : HvccBox
  /// 上記のいずれにも該当しなかった子ボックス群（未知の box_type を含む）
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend Hvc1Box with Eq::{equal, not_equal}

///|
pub extend Hvc1Box with Hash::{hash, hash_combine}

///|
pub extend Hvc1Box with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn Hvc1Box::new(
  visual : VisualSampleEntryFields,
  hvcc_box : HvccBox,
  unknown_boxes : Array[UnknownBox],
) -> Hvc1Box {
  { visual, hvcc_box, unknown_boxes, }
}

///|
/// `hvc1` をデコードする。必須の `hvcC` ボックスが無い場合は
/// [`@bytes.ErrorKind::InvalidData`] で失敗する（[`Hev1Box`] と同じ規則）。
pub impl @bytes.Decode for Hvc1Box with fn decode(cursor : @bytes.ReadCursor) -> Hvc1Box raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(hvc1_type(), fn() raise @bytes.Mp4Error {
    let (visual, hvcc_box, unknown_boxes) = decode_hevc_sample_entry(
      cursor,
      hvc1_type(),
      "hvc1",
    )
    { visual, hvcc_box, unknown_boxes, }
  })
}

///|
pub extend Hvc1Box with @bytes.Decode::{decode}

///|
/// `hvc1` をエンコードする。
pub impl @bytes.Encode for Hvc1Box with fn encode(
  self : Hvc1Box,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  encode_hevc_sample_entry(
    cursor,
    hvc1_type(),
    self.visual,
    self.hvcc_box,
    self.unknown_boxes,
  )
}

///|
pub extend Hvc1Box with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for Hvc1Box with fn box_type(_self) {
  hvc1_type()
}

///|
/// `hvcC` ボックス、その後に未知子ボックス群を順に返す（上流と同じ順序）。
pub impl @box.BaseBox for Hvc1Box with fn children(self) {
  let children : Array[&@box.BaseBox] = [self.hvcc_box]
  for b in self.unknown_boxes {
    children.push(b)
  }
  children
}

///|
pub extend Hvc1Box with @box.BaseBox::{box_type, is_unknown_box, children}
