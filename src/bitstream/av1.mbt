///|
/// AV1 の OBU 種別。
pub(all) enum Av1ObuType {
  /// Sequence Header (1)
  SequenceHeader
  /// Temporal Delimiter (2)
  TemporalDelimiter
  /// Frame Header (3)
  FrameHeader
  /// Frame (6)
  Frame
  /// その他
  Other(UInt32)
} derive(Eq, Hash, Debug)

///|
pub extend Av1ObuType with Eq::{equal, not_equal}

///|
pub extend Av1ObuType with Hash::{hash, hash_combine}

///|
pub extend Av1ObuType with Debug::{to_repr}

///|
/// OBU 種別を値から作る。
pub fn Av1ObuType::from_value(value : UInt32) -> Av1ObuType {
  match value {
    1U => SequenceHeader
    2U => TemporalDelimiter
    3U => FrameHeader
    6U => Frame
    other => Other(other)
  }
}

///|
/// OBU 解析時のコンテキスト。
pub(all) enum Av1ObuParseContext {
  /// 通常のストリーム
  Stream
  /// 設定 OBU 列（`av1C`）
  Config
} derive(Eq, Hash, Debug)

///|
pub extend Av1ObuParseContext with Eq::{equal, not_equal}

///|
pub extend Av1ObuParseContext with Hash::{hash, hash_combine}

///|
pub extend Av1ObuParseContext with Debug::{to_repr}

