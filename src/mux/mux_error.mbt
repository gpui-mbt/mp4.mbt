///|
/// マルチプレックス処理中に発生するエラー。
pub(all) suberror MuxError {
  /// MP4 ボックスのエンコード中に発生したエラー
  EncodeError(@bytes.Mp4Error)
  /// まだトラックが観測されていない
  EmptyTracks
  /// サンプルが指定されていない
  EmptySamples
  /// ファイルポジションの不一致
  PositionMismatch(expected~ : UInt64, actual~ : UInt64)
  /// 必須の sample_entry が欠落している
  MissingSampleEntry(track_kind~ : @bytes.TrackKind)
  /// 既にファイナライズ済み
  AlreadyFinalized
  /// 同じトラック内のタイムスケール値の不一致
  TimescaleMismatch(
    track_kind~ : @bytes.TrackKind,
    expected~ : @bytes.NonZeroU32,
    actual~ : @bytes.NonZeroU32
  )
  /// 同一トラック内に両立しない sample entry が混在している
  MixedSampleEntries(track_kind~ : @bytes.TrackKind)
  /// トラックに同期サンプルが 1 つも存在しない
  NoSyncSamples(track_kind~ : @bytes.TrackKind)
  /// 内部カウンタがオーバーフローした
  Overflow
}

///|
/// 上流 `Display for MuxError` に対応する文字列化。
pub fn MuxError::to_string(self : MuxError) -> String {
  match self {
    EncodeError(e) => "MP4 box encode error: \{e.to_string()}"
    EmptyTracks => "No tracks have been observed"
    EmptySamples => "No samples were provided"
    PositionMismatch(expected~, actual~) =>
      "Sample data position mismatch: expected \{expected}, got \{actual}"
    MissingSampleEntry(track_kind~) =>
      "Missing sample entry for \{track_kind_name(track_kind)}"
    AlreadyFinalized => "The muxer has already been finalized"
    TimescaleMismatch(track_kind~, expected~, actual~) =>
      "Timescale mismatch for \{track_kind_name(track_kind)}: expected \{expected.get()}, got \{actual.get()}"
    MixedSampleEntries(track_kind~) =>
      "Mixed sample entries are not allowed for \{track_kind_name(track_kind)}"
    NoSyncSamples(track_kind~) =>
      "No sync samples were found for \{track_kind_name(track_kind)}"
    Overflow => "Internal counter overflow"
  }
}

///|
/// `TrackKind` の表示名。
fn track_kind_name(kind : @bytes.TrackKind) -> String {
  match kind {
    @bytes.TrackKind::Audio => "audio"
    @bytes.TrackKind::Video => "video"
    @bytes.TrackKind::Subtitle => "subtitle"
  }
}

///|
/// `Mp4Error` を [`MuxError`] で包む。
fn[T] wrap_mux_encode(f : () -> T raise @bytes.Mp4Error) -> T raise MuxError {
  try f() catch {
    e => raise MuxError::EncodeError(e)
  } noraise {
    v => v
  }
}
