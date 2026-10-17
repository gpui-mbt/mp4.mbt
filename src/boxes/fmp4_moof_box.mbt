///|
/// [ISO/IEC 14496-12] MovieFragmentBox（`moof`）。
///
/// fMP4 のメディアセグメントを構成する。上流 `MoofBox` に対応する。
pub struct MoofBox {
  /// フラグメントのシーケンス番号を保持する `mfhd`
  mfhd_box : MfhdBox
  /// トラックごとの `traf`
  traf_boxes : Array[TrafBox]
  /// 未知の子ボックス
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend MoofBox with Eq::{equal, not_equal}

///|
pub extend MoofBox with Hash::{hash, hash_combine}

///|
pub extend MoofBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MoofBox::new(
  mfhd_box : MfhdBox,
  traf_boxes : Array[TrafBox],
  unknown_boxes : Array[UnknownBox],
) -> MoofBox {
  { mfhd_box, traf_boxes, unknown_boxes, }
}

///|
/// `moof` をデコードする。`mfhd` は必須。
pub impl @bytes.Decode for MoofBox with fn decode(cursor : @bytes.ReadCursor) -> MoofBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(moof_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(moof_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut mfhd_box : MfhdBox? = None
    let traf_boxes : Array[TrafBox] = []
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == mfhd_type() && mfhd_box is None {
        mfhd_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == traf_type() {
        traf_boxes.push(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      mfhd_box: check_mandatory_box(mfhd_box, "mfhd", "moof"),
      traf_boxes,
      unknown_boxes,
    }
  })
}

///|
pub extend MoofBox with @bytes.Decode::{decode}

///|
/// `moof` を canonical な形式でエンコードする。
pub impl @bytes.Encode for MoofBox with fn encode(
  self : MoofBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, moof_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.mfhd_box, payload)
    for traf in self.traf_boxes {
      @bytes.Encode::encode(traf, payload)
    }
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend MoofBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MoofBox with fn box_type(_self) {
  moof_type()
}

///|
pub impl @box.BaseBox for MoofBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.mfhd_box)
  for traf in self.traf_boxes {
    children.push(traf)
  }
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend MoofBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// [ISO/IEC 14496-12] MovieFragmentHeaderBox（`mfhd`）(親: [`MoofBox`])。
pub struct MfhdBox {
  /// フラグメントの通番（1 始まり）
  sequence_number : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend MfhdBox with Eq::{equal, not_equal}

///|
pub extend MfhdBox with Hash::{hash, hash_combine}

///|
pub extend MfhdBox with Debug::{to_repr}

///|
/// シーケンス番号を指定して作成する。
pub fn MfhdBox::new(sequence_number : UInt32) -> MfhdBox {
  { sequence_number, }
}

///|
/// `mfhd` をデコードする。
pub impl @bytes.Decode for MfhdBox with fn decode(cursor : @bytes.ReadCursor) -> MfhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mfhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mfhd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    { sequence_number: payload_cursor.read_u32(), }
  })
}

///|
pub extend MfhdBox with @bytes.Decode::{decode}

///|
/// `mfhd` をエンコードする。
pub impl @bytes.Encode for MfhdBox with fn encode(
  self : MfhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mfhd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.sequence_number)
  })
}

///|
pub extend MfhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MfhdBox with fn box_type(_self) {
  mfhd_type()
}

///|
pub impl @box.BaseBox for MfhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend MfhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for MfhdBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for MfhdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::empty()
}

///|
pub extend MfhdBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] TrackFragmentBox（`traf`）(親: [`MoofBox`])。
pub struct TrafBox {
  /// トラックフラグメントヘッダー
  tfhd_box : TfhdBox
  /// ベースデコード時間（省略可）
  tfdt_box : TfdtBox?
  /// サンプル列
  trun_boxes : Array[TrunBox]
  /// 未知の子ボックス
  unknown_boxes : Array[UnknownBox]
} derive(Eq, Hash, Debug)

///|
pub extend TrafBox with Eq::{equal, not_equal}

///|
pub extend TrafBox with Hash::{hash, hash_combine}

