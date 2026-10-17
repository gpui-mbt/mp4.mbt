///|
/// H.264 の NAL ユニット種別（主要値）。
pub(all) enum H264NalUnitType {
  /// 非 IDR スライス (1)
  NonIdrSlice
  /// IDR スライス (5)
  IdrSlice
  /// SEI (6)
  Sei
  /// SPS (7)
  Sps
  /// PPS (8)
  Pps
  /// AUD (9)
  Aud
  /// その他
  Other(UInt32)
} derive(Eq, Hash, Debug)

///|
pub extend H264NalUnitType with Eq::{equal, not_equal}

///|
pub extend H264NalUnitType with Hash::{hash, hash_combine}

///|
pub extend H264NalUnitType with Debug::{to_repr}

///|
/// NAL ヘッダー値から種別を作る。
pub fn H264NalUnitType::from_value(value : UInt32) -> H264NalUnitType {
  match value {
    1U => NonIdrSlice
    5U => IdrSlice
    6U => Sei
    7U => Sps
    8U => Pps
    9U => Aud
    other => Other(other)
  }
}

///|
/// 1 個の NAL ユニット（NAL ヘッダーを含む）。
pub struct H264NalUnit {
  /// NAL 種別
  nal_unit_type : H264NalUnitType
  /// NAL 本体（NAL ヘッダーを含み、開始コード/長さプレフィックスを含まない）
  data : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend H264NalUnit with Eq::{equal, not_equal}

///|
pub extend H264NalUnit with Hash::{hash, hash_combine}

///|
pub extend H264NalUnit with Debug::{to_repr}

///|
fn h264_nal_from_bytes(data : Bytes) -> H264NalUnit raise @bytes.Mp4Error {
  if data.length() < 1 {
    raise @bytes.Mp4Error::invalid_input("NAL unit is shorter than 1 byte")
  }
  let header = data[0].to_uint()
  if (header & 0x80U) != 0U {
    raise @bytes.Mp4Error::invalid_input("forbidden_zero_bit must be 0")
  }
  { nal_unit_type: H264NalUnitType::from_value(header & 0x1FU), data, }
}

///|
/// Annex B の NAL ユニット列を解析する。
pub fn parse_annexb_nal_units(
  input : Bytes,
) -> Array[H264NalUnit] raise @bytes.Mp4Error {
  let nals : Array[H264NalUnit] = []
  let mut i = 0
  let mut start = -1
  while i + 3 <= input.length() {
    let is4 = i + 4 <= input.length() &&
      input[i] == b'\x00' &&
      input[i + 1] == b'\x00' &&
      input[i + 2] == b'\x00' &&
      input[i + 3] == b'\x01'
    let is3 = input[i] == b'\x00' &&
      input[i + 1] == b'\x00' &&
      input[i + 2] == b'\x01'
    if is4 || is3 {
      if start >= 0 && i > start {
        nals.push(h264_nal_from_bytes(input[start:i].to_owned()))
      }
      i = i + (if is4 { 4 } else { 3 })
      start = i
    } else {
      i = i + 1
    }
  }
  if start >= 0 && start < input.length() {
    nals.push(h264_nal_from_bytes(input[start:].to_owned()))
  } else if input.length() > 0 {
    raise @bytes.Mp4Error::invalid_input("Annex B start code not found")
  }
  nals
}

///|
/// length-prefixed 形式の NAL ユニット列を解析する。
pub fn parse_length_prefixed_nal_units(
  input : Bytes,
  length_size : LengthSize,
) -> Array[H264NalUnit] raise @bytes.Mp4Error {
  let nals : Array[H264NalUnit] = []
  let mut offset = 0
  let width = length_size.bytes()
  while offset < input.length() {
    if offset + width > input.length() {
      raise @bytes.Mp4Error::invalid_input("truncated NAL length field")
    }
    let mut length : UInt32 = 0U
    let mut i = 0
    while i < width {
      length = (length << 8) | input[offset + i].to_uint()
      i = i + 1
    }
    offset = offset + width
    if length == 0U {
      raise @bytes.Mp4Error::invalid_input("NAL unit length must be non-zero")
    }
    let end = offset + length.reinterpret_as_int()
    if end > input.length() {
      raise @bytes.Mp4Error::invalid_input("NAL unit exceeds input")
    }
    nals.push(h264_nal_from_bytes(input[offset:end].to_owned()))
    offset = end
  }
  nals
}

///|
/// Annex B を length-prefixed 形式へ変換する。
pub fn annexb_to_length_prefixed(
  input : Bytes,
  length_size : LengthSize,
) -> Bytes raise @bytes.Mp4Error {
  let nals = parse_annexb_nal_units(input)
  let writer = @bytes.WriteCursor::new()
  for nal in nals {
    write_h264_length(writer, nal.data.length(), length_size)
    writer.write_bytes(nal.data)
  }
  writer.to_bytes()
}

///|
/// length-prefixed 形式を Annex B へ変換する。
pub fn length_prefixed_to_annexb(
  input : Bytes,
  length_size : LengthSize,
) -> Bytes raise @bytes.Mp4Error {
  let nals = parse_length_prefixed_nal_units(input, length_size)
  let writer = @bytes.WriteCursor::new()
  for nal in nals {
    writer.write_bytes(b"\x00\x00\x00\x01")
    writer.write_bytes(nal.data)
  }
  writer.to_bytes()
}

///|
fn write_h264_length(
  writer : @bytes.WriteCursor,
  length : Int32,
  length_size : LengthSize,
) -> Unit raise @bytes.Mp4Error {
  let width = length_size.bytes()
  if length < 0 || (width < 4 && length >= 1 << (width * 8)) {
    raise @bytes.Mp4Error::invalid_input("NAL unit length exceeds length_size")
  }
  let value = length.reinterpret_as_uint()
  if width == 1 {
    writer.write_u8(value)
  } else if width == 2 {
    writer.write_u16(value)
  } else if width == 3 {
    writer.write_u24(value)
  } else {
    writer.write_u32(value)
  }
}

///|
/// `nal_unit_type` に一致する NAL を入力順に集める。
pub fn collect_nal_units(
  nals : Array[H264NalUnit],
  nal_unit_type : H264NalUnitType,
) -> Array[Bytes] {
  let out : Array[Bytes] = []
  for nal in nals {
    if nal.nal_unit_type == nal_unit_type {
      out.push(nal.data)
    }
  }
  out
}

///|
/// H.264 の profile / level 情報。
pub struct H264ProfileLevelId {
  /// profile_idc
  profile_idc : UInt32
  /// profile-iop 1 バイト
  profile_iop : UInt32
  /// level_idc
  level_idc : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend H264ProfileLevelId with Eq::{equal, not_equal}

///|
pub extend H264ProfileLevelId with Hash::{hash, hash_combine}

///|
pub extend H264ProfileLevelId with Debug::{to_repr}

///|
/// 6 桁 hex から作る。
pub fn H264ProfileLevelId::from_hex(
  hex : String,
) -> H264ProfileLevelId raise @bytes.Mp4Error {
  let value = parse_hex(hex) catch {
    _ => raise @bytes.Mp4Error::invalid_input("invalid profile-level-id")
  }
  {
    profile_idc: (value >> 16) & 0xFFU,
    profile_iop: (value >> 8) & 0xFFU,
    level_idc: value & 0xFFU,
  }
}

///|
/// 6 桁小文字 hex へ変換する。
pub fn H264ProfileLevelId::to_hex(self : H264ProfileLevelId) -> String {
  hex2(self.profile_idc) + hex2(self.profile_iop) + hex2(self.level_idc)
}

///|
fn parse_hex(s : String) -> UInt32 raise {
  if s.length() != 6 {
    raise @bytes.Mp4Error::invalid_input(
      "profile-level-id must be 6 hex digits",
    )
  }
  let mut value : UInt32 = 0U
  for c in s {
    let digit = match c {
      '0'..<='9' => c.to_int() - '0'.to_int()
      'a'..<='f' => c.to_int() - 'a'.to_int() + 10
      'A'..<='F' => c.to_int() - 'A'.to_int() + 10
      _ => raise @bytes.Mp4Error::invalid_input("invalid hex digit")
    }
    value = (value << 4) | digit.reinterpret_as_uint()
  }
  value
}

///|
fn hex2(value : UInt32) -> String {
  let digits = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let hi = ((value >> 4) & 0xFU).reinterpret_as_int()
  let lo = (value & 0xFU).reinterpret_as_int()
  let builder = StringBuilder()
  builder.write_char(digits[hi])
  builder.write_char(digits[lo])
  builder.to_string()
}

///|
/// SPS の解析結果（幅・高さ・profile/level）。
pub struct H264Sps {
  /// profile / level
  profile_level_id : H264ProfileLevelId
  /// chroma_format_idc
  chroma_format_idc : UInt32
  /// bit_depth_luma_minus8
  bit_depth_luma_minus8 : UInt32
  /// bit_depth_chroma_minus8
  bit_depth_chroma_minus8 : UInt32
  /// クロップ適用後の幅
  width : UInt32
  /// クロップ適用後の高さ
  height : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend H264Sps with Eq::{equal, not_equal}

///|
pub extend H264Sps with Hash::{hash, hash_combine}

///|
pub extend H264Sps with Debug::{to_repr}

///|
/// BitReader から Exp-Golomb の `ue(v)` を読む。
fn h264_read_ue(reader : BitReader) -> UInt32 raise @bytes.Mp4Error {
  let mut leading_zeros = 0
  while reader.read_bit() == 0U {
    leading_zeros = leading_zeros + 1
    if leading_zeros > 31 {
      raise @bytes.Mp4Error::invalid_input("invalid Exp-Golomb code")
    }
  }
  let mut value : UInt32 = 0U
  let mut i = 0
  while i < leading_zeros {
    value = (value << 1) | reader.read_bit()
    i = i + 1
  }
  (1U << leading_zeros) - 1U + value
}

///|
/// SPS NAL（NAL ヘッダー含む）を解析する。
pub fn parse_sps(nal_unit : Bytes) -> H264Sps raise @bytes.Mp4Error {
  if nal_unit.length() < 4 {
    raise @bytes.Mp4Error::invalid_input("SPS is too short")
  }
  let header = nal_unit[0].to_uint()
  if (header & 0x1FU) != 7U {
    raise @bytes.Mp4Error::invalid_input("SPS NAL unit type must be 7")
  }
  let rbsp = remove_emulation_prevention(nal_unit[1:].to_owned())
  let reader = BitReader::new(rbsp)
  let profile_idc = reader.read_bits(8)
  let profile_iop = reader.read_bits(8)
  let level_idc = reader.read_bits(8)
  let _sps_id = h264_read_ue(reader)
  let mut chroma_format_idc : UInt32 = 1U
  let mut bit_depth_luma_minus8 : UInt32 = 0U
  let mut bit_depth_chroma_minus8 : UInt32 = 0U
  let high_profile = profile_idc == 100U ||
    profile_idc == 110U ||
    profile_idc == 122U ||
    profile_idc == 244U ||
    profile_idc == 44U ||
    profile_idc == 83U ||
    profile_idc == 86U ||
    profile_idc == 118U ||
    profile_idc == 128U ||
    profile_idc == 138U ||
    profile_idc == 139U ||
    profile_idc == 134U ||
    profile_idc == 135U
  if high_profile {
    chroma_format_idc = h264_read_ue(reader)
    if chroma_format_idc == 3U {
      let _separate_colour_plane_flag = reader.read_bit()
    }
    bit_depth_luma_minus8 = h264_read_ue(reader)
    bit_depth_chroma_minus8 = h264_read_ue(reader)
    let _qpprime_y_zero_transform_bypass_flag = reader.read_bit()
    let seq_scaling_matrix_present_flag = reader.read_bit()
    if seq_scaling_matrix_present_flag != 0U {
      let count = if chroma_format_idc != 3U { 8 } else { 12 }
      let mut i = 0
      while i < count {
        let present = reader.read_bit()
        if present != 0U {
          let size = if i < 6 { 16 } else { 64 }
          let mut last : Int32 = 8
          let mut j = 0
          while j < size {
            let delta = h264_read_se(reader)
            if j == 0 || last == 0 {
              last = delta
            }
            j = j + 1
          }
        }
        i = i + 1
      }
    }
  }
  let _log2_max_frame_num_minus4 = h264_read_ue(reader)
  let pic_order_cnt_type = h264_read_ue(reader)
  if pic_order_cnt_type == 0U {
    let _log2_max_pic_order_cnt_lsb_minus4 = h264_read_ue(reader)
  } else if pic_order_cnt_type == 1U {
    let _delta_pic_order_always_zero_flag = reader.read_bit()
    let _offset_for_non_ref_pic = h264_read_se(reader)
    let _offset_for_top_to_bottom_field = h264_read_se(reader)
    let num_ref_frames_in_pic_order_cnt_cycle = h264_read_ue(reader)
    let mut i = 0
    while i < num_ref_frames_in_pic_order_cnt_cycle.reinterpret_as_int() {
      let _offset = h264_read_se(reader)
      i = i + 1
    }
  }
  let _max_num_ref_frames = h264_read_ue(reader)
  let _gaps_in_frame_num_value_allowed_flag = reader.read_bit()
  let pic_width_in_mbs_minus1 = h264_read_ue(reader)
  let pic_height_in_map_units_minus1 = h264_read_ue(reader)
  let frame_mbs_only_flag = reader.read_bit()
  if frame_mbs_only_flag == 0U {
    let _mb_adaptive_frame_field_flag = reader.read_bit()
  }
  let _direct_8x8_inference_flag = reader.read_bit()
  let frame_cropping_flag = reader.read_bit()
  let mut crop_left = 0U
  let mut crop_right = 0U
  let mut crop_top = 0U
  let mut crop_bottom = 0U
  if frame_cropping_flag != 0U {
    crop_left = h264_read_ue(reader)
    crop_right = h264_read_ue(reader)
    crop_top = h264_read_ue(reader)
    crop_bottom = h264_read_ue(reader)
  }
  let frame_height_in_mbs = (pic_height_in_map_units_minus1 + 1U) *
    (2U - frame_mbs_only_flag)
  let mut width = (pic_width_in_mbs_minus1 + 1U) * 16U
  let mut height = frame_height_in_mbs * 16U
  let chroma_array_type = if chroma_format_idc == 0U {
    1U
  } else {
    chroma_format_idc
  }
  let sub_width = if chroma_array_type == 3U { 1U } else { 2U }
  let sub_height = if chroma_array_type == 1U { 2U } else { 1U }
  width = width - sub_width * (crop_left + crop_right)
  height = height -
    sub_height * (2U - frame_mbs_only_flag) * (crop_top + crop_bottom)
  {
    profile_level_id: { profile_idc, profile_iop, level_idc, },
    chroma_format_idc,
    bit_depth_luma_minus8,
    bit_depth_chroma_minus8,
    width,
    height,
  }
}

///|
fn h264_read_se(reader : BitReader) -> Int32 raise @bytes.Mp4Error {
  let ue = h264_read_ue(reader)
  if (ue & 1U) == 1U {
    ((ue + 1U) >> 1).reinterpret_as_int()
  } else {
    -(ue >> 1).reinterpret_as_int()
  }
}

///|
/// emulation prevention byte (0x03) を除く。
pub fn remove_emulation_prevention(data : Bytes) -> Bytes {
  let out = @bytes.WriteCursor::new()
  let mut zeros = 0
  for byte in data {
    if zeros >= 2 && byte == b'\x03' {
      zeros = 0
    } else {
      out.write_u8(byte.to_uint())
      if byte == b'\x00' {
        zeros = zeros + 1
      } else {
        zeros = 0
      }
    }
  }
  out.to_bytes()
}

///|
/// `build_avc1_box` の設定。
pub struct H264SampleEntryConfig {
  /// NAL 長フィールド幅
  length_size : LengthSize
} derive(Eq, Hash, Debug)

///|
pub extend H264SampleEntryConfig with Eq::{equal, not_equal}

///|
pub extend H264SampleEntryConfig with Hash::{hash, hash_combine}

///|
pub extend H264SampleEntryConfig with Debug::{to_repr}

///|
/// 設定を作る。
pub fn H264SampleEntryConfig::new(
  length_size : LengthSize,
) -> H264SampleEntryConfig {
  { length_size, }
}

///|
/// SPS/PPS から `avc1` ボックスを構築する。
pub fn build_avc1_box(
  sps_list : Array[Bytes],
  pps_list : Array[Bytes],
  config : H264SampleEntryConfig,
) -> @boxes.Avc1Box raise @bytes.Mp4Error {
  if sps_list.length() == 0 {
    raise @bytes.Mp4Error::invalid_input("SPS list must not be empty")
  }
  if pps_list.length() == 0 {
    raise @bytes.Mp4Error::invalid_input("PPS list must not be empty")
  }
  let sps = parse_sps(sps_list[0])
  let length_size_minus_one = @bytes.Uint::from_bits(
    config.length_size.length_size_minus_one().to_uint64(),
    bits=2,
    offset=0,
  )
  let (chroma_format, luma, chroma) = if sps.profile_level_id.profile_idc == 66U ||
    sps.profile_level_id.profile_idc == 77U ||
    sps.profile_level_id.profile_idc == 88U {
    (None, None, None)
  } else {
    (
      Some(
        @bytes.Uint::new(sps.chroma_format_idc.to_uint64(), bits=2, offset=0).unwrap(),
      ),
      Some(
        @bytes.Uint::new(
          sps.bit_depth_luma_minus8.to_uint64(),
          bits=3,
          offset=0,
        ).unwrap(),
      ),
      Some(
        @bytes.Uint::new(
          sps.bit_depth_chroma_minus8.to_uint64(),
          bits=3,
          offset=0,
        ).unwrap(),
      ),
    )
  }
  let avcc = @boxes.AvccBox::new(
    sps.profile_level_id.profile_idc,
    sps.profile_level_id.profile_iop,
    sps.profile_level_id.level_idc,
    length_size_minus_one,
    sps_list,
    pps_list,
    chroma_format,
    luma,
    chroma,
    [],
  )
  let visual = @boxes.VisualSampleEntryFields::new(
    @boxes.VisualSampleEntryFields::default_data_reference_index(),
    sps.width,
    sps.height,
    @boxes.VisualSampleEntryFields::default_horizresolution(),
    @boxes.VisualSampleEntryFields::default_vertresolution(),
    @boxes.VisualSampleEntryFields::default_frame_count(),
    @boxes.VisualSampleEntryFields::null_compressorname(),
    @boxes.VisualSampleEntryFields::default_depth(),
  )
  @boxes.Avc1Box::new(visual, avcc, [])
}

///|
/// Annex B 入力から SPS/PPS を集めて `avc1` を構築する。
pub fn build_avc1_box_from_annexb(
  input : Bytes,
  config : H264SampleEntryConfig,
) -> @boxes.Avc1Box raise @bytes.Mp4Error {
  let nals = parse_annexb_nal_units(input)
  let sps = collect_nal_units(nals, H264NalUnitType::Sps)
  let pps = collect_nal_units(nals, H264NalUnitType::Pps)
  build_avc1_box(sps, pps, config)
}
