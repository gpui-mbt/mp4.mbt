///|
/// [ISO/IEC 14496-12] MovieFragmentRandomAccessBox（`mfra`）。
///
/// ランダムアクセス用のインデックスを保持する。上流 `MfraBox` に対応する。
/// 末尾の `mfro` は必須。
pub struct MfraBox {
  /// トラックごとの `tfra`
  tfra_boxes : Array[TfraBox]
  /// この `mfra` のサイズを保持する `mfro`
  mfro_box : MfroBox
} derive(Eq, Hash, Debug)

///|
pub extend MfraBox with Eq::{equal, not_equal}

///|
pub extend MfraBox with Hash::{hash, hash_combine}

///|
pub extend MfraBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MfraBox::new(tfra_boxes : Array[TfraBox], mfro_box : MfroBox) -> MfraBox {
  { tfra_boxes, mfro_box, }
}

///|
/// `mfra` をデコードする。`mfro` は必須。
pub impl @bytes.Decode for MfraBox with fn decode(cursor : @bytes.ReadCursor) -> MfraBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mfra_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mfra_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let tfra_boxes : Array[TfraBox] = []
    let mut mfro_box : MfroBox? = None
    while !payload_cursor.is_empty() {
      let child_type = peek_box_type(payload_cursor)
      if child_type == tfra_type() {
        tfra_boxes.push(@bytes.decode_from(payload_cursor))
      } else if child_type == mfro_type() {
        mfro_box = Some(@bytes.decode_from(payload_cursor))
      } else {
        let _unknown : UnknownBox = @bytes.decode_from(payload_cursor)
      }
    }
    { tfra_boxes, mfro_box: check_mandatory_box(mfro_box, "mfro", "mfra"), }
  })
}

///|
pub extend MfraBox with @bytes.Decode::{decode}

///|
/// `mfra` をエンコードする。
pub impl @bytes.Encode for MfraBox with fn encode(
  self : MfraBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mfra_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    for tfra in self.tfra_boxes {
      @bytes.Encode::encode(tfra, payload)
    }
    @bytes.Encode::encode(self.mfro_box, payload)
  })
}

///|
pub extend MfraBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MfraBox with fn box_type(_self) {
  mfra_type()
}

///|
pub impl @box.BaseBox for MfraBox with fn children(self) {
  let children : Array[&@box.BaseBox] = []
  for tfra in self.tfra_boxes {
    children.push(tfra)
  }
  children.push(self.mfro_box)
  children
}

///|
pub extend MfraBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// [`TfraBox`] の 1 エントリー。
pub struct TfraEntry {
  /// このエントリーが指すサンプルの presentation time（media timescale 単位）
  time : UInt64
  /// 該当サンプルを含む `moof` のファイル先頭からの絶対位置
  moof_offset : UInt64
  /// 該当 `moof` 内の `traf` 番号（1 始まり）
  traf_number : UInt32
  /// 該当 `traf` 内の `trun` 番号（1 始まり）
  trun_number : UInt32
  /// 該当 `trun` 内のサンプル番号（1 始まり）
  sample_number : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend TfraEntry with Eq::{equal, not_equal}

///|
pub extend TfraEntry with Hash::{hash, hash_combine}

///|
pub extend TfraEntry with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TfraEntry::new(
  time : UInt64,
  moof_offset : UInt64,
  traf_number : UInt32,
  trun_number : UInt32,
  sample_number : UInt32,
) -> TfraEntry {
  { time, moof_offset, traf_number, trun_number, sample_number, }
}

///|
/// 【ISO/IEC 14496-12】TrackFragmentRandomAccessBox（`tfra`）。
pub struct TfraBox {
  /// デコード時の FullBox バージョン（0 または 1）
  version : UInt32
  /// このエントリーが対応する track_id
  track_id : UInt32
  /// traf_number のバイト数 - 1（0-3）
  length_size_of_traf_num : UInt32
  /// trun_number のバイト数 - 1（0-3）
  length_size_of_trun_num : UInt32
  /// sample_number のバイト数 - 1（0-3）
  length_size_of_sample_num : UInt32
  /// エントリー列
  entries : Array[TfraEntry]
} derive(Eq, Hash, Debug)

///|
pub extend TfraBox with Eq::{equal, not_equal}

///|
pub extend TfraBox with Hash::{hash, hash_combine}

///|
pub extend TfraBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TfraBox::new(
  version : UInt32,
  track_id : UInt32,
  length_size_of_traf_num : UInt32,
  length_size_of_trun_num : UInt32,
  length_size_of_sample_num : UInt32,
  entries : Array[TfraEntry],
) -> TfraBox {
  {
    version,
    track_id,
    length_size_of_traf_num,
    length_size_of_trun_num,
    length_size_of_sample_num,
    entries,
  }
}

///|
/// `tfra` をデコードする。
pub impl @bytes.Decode for TfraBox with fn decode(cursor : @bytes.ReadCursor) -> TfraBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(tfra_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(tfra_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let version = full_header.version()
    let track_id = payload_cursor.read_u32()
    let lengths = payload_cursor.read_u32()
    let length_size_of_traf_num = (lengths >> 4) & 0b11U
    let length_size_of_trun_num = (lengths >> 2) & 0b11U
    let length_size_of_sample_num = lengths & 0b11U
    let number_of_entry = payload_cursor.read_u32()
    if number_of_entry > 0x7FFFFFFFU {
      raise @bytes.Mp4Error::invalid_data(
        "TfraBox number_of_entry exceeds Int range",
      )
    }
    let time_moof_size = if version == 1 { 16 } else { 8 }
    let variable_size = length_size_of_traf_num.reinterpret_as_int() +
      1 +
      (length_size_of_trun_num.reinterpret_as_int() + 1) +
      (length_size_of_sample_num.reinterpret_as_int() + 1)
    let entry_size = time_moof_size + variable_size
    let required = number_of_entry.reinterpret_as_int() * entry_size
    if required > payload_cursor.remaining() {
      raise @bytes.Mp4Error::invalid_data(
        "TfraBox number_of_entry exceeds remaining payload",
      )
    }
    let entries : Array[TfraEntry] = []
    let mut remaining = number_of_entry
    while remaining > 0U {
      let time_and_offset : (UInt64, UInt64) = if version == 1 {
        (payload_cursor.read_u64(), payload_cursor.read_u64())
      } else {
        (
          payload_cursor.read_u32().to_uint64(),
          payload_cursor.read_u32().to_uint64(),
        )
      }
      let (time, moof_offset) = time_and_offset
      let traf_number = read_variable_uint(
        payload_cursor,
        length_size_of_traf_num.reinterpret_as_int() + 1,
      )
      let trun_number = read_variable_uint(
        payload_cursor,
        length_size_of_trun_num.reinterpret_as_int() + 1,
      )
      let sample_number = read_variable_uint(
        payload_cursor,
        length_size_of_sample_num.reinterpret_as_int() + 1,
      )
      entries.push(
        TfraEntry::new(
          time, moof_offset, traf_number, trun_number, sample_number,
        ),
      )
      remaining = remaining - 1U
    }
    {
      version,
      track_id,
      length_size_of_traf_num,
      length_size_of_trun_num,
      length_size_of_sample_num,
      entries,
    }
  })
}