///|
pub extend TrafBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TrafBox::new(
  tfhd_box : TfhdBox,
  tfdt_box : TfdtBox?,
  trun_boxes : Array[TrunBox],
  unknown_boxes : Array[UnknownBox],
) -> TrafBox {
  { tfhd_box, tfdt_box, trun_boxes, unknown_boxes, }
}

///|
/// `traf` をデコードする。`tfhd` は必須。
pub impl @bytes.Decode for TrafBox with fn decode(cursor : @bytes.ReadCursor) -> TrafBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(traf_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(traf_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let mut tfhd_box : TfhdBox? = None
    let mut tfdt_box : TfdtBox? = None
    let trun_boxes : Array[TrunBox] = []
    let unknown_boxes : Array[UnknownBox] = []
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == tfhd_type() && tfhd_box is None {
        tfhd_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == tfdt_type() && tfdt_box is None {
        tfdt_box = Some(@bytes.decode_from(payload_cursor))
      } else if child_type == trun_type() {
        trun_boxes.push(@bytes.decode_from(payload_cursor))
      } else {
        unknown_boxes.push(@bytes.decode_from(payload_cursor))
      }
    }
    {
      tfhd_box: check_mandatory_box(tfhd_box, "tfhd", "traf"),
      tfdt_box,
      trun_boxes,
      unknown_boxes,
    }
  })
}

///|
pub extend TrafBox with @bytes.Decode::{decode}

///|
/// `traf` を canonical な形式でエンコードする。
pub impl @bytes.Encode for TrafBox with fn encode(
  self : TrafBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, traf_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(self.tfhd_box, payload)
    match self.tfdt_box {
      Some(tfdt) => @bytes.Encode::encode(tfdt, payload)
      None => ()
    }
    for trun in self.trun_boxes {
      @bytes.Encode::encode(trun, payload)
    }
    for unknown in self.unknown_boxes {
      @bytes.Encode::encode(unknown, payload)
    }
  })
}

///|
pub extend TrafBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TrafBox with fn box_type(_self) {
  traf_type()
}

///|
pub impl @box.BaseBox for TrafBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  children.push(self.tfhd_box)
  match self.tfdt_box {
    Some(tfdt) => children.push(tfdt)
    None => ()
  }
  for trun in self.trun_boxes {
    children.push(trun)
  }
  for unknown in self.unknown_boxes {
    children.push(unknown)
  }
  children
}

///|
pub extend TrafBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// `tfhd.base_data_offset` が存在することを示すフラグ。
pub const TFHD_FLAG_BASE_DATA_OFFSET_PRESENT : UInt32 = 0x000001U

///|
/// `tfhd.sample_description_index` が存在することを示すフラグ。
pub const TFHD_FLAG_SAMPLE_DESCRIPTION_INDEX_PRESENT : UInt32 = 0x000002U

///|
/// `tfhd.default_sample_duration` が存在することを示すフラグ。
pub const TFHD_FLAG_DEFAULT_SAMPLE_DURATION_PRESENT : UInt32 = 0x000008U

///|
/// `tfhd.default_sample_size` が存在することを示すフラグ。
pub const TFHD_FLAG_DEFAULT_SAMPLE_SIZE_PRESENT : UInt32 = 0x000010U

///|
/// `tfhd.default_sample_flags` が存在することを示すフラグ。
pub const TFHD_FLAG_DEFAULT_SAMPLE_FLAGS_PRESENT : UInt32 = 0x000020U

///|
/// 継続時間が空であることを示すフラグ。
pub const TFHD_FLAG_DURATION_IS_EMPTY : UInt32 = 0x010000U

///|
/// `base_data_offset` の既定値を moof の先頭にするフラグ。
pub const TFHD_FLAG_DEFAULT_BASE_IS_MOOF : UInt32 = 0x020000U

