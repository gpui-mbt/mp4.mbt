///|
/// Opus のチャンネル数。
pub struct ChannelCount {
  /// 1..=2（この実装がサポートする範囲）
  value : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend ChannelCount with Eq::{equal, not_equal}

///|
pub extend ChannelCount with Hash::{hash, hash_combine}

///|
pub extend ChannelCount with Debug::{to_repr}

///|
/// 1 または 2 から作る。
pub fn ChannelCount::new(value : UInt32) -> ChannelCount raise @bytes.Mp4Error {
  if value < 1U || value > 2U {
    raise @bytes.Mp4Error::invalid_input("Opus channel count must be 1 or 2")
  }
  { value, }
}

///|
/// 値を返す。
pub fn ChannelCount::get(self : ChannelCount) -> UInt32 {
  self.value
}

///|
/// `build_opus_box` の設定。
pub struct OpusSampleEntryConfig {
  /// チャンネル数
  channel_count : ChannelCount
  /// pre-skip（48 kHz 基準）
  pre_skip : UInt32
  /// 入力サンプリングレート（Hz）
  input_sample_rate : UInt32
  /// 出力ゲイン（Q7.8 dB）
  output_gain : Int16
} derive(Eq, Hash, Debug)

///|
pub extend OpusSampleEntryConfig with Eq::{equal, not_equal}

///|
pub extend OpusSampleEntryConfig with Hash::{hash, hash_combine}

///|
pub extend OpusSampleEntryConfig with Debug::{to_repr}

///|
/// 設定を作る。
pub fn OpusSampleEntryConfig::new(
  channel_count : ChannelCount,
  pre_skip : UInt32,
  input_sample_rate : UInt32,
  output_gain? : Int16,
) -> OpusSampleEntryConfig {
  {
    channel_count,
    pre_skip,
    input_sample_rate,
    output_gain: output_gain.unwrap_or(0),
  }
}

///|
/// `Opus` sample entry を構築する。
pub fn build_opus_box(config : OpusSampleEntryConfig) -> @boxes.OpusBox {
  let audio = @boxes.AudioSampleEntryFields::new(
    @boxes.AudioSampleEntryFields::default_data_reference_index(),
    config.channel_count.get(),
    @boxes.AudioSampleEntryFields::default_samplesize(),
    @bytes.FixedPointNumber::new(
      if config.input_sample_rate <= 65535U {
        config.input_sample_rate.reinterpret_as_int()
      } else {
        0
      },
      0,
    ),
  )
  let dops = @boxes.DopsBox::new(
    config.channel_count.get(),
    config.pre_skip,
    config.input_sample_rate,
    config.output_gain,
  )
  @boxes.OpusBox::new(audio, dops, [])
}
