///|
/// H.265 の NAL ユニット種別（主要値）。
pub(all) enum H265NalUnitType {
  /// VPS (32)
  Vps
  /// SPS (33)
  Sps
  /// PPS (34)
  Pps
  /// IDR_W_RADL (19)
  IdrWRadl
  /// IDR_N_LP (20)
  IdrNLp
  /// その他
  Other(UInt32)
} derive(Eq, Hash, Debug)

///|
pub extend H265NalUnitType with Eq::{equal, not_equal}

///|
pub extend H265NalUnitType with Hash::{hash, hash_combine}

///|
pub extend H265NalUnitType with Debug::{to_repr}

///|
/// NAL ヘッダー値から種別を作る。
pub fn H265NalUnitType::from_value(value : UInt32) -> H265NalUnitType {
  match value {
    32U => Vps
    33U => Sps
    34U => Pps
    19U => IdrWRadl
    20U => IdrNLp
    other => Other(other)
  }
}

///|
/// 1 個の H.265 NAL ユニット（2 バイトの NAL ヘッダーを含む）。
pub struct H265NalUnit {
  /// NAL 種別
  nal_unit_type : H265NalUnitType
  /// NAL 本体
  data : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend H265NalUnit with Eq::{equal, not_equal}

///|
pub extend H265NalUnit with Hash::{hash, hash_combine}

///|
pub extend H265NalUnit with Debug::{to_repr}

///|
fn h265_nal_from_bytes(data : Bytes) -> H265NalUnit raise @bytes.Mp4Error {
  if data.length() < 2 {
    raise @bytes.Mp4Error::invalid_input(
      "H.265 NAL unit is shorter than 2 bytes",
    )
  }
  let header = (data[0].to_uint() << 8) | data[1].to_uint()
  let type_value = (header >> 9) & 0x3FU
  { nal_unit_type: H265NalUnitType::from_value(type_value), data, }
}

///|
/// Annex B の H.265 NAL ユニット列を解析する。
pub fn parse_annexb_nal_units_h265(
  input : Bytes,
) -> Array[H265NalUnit] raise @bytes.Mp4Error {
  let nals : Array[H265NalUnit] = []
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
        nals.push(h265_nal_from_bytes(input[start:i].to_owned()))
      }
      i = i + (if is4 { 4 } else { 3 })
      start = i
    } else {
      i = i + 1
    }
  }
  if start >= 0 && start < input.length() {
    nals.push(h265_nal_from_bytes(input[start:].to_owned()))
  } else if input.length() > 0 {
    raise @bytes.Mp4Error::invalid_input("Annex B start code not found")
  }
  nals
}

///|
/// length-prefixed の H.265 NAL ユニット列を解析する。
pub fn parse_length_prefixed_nal_units_h265(
  input : Bytes,
  length_size : LengthSize,
) -> Array[H265NalUnit] raise @bytes.Mp4Error {
  let nals : Array[H265NalUnit] = []
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
    nals.push(h265_nal_from_bytes(input[offset:end].to_owned()))
    offset = end
  }
  nals
}

///|
/// Annex B を length-prefixed 形式へ変換する。
pub fn annexb_to_length_prefixed_h265(
  input : Bytes,
  length_size : LengthSize,
) -> Bytes raise @bytes.Mp4Error {
  let nals = parse_annexb_nal_units_h265(input)
  let writer = @bytes.WriteCursor::new()
  for nal in nals {
    let width = length_size.bytes()
    let length = nal.data.length()
    if width == 1 {
      writer.write_u8(length.reinterpret_as_uint())
    } else if width == 2 {
      writer.write_u16(length.reinterpret_as_uint())
    } else if width == 3 {
      writer.write_u24(length.reinterpret_as_uint())
    } else {
      writer.write_u32(length.reinterpret_as_uint())
    }
    writer.write_bytes(nal.data)
  }
  writer.to_bytes()
}

///|
/// length-prefixed 形式を Annex B へ変換する。
pub fn length_prefixed_to_annexb_h265(
  input : Bytes,
  length_size : LengthSize,
) -> Bytes raise @bytes.Mp4Error {
  let nals = parse_length_prefixed_nal_units_h265(input, length_size)
  let writer = @bytes.WriteCursor::new()
  for nal in nals {
    writer.write_bytes(b"\x00\x00\x00\x01")
    writer.write_bytes(nal.data)
  }
  writer.to_bytes()
}