///|
/// [ISO/IEC 14496-12] TrackFragmentHeaderBox（`tfhd`）(親: [`TrafBox`])。
///
/// 7 種類の flags に対応する省略可能フィールドを持つ。上流 `TfhdBox` に対応する。
pub struct TfhdBox {
  /// トラック ID
  track_id : UInt32
  /// サンプルデータの基準オフセット（ファイル先頭からの絶対位置）
  base_data_offset : UInt64?
  /// `stsd` エントリーのインデックス（1 始まり）
  sample_description_index : UInt32?
  /// 既定のサンプル尺
  default_sample_duration : UInt32?
  /// 既定のサンプルサイズ
  default_sample_size : UInt32?
  /// 既定のサンプルフラグ
  default_sample_flags : SampleFlags?
  /// 継続時間が空かどうか
  duration_is_empty : Bool
  /// `base_data_offset` の既定値を moof の先頭にするかどうか
  default_base_is_moof : Bool
} derive(Eq, Hash, Debug)

///|
pub extend TfhdBox with Eq::{equal, not_equal}

///|
pub extend TfhdBox with Hash::{hash, hash_combine}

///|
pub extend TfhdBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TfhdBox::new(
  track_id : UInt32,
  base_data_offset : UInt64?,
  sample_description_index : UInt32?,
  default_sample_duration : UInt32?,
  default_sample_size : UInt32?,
  default_sample_flags : SampleFlags?,
  duration_is_empty : Bool,
  default_base_is_moof : Bool,
) -> TfhdBox {
  {
    track_id,
    base_data_offset,
    sample_description_index,
    default_sample_duration,
    default_sample_size,
    default_sample_flags,
    duration_is_empty,
    default_base_is_moof,
  }
}

///|
/// `tfhd` をデコードする。flags と optional フィールドの有無を一致させる。
pub impl @bytes.Decode for TfhdBox with fn decode(cursor : @bytes.ReadCursor) -> TfhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(tfhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(tfhd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let flags = full_header.flags().get()
    let track_id = payload_cursor.read_u32()
    let base_data_offset : UInt64? = if (
        flags & TFHD_FLAG_BASE_DATA_OFFSET_PRESENT
      ) !=
      0U {
      Some(payload_cursor.read_u64())
    } else {
      None
    }
    let sample_description_index : UInt32? = if (
        flags & TFHD_FLAG_SAMPLE_DESCRIPTION_INDEX_PRESENT
      ) !=
      0U {
      Some(payload_cursor.read_u32())
    } else {
      None
    }
    let default_sample_duration : UInt32? = if (
        flags & TFHD_FLAG_DEFAULT_SAMPLE_DURATION_PRESENT
      ) !=
      0U {
      Some(payload_cursor.read_u32())
    } else {
      None
    }
    let default_sample_size : UInt32? = if (
        flags & TFHD_FLAG_DEFAULT_SAMPLE_SIZE_PRESENT
      ) !=
      0U {
      Some(payload_cursor.read_u32())
    } else {
      None
    }
    let default_sample_flags : SampleFlags? = if (
        flags & TFHD_FLAG_DEFAULT_SAMPLE_FLAGS_PRESENT
      ) !=
      0U {
      Some(@bytes.decode_from(payload_cursor))
    } else {
      None
    }
    {
      track_id,
      base_data_offset,
      sample_description_index,
      default_sample_duration,
      default_sample_size,
      default_sample_flags,
      duration_is_empty: (flags & TFHD_FLAG_DURATION_IS_EMPTY) != 0U,
      default_base_is_moof: (flags & TFHD_FLAG_DEFAULT_BASE_IS_MOOF) != 0U,
    }
  })
}

///|
pub extend TfhdBox with @bytes.Decode::{decode}

///|
/// `tfhd` をエンコードする。フィールドの有無から flags を再構成する。
pub impl @bytes.Encode for TfhdBox with fn encode(
  self : TfhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, tfhd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.track_id)
    match self.base_data_offset {
      Some(value) => payload.write_u64(value)
      None => ()
    }
    match self.sample_description_index {
      Some(value) => payload.write_u32(value)
      None => ()
    }
    match self.default_sample_duration {
      Some(value) => payload.write_u32(value)
      None => ()
    }
    match self.default_sample_size {
      Some(value) => payload.write_u32(value)
      None => ()
    }
    match self.default_sample_flags {
      Some(value) => @bytes.Encode::encode(value, payload)
      None => ()
    }
  })
}