///|
pub extend TfraBox with @bytes.Decode::{decode}

///|
/// `tfra` をエンコードする。
pub impl @bytes.Encode for TfraBox with fn encode(
  self : TfraBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, tfra_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    let version = full_header.version()
    @bytes.Encode::encode(full_header, payload)
    payload.write_u32(self.track_id)
    payload.write_u32(
      ((self.length_size_of_traf_num & 0b11U) << 4) |
      ((self.length_size_of_trun_num & 0b11U) << 2) |
      (self.length_size_of_sample_num & 0b11U),
    )
    payload.write_u32(self.entries.length().reinterpret_as_uint())
    for entry in self.entries {
      if version == 1 {
        payload.write_u64(entry.time)
        payload.write_u64(entry.moof_offset)
      } else {
        if entry.time > 0xFFFFFFFFUL || entry.moof_offset > 0xFFFFFFFFUL {
          raise @bytes.Mp4Error::invalid_data(
            "TfraBox version 0 requires 32-bit time and moof_offset",
          )
        }
        payload.write_u32(entry.time.to_uint())
        payload.write_u32(entry.moof_offset.to_uint())
      }
      write_variable_uint(
        payload,
        entry.traf_number,
        self.length_size_of_traf_num.reinterpret_as_int() + 1,
      )
      write_variable_uint(
        payload,
        entry.trun_number,
        self.length_size_of_trun_num.reinterpret_as_int() + 1,
      )
      write_variable_uint(
        payload,
        entry.sample_number,
        self.length_size_of_sample_num.reinterpret_as_int() + 1,
      )
    }
  })
}

///|
pub extend TfraBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TfraBox with fn box_type(_self) {
  tfra_type()
}

///|
pub impl @box.BaseBox for TfraBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend TfraBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for TfraBox with fn full_box_version(self) {
  for entry in self.entries {
    if entry.time > 0xFFFFFFFFUL || entry.moof_offset > 0xFFFFFFFFUL {
      return 1U
    }
  }
  self.version
}

///|
pub impl @box.FullBox for TfraBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::empty()
}

///|
pub extend TfraBox with @box.FullBox::{full_box_version, full_box_flags}

///|
/// [ISO/IEC 14496-12] MovieFragmentRandomAccessOffsetBox（`mfro`）。
pub struct MfroBox {
  /// `mfra` ボックスのサイズ
  size : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend MfroBox with Eq::{equal, not_equal}

///|
pub extend MfroBox with Hash::{hash, hash_combine}

///|
pub extend MfroBox with Debug::{to_repr}

///|
/// サイズを指定して作成する。
pub fn MfroBox::new(size : UInt32) -> MfroBox {
  { size, }
}

///|
/// `mfro` をデコードする。
pub impl @bytes.Decode for MfroBox with fn decode(cursor : @bytes.ReadCursor) -> MfroBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mfro_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mfro_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let _full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    { size: payload_cursor.read_u32(), }
  })
}

///|
pub extend MfroBox with @bytes.Decode::{decode}

///|
/// `mfro` をエンコードする。
pub impl @bytes.Encode for MfroBox with fn encode(
  self : MfroBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mfro_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    payload.write_u32(self.size)
  })
}

///|
pub extend MfroBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MfroBox with fn box_type(_self) {
  mfro_type()
}

///|
pub impl @box.BaseBox for MfroBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend MfroBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for MfroBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for MfroBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::empty()
}

///|
pub extend MfroBox with @box.FullBox::{full_box_version, full_box_flags}
