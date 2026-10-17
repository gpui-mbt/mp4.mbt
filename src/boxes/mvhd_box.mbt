///|
/// [ISO/IEC 14496-12] MovieHeaderBox（`mvhd`）(親: [`MoovBox`])。
///
/// movie 全体のメタデータを保持する。上流 `MvhdBox` に対応する。
/// `creation_time` / `modification_time` / `duration` が 32-bit に収まらない場合は
/// version 1（64-bit フィールド）で書かれ、収まる場合は version 0 になる
/// （[`@box.FullBox`] の実装がエンコード時に決める）。
///
/// ```mbt check
/// test {
///   let box = @boxes.MvhdBox::new(
///     @bytes.Mp4FileTime::from_secs(0UL),
///     @bytes.Mp4FileTime::from_secs(0UL),
///     @bytes.NonZeroU32::new(1000U).unwrap(),
///     2000UL,
///     @boxes.MvhdBox::default_rate(),
///     @boxes.MvhdBox::default_volume(),
///     @boxes.MvhdBox::default_matrix(),
///     1U,
///   )
///   let decoded : @boxes.MvhdBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.duration, content="2000")
///   inspect(decoded.timescale.get(), content="1000")
///   inspect(decoded.next_track_id, content="1")
/// }
/// ```
pub struct MvhdBox {
  /// このムービーが作成された時刻
  creation_time : @bytes.Mp4FileTime
  /// このムービーが最後に修正された時刻
  modification_time : @bytes.Mp4FileTime
  /// movie 全体のタイムスケール定義（1 秒あたりの時間単位数）
  ///
  /// [`MvhdBox::duration`] や [`TkhdBox::duration`] はこの単位で表される。
  /// トラック固有の [`MdhdBox::timescale`] とは別物である。
  timescale : @bytes.NonZeroU32
  /// [`MvhdBox::timescale`] 単位で表した movie 全体の尺
  duration : UInt64
  /// 推奨再生レート（1.0 が通常速度）
  rate : @bytes.FixedPointNumber
  /// 推奨音量（1.0 が最大）
  volume : @bytes.FixedPointNumber
  /// 映像変換行列（3x3 の固定小数点行列を row-major で並べたもの）
  matrix : Array[Int32]
  /// 次のトラックに割り当てるべきトラック ID の候補値
  next_track_id : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend MvhdBox with Eq::{equal, not_equal}

///|
pub extend MvhdBox with Hash::{hash, hash_combine}

///|
pub extend MvhdBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MvhdBox::new(
  creation_time : @bytes.Mp4FileTime,
  modification_time : @bytes.Mp4FileTime,
  timescale : @bytes.NonZeroU32,
  duration : UInt64,
  rate : @bytes.FixedPointNumber,
  volume : @bytes.FixedPointNumber,
  matrix : Array[Int32],
  next_track_id : UInt32,
) -> MvhdBox {
  {
    creation_time,
    modification_time,
    timescale,
    duration,
    rate,
    volume,
    matrix,
    next_track_id,
  }
}

///|
/// [`MvhdBox::rate`] のデフォルト値（通常の再生速度）。
pub fn MvhdBox::default_rate() -> @bytes.FixedPointNumber {
  @bytes.FixedPointNumber::new(1, 0)
}

///|
/// [`MvhdBox::volume`] のデフォルト値（最大音量）。
pub fn MvhdBox::default_volume() -> @bytes.FixedPointNumber {
  @bytes.FixedPointNumber::new(1, 0)
}

///|
/// [`MvhdBox::matrix`] のデフォルト値。
pub fn MvhdBox::default_matrix() -> Array[Int32] {
  [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
}

///|
/// `mvhd` をデコードする。
///
/// version 0 では時刻と duration を 32-bit として読み、version 1 では 64-bit として
/// 読む。どちらも [`@bytes.Mp4FileTime`]（秒の整数）と `UInt64` のまま保持し、
/// 暗黙の float 丸めは行わない。
pub impl @bytes.Decode for MvhdBox with fn decode(cursor : @bytes.ReadCursor) -> MvhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mvhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mvhd_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let mut creation_time = @bytes.Mp4FileTime::default()
    let mut modification_time = @bytes.Mp4FileTime::default()
    let mut timescale = @bytes.NonZeroU32::default()
    let mut duration : UInt64 = 0UL
    if full_header.version() == 1 {
      creation_time = @bytes.Mp4FileTime::from_secs(payload_cursor.read_u64())
      modification_time = @bytes.Mp4FileTime::from_secs(
        payload_cursor.read_u64(),
      )
      timescale = @bytes.decode_from(payload_cursor)
      duration = payload_cursor.read_u64()
    } else {
      creation_time = @bytes.Mp4FileTime::from_secs(
        payload_cursor.read_u32().to_uint64(),
      )
      modification_time = @bytes.Mp4FileTime::from_secs(
        payload_cursor.read_u32().to_uint64(),
      )
      timescale = @bytes.decode_from(payload_cursor)
      duration = payload_cursor.read_u32().to_uint64()
    }
    let rate = payload_cursor.read_fixed_16_16()
    let volume = payload_cursor.read_fixed_8_8()
    // pre_defined（2 バイト）+ reserved（8 バイト）
    payload_cursor.skip(2 + 4 * 2)
    let matrix : Array[Int32] = []
    for _ in 0..<9 {
      matrix.push(payload_cursor.read_i32())
    }
    // pre_defined（24 バイト）
    payload_cursor.skip(4 * 6)
    let next_track_id = payload_cursor.read_u32()
    {
      creation_time,
      modification_time,
      timescale,
      duration,
      rate,
      volume,
      matrix,
      next_track_id,
    }
  })
}