///|
pub extend TfhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TfhdBox with fn box_type(_self) {
  tfhd_type()
}

///|
pub impl @box.BaseBox for TfhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend TfhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for TfhdBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for TfhdBox with fn full_box_flags(self) {
  let mut flags : UInt32 = 0U
  if self.base_data_offset is Some(_) {
    flags = flags | TFHD_FLAG_BASE_DATA_OFFSET_PRESENT
  }
  if self.sample_description_index is Some(_) {
    flags = flags | TFHD_FLAG_SAMPLE_DESCRIPTION_INDEX_PRESENT
  }
  if self.default_sample_duration is Some(_) {
    flags = flags | TFHD_FLAG_DEFAULT_SAMPLE_DURATION_PRESENT
  }
  if self.default_sample_size is Some(_) {
    flags = flags | TFHD_FLAG_DEFAULT_SAMPLE_SIZE_PRESENT
  }
  if self.default_sample_flags is Some(_) {
    flags = flags | TFHD_FLAG_DEFAULT_SAMPLE_FLAGS_PRESENT
  }
  if self.duration_is_empty {
    flags = flags | TFHD_FLAG_DURATION_IS_EMPTY
  }
  if self.default_base_is_moof {
    flags = flags | TFHD_FLAG_DEFAULT_BASE_IS_MOOF
  }
  @box.FullBoxFlags::new(flags)
}

///|
pub extend TfhdBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] TrackFragmentBaseMediaDecodeTimeBox（`tfdt`）(親: [`TrafBox`])。
///
/// version 0 は 32-bit、version 1 は 64-bit の base media decode time を持つ。
pub struct TfdtBox {
  /// デコード時の FullBox バージョン（0 または 1）
  version : UInt32
  /// このトラックフラグメントの最初のサンプルの DTS
  base_media_decode_time : UInt64
} derive(Eq, Hash, Debug)

///|
pub extend TfdtBox with Eq::{equal, not_equal}

///|
pub extend TfdtBox with Hash::{hash, hash_combine}

///|
pub extend TfdtBox with Debug::{to_repr}

///|
/// version と値を指定して作成する。
pub fn TfdtBox::new(
  version : UInt32,
  base_media_decode_time : UInt64,
) -> TfdtBox {
  { version, base_media_decode_time, }
}

///|
/// `tfdt` をデコードする。
pub impl @bytes.Decode for TfdtBox with fn decode(cursor : @bytes.ReadCursor) -> TfdtBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(tfdt_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(tfdt_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let version = full_header.version()
    let base_media_decode_time : UInt64 = if version == 1 {
      payload_cursor.read_u64()
    } else {
      payload_cursor.read_u32().to_uint64()
    }
    { version, base_media_decode_time, }
  })
}

///|
pub extend TfdtBox with @bytes.Decode::{decode}

///|
/// `tfdt` をエンコードする。値が 32-bit に収まらない場合は version 1 になる。
pub impl @bytes.Encode for TfdtBox with fn encode(
  self : TfdtBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, tfdt_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    if full_header.version() == 1 {
      payload.write_u64(self.base_media_decode_time)
    } else {
      payload.write_u32(self.base_media_decode_time.to_uint())
    }
  })
}

///|
pub extend TfdtBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TfdtBox with fn box_type(_self) {
  tfdt_type()
}

///|
pub impl @box.BaseBox for TfdtBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend TfdtBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for TfdtBox with fn full_box_version(self) {
  if self.base_media_decode_time > 0xFFFFFFFFUL {
    1U
  } else {
    self.version
  }
}

///|
pub impl @box.FullBox for TfdtBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::empty()
}

///|
pub extend TfdtBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// `trun.data_offset` が存在することを示すフラグ。
pub const TRUN_FLAG_DATA_OFFSET_PRESENT : UInt32 = 0x000001U

///|
/// `trun.first_sample_flags` が存在することを示すフラグ。
pub const TRUN_FLAG_FIRST_SAMPLE_FLAGS_PRESENT : UInt32 = 0x000004U