///|
/// `nal_unit_type` に一致する NAL を集める。
pub fn collect_nal_units_h265(
  nals : Array[H265NalUnit],
  nal_unit_type : H265NalUnitType,
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
/// H.265 の SPS 解析結果（profile/level と設定値）。
pub struct H265Sps {
  /// general_profile_space
  general_profile_space : UInt32
  /// general_tier_flag
  general_tier_flag : UInt32
  /// general_profile_idc
  general_profile_idc : UInt32
  /// general_profile_compatibility_flags
  general_profile_compatibility_flags : UInt32
  /// general_constraint_indicator_flags（下位 48 bit）
  general_constraint_indicator_flags : UInt64
  /// general_level_idc
  general_level_idc : UInt32
  /// sps_max_sub_layers_minus1
  sps_max_sub_layers_minus1 : UInt32
  /// sps_temporal_id_nesting_flag
  sps_temporal_id_nesting_flag : UInt32
  /// クロップ適用後の幅（設定値から写す）
  width : UInt32
  /// クロップ適用後の高さ（設定値から写す）
  height : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend H265Sps with Eq::{equal, not_equal}

///|
pub extend H265Sps with Hash::{hash, hash_combine}

///|
pub extend H265Sps with Debug::{to_repr}

///|
/// H.265 SPS の profile_tier_level を解析する。寸法は設定値を使う。
pub fn parse_sps_h265(
  nal_unit : Bytes,
  width : UInt32,
  height : UInt32,
) -> H265Sps raise @bytes.Mp4Error {
  if nal_unit.length() < 3 {
    raise @bytes.Mp4Error::invalid_input("H.265 SPS is too short")
  }
  let header = (nal_unit[0].to_uint() << 8) | nal_unit[1].to_uint()
  if ((header >> 9) & 0x3FU) != 33U {
    raise @bytes.Mp4Error::invalid_input("SPS NAL unit type must be 33")
  }
  let rbsp = remove_emulation_prevention(nal_unit[2:].to_owned())
  let reader = BitReader::new(rbsp)
  let _vps_id = reader.read_bits(4)
  let max_sub_layers_minus1 = reader.read_bits(3)
  let temporal_id_nesting = reader.read_bits(1)
  let general_profile_space = reader.read_bits(2)
  let general_tier_flag = reader.read_bits(1)
  let general_profile_idc = reader.read_bits(5)
  let compat = reader.read_bits(32)
  let mut constraint : UInt64 = 0UL
  let mut i = 0
  while i < 6 {
    constraint = (constraint << 8) | reader.read_bits(8).to_uint64()
    i = i + 1
  }
  let level = reader.read_bits(8)
  {
    general_profile_space,
    general_tier_flag,
    general_profile_idc,
    general_profile_compatibility_flags: compat,
    general_constraint_indicator_flags: constraint,
    general_level_idc: level,
    sps_max_sub_layers_minus1: max_sub_layers_minus1,
    sps_temporal_id_nesting_flag: temporal_id_nesting,
    width,
    height,
  }
}

///|
/// 固定フレームレートの状態。
pub(all) enum H265ConstantFrameRate {
  /// 不明
  Unknown
  /// 定フレームレート
  Constant
  /// temporal layer ごとに定フレームレート
  PerTemporalLayer
} derive(Eq, Hash, Debug)

///|
pub extend H265ConstantFrameRate with Eq::{equal, not_equal}

///|
pub extend H265ConstantFrameRate with Hash::{hash, hash_combine}

///|
pub extend H265ConstantFrameRate with Debug::{to_repr}

///|
/// `build_hev1_box` / `build_hvc1_box` の設定。
pub struct H265SampleEntryConfig {
  /// NAL 長フィールド幅
  length_size : LengthSize
  /// `avgFrameRate` の 16 ビット raw 値
  avg_frame_rate : UInt32
  /// 固定フレームレート状態
  constant_frame_rate : H265ConstantFrameRate
  /// 映像の幅（SPS から導出しない場合に使う）
  width : UInt32
  /// 映像の高さ
  height : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend H265SampleEntryConfig with Eq::{equal, not_equal}

///|
pub extend H265SampleEntryConfig with Hash::{hash, hash_combine}

///|
pub extend H265SampleEntryConfig with Debug::{to_repr}

///|
/// 設定を作る。
pub fn H265SampleEntryConfig::new(
  length_size : LengthSize,
  width : UInt32,
  height : UInt32,
  avg_frame_rate? : UInt32,
  constant_frame_rate? : H265ConstantFrameRate,
) -> H265SampleEntryConfig {
  {
    length_size,
    width,
    height,
    avg_frame_rate: avg_frame_rate.unwrap_or(0U),
    constant_frame_rate: constant_frame_rate.unwrap_or(
      H265ConstantFrameRate::Unknown,
    ),
  }
}

///|
fn h265_build_visual(
  sps : H265Sps,
) -> @boxes.VisualSampleEntryFields raise @bytes.Mp4Error {
  @boxes.VisualSampleEntryFields::new(
    @boxes.VisualSampleEntryFields::default_data_reference_index(),
    sps.width,
    sps.height,
    @boxes.VisualSampleEntryFields::default_horizresolution(),
    @boxes.VisualSampleEntryFields::default_vertresolution(),
    @boxes.VisualSampleEntryFields::default_frame_count(),
    @boxes.VisualSampleEntryFields::null_compressorname(),
    @boxes.VisualSampleEntryFields::default_depth(),
  )
}

///|
fn h265_build_hvcc(
  sps : H265Sps,
  vps_list : Array[Bytes],
  sps_list : Array[Bytes],
  pps_list : Array[Bytes],
  config : H265SampleEntryConfig,
) -> @boxes.HvccBox {
  let nalu_arrays = [
    @boxes.HvccNalUintArray::new(
      @bytes.Uint::from_bits(0UL, bits=1, offset=0),
      @bytes.Uint::from_bits(32UL, bits=6, offset=0),
      vps_list,
    ),
    @boxes.HvccNalUintArray::new(
      @bytes.Uint::from_bits(0UL, bits=1, offset=0),
      @bytes.Uint::from_bits(33UL, bits=6, offset=0),
      sps_list,
    ),
    @boxes.HvccNalUintArray::new(
      @bytes.Uint::from_bits(0UL, bits=1, offset=0),
      @bytes.Uint::from_bits(34UL, bits=6, offset=0),
      pps_list,
    ),
  ]
  @boxes.HvccBox::new(
    @bytes.Uint::new(sps.general_profile_space.to_uint64(), bits=2, offset=0).unwrap(),
    @bytes.Uint::new(sps.general_tier_flag.to_uint64(), bits=1, offset=0).unwrap(),
    @bytes.Uint::new(sps.general_profile_idc.to_uint64(), bits=5, offset=0).unwrap(),
    sps.general_profile_compatibility_flags,
    @bytes.Uint::from_bits(
      sps.general_constraint_indicator_flags,
      bits=48,
      offset=0,
    ),
    sps.general_level_idc,
    @bytes.Uint::from_bits(0UL, bits=12, offset=0),
    @bytes.Uint::from_bits(0UL, bits=2, offset=0),
    @bytes.Uint::from_bits(1UL, bits=2, offset=0),
    @bytes.Uint::from_bits(0UL, bits=3, offset=0),
    @bytes.Uint::from_bits(0UL, bits=3, offset=0),
    config.avg_frame_rate,
    @bytes.Uint::from_bits(
      match config.constant_frame_rate {
        Unknown => 0UL
        Constant => 1UL
        PerTemporalLayer => 2UL
      },
      bits=2,
      offset=0,
    ),
    @bytes.Uint::from_bits(0UL, bits=3, offset=0),
    @bytes.Uint::from_bits(0UL, bits=1, offset=0),
    @bytes.Uint::from_bits(
      config.length_size.length_size_minus_one().to_uint64(),
      bits=2,
      offset=0,
    ),
    nalu_arrays,
  )
}

///|
/// VPS/SPS/PPS から `hev1` を構築する。
pub fn build_hev1_box(
  vps_list : Array[Bytes],
  sps_list : Array[Bytes],
  pps_list : Array[Bytes],
  config : H265SampleEntryConfig,
) -> @boxes.Hev1Box raise @bytes.Mp4Error {
  if vps_list.length() == 0 || sps_list.length() == 0 || pps_list.length() == 0 {
    raise @bytes.Mp4Error::invalid_input("VPS, SPS and PPS must not be empty")
  }
  let sps = parse_sps_h265(sps_list[0], config.width, config.height)
  @boxes.Hev1Box::new(
    h265_build_visual(sps),
    h265_build_hvcc(sps, vps_list, sps_list, pps_list, config),
    [],
  )
}

///|
/// VPS/SPS/PPS から `hvc1` を構築する。
pub fn build_hvc1_box(
  vps_list : Array[Bytes],
  sps_list : Array[Bytes],
  pps_list : Array[Bytes],
  config : H265SampleEntryConfig,
) -> @boxes.Hvc1Box raise @bytes.Mp4Error {
  if vps_list.length() == 0 || sps_list.length() == 0 || pps_list.length() == 0 {
    raise @bytes.Mp4Error::invalid_input("VPS, SPS and PPS must not be empty")
  }
  let sps = parse_sps_h265(sps_list[0], config.width, config.height)
  @boxes.Hvc1Box::new(
    h265_build_visual(sps),
    h265_build_hvcc(sps, vps_list, sps_list, pps_list, config),
    [],
  )
}

///|
/// Annex B 入力から `hev1` を構築する。
pub fn build_hev1_box_from_annexb(
  input : Bytes,
  config : H265SampleEntryConfig,
) -> @boxes.Hev1Box raise @bytes.Mp4Error {
  let nals = parse_annexb_nal_units_h265(input)
  build_hev1_box(
    collect_nal_units_h265(nals, H265NalUnitType::Vps),
    collect_nal_units_h265(nals, H265NalUnitType::Sps),
    collect_nal_units_h265(nals, H265NalUnitType::Pps),
    config,
  )
}

///|
/// Annex B 入力から `hvc1` を構築する。
pub fn build_hvc1_box_from_annexb(
  input : Bytes,
  config : H265SampleEntryConfig,
) -> @boxes.Hvc1Box raise @bytes.Mp4Error {
  let nals = parse_annexb_nal_units_h265(input)
  build_hvc1_box(
    collect_nal_units_h265(nals, H265NalUnitType::Vps),
    collect_nal_units_h265(nals, H265NalUnitType::Sps),
    collect_nal_units_h265(nals, H265NalUnitType::Pps),
    config,
  )
}
