///|
/// VP9 のフレーム種別。
pub(all) enum Vp9FrameType {
  /// キーフレーム
  Key
  /// 非キーフレーム
  Inter
} derive(Eq, Hash, Debug)

///|
pub extend Vp9FrameType with Eq::{equal, not_equal}

///|
pub extend Vp9FrameType with Hash::{hash, hash_combine}

///|
pub extend Vp9FrameType with Debug::{to_repr}

///|
/// VP9 のフレームヘッダー（先頭の uncompressed header の一部）。
pub struct Vp9FrameHeader {
  /// キーフレームか
  keyframe : Bool
  /// プロファイル
  profile : UInt32
  /// ビット深度（8/10/12）
  bit_depth : UInt32
  /// 幅
  width : UInt32
  /// 高さ
  height : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend Vp9FrameHeader with Eq::{equal, not_equal}

///|
pub extend Vp9FrameHeader with Hash::{hash, hash_combine}

///|
pub extend Vp9FrameHeader with Debug::{to_repr}

///|
/// VP9 の frame marker を検証し、profile とキーフレーム判定を読む。
pub fn parse_vp9_frame_header(
  input : Bytes,
) -> Vp9FrameHeader raise @bytes.Mp4Error {
  if input.length() < 1 {
    raise @bytes.Mp4Error::invalid_input("VP9 frame is too short")
  }
  let reader = BitReader::new(input)
  let marker = reader.read_bits(2)
  if marker != 2U {
    raise @bytes.Mp4Error::invalid_input("invalid VP9 frame marker")
  }
  let profile = reader.read_bits(2)
  let _show_existing = reader.read_bit()
  let frame_type = reader.read_bit()
  let _show_frame = reader.read_bit()
  let _error_resilient = reader.read_bit()
  let bit_depth = match profile {
    0U => 8U
    1U => 8U
    2U => if reader.read_bit() == 1U { 12U } else { 10U }
    _ => if reader.read_bit() == 1U { 12U } else { 10U }
  }
  { keyframe: frame_type == 0U, profile, bit_depth, width: 0U, height: 0U, }
}

///|
/// `build_vp09_box` の設定。
pub struct Vp9SampleEntryConfig {
  /// 幅
  width : UInt32
  /// 高さ
  height : UInt32
  /// profile
  profile : UInt32
  /// level
  level : UInt32
  /// bit depth
  bit_depth : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend Vp9SampleEntryConfig with Eq::{equal, not_equal}

///|
pub extend Vp9SampleEntryConfig with Hash::{hash, hash_combine}

///|
pub extend Vp9SampleEntryConfig with Debug::{to_repr}

///|
/// 設定を作る。
pub fn Vp9SampleEntryConfig::new(
  width : UInt32,
  height : UInt32,
  profile? : UInt32,
  level? : UInt32,
  bit_depth? : UInt32,
) -> Vp9SampleEntryConfig {
  {
    width,
    height,
    profile: profile.unwrap_or(0U),
    level: level.unwrap_or(0U),
    bit_depth: bit_depth.unwrap_or(8U),
  }
}

///|
/// `vp09` sample entry を構築する。
pub fn build_vp09_box(
  header : Vp9FrameHeader,
  config : Vp9SampleEntryConfig,
) -> @boxes.Vp09Box raise @bytes.Mp4Error {
  let profile = if config.profile != 0U {
    config.profile
  } else {
    header.profile
  }
  let bit_depth = if config.bit_depth != 0U {
    config.bit_depth
  } else {
    header.bit_depth
  }
  let vpcc = @boxes.VpccBox::new(
    profile,
    config.level,
    @bytes.Uint::new(bit_depth.to_uint64(), bits=4, offset=0).unwrap(),
    @bytes.Uint::from_bits(0UL, bits=3, offset=0),
    @bytes.Uint::from_bits(0UL, bits=1, offset=0),
    1U,
    1U,
    1U,
    b"",
  )
  let visual = @boxes.VisualSampleEntryFields::new(
    @boxes.VisualSampleEntryFields::default_data_reference_index(),
    if config.width != 0U {
      config.width
    } else {
      header.width
    },
    if config.height != 0U {
      config.height
    } else {
      header.height
    },
    @boxes.VisualSampleEntryFields::default_horizresolution(),
    @boxes.VisualSampleEntryFields::default_vertresolution(),
    @boxes.VisualSampleEntryFields::default_frame_count(),
    @boxes.VisualSampleEntryFields::null_compressorname(),
    @boxes.VisualSampleEntryFields::default_depth(),
  )
  @boxes.Vp09Box::new(visual, vpcc, [])
}