///|
/// per-sample duration が存在することを示すフラグ。
pub const TRUN_FLAG_SAMPLE_DURATION_PRESENT : UInt32 = 0x000100U

///|
/// per-sample size が存在することを示すフラグ。
pub const TRUN_FLAG_SAMPLE_SIZE_PRESENT : UInt32 = 0x000200U

///|
/// per-sample flags が存在することを示すフラグ。
pub const TRUN_FLAG_SAMPLE_FLAGS_PRESENT : UInt32 = 0x000400U

///|
/// per-sample composition time offset が存在することを示すフラグ。
pub const TRUN_FLAG_SAMPLE_COMPOSITION_TIME_OFFSETS_PRESENT : UInt32 = 0x000800U

///|
/// per-sample データなしで許容するサンプル数の上限（上流と同じ）。
pub const TRUN_MAX_SAMPLES_WITHOUT_DATA : UInt32 = 16777216U

///|
/// [`TrunBox`] の 1 サンプル分の情報。
///
/// per-sample フィールドの `Option` の有無は run 全体で一致していなければならない。
pub struct TrunSample {
  /// このサンプルの尺（省略時は `tfhd` / `trex` の既定値）
  duration : UInt32?
  /// このサンプルのサイズ（省略時は `tfhd` / `trex` の既定値）
  size : UInt32?
  /// このサンプルのフラグ（省略時は `tfhd` / `trex` の既定値）
  flags : SampleFlags?
  /// CTS - DTS（省略時は 0 とみなす）
  composition_time_offset : Int64?
} derive(Eq, Hash, Debug)

///|
pub extend TrunSample with Eq::{equal, not_equal}

///|
pub extend TrunSample with Hash::{hash, hash_combine}

///|
pub extend TrunSample with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TrunSample::new(
  duration : UInt32?,
  size : UInt32?,
  flags : SampleFlags?,
  composition_time_offset : Int64?,
) -> TrunSample {
  { duration, size, flags, composition_time_offset, }
}

///|
/// [ISO/IEC 14496-12] TrackRunBox（`trun`）(親: [`TrafBox`])。
///
/// flags に応じて per-sample フィールドを持つ。上流 `TrunBox` に対応する。
pub struct TrunBox {
  /// この run の基準位置からの相対バイトオフセット
  data_offset : Int32?
  /// 最初のサンプルだけに適用するフラグ
  first_sample_flags : SampleFlags?
  /// サンプル列
  samples : Array[TrunSample]
} derive(Eq, Hash, Debug)

///|
pub extend TrunBox with Eq::{equal, not_equal}

///|
pub extend TrunBox with Hash::{hash, hash_combine}

///|
pub extend TrunBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TrunBox::new(
  data_offset : Int32?,
  first_sample_flags : SampleFlags?,
  samples : Array[TrunSample],
) -> TrunBox {
  { data_offset, first_sample_flags, samples, }
}

///|
/// per-sample フィールドの `Option` 有無が run 全体で一致することを検証する。
fn TrunBox::validate_sample_option_consistency(
  self : TrunBox,
) -> Unit raise @bytes.Mp4Error {
  if self.samples.length() == 0 {
    return
  }
  let first = self.samples[0]
  let has_duration = first.duration is Some(_)
  let has_size = first.size is Some(_)
  let has_flags = first.flags is Some(_)
  let has_cto = first.composition_time_offset is Some(_)
  let mut index = 1
  while index < self.samples.length() {
    let sample = self.samples[index]
    let mismatch = if (sample.duration is Some(_)) != has_duration {
      Some(("duration", has_duration, sample.duration is Some(_)))
    } else if (sample.size is Some(_)) != has_size {
      Some(("size", has_size, sample.size is Some(_)))
    } else if (sample.flags is Some(_)) != has_flags {
      Some(("flags", has_flags, sample.flags is Some(_)))
    } else if (sample.composition_time_offset is Some(_)) != has_cto {
      Some(
        (
          "composition_time_offset",
          has_cto,
          sample.composition_time_offset is Some(_),
        ),
      )
    } else {
      let none : (String, Bool, Bool)? = None
      none
    }
    match mismatch {
      Some((field, expected_some, got_some)) => {
        let presence = fn(is_some : Bool) -> String {
          if is_some {
            "Some"
          } else {
            "None"
          }
        }
        raise @bytes.Mp4Error::invalid_input(
          "TrunBox sample \{index} has inconsistent Option presence for \{field}: sample 0 is \{presence(expected_some)}, sample \{index} is \{presence(got_some)}",
        )
      }
      None => ()
    }
    index = index + 1
  }
}

