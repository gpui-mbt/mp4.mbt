///|
/// トラックの種類を表す列挙型。
///
/// 上流 `TrackKind` に対応する。`hdlr` の handler type から
/// [`HdlrBox::track_kind`](gpui-mbt/mp4/boxes) で導出する。上流と同じく
/// 未知の handler を表す variant は持たず、未知は `None` として扱う
/// （映像などへ丸めない）。
pub(all) enum TrackKind {
  /// 音声トラック
  Audio
  /// 映像トラック
  Video
  /// 字幕トラック
  ///
  /// ISO/IEC 14496-30 の `stpp` / `wvtt` や 3GPP TS 26.245 の `tx3g` などの
  /// Timed Text 系サンプルエントリーを持つトラックを表す。対応するハンドラー
  /// 種別は `subt`（`stpp` 用）または `text`（`wvtt` / `tx3g` 用）で、
  /// どちらもこの variant にマップされる。
  Subtitle
} derive(Eq, Hash, Debug)

///|
pub extend TrackKind with Eq::{equal, not_equal}

///|
pub extend TrackKind with Hash::{hash, hash_combine}

///|
pub extend TrackKind with Debug::{to_repr}
