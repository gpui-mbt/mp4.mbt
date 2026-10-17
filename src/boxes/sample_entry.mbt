///|
/// [`StsdBox`] に含まれるサンプルエントリー。上流 `SampleEntry` に対応する。
///
/// 映像（`avc1` / `hev1` / `hvc1` / `vp08` / `vp09` / `av01`）と音声
/// （`Opus` / `mp4a` / `fLaC`）の既知エントリーは型付き variant として
/// decode/encode する。それ以外の box_type は [`SampleEntry::Unknown`]
/// として生バイト列を保持する（上流の `Unknown` フォールバックと同じ）。
///
/// 字幕系エントリー（`stpp` / `wvtt` / `tx3g`）も型付き variant として扱う。
pub(all) enum SampleEntry {
  /// H.264 (AVC) 用サンプルエントリー（`avc1`）
  Avc1(Avc1Box)
  /// H.265 (HEVC) 用サンプルエントリー（`hev1`。パラメータセットが in-band 前提）
  Hev1(Hev1Box)
  /// H.265 (HEVC) 用サンプルエントリー（`hvc1`。パラメータセットが out-of-band 前提）
  Hvc1(Hvc1Box)
  /// VP8 用サンプルエントリー（`vp08`）
  Vp08(Vp08Box)
  /// VP9 用サンプルエントリー（`vp09`）
  Vp09(Vp09Box)
  /// AV1 用サンプルエントリー（`av01`）
  Av01(Av01Box)
  /// Opus 音声用サンプルエントリー（`Opus`）
  Opus(OpusBox)
  /// MPEG-4 音声（主に AAC）用サンプルエントリー（`mp4a`）
  Mp4a(Mp4aBox)
  /// FLAC 音声用サンプルエントリー（`fLaC`）
  Flac(FlacBox)
  /// XML 字幕（TTML/IMSC）用サンプルエントリー（`stpp`）
  Stpp(StppBox)
  /// WebVTT 字幕用サンプルエントリー（`wvtt`）
  Wvtt(WvttBox)
  /// 3GPP Timed Text 字幕用サンプルエントリー（`tx3g`）
  Tx3g(Tx3gBox)
  /// 上記のいずれにも該当しない box_type だった場合の受け皿
  ///
  /// demux 時に未知の box_type が出現した場合の保持先、および
  /// mux 時に任意の未知サンプルエントリーを組み込む場合に使う
  Unknown(UnknownBox)
} derive(Eq, Hash, Debug)

///|
pub extend SampleEntry with Eq::{equal, not_equal}

///|
pub extend SampleEntry with Hash::{hash, hash_combine}

///|
pub extend SampleEntry with Debug::{to_repr}

///|
/// チャンネル数を取得する。上流 `audio_channel_count` に対応する。
///
/// 音声の場合はチャンネル数、映像や未知エントリーの場合は `None` を返す。
/// 上流では `u8`（`channelcount` の下位 8 ビット）で返すため、ここでも
/// `channelcount` を `u8` に丸めた値を返す。
pub fn SampleEntry::audio_channel_count(self : SampleEntry) -> UInt32? {
  match self {
    Opus(b) => Some(b.audio.channelcount & 0xFFU)
    Mp4a(b) => Some(b.audio.channelcount & 0xFFU)
    Flac(b) => Some(b.audio.channelcount & 0xFFU)
    _ => None
  }
}

///|
/// サンプリングレートを取得する。上流 `audio_sample_rate` に対応する。
///
/// 音声の場合はサンプリングレート、映像や未知エントリーの場合は `None`
/// を返す。
///
/// # NOTE
///
/// このメソッドはサンプリングレートの整数部分のみを返し、小数部分は
/// 切り捨てられる。ただし通常は、MP4 ファイルでは音声のサンプリングレートは
/// 常に整数値（例: 44100 Hz, 48000 Hz）であり、小数部分が 0 以外の値を
/// 持つことはないため、問題ないと想定している。
///
/// なお音声コーデックによっては u16 の範囲を超えるサンプリングレートが
/// 使用される場合もある。その可能性がある場合は、このメソッドではなく、
/// コーデック固有の方法（例: [`DopsBox::input_sample_rate`]）で実際の
/// サンプリングレートを取得すること。
pub fn SampleEntry::audio_sample_rate(self : SampleEntry) -> UInt32? {
  match self {
    Opus(b) => Some(b.audio.samplerate.integer().reinterpret_as_uint())
    Mp4a(b) => Some(b.audio.samplerate.integer().reinterpret_as_uint())
    Flac(b) => Some(b.audio.samplerate.integer().reinterpret_as_uint())
    _ => None
  }
}

///|
/// サンプルサイズ（ビット深度）を取得する。上流 `audio_sample_size` に対応する。
///
/// 音声の場合はサンプルサイズ、映像や未知エントリーの場合は `None` を返す。
pub fn SampleEntry::audio_sample_size(self : SampleEntry) -> UInt32? {
  match self {
    Opus(b) => Some(b.audio.samplesize)
    Mp4a(b) => Some(b.audio.samplesize)
    Flac(b) => Some(b.audio.samplesize)
    _ => None
  }
}