///|
/// run 全体で使う flags を計算する。
fn TrunBox::compute_flags(self : TrunBox) -> UInt32 {
  let mut flags : UInt32 = 0U
  if self.data_offset is Some(_) {
    flags = flags | TRUN_FLAG_DATA_OFFSET_PRESENT
  }
  if self.first_sample_flags is Some(_) {
    flags = flags | TRUN_FLAG_FIRST_SAMPLE_FLAGS_PRESENT
  }
  for sample in self.samples {
    if sample.duration is Some(_) {
      flags = flags | TRUN_FLAG_SAMPLE_DURATION_PRESENT
    }
    if sample.size is Some(_) {
      flags = flags | TRUN_FLAG_SAMPLE_SIZE_PRESENT
    }
    if sample.flags is Some(_) {
      flags = flags | TRUN_FLAG_SAMPLE_FLAGS_PRESENT
    }
    if sample.composition_time_offset is Some(_) {
      flags = flags | TRUN_FLAG_SAMPLE_COMPOSITION_TIME_OFFSETS_PRESENT
    }
  }
  flags
}

///|
/// 負の composition time offset を含む場合は version 1 が必要。
fn TrunBox::uses_version_1(self : TrunBox) -> Bool {
  for sample in self.samples {
    match sample.composition_time_offset {
      Some(offset) => if offset < 0L { return true }
      None => ()
    }
  }
  false
}

///|
/// `trun` をデコードする。
pub impl @bytes.Decode for TrunBox with fn decode(cursor : @bytes.ReadCursor) -> TrunBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(trun_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(trun_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let flags = full_header.flags().get()
    let version = full_header.version()
    let sample_count = payload_cursor.read_u32()
    let data_offset : Int32? = if (flags & TRUN_FLAG_DATA_OFFSET_PRESENT) != 0U {
      Some(payload_cursor.read_i32())
    } else {
      None
    }
    let first_sample_flags : SampleFlags? = if (
        flags & TRUN_FLAG_FIRST_SAMPLE_FLAGS_PRESENT
      ) !=
      0U {
      Some(@bytes.decode_from(payload_cursor))
    } else {
      None
    }
    let mut bytes_per_sample = 0
    if (flags & TRUN_FLAG_SAMPLE_DURATION_PRESENT) != 0U {
      bytes_per_sample = bytes_per_sample + 4
    }
    if (flags & TRUN_FLAG_SAMPLE_SIZE_PRESENT) != 0U {
      bytes_per_sample = bytes_per_sample + 4
    }
    if (flags & TRUN_FLAG_SAMPLE_FLAGS_PRESENT) != 0U {
      bytes_per_sample = bytes_per_sample + 4
    }
    if (flags & TRUN_FLAG_SAMPLE_COMPOSITION_TIME_OFFSETS_PRESENT) != 0U {
      bytes_per_sample = bytes_per_sample + 4
    }
    if bytes_per_sample > 0 {
      let max_samples = payload_cursor.remaining() / bytes_per_sample
      if sample_count.to_uint64() > max_samples.to_uint64() {
        raise @bytes.Mp4Error::invalid_data(
          "TrunBox sample_count exceeds available payload",
        )
      }
    } else if sample_count > TRUN_MAX_SAMPLES_WITHOUT_DATA {
      raise @bytes.Mp4Error::invalid_data(
        "TrunBox sample_count exceeds maximum allowed when no per-sample data is present",
      )
    }
    let samples : Array[TrunSample] = []
    let mut remaining = sample_count
    while remaining > 0U {
      let duration : UInt32? = if (flags & TRUN_FLAG_SAMPLE_DURATION_PRESENT) !=
        0U {
        Some(payload_cursor.read_u32())
      } else {
        None
      }
      let size : UInt32? = if (flags & TRUN_FLAG_SAMPLE_SIZE_PRESENT) != 0U {
        Some(payload_cursor.read_u32())
      } else {
        None
      }
      let sample_flags : SampleFlags? = if (
          flags & TRUN_FLAG_SAMPLE_FLAGS_PRESENT
        ) !=
        0U {
        Some(@bytes.decode_from(payload_cursor))
      } else {
        None
      }
      let composition_time_offset : Int64? = if (
          flags & TRUN_FLAG_SAMPLE_COMPOSITION_TIME_OFFSETS_PRESENT
        ) !=
        0U {
        if version == 1 {
          Some(payload_cursor.read_i32().to_int64())
        } else {
          Some(payload_cursor.read_u32().to_uint64().reinterpret_as_int64())
        }
      } else {
        None
      }
      samples.push(
        TrunSample::new(duration, size, sample_flags, composition_time_offset),
      )
      remaining = remaining - 1U
    }
    { data_offset, first_sample_flags, samples, }
  })
}