///|
pub extend MvhdBox with @bytes.Decode::{decode}

///|
/// `mvhd` を canonical な形式でエンコードする。
///
/// version は [`@box.FullBox`] の実装が決め、payload 長から最小幅のサイズを書く。
pub impl @bytes.Encode for MvhdBox with fn encode(
  self : MvhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mvhd_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    let full_header = @box.FullBoxHeader::from_box(self)
    @bytes.Encode::encode(full_header, payload)
    if full_header.version() == 1 {
      payload.write_u64(self.creation_time.as_secs())
      payload.write_u64(self.modification_time.as_secs())
      payload.write_u32(self.timescale.get())
      payload.write_u64(self.duration)
    } else {
      payload.write_u32(self.creation_time.as_secs().to_uint())
      payload.write_u32(self.modification_time.as_secs().to_uint())
      payload.write_u32(self.timescale.get())
      payload.write_u32(self.duration.to_uint())
    }
    payload.write_fixed_16_16(self.rate)
    payload.write_fixed_8_8(self.volume)
    // pre_defined（2 バイト）+ reserved（8 バイト）
    payload.write_u16(0)
    payload.write_u32(0)
    payload.write_u32(0)
    for value in self.matrix {
      payload.write_i32(value)
    }
    for _ in 0..<6 {
      payload.write_u32(0)
    }
    payload.write_u32(self.next_track_id)
  })
}

///|
pub extend MvhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MvhdBox with fn box_type(_self) {
  mvhd_type()
}

///|
pub impl @box.BaseBox for MvhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend MvhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 32-bit に収まらない時刻・duration がある場合は version 1 を使う（上流と同じ判定）。
pub impl @box.FullBox for MvhdBox with fn full_box_version(self) {
  if self.creation_time.as_secs() > 0xFFFFFFFFUL ||
    self.modification_time.as_secs() > 0xFFFFFFFFUL ||
    self.duration > 0xFFFFFFFFUL {
    1U
  } else {
    0U
  }
}

///|
pub impl @box.FullBox for MvhdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend MvhdBox with @box.FullBox::{full_box_version, full_box_flags}