///|
/// 解像度を取得する。上流 `video_resolution` に対応する。
///
/// 映像の場合は (幅, 高さ)、音声や未知エントリーの場合は `None` を返す。
pub fn SampleEntry::video_resolution(self : SampleEntry) -> (UInt32, UInt32)? {
  match self {
    Avc1(b) => Some((b.visual.width, b.visual.height))
    Hev1(b) => Some((b.visual.width, b.visual.height))
    Hvc1(b) => Some((b.visual.width, b.visual.height))
    Vp08(b) => Some((b.visual.width, b.visual.height))
    Vp09(b) => Some((b.visual.width, b.visual.height))
    Av01(b) => Some((b.visual.width, b.visual.height))
    _ => None
  }
}

///|
/// サンプルエントリーをデコードする。
///
/// 先にボックスヘッダーを読んで FourCC でディスパッチし、各型付き
/// エントリーの `decode` に委譲する（上流 `SampleEntry::decode` に対応）。
/// 既知でない box_type は [`UnknownBox`] として読む。
pub impl @bytes.Decode for SampleEntry with fn decode(
  cursor : @bytes.ReadCursor,
) -> SampleEntry raise @bytes.Mp4Error {
  let box_type = peek_box_type(cursor)
  if box_type == avc1_type() {
    Avc1(@bytes.decode_from(cursor))
  } else if box_type == hev1_type() {
    Hev1(@bytes.decode_from(cursor))
  } else if box_type == hvc1_type() {
    Hvc1(@bytes.decode_from(cursor))
  } else if box_type == vp08_type() {
    Vp08(@bytes.decode_from(cursor))
  } else if box_type == vp09_type() {
    Vp09(@bytes.decode_from(cursor))
  } else if box_type == av01_type() {
    Av01(@bytes.decode_from(cursor))
  } else if box_type == opus_type() {
    Opus(@bytes.decode_from(cursor))
  } else if box_type == mp4a_type() {
    Mp4a(@bytes.decode_from(cursor))
  } else if box_type == flac_type() {
    Flac(@bytes.decode_from(cursor))
  } else if box_type == stpp_type() {
    Stpp(@bytes.decode_from(cursor))
  } else if box_type == wvtt_type() {
    Wvtt(@bytes.decode_from(cursor))
  } else if box_type == tx3g_type() {
    Tx3g(@bytes.decode_from(cursor))
  } else {
    Unknown(@bytes.decode_from(cursor))
  }
}

///|
pub extend SampleEntry with @bytes.Decode::{decode}

///|
/// サンプルエントリーをエンコードする（内部ボックスの `encode` に委譲）。
pub impl @bytes.Encode for SampleEntry with fn encode(
  self : SampleEntry,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  match self {
    Avc1(b) => @bytes.Encode::encode(b, cursor)
    Hev1(b) => @bytes.Encode::encode(b, cursor)
    Hvc1(b) => @bytes.Encode::encode(b, cursor)
    Vp08(b) => @bytes.Encode::encode(b, cursor)
    Vp09(b) => @bytes.Encode::encode(b, cursor)
    Av01(b) => @bytes.Encode::encode(b, cursor)
    Opus(b) => @bytes.Encode::encode(b, cursor)
    Mp4a(b) => @bytes.Encode::encode(b, cursor)
    Flac(b) => @bytes.Encode::encode(b, cursor)
    Stpp(b) => @bytes.Encode::encode(b, cursor)
    Wvtt(b) => @bytes.Encode::encode(b, cursor)
    Tx3g(b) => @bytes.Encode::encode(b, cursor)
    Unknown(b) => @bytes.Encode::encode(b, cursor)
  }
}

///|
pub extend SampleEntry with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for SampleEntry with fn box_type(self) {
  match self {
    Avc1(b) => b.box_type()
    Hev1(b) => b.box_type()
    Hvc1(b) => b.box_type()
    Vp08(b) => b.box_type()
    Vp09(b) => b.box_type()
    Av01(b) => b.box_type()
    Opus(b) => b.box_type()
    Mp4a(b) => b.box_type()
    Flac(b) => b.box_type()
    Stpp(b) => b.box_type()
    Wvtt(b) => b.box_type()
    Tx3g(b) => b.box_type()
    Unknown(b) => b.box_type()
  }
}

///|
/// 型付きエントリーは `false`、[`UnknownBox`] を保持する `Unknown`
/// variant のみ `true` を返す（上流と同じ）。
pub impl @box.BaseBox for SampleEntry with fn is_unknown_box(self) {
  match self {
    Unknown(b) => @box.BaseBox::is_unknown_box(b)
    _ => false
  }
}

///|
pub impl @box.BaseBox for SampleEntry with fn children(self) {
  match self {
    Avc1(b) => b.children()
    Hev1(b) => b.children()
    Hvc1(b) => b.children()
    Vp08(b) => b.children()
    Vp09(b) => b.children()
    Av01(b) => b.children()
    Opus(b) => b.children()
    Mp4a(b) => b.children()
    Flac(b) => b.children()
    Stpp(b) => b.children()
    Wvtt(b) => b.children()
    Tx3g(b) => b.children()
    Unknown(b) => @box.BaseBox::children(b)
  }
}

///|
pub extend SampleEntry with @box.BaseBox::{box_type, is_unknown_box, children}