///|
pub extend TrunBox with @bytes.Decode::{decode}

///|
/// `trun` をエンコードする。
pub impl @bytes.Encode for TrunBox with fn encode(
  self : TrunBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  self.validate_sample_option_consistency()
  write_box_with_payload(cursor, trun_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let version = if self.uses_version_1() { 1U } else { 0U }
    let flags = self.compute_flags()
    @bytes.Encode::encode(
      @box.FullBoxHeader::new(version, @box.FullBoxFlags::new(flags)),
      payload,
    )
    payload.write_u32(self.samples.length().reinterpret_as_uint())
    match self.data_offset {
      Some(value) => payload.write_i32(value)
      None => ()
    }
    match self.first_sample_flags {
      Some(value) => @bytes.Encode::encode(value, payload)
      None => ()
    }
    for sample in self.samples {
      if (flags & TRUN_FLAG_SAMPLE_DURATION_PRESENT) != 0U {
        payload.write_u32(sample.duration.unwrap_or(0U))
      }
      if (flags & TRUN_FLAG_SAMPLE_SIZE_PRESENT) != 0U {
        payload.write_u32(sample.size.unwrap_or(0U))
      }
      if (flags & TRUN_FLAG_SAMPLE_FLAGS_PRESENT) != 0U {
        match sample.flags {
          Some(value) => @bytes.Encode::encode(value, payload)
          None => @bytes.Encode::encode(SampleFlags::empty(), payload)
        }
      }
      if (flags & TRUN_FLAG_SAMPLE_COMPOSITION_TIME_OFFSETS_PRESENT) != 0U {
        let cto = sample.composition_time_offset.unwrap_or(0L)
        if version == 1U {
          if cto > 0x7FFFFFFFL || cto < -0x80000000L {
            raise @bytes.Mp4Error::invalid_input(
              "trun version 1 requires composition_time_offset to be in i32 range, got \{cto}",
            )
          }
          payload.write_i32(cto.to_int())
        } else {
          if cto < 0L || cto > 0xFFFFFFFFL {
            raise @bytes.Mp4Error::invalid_input(
              "trun version 0 requires composition_time_offset to be in u32 range, got \{cto}",
            )
          }
          payload.write_u32(cto.reinterpret_as_uint64().to_uint())
        }
      }
    }
  })
}

///|
pub extend TrunBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TrunBox with fn box_type(_self) {
  trun_type()
}

///|
pub impl @box.BaseBox for TrunBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend TrunBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for TrunBox with fn full_box_version(self) {
  if self.uses_version_1() {
    1U
  } else {
    0U
  }
}

///|
pub impl @box.FullBox for TrunBox with fn full_box_flags(self) {
  @box.FullBoxFlags::new(self.compute_flags())
}

///|
pub extend TrunBox with @box.FullBox::{full_box_version, full_box_flags}
