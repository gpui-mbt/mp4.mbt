///|
/// AAC の Audio Object Type。
pub(all) enum AudioObjectType {
  /// AAC-LC (2)
  AacLc
} derive(Eq, Hash, Debug)

///|
pub extend AudioObjectType with Eq::{equal, not_equal}

///|
pub extend AudioObjectType with Hash::{hash, hash_combine}

///|
pub extend AudioObjectType with Debug::{to_repr}

///|
/// `AudioObjectType` の 5 ビット値を返す。
pub fn AudioObjectType::as_u8(self : AudioObjectType) -> UInt32 {
  match self {
    AacLc => 2U
  }
}

///|
/// サンプリング周波数。
pub struct SamplingFrequency {
  /// AAC の samplingFrequencyIndex（0..=12）。明示周波数の場合は 15
  index : UInt32
  /// 実効周波数（Hz）
  hz : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend SamplingFrequency with Eq::{equal, not_equal}

///|
pub extend SamplingFrequency with Hash::{hash, hash_combine}

///|
pub extend SamplingFrequency with Debug::{to_repr}

///|
/// AAC の周波数テーブル。
fn aac_frequency_table() -> Array[UInt32] {
  [
    96000U, 88200U, 64000U, 48000U, 44100U, 32000U, 24000U, 22050U, 16000U, 12000U,
    11025U, 8000U, 7350U,
  ]
}

///|
/// インデックスから作る（0..=12）。
pub fn SamplingFrequency::from_index(
  index : UInt32,
) -> SamplingFrequency raise @bytes.Mp4Error {
  let table = aac_frequency_table()
  if index >= table.length().reinterpret_as_uint() {
    raise @bytes.Mp4Error::invalid_input("invalid AAC sampling frequency index")
  }
  { index, hz: table[index.reinterpret_as_int()], }
}

///|
/// Hz からテーブル上の値を探す。
pub fn SamplingFrequency::from_hz(
  hz : UInt32,
) -> SamplingFrequency raise @bytes.Mp4Error {
  let table = aac_frequency_table()
  let mut i = 0
  while i < table.length() {
    if table[i] == hz {
      return { index: i.reinterpret_as_uint(), hz, }
    }
    i = i + 1
  }
  raise @bytes.Mp4Error::invalid_input("unsupported AAC sampling frequency")
}

///|
/// インデックスを返す。
pub fn SamplingFrequency::sampling_frequency_index(
  self : SamplingFrequency,
) -> UInt32 {
  self.index
}

///|
/// 実効周波数を返す。
pub fn SamplingFrequency::hz(self : SamplingFrequency) -> UInt32 {
  self.hz
}

///|
/// チャンネル構成。
pub struct ChannelConfiguration {
  /// 1..=7
  value : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend ChannelConfiguration with Eq::{equal, not_equal}

///|
pub extend ChannelConfiguration with Hash::{hash, hash_combine}

///|
pub extend ChannelConfiguration with Debug::{to_repr}

///|
/// 1..=7 の値から作る。
pub fn ChannelConfiguration::new(
  value : UInt32,
) -> ChannelConfiguration raise @bytes.Mp4Error {
  if value < 1U || value > 7U {
    raise @bytes.Mp4Error::invalid_input("invalid AAC channel configuration")
  }
  { value, }
}

///|
/// チャンネル数を返す。
pub fn ChannelConfiguration::channel_count(
  self : ChannelConfiguration,
) -> UInt32 {
  match self.value {
    1U => 1U
    2U => 2U
    3U => 3U
    4U => 4U
    5U => 5U
    6U => 6U
    _ => 8U
  }
}

///|
/// 生の値を返す。
pub fn ChannelConfiguration::as_u8(self : ChannelConfiguration) -> UInt32 {
  self.value
}

///|
/// AAC-LC の AudioSpecificConfig。
pub struct AudioSpecificConfig {
  /// オブジェクトタイプ
  audio_object_type : AudioObjectType
  /// サンプリング周波数
  sampling_frequency : SamplingFrequency
  /// チャンネル構成
  channel_configuration : ChannelConfiguration
} derive(Eq, Hash, Debug)

///|
pub extend AudioSpecificConfig with Eq::{equal, not_equal}

///|
pub extend AudioSpecificConfig with Hash::{hash, hash_combine}

///|
pub extend AudioSpecificConfig with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn AudioSpecificConfig::new(
  audio_object_type : AudioObjectType,
  sampling_frequency : SamplingFrequency,
  channel_configuration : ChannelConfiguration,
) -> AudioSpecificConfig {
  { audio_object_type, sampling_frequency, channel_configuration, }
}

///|
/// AudioSpecificConfig を解析する。
pub fn parse_audio_specific_config(
  input : Bytes,
) -> AudioSpecificConfig raise @bytes.Mp4Error {
  let reader = BitReader::new(input)
  let aot = reader.read_bits(5)
  if aot != 2U {
    raise @bytes.Mp4Error::invalid_input(
      "AAC audio object type must be 2 (AAC-LC)",
    )
  }
  let index = reader.read_bits(4)
  let sampling_frequency = if index == 15U {
    let hz = reader.read_bits(24)
    if hz == 0U {
      raise @bytes.Mp4Error::invalid_input(
        "explicit AAC sampling frequency is 0",
      )
    }
    { index: 15U, hz, }
  } else {
    SamplingFrequency::from_index(index)
  }
  let channel_value = reader.read_bits(4)
  let channels = ChannelConfiguration::new(channel_value)
  let frame_length_flag = reader.read_bit()
  let depends_on_core_coder = reader.read_bit()
  let extension_flag = reader.read_bit()
  if frame_length_flag != 0U ||
    depends_on_core_coder != 0U ||
    extension_flag != 0U {
    raise @bytes.Mp4Error::invalid_input(
      "unsupported AAC GASpecificConfig flags",
    )
  }
  if reader.remaining_bits() != 0 {
    raise @bytes.Mp4Error::invalid_input(
      "trailing bytes after AAC AudioSpecificConfig",
    )
  }
  {
    audio_object_type: AacLc,
    sampling_frequency,
    channel_configuration: channels,
  }
}

///|
/// AudioSpecificConfig を標準形でエンコードする。
pub fn encode_audio_specific_config(
  config : AudioSpecificConfig,
) -> Bytes raise @bytes.Mp4Error {
  let writer = BitWriter::new()
  writer.write_bits(config.audio_object_type.as_u8(), 5)
  if config.sampling_frequency.index == 15U {
    writer.write_bits(15U, 4)
    writer.write_bits(config.sampling_frequency.hz, 24)
  } else {
    writer.write_bits(config.sampling_frequency.sampling_frequency_index(), 4)
  }
  writer.write_bits(config.channel_configuration.as_u8(), 4)
  writer.write_bits(0U, 3)
  writer.byte_align()
  writer.to_bytes()
}

///|
/// ADTS の MPEG バージョン。
pub(all) enum AdtsMpegVersion {
  /// MPEG-4
  Mpeg4
  /// MPEG-2
  Mpeg2
} derive(Eq, Hash, Debug)

///|
pub extend AdtsMpegVersion with Eq::{equal, not_equal}

///|
pub extend AdtsMpegVersion with Hash::{hash, hash_combine}

///|
pub extend AdtsMpegVersion with Debug::{to_repr}

///|
/// ADTS ヘッダーの解析結果。
pub struct AdtsHeader {
  /// MPEG バージョン
  mpeg_version : AdtsMpegVersion
  /// CRC がないか
  protection_absent : Bool
  /// 0..=12
  sampling_frequency_index : UInt32
  /// チャンネル構成（生値）
  channel_configuration : UInt32
  /// ヘッダー込みのフレーム長
  frame_length : UInt32
  /// original_copy
  original_copy : Bool
  /// home
  home : Bool
} derive(Eq, Hash, Debug)

///|
pub extend AdtsHeader with Eq::{equal, not_equal}

///|
pub extend AdtsHeader with Hash::{hash, hash_combine}

///|
pub extend AdtsHeader with Debug::{to_repr}

///|
/// ADTS フレームを解析し、ヘッダーと raw payload を返す。
pub fn parse_adts_frame(
  input : Bytes,
) -> (AdtsHeader, Bytes) raise @bytes.Mp4Error {
  if input.length() < 7 {
    raise @bytes.Mp4Error::invalid_input("ADTS frame is too short")
  }
  let reader = BitReader::new(input)
  let sync = reader.read_bits(12)
  if sync != 0xFFFU {
    raise @bytes.Mp4Error::invalid_input("invalid ADTS syncword")
  }
  let id = reader.read_bit()
  let _layer = reader.read_bits(2)
  let protection_absent = reader.read_bit() == 1U
  let _profile = reader.read_bits(2)
  let frequency_index = reader.read_bits(4)
  let _private = reader.read_bit()
  let channel_configuration = reader.read_bits(3)
  let original_copy = reader.read_bit() == 1U
  let home = reader.read_bit() == 1U
  let _copyright_id = reader.read_bit()
  let _copyright_start = reader.read_bit()
  let frame_length = reader.read_bits(13)
  let _buffer_fullness = reader.read_bits(11)
  let _raw_blocks = reader.read_bits(2)
  let header_size = if protection_absent { 7 } else { 9 }
  if frame_length < header_size.reinterpret_as_uint() ||
    frame_length.reinterpret_as_int() > input.length() {
    raise @bytes.Mp4Error::invalid_input("invalid ADTS frame length")
  }
  let header = {
    mpeg_version: if id == 0U {
      Mpeg4
    } else {
      Mpeg2
    },
    protection_absent,
    sampling_frequency_index: frequency_index,
    channel_configuration,
    frame_length,
    original_copy,
    home,
  }
  (header, input[header_size:frame_length.reinterpret_as_int()].to_owned())
}

///|
/// ADTS 組み立て時の設定。
pub struct AdtsEncodeConfig {
  /// MPEG バージョン
  mpeg_version : AdtsMpegVersion
  /// original_copy
  original_copy : Bool
  /// home
  home : Bool
} derive(Eq, Hash, Debug)

///|
pub extend AdtsEncodeConfig with Eq::{equal, not_equal}

///|
pub extend AdtsEncodeConfig with Hash::{hash, hash_combine}

///|
pub extend AdtsEncodeConfig with Debug::{to_repr}

///|
/// 既定の設定。
pub fn AdtsEncodeConfig::default() -> AdtsEncodeConfig {
  { mpeg_version: Mpeg4, original_copy: false, home: false, }
}

///|
/// raw AAC フレームに ADTS ヘッダーを付ける。
pub fn wrap_raw_aac_in_adts(
  raw : Bytes,
  asc : AudioSpecificConfig,
  config : AdtsEncodeConfig,
) -> Bytes raise @bytes.Mp4Error {
  let frequency_index = asc.sampling_frequency.sampling_frequency_index()
  if frequency_index == 15U {
    raise @bytes.Mp4Error::invalid_input(
      "ADTS cannot represent an explicit sampling frequency",
    )
  }
  let frame_length = 7 + raw.length()
  if frame_length > 8191 {
    raise @bytes.Mp4Error::invalid_input(
      "ADTS frame_length does not fit in 13 bits",
    )
  }
  let writer = BitWriter::new()
  writer.write_bits(0xFFFU, 12)
  writer.write_bit(if config.mpeg_version is Mpeg4 { 0U } else { 1U })
  writer.write_bits(0U, 2)
  writer.write_bit(1U)
  writer.write_bits(2U, 2)
  writer.write_bits(frequency_index, 4)
  writer.write_bit(0U)
  writer.write_bits(asc.channel_configuration.as_u8(), 3)
  writer.write_bit(if config.original_copy { 1U } else { 0U })
  writer.write_bit(if config.home { 1U } else { 0U })
  writer.write_bit(0U)
  writer.write_bit(0U)
  writer.write_bits(frame_length.reinterpret_as_uint(), 13)
  writer.write_bits(0x7FFU, 11)
  writer.write_bits(0U, 2)
  writer.byte_align()
  let mut out = writer.to_bytes()
  out = out + raw
  out
}

///|
/// `build_mp4a_box` の設定。
pub struct Mp4aSampleEntryConfig {
  /// `es_id`（1 以上）
  es_id : UInt32
  /// デコーダーバッファサイズ（24 ビット）
  buffer_size_db : UInt32
  /// 最大ビットレート
  max_bitrate : UInt32
  /// 平均ビットレート
  avg_bitrate : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend Mp4aSampleEntryConfig with Eq::{equal, not_equal}

///|
pub extend Mp4aSampleEntryConfig with Hash::{hash, hash_combine}

///|
pub extend Mp4aSampleEntryConfig with Debug::{to_repr}

///|
/// 設定を作る。
pub fn Mp4aSampleEntryConfig::new(
  es_id : UInt32,
  buffer_size_db : UInt32,
  max_bitrate : UInt32,
  avg_bitrate : UInt32,
) -> Mp4aSampleEntryConfig raise @bytes.Mp4Error {
  if es_id == 0U {
    raise @bytes.Mp4Error::invalid_input("es_id must be greater than zero")
  }
  if buffer_size_db > 0xFFFFFFU {
    raise @bytes.Mp4Error::invalid_input("buffer_size_db exceeds 24 bits")
  }
  { es_id, buffer_size_db, max_bitrate, avg_bitrate, }
}

///|
/// ASC から `mp4a` ボックスを構築する。
pub fn build_mp4a_box(
  asc : AudioSpecificConfig,
  config : Mp4aSampleEntryConfig,
) -> @boxes.Mp4aBox raise @bytes.Mp4Error {
  let asc_bytes = encode_audio_specific_config(asc)
  let dcd = @boxes.DecoderConfigDescriptor::new(
    @boxes.DecoderConfigDescriptor::object_type_indication_audio_iso_iec_14496_3(),
    @bytes.Uint::from_bits(5UL, bits=6, offset=0),
    @bytes.Uint::from_bits(0UL, bits=1, offset=0),
    @bytes.Uint::from_bits(config.buffer_size_db.to_uint64(), bits=24, offset=0),
    config.max_bitrate,
    config.avg_bitrate,
    Some(@boxes.DecoderSpecificInfo::new(asc_bytes)),
  )
  let es = @boxes.EsDescriptor::new(
    config.es_id,
    @bytes.Uint::from_bits(0UL, bits=5, offset=0),
    None,
    None,
    None,
    dcd,
    @boxes.SlConfigDescriptor::new(),
  )
  let audio = @boxes.AudioSampleEntryFields::new(
    @boxes.AudioSampleEntryFields::default_data_reference_index(),
    asc.channel_configuration.channel_count(),
    @boxes.AudioSampleEntryFields::default_samplesize(),
    @bytes.FixedPointNumber::new(
      if asc.sampling_frequency.hz <= 65535U {
        asc.sampling_frequency.hz.reinterpret_as_int()
      } else {
        0
      },
      0,
    ),
  )
  @boxes.Mp4aBox::new(audio, @boxes.EsdsBox::new(es), [])
}
