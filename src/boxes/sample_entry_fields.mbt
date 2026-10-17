///|
/// 映像系の [`SampleEntry`] に共通のフィールドをまとめた構造体。
/// 上流 `VisualSampleEntryFields` に対応する。
///
/// `SampleEntry`（SampleDescription）ヘッダーの
/// `reserved(6) + data_reference_index` に続く、映像サンプルエントリーの
/// 固定レイアウト部分（計 78 バイト）を読み書きする。
pub struct VisualSampleEntryFields {
  /// データ参照インデックス（`dref` 内のエントリーを 1-based で指す）
  data_reference_index : @bytes.NonZeroU16
  /// 映像フレームの幅（ピクセル）
  width : UInt32
  /// 映像フレームの高さ（ピクセル）
  height : UInt32
  /// 水平解像度（dpi、u16.u16 固定小数点）
  horizresolution : @bytes.FixedPointNumber
  /// 垂直解像度（dpi、u16.u16 固定小数点）
  vertresolution : @bytes.FixedPointNumber
  /// 1 サンプルに含まれるフレーム数（通常は 1）
  frame_count : UInt32
  /// コンプレッサー名（32 バイト固定。先頭 1 バイトが長さで残りが
  /// ASCII 文字列という Pascal 文字列形式）
  compressorname : Bytes
  /// 色深度（ビット数。24 は透明無しのカラー画像を意味する）
  depth : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend VisualSampleEntryFields with Eq::{equal, not_equal}

///|
pub extend VisualSampleEntryFields with Hash::{hash, hash_combine}

///|
pub extend VisualSampleEntryFields with Debug::{to_repr}

///|
/// [`VisualSampleEntryFields::data_reference_index`] のデフォルト値。
/// 上流 `DEFAULT_DATA_REFERENCE_INDEX`。
pub fn VisualSampleEntryFields::default_data_reference_index() -> @bytes.NonZeroU16 {
  @bytes.NonZeroU16::one()
}

///|
/// [`VisualSampleEntryFields::horizresolution`] のデフォルト値 (72 dpi)。
/// 上流 `DEFAULT_HORIZRESOLUTION`。
pub fn VisualSampleEntryFields::default_horizresolution() -> @bytes.FixedPointNumber {
  @bytes.FixedPointNumber::new(0x48, 0)
}

///|
/// [`VisualSampleEntryFields::vertresolution`] のデフォルト値 (72 dpi)。
/// 上流 `DEFAULT_VERTRESOLUTION`。
pub fn VisualSampleEntryFields::default_vertresolution() -> @bytes.FixedPointNumber {
  @bytes.FixedPointNumber::new(0x48, 0)
}

///|
/// [`VisualSampleEntryFields::frame_count`] のデフォルト値 (1)。
/// 上流 `DEFAULT_FRAME_COUNT`。
pub fn VisualSampleEntryFields::default_frame_count() -> UInt32 {
  1U
}

///|
/// [`VisualSampleEntryFields::depth`] のデフォルト値
/// (24: images are in colour with no alpha)。上流 `DEFAULT_DEPTH`。
pub fn VisualSampleEntryFields::default_depth() -> UInt32 {
  0x0018U
}

///|
/// 名前なしを表す [`VisualSampleEntryFields::compressorname`] の値（32 バイトの 0）。
/// 上流 `NULL_COMPRESSORNAME`。
pub fn VisualSampleEntryFields::null_compressorname() -> Bytes {
  Bytes::make(32, b'\x00')
}

///|
/// 各フィールドを指定して作成する。
///
/// `compressorname` は 32 バイト固定であり、それ以外の長さは
/// [`@bytes.ErrorKind::InvalidInput`] で失敗する（上流の `[u8; 32]` に対応する検査）。
pub fn VisualSampleEntryFields::new(
  data_reference_index : @bytes.NonZeroU16,
  width : UInt32,
  height : UInt32,
  horizresolution : @bytes.FixedPointNumber,
  vertresolution : @bytes.FixedPointNumber,
  frame_count : UInt32,
  compressorname : Bytes,
  depth : UInt32,
) -> VisualSampleEntryFields raise @bytes.Mp4Error {
  if compressorname.length() != 32 {
    raise @bytes.Mp4Error::invalid_input(
      "compressorname must be exactly 32 bytes",
    )
  }
  {
    data_reference_index,
    width,
    height,
    horizresolution,
    vertresolution,
    frame_count,
    compressorname,
    depth,
  }
}

///|
/// 映像系サンプルエントリー共通フィールド（78 バイト）をデコードする。
///
/// 予約領域と pre-defined 領域は読み飛ばすだけで値は保持しない（上流と同じ）。
pub impl @bytes.Decode for VisualSampleEntryFields with fn decode(
  cursor : @bytes.ReadCursor,
) -> VisualSampleEntryFields raise @bytes.Mp4Error {
  // reserved（6 バイト）
  cursor.skip(6)
  let data_reference_index : @bytes.NonZeroU16 = @bytes.decode_from(cursor)
  // pre_defined（2 バイト）+ reserved（2 バイト）+ pre_defined（4 バイト x 3）
  cursor.skip(2 + 2 + 4 * 3)
  let width = cursor.read_u16()
  let height = cursor.read_u16()
  let horizresolution = cursor.read_fixed_16_16_unsigned()
  let vertresolution = cursor.read_fixed_16_16_unsigned()
  // reserved（4 バイト）
  cursor.skip(4)
  let frame_count = cursor.read_u16()
  let compressorname = cursor.read_bytes(32)
  let depth = cursor.read_u16()
  // pre_defined = -1（2 バイト）
  cursor.skip(2)
  {
    data_reference_index,
    width,
    height,
    horizresolution,
    vertresolution,
    frame_count,
    compressorname,
    depth,
  }
}

///|
pub extend VisualSampleEntryFields with @bytes.Decode::{decode}

///|
/// 映像系サンプルエントリー共通フィールド（78 バイト）をエンコードする。
///
/// 予約領域は 0、末尾の pre_defined は -1 を書く（上流と同じ）。
pub impl @bytes.Encode for VisualSampleEntryFields with fn encode(
  self : VisualSampleEntryFields,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  cursor.write_bytes(Bytes::make(6, b'\x00'))
  @bytes.Encode::encode(self.data_reference_index, cursor)
  cursor.write_bytes(Bytes::make(2 + 2 + 4 * 3, b'\x00'))
  cursor.write_u16(self.width)
  cursor.write_u16(self.height)
  cursor.write_fixed_16_16_unsigned(self.horizresolution)
  cursor.write_fixed_16_16_unsigned(self.vertresolution)
  cursor.write_u32(0)
  cursor.write_u16(self.frame_count)
  if self.compressorname.length() != 32 {
    raise @bytes.Mp4Error::invalid_input(
      "compressorname must be exactly 32 bytes",
    )
  }
  cursor.write_bytes(self.compressorname)
  cursor.write_u16(self.depth)
  cursor.write_i16(-1)
}

///|
pub extend VisualSampleEntryFields with @bytes.Encode::{encode}

///|
/// 音声系の [`SampleEntry`] に共通のフィールドをまとめた構造体。
/// 上流 `AudioSampleEntryFields` に対応する。
///
/// `SampleEntry` ヘッダーに続く、音声サンプルエントリーの固定レイアウト部分
/// （計 28 バイト）を読み書きする。
pub struct AudioSampleEntryFields {
  /// データ参照インデックス（`dref` 内のエントリーを 1-based で指す）
  data_reference_index : @bytes.NonZeroU16
  /// チャンネル数（1 = モノラル、2 = ステレオ など）
  channelcount : UInt32
  /// 1 サンプルあたりのビット数（例: 16）
  samplesize : UInt32
  /// サンプリングレート（Hz、u16.u16 固定小数点）。整数部が u16 に収まらない
  /// コーデックではコーデック固有のフィールド（例: [`DopsBox::input_sample_rate`]）
  /// を優先する
  samplerate : @bytes.FixedPointNumber
} derive(Eq, Hash, Debug)

///|
pub extend AudioSampleEntryFields with Eq::{equal, not_equal}

///|
pub extend AudioSampleEntryFields with Hash::{hash, hash_combine}

///|
pub extend AudioSampleEntryFields with Debug::{to_repr}

///|
/// [`AudioSampleEntryFields::data_reference_index`] のデフォルト値。
/// 上流 `DEFAULT_DATA_REFERENCE_INDEX`。
pub fn AudioSampleEntryFields::default_data_reference_index() -> @bytes.NonZeroU16 {
  @bytes.NonZeroU16::one()
}

///|
/// [`AudioSampleEntryFields::samplesize`] のデフォルト値 (16)。
/// 上流 `DEFAULT_SAMPLESIZE`。
pub fn AudioSampleEntryFields::default_samplesize() -> UInt32 {
  16U
}

///|
/// 各フィールドを指定して作成する。
pub fn AudioSampleEntryFields::new(
  data_reference_index : @bytes.NonZeroU16,
  channelcount : UInt32,
  samplesize : UInt32,
  samplerate : @bytes.FixedPointNumber,
) -> AudioSampleEntryFields {
  { data_reference_index, channelcount, samplesize, samplerate, }
}

///|
/// 音声系サンプルエントリー共通フィールド（28 バイト）をデコードする。
///
/// 予約領域と pre-defined 領域は読み飛ばすだけで値は保持しない（上流と同じ）。
pub impl @bytes.Decode for AudioSampleEntryFields with fn decode(
  cursor : @bytes.ReadCursor,
) -> AudioSampleEntryFields raise @bytes.Mp4Error {
  // reserved（6 バイト）
  cursor.skip(6)
  let data_reference_index : @bytes.NonZeroU16 = @bytes.decode_from(cursor)
  // reserved（4 バイト x 2）
  cursor.skip(4 * 2)
  let channelcount = cursor.read_u16()
  let samplesize = cursor.read_u16()
  // pre_defined（2 バイト）+ reserved（2 バイト）
  cursor.skip(2 + 2)
  let samplerate = cursor.read_fixed_16_16_unsigned()
  { data_reference_index, channelcount, samplesize, samplerate, }
}

///|
pub extend AudioSampleEntryFields with @bytes.Decode::{decode}

///|
/// 音声系サンプルエントリー共通フィールド（28 バイト）をエンコードする。
///
/// 予約領域と pre-defined 領域は 0 を書く（上流と同じ）。
pub impl @bytes.Encode for AudioSampleEntryFields with fn encode(
  self : AudioSampleEntryFields,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  cursor.write_bytes(Bytes::make(6, b'\x00'))
  @bytes.Encode::encode(self.data_reference_index, cursor)
  cursor.write_bytes(Bytes::make(4 * 2, b'\x00'))
  cursor.write_u16(self.channelcount)
  cursor.write_u16(self.samplesize)
  cursor.write_bytes(Bytes::make(2 + 2, b'\x00'))
  cursor.write_fixed_16_16_unsigned(self.samplerate)
}

///|
pub extend AudioSampleEntryFields with @bytes.Encode::{encode}
