///|
/// [ISO/IEC 14496-12] TrackHeaderBox（`tkhd`）(親: [`TrakBox`])。
///
/// 1 トラックのヘッダーを保持する。上流 `TkhdBox` に対応する。flags の下位 4 ビットは
/// 各 `flag_track_*` フィールドに対応し、`creation_time` / `modification_time` /
/// `duration` が 32-bit に収まらない場合は version 1 で書かれる。
///
/// ```mbt check
/// test {
///   let box = @boxes.TkhdBox::new(
///     true,
///     true,
///     false,
///     false,
///     @bytes.Mp4FileTime::from_secs(0UL),
///     @bytes.Mp4FileTime::from_secs(0UL),
///     1U,
///     1000UL,
///     @boxes.TkhdBox::default_layer(),
///     @boxes.TkhdBox::default_alternate_group(),
///     @boxes.TkhdBox::default_video_volume(),
///     @boxes.TkhdBox::default_matrix(),
///     @bytes.FixedPointNumber::new(1920, 0),
///     @bytes.FixedPointNumber::new(1080, 0),
///   )
///   let decoded : @boxes.TkhdBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.flag_track_enabled, content="true")
///   inspect(decoded.track_id, content="1")
///   inspect(decoded.width.integer(), content="1920")
/// }
/// ```
pub struct TkhdBox {
  /// このトラックが有効かどうか（`flags` の bit 0 に対応）
  flag_track_enabled : Bool
  /// このトラックが movie の一部として扱われるか（`flags` の bit 1 に対応）
  flag_track_in_movie : Bool
  /// このトラックがプレビューで使われるか（`flags` の bit 2 に対応）
  flag_track_in_preview : Bool
  /// [`TkhdBox::width`] / [`TkhdBox::height`] がアスペクト比を表すか（`flags` の bit 3 に対応）
  flag_track_size_is_aspect_ratio : Bool
  /// このトラックが作成された時刻
  creation_time : @bytes.Mp4FileTime
  /// このトラックが最後に修正された時刻
  modification_time : @bytes.Mp4FileTime
  /// このトラックの識別子（同一ムービー内で一意）
  track_id : UInt32
  /// [`MvhdBox::timescale`] 単位で表したこのトラックの尺
  ///
  /// トラック固有の [`MdhdBox::timescale`] 単位ではないことに注意。
  /// この不整合が原因で `tkhd` を参照するプレイヤーでサンプルが打ち切られる
  /// 不具合が過去に発生している。
  duration : UInt64
  /// 同一時刻に重ねて描画するときの前後関係（値が小さいほど手前）
  layer : Int16
  /// 代替グループ（同じグループ内の別トラックと相互排他で切り替えることを示す）
  alternate_group : Int16
  /// 音声トラックの再生音量（1.0 が最大）。映像トラックでは 0
  volume : @bytes.FixedPointNumber
  /// 映像変換行列（3x3 の固定小数点行列を row-major で並べたもの）
  matrix : Array[Int32]
  /// トラックの表示幅
  ///
  /// [`TkhdBox::flag_track_size_is_aspect_ratio`] が `true` のときはアスペクト比を表す
  width : @bytes.FixedPointNumber
  /// トラックの表示高さ
  ///
  /// [`TkhdBox::flag_track_size_is_aspect_ratio`] が `true` のときはアスペクト比を表す
  height : @bytes.FixedPointNumber
} derive(Eq, Hash, Debug)

///|
pub extend TkhdBox with Eq::{equal, not_equal}

///|
pub extend TkhdBox with Hash::{hash, hash_combine}

///|
pub extend TkhdBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn TkhdBox::new(
  flag_track_enabled : Bool,
  flag_track_in_movie : Bool,
  flag_track_in_preview : Bool,
  flag_track_size_is_aspect_ratio : Bool,
  creation_time : @bytes.Mp4FileTime,
  modification_time : @bytes.Mp4FileTime,
  track_id : UInt32,
  duration : UInt64,
  layer : Int16,
  alternate_group : Int16,
  volume : @bytes.FixedPointNumber,
  matrix : Array[Int32],
  width : @bytes.FixedPointNumber,
  height : @bytes.FixedPointNumber,
) -> TkhdBox {
  {
    flag_track_enabled,
    flag_track_in_movie,
    flag_track_in_preview,
    flag_track_size_is_aspect_ratio,
    creation_time,
    modification_time,
    track_id,
    duration,
    layer,
    alternate_group,
    volume,
    matrix,
    width,
    height,
  }
}

///|
/// [`TkhdBox::layer`] のデフォルト値。
pub fn TkhdBox::default_layer() -> Int16 {
  0
}

///|
/// [`TkhdBox::alternate_group`] のデフォルト値。
pub fn TkhdBox::default_alternate_group() -> Int16 {
  0
}

///|
/// 音声用の [`TkhdBox::volume`] のデフォルト値（最大音量）。
pub fn TkhdBox::default_audio_volume() -> @bytes.FixedPointNumber {
  @bytes.FixedPointNumber::new(1, 0)
}

///|
/// 映像用の [`TkhdBox::volume`] のデフォルト値（無音）。
pub fn TkhdBox::default_video_volume() -> @bytes.FixedPointNumber {
  @bytes.FixedPointNumber::new(0, 0)
}