///|
/// 1 個の OBU。
pub struct Av1Obu {
  /// OBU 種別
  obu_type : Av1ObuType
  /// 拡張ヘッダーがあるか
  has_extension : Bool
  /// ペイロード
  payload : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend Av1Obu with Eq::{equal, not_equal}

///|
pub extend Av1Obu with Hash::{hash, hash_combine}

///|
pub extend Av1Obu with Debug::{to_repr}

///|
/// LEB128 を読む。`(value, bytes_consumed)` を返す。
pub fn decode_leb128(input : Bytes) -> (UInt32, Int32) raise @bytes.Mp4Error {
  let mut value : UInt32 = 0U
  let mut shift = 0
  let mut offset = 0
  while offset < input.length() {
    let byte = input[offset].to_uint()
    value = value | ((byte & 0x7FU) << shift)
    offset = offset + 1
    if (byte & 0x80U) == 0U {
      return (value, offset)
    }
    shift = shift + 7
    if shift >= 32 {
      raise @bytes.Mp4Error::invalid_input("LEB128 value exceeds u32")
    }
  }
  raise @bytes.Mp4Error::invalid_input("truncated LEB128 value")
}

///|
/// OBU 列を解析する。
pub fn parse_obus(
  input : Bytes,
  _context : Av1ObuParseContext,
) -> Array[Av1Obu] raise @bytes.Mp4Error {
  let obus : Array[Av1Obu] = []
  let mut offset = 0
  while offset < input.length() {
    let header = input[offset].to_uint()
    offset = offset + 1
    if (header & 0x80U) != 0U {
      raise @bytes.Mp4Error::invalid_input("AV1 OBU forbidden bit is set")
    }
    let obu_type = Av1ObuType::from_value((header >> 3) & 0xFU)
    let has_extension = (header & 0x4U) != 0U
    let has_size = (header & 0x2U) != 0U
    if has_extension {
      if offset >= input.length() {
        raise @bytes.Mp4Error::invalid_input("truncated AV1 OBU extension")
      }
      offset = offset + 1
    }
    let payload_size = if has_size {
      let (size, consumed) = decode_leb128(input[offset:].to_owned())
      offset = offset + consumed
      size
    } else {
      (input.length() - offset).reinterpret_as_uint()
    }
    let end = offset + payload_size.reinterpret_as_int()
    if end > input.length() {
      raise @bytes.Mp4Error::invalid_input("AV1 OBU payload exceeds input")
    }
    obus.push({
      obu_type,
      has_extension,
      payload: input[offset:end].to_owned(),
    })
    offset = end
  }
  obus
}

///|
/// AV1 の Sequence Header（先頭の profile/level のみ）。
pub struct Av1SequenceHeader {
  /// seq_profile (0..=2)
  seq_profile : UInt32
  /// seq_level_idx[0]
  seq_level_idx : UInt32
  /// seq_tier[0]
  seq_tier : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend Av1SequenceHeader with Eq::{equal, not_equal}

///|
pub extend Av1SequenceHeader with Hash::{hash, hash_combine}

///|
pub extend Av1SequenceHeader with Debug::{to_repr}

///|
/// Sequence Header の先頭ビットを解析する。
pub fn parse_sequence_header(
  payload : Bytes,
) -> Av1SequenceHeader raise @bytes.Mp4Error {
  let reader = BitReader::new(payload)
  let seq_profile = reader.read_bits(3)
  if seq_profile > 2U {
    raise @bytes.Mp4Error::invalid_input("AV1 seq_profile must be 0..=2")
  }
  let _still_picture = reader.read_bit()
  let reduced = reader.read_bit()
  let mut seq_level_idx : UInt32 = 0U
  let mut seq_tier : UInt32 = 0U
  if reduced == 1U {
    seq_level_idx = reader.read_bits(5)
  } else {
    let timing_info_present = reader.read_bit()
    if timing_info_present == 1U {
      let _num_units = reader.read_bits(32)
      let _time_scale = reader.read_bits(32)
      let _equal_picture_interval = reader.read_bit()
    }
    let _decoder_model_info_present = reader.read_bit()
    let _initial_display_delay_present = reader.read_bit()
    let operating_points_cnt_minus_1 = reader.read_bits(5)
    let mut i = 0
    while i <= operating_points_cnt_minus_1.reinterpret_as_int() {
      let _operating_point_idc = reader.read_bits(12)
      let level = reader.read_bits(5)
      if i == 0 {
        seq_level_idx = level
        if level > 7U {
          seq_tier = reader.read_bit()
        }
      } else if level > 7U {
        let _tier = reader.read_bit()
      }
      i = i + 1
    }
  }
  { seq_profile, seq_level_idx, seq_tier, }
}

///|
/// AV1 の frame header prefix（先頭の frame_type/show_frame のみ）。
pub struct Av1FrameHeaderPrefix {
  /// show_frame
  show_frame : Bool
  /// frame_type
  frame_type : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend Av1FrameHeaderPrefix with Eq::{equal, not_equal}

///|
pub extend Av1FrameHeaderPrefix with Hash::{hash, hash_combine}

///|
pub extend Av1FrameHeaderPrefix with Debug::{to_repr}

///|
/// frame header prefix を解析する。
pub fn parse_frame_header_prefix(
  payload : Bytes,
) -> Av1FrameHeaderPrefix raise @bytes.Mp4Error {
  let reader = BitReader::new(payload)
  let _show_existing_frame = reader.read_bit()
  let frame_type = reader.read_bits(2)
  let show_frame = reader.read_bit() == 1U
  { show_frame, frame_type, }
}

///|
/// `build_av01_box` の設定。
pub struct Av1SampleEntryConfig {
  /// 幅
  width : UInt32
  /// 高さ
  height : UInt32
  /// seq_profile
  seq_profile : UInt32
  /// seq_level_idx[0]
  seq_level_idx : UInt32
  /// seq_tier[0]
  seq_tier : UInt32
  /// high_bitdepth
  high_bitdepth : Bool
  /// twelve_bit
  twelve_bit : Bool
  /// monochrome
  monochrome : Bool
  /// subsampling_x
  subsampling_x : Bool
  /// subsampling_y
  subsampling_y : Bool
} derive(Eq, Hash, Debug)

///|
pub extend Av1SampleEntryConfig with Eq::{equal, not_equal}

///|
pub extend Av1SampleEntryConfig with Hash::{hash, hash_combine}

///|
pub extend Av1SampleEntryConfig with Debug::{to_repr}

///|
/// 設定を作る。
pub fn Av1SampleEntryConfig::new(
  width : UInt32,
  height : UInt32,
  seq_profile : UInt32,
  seq_level_idx : UInt32,
  seq_tier? : UInt32,
  high_bitdepth? : Bool,
  twelve_bit? : Bool,
  monochrome? : Bool,
  subsampling_x? : Bool,
  subsampling_y? : Bool,
) -> Av1SampleEntryConfig {
  {
    width,
    height,
    seq_profile,
    seq_level_idx,
    seq_tier: seq_tier.unwrap_or(0U),
    high_bitdepth: high_bitdepth.unwrap_or(false),
    twelve_bit: twelve_bit.unwrap_or(false),
    monochrome: monochrome.unwrap_or(false),
    subsampling_x: subsampling_x.unwrap_or(true),
    subsampling_y: subsampling_y.unwrap_or(true),
  }
}

///|
/// `av01` sample entry を構築する。
pub fn build_av01_box(
  config : Av1SampleEntryConfig,
  sequence_header_obu : Bytes,
) -> @boxes.Av01Box raise @bytes.Mp4Error {
  let bool_uint = fn(value : Bool) -> @bytes.Uint {
    @bytes.Uint::from_bits(if value { 1UL } else { 0UL }, bits=1, offset=0)
  }
  let av1c = @boxes.Av1cBox::new(
    @bytes.Uint::new(config.seq_profile.to_uint64(), bits=3, offset=0).unwrap(),
    @bytes.Uint::new(config.seq_level_idx.to_uint64(), bits=5, offset=0).unwrap(),
    bool_uint(config.seq_tier != 0U),
    bool_uint(config.high_bitdepth),
    bool_uint(config.twelve_bit),
    bool_uint(config.monochrome),
    bool_uint(config.subsampling_x),
    bool_uint(config.subsampling_y),
    @bytes.Uint::from_bits(0UL, bits=2, offset=0),
    None,
    sequence_header_obu,
  )
  let visual = @boxes.VisualSampleEntryFields::new(
    @boxes.VisualSampleEntryFields::default_data_reference_index(),
    config.width,
    config.height,
    @boxes.VisualSampleEntryFields::default_horizresolution(),
    @boxes.VisualSampleEntryFields::default_vertresolution(),
    @boxes.VisualSampleEntryFields::default_frame_count(),
    @boxes.VisualSampleEntryFields::null_compressorname(),
    @boxes.VisualSampleEntryFields::default_depth(),
  )
  @boxes.Av01Box::new(visual, av1c, [])
}

///|
/// Sequence Header OBU から設定を作って `av01` を構築する。
pub fn build_av01_box_from_config_obus(
  config_obus : Bytes,
  width : UInt32,
  height : UInt32,
) -> @boxes.Av01Box raise @bytes.Mp4Error {
  let obus = parse_obus(config_obus, Av1ObuParseContext::Config)
  let mut seq : Av1SequenceHeader? = None
  for obu in obus {
    if obu.obu_type is SequenceHeader {
      seq = Some(parse_sequence_header(obu.payload))
    }
  }
  let header = match seq {
    Some(header) => header
    None =>
      raise @bytes.Mp4Error::invalid_input("Sequence Header OBU not found")
  }
  let config = Av1SampleEntryConfig::new(
    width,
    height,
    header.seq_profile,
    header.seq_level_idx,
    seq_tier=header.seq_tier,
  )
  build_av01_box(config, config_obus)
}
