///|
/// トラック単位のメタデータ（`mdhd.language` / `hdlr.name`）。
pub struct TrackMetadata {
  /// 言語コード（既定は `und`）
  language : @bytes.LanguageCode
  /// ハンドラー名（既定は空）
  name : @bytes.Utf8String
} derive(Eq, Hash, Debug)

///|
pub extend TrackMetadata with Eq::{equal, not_equal}

///|
pub extend TrackMetadata with Hash::{hash, hash_combine}

///|
pub extend TrackMetadata with Debug::{to_repr}

///|
/// 既定のトラックメタデータ（`und` + 空文字列）。
pub fn TrackMetadata::default() -> TrackMetadata {
  {
    language: @bytes.LanguageCode::undefined(),
    name: @bytes.Utf8String::empty(),
  }
}

///|
/// 音声・映像・字幕のトラックメタデータをまとめた設定。
pub struct TrackMetadataOptions {
  /// 音声トラック
  audio_track : TrackMetadata
  /// 映像トラック
  video_track : TrackMetadata
  /// 字幕トラック
  subtitle_track : TrackMetadata
} derive(Eq, Hash, Debug)

///|
pub extend TrackMetadataOptions with Eq::{equal, not_equal}

///|
pub extend TrackMetadataOptions with Hash::{hash, hash_combine}

///|
pub extend TrackMetadataOptions with Debug::{to_repr}

///|
/// 既定値を返す。
pub fn TrackMetadataOptions::default() -> TrackMetadataOptions {
  {
    audio_track: TrackMetadata::default(),
    video_track: TrackMetadata::default(),
    subtitle_track: TrackMetadata::default(),
  }
}

///|
/// [`@bytes.TrackKind`] に対応するメタデータを返す。
pub fn TrackMetadataOptions::for_kind(
  self : TrackMetadataOptions,
  kind : @bytes.TrackKind,
) -> TrackMetadata {
  match kind {
    @bytes.TrackKind::Audio => self.audio_track
    @bytes.TrackKind::Video => self.video_track
    @bytes.TrackKind::Subtitle => self.subtitle_track
  }
}

///|
/// マルチプレックス対象のサンプル。
pub struct Sample {
  /// トラック種別
  track_kind : @bytes.TrackKind
  /// サンプルの詳細情報（最初のサンプルでは必須）
  sample_entry : @boxes.SampleEntry?
  /// キーフレームかどうか
  keyframe : Bool
  /// トラックのタイムスケール
  timescale : @bytes.NonZeroU32
  /// サンプルの尺
  duration : UInt32
  /// PTS - DTS
  composition_time_offset : Int64?
  /// サンプルデータの開始位置（基準は API ごとに異なる）
  data_offset : UInt64
  /// サンプルデータのサイズ
  data_size : UInt32
} derive(Eq, Debug)

///|
/// 各フィールドを指定してサンプルを作る。
pub fn Sample::new(
  track_kind : @bytes.TrackKind,
  sample_entry : @boxes.SampleEntry?,
  keyframe : Bool,
  timescale : @bytes.NonZeroU32,
  duration : UInt32,
  composition_time_offset : Int64?,
  data_offset : UInt64,
  data_size : UInt32,
) -> Sample {
  {
    track_kind,
    sample_entry,
    keyframe,
    timescale,
    duration,
    composition_time_offset,
    data_offset,
    data_size,
  }
}

///|
pub extend Sample with Eq::{equal, not_equal}

///|
pub extend Sample with Debug::{to_repr}