///|
/// [`TkhdBox::matrix`] のデフォルト値。
pub fn TkhdBox::default_matrix() -> Array[Int32] {
  [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
}

///|
/// `tkhd` をデコードする。
///
/// flags の下位 4 ビットを各 `flag_track_*` フィールドへ展開し、version 0 では
/// 32-bit、version 1 では 64-bit の時刻・duration を読む。
pub impl @bytes.Decode for TkhdBox with fn decode(cursor : @bytes.ReadCursor) -> TkhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(tkhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(tkhd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let mut creation_time = @bytes.Mp4FileTime::default()
    let mut modification_time = @bytes.Mp4FileTime::default()
    let mut track_id : UInt32 = 0U
    let mut duration : UInt64 = 0UL
    if full_header.version() == 1 {
      creation_time = @bytes.Mp4FileTime::from_secs(payload_cursor.read_u64())
      modification_time = @bytes.Mp4FileTime::from_secs(
        payload_cursor.read_u64(),
      )
      track_id = payload_cursor.read_u32()
      // reserved（4 バイト）
      payload_cursor.skip(4)
      duration = payload_cursor.read_u64()
    } else {
      creation_time = @bytes.Mp4FileTime::from_secs(
        payload_cursor.read_u32().to_uint64(),
      )
      modification_time = @bytes.Mp4FileTime::from_secs(
        payload_cursor.read_u32().to_uint64(),
      )
      track_id = payload_cursor.read_u32()
      // reserved（4 バイト）
      payload_cursor.skip(4)
      duration = payload_cursor.read_u32().to_uint64()
    }
    // reserved（8 バイト）
    payload_cursor.skip(4 * 2)
    let layer = Int16::from_int(payload_cursor.read_i16())
    let alternate_group = Int16::from_int(payload_cursor.read_i16())
    let volume = payload_cursor.read_fixed_8_8()
    // reserved（2 バイト）
    payload_cursor.skip(2)
    let matrix : Array[Int32] = []
    for _ in 0..<9 {
      matrix.push(payload_cursor.read_i32())
    }
    let width = payload_cursor.read_fixed_16_16()
    let height = payload_cursor.read_fixed_16_16()
    {
      flag_track_enabled: full_header.flags().is_set(0),
      flag_track_in_movie: full_header.flags().is_set(1),
      flag_track_in_preview: full_header.flags().is_set(2),
      flag_track_size_is_aspect_ratio: full_header.flags().is_set(3),
      creation_time,
      modification_time,
      track_id,
      duration,
      layer,
      alternate_group,
      volume,
      matrix,
      width,
      height,
    }
  })
}

///|
pub extend TkhdBox with @bytes.Decode::{decode}

///|
/// `tkhd` を canonical な形式でエンコードする。
///
/// flags は各 `flag_track_*` フィールドから組み立てる
/// （エンコード時に `layer` / `alternate_group` の生ビットは書かれない）。
pub impl @bytes.Encode for TkhdBox with fn encode(
  self : TkhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, tkhd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    if full_header.version() == 1 {
      payload.write_u64(self.creation_time.as_secs())
      payload.write_u64(self.modification_time.as_secs())
      payload.write_u32(self.track_id)
      payload.write_u32(0)
      payload.write_u64(self.duration)
    } else {
      payload.write_u32(self.creation_time.as_secs().to_uint())
      payload.write_u32(self.modification_time.as_secs().to_uint())
      payload.write_u32(self.track_id)
      payload.write_u32(0)
      payload.write_u32(self.duration.to_uint())
    }
    payload.write_u32(0)
    payload.write_u32(0)
    payload.write_i16(self.layer.to_int())
    payload.write_i16(self.alternate_group.to_int())
    payload.write_fixed_8_8(self.volume)
    payload.write_u16(0)
    for value in self.matrix {
      payload.write_i32(value)
    }
    payload.write_fixed_16_16(self.width)
    payload.write_fixed_16_16(self.height)
  })
}

///|
pub extend TkhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for TkhdBox with fn box_type(_self) {
  tkhd_type()
}

///|
pub impl @box.BaseBox for TkhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend TkhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 32-bit に収まらない時刻・duration がある場合は version 1 を使う（上流と同じ判定）。
pub impl @box.FullBox for TkhdBox with fn full_box_version(self) {
  if self.creation_time.as_secs() > 0xFFFFFFFFUL ||
    self.modification_time.as_secs() > 0xFFFFFFFFUL ||
    self.duration > 0xFFFFFFFFUL {
    1U
  } else {
    0U
  }
}

///|
/// 各 `flag_track_*` フィールドを flags の下位 4 ビットへ詰める（上流と同じビット位置）。
pub impl @box.FullBox for TkhdBox with fn full_box_flags(self) {
  @box.FullBoxFlags::from_flags([
    (0, self.flag_track_enabled),
    (1, self.flag_track_in_movie),
    (2, self.flag_track_in_preview),
    (3, self.flag_track_size_is_aspect_ratio),
  ])
}

///|
pub extend TkhdBox with @box.FullBox::{full_box_version, full_box_flags}
