///|
/// VP8 のフレーム種別。
pub(all) enum Vp8FrameType {
  /// キーフレーム
  Key
  /// 非キーフレーム
  Inter
} derive(Eq, Hash, Debug)

///|
pub extend Vp8FrameType with Eq::{equal, not_equal}

///|
pub extend Vp8FrameType with Hash::{hash, hash_combine}

///|
pub extend Vp8FrameType with Debug::{to_repr}

///|
/// VP8 のフレームヘッダー（先頭の tag のみ）。
pub struct Vp8FrameHeader {
  /// キーフレームか
  keyframe : Bool
  /// フレームサイズ（ヘッダー込み）
  first_partition_size : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend Vp8FrameHeader with Eq::{equal, not_equal}

///|
pub extend Vp8FrameHeader with Hash::{hash, hash_combine}

///|
pub extend Vp8FrameHeader with Debug::{to_repr}

///|
/// VP8 フレームヘッダーを解析する。
pub fn parse_vp8_frame_header(
  input : Bytes,
) -> Vp8FrameHeader raise @bytes.Mp4Error {
  if input.length() < 3 {
    raise @bytes.Mp4Error::invalid_input("VP8 frame is too short")
  }
  let tag = input[0].to_uint() |
    (input[1].to_uint() << 8) |
    (input[2].to_uint() << 16)
  if (tag & 1U) != 0U {
    raise @bytes.Mp4Error::invalid_input(
      "VP8 frame must be a keyframe for metadata",
    )
  }
  let keyframe = (tag & 1U) == 0U
  let size = (tag >> 5) & 0x7FFFFU
  { keyframe, first_partition_size: size, }
}

///|
/// `build_vp08_box` の設定。
pub struct Vp8SampleEntryConfig {
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
pub extend Vp8SampleEntryConfig with Eq::{equal, not_equal}

///|
pub extend Vp8SampleEntryConfig with Hash::{hash, hash_combine}

///|
pub extend Vp8SampleEntryConfig with Debug::{to_repr}

///|
/// 設定を作る。
pub fn Vp8SampleEntryConfig::new(
  width : UInt32,
  height : UInt32,
  profile? : UInt32,
  level? : UInt32,
  bit_depth? : UInt32,
) -> Vp8SampleEntryConfig {
  {
    width,
    height,
    profile: profile.unwrap_or(0U),
    level: level.unwrap_or(0U),
    bit_depth: bit_depth.unwrap_or(8U),
  }
}

///|
/// `vp08` sample entry を構築する。
pub fn build_vp08_box(
  config : Vp8SampleEntryConfig,
) -> @boxes.Vp08Box raise @bytes.Mp4Error {
  let vpcc = @boxes.VpccBox::new(
    config.profile,
    config.level,
    @bytes.Uint::new(config.bit_depth.to_uint64(), bits=4, offset=0).unwrap(),
    @bytes.Uint::from_bits(0UL, bits=3, offset=0),
    @bytes.Uint::from_bits(0UL, bits=1, offset=0),
    1U,
    1U,
    1U,
    b"",
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
  @boxes.Vp08Box::new(visual, vpcc, [])
}
