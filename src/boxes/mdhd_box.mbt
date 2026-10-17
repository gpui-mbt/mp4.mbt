///|
/// [ISO/IEC 14496-12] MediaHeaderBox（`mdhd`）(親: [`MdiaBox`])。
///
/// トラック固有のタイムスケールと言語を保持する。上流 `MdhdBox` に対応する。
/// `creation_time` / `modification_time` / `duration` が 32-bit に収まらない場合は
/// version 1（64-bit フィールド）で書かれる。
///
/// ```mbt check
/// test {
///   let box = @boxes.MdhdBox::new(
///     @bytes.Mp4FileTime::from_secs(0UL),
///     @bytes.Mp4FileTime::from_secs(0UL),
///     @bytes.NonZeroU32::new(48000U).unwrap(),
///     96000UL,
///     @bytes.LanguageCode::from_ascii("jpn").unwrap(),
///   )
///   let decoded : @boxes.MdhdBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.duration, content="96000")
///   inspect(decoded.language.to_string(), content="jpn")
/// }
/// ```
pub struct MdhdBox {
  /// このメディアが作成された時刻
  creation_time : @bytes.Mp4FileTime
  /// このメディアが最後に修正された時刻
  modification_time : @bytes.Mp4FileTime
  /// そのトラック固有のタイムスケール定義（1 秒あたりの時間単位数）
  ///
  /// [`MdhdBox::duration`] や `stts` / `ctts` などのトラック内メディア時間は
  /// この単位で表される。movie 全体の [`MvhdBox::timescale`] とは別物である。
  timescale : @bytes.NonZeroU32
  /// [`MdhdBox::timescale`] 単位で表したこのトラック（メディア）の尺
  duration : UInt64
  /// ISO-639-2/T 言語コード
  ///
  /// ISO/IEC 14496-12 の MediaHeaderBox では各文字を `char - 0x60` した値を
  /// `unsigned int(5)` にパックする。各バイトが `0x60..=0x7F` に収まることは
  /// [`@bytes.LanguageCode`] の構築時に検証済みであるため、language 起因で
  /// encode が失敗することはない。
  language : @bytes.LanguageCode
} derive(Eq, Hash, Debug)

///|
pub extend MdhdBox with Eq::{equal, not_equal}

///|
pub extend MdhdBox with Hash::{hash, hash_combine}

///|
pub extend MdhdBox with Debug::{to_repr}

///|
/// 各フィールドを指定して作成する。
pub fn MdhdBox::new(
  creation_time : @bytes.Mp4FileTime,
  modification_time : @bytes.Mp4FileTime,
  timescale : @bytes.NonZeroU32,
  duration : UInt64,
  language : @bytes.LanguageCode,
) -> MdhdBox {
  { creation_time, modification_time, timescale, duration, language, }
}

///|
/// `mdhd` をデコードする。
///
/// 言語コードは 5 ビットパック（`unsigned int(5)[3]`）を各 5 ビットマスクで
/// 復元する。マスク結果は常に `0x60..=0x7F` に収まるため、この経路で
/// [`@bytes.LanguageCode::new`] が失敗することはない。
pub impl @bytes.Decode for MdhdBox with fn decode(cursor : @bytes.ReadCursor) -> MdhdBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(mdhd_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(mdhd_type())
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
    let language = @bytes.LanguageCode::from_packed(payload_cursor.read_u16())
    // pre_defined（2 バイト）
    payload_cursor.skip(2)
    { creation_time, modification_time, timescale, duration, language, }
  })
}

///|
pub extend MdhdBox with @bytes.Decode::{decode}

///|
/// `mdhd` を canonical な形式でエンコードする。
///
/// 言語コードは各バイトの値域が構築時に保証済みのため、15 ビットへパックして
/// 書いても情報は失われない。
pub impl @bytes.Encode for MdhdBox with fn encode(
  self : MdhdBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, mdhd_type(), fn(
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
    payload.write_u16(self.language.to_packed())
    payload.write_u16(0)
  })
}

///|
pub extend MdhdBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for MdhdBox with fn box_type(_self) {
  mdhd_type()
}

///|
pub impl @box.BaseBox for MdhdBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend MdhdBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
/// 32-bit に収まらない時刻・duration がある場合は version 1 を使う（上流と同じ判定）。
pub impl @box.FullBox for MdhdBox with fn full_box_version(self) {
  if self.creation_time.as_secs() > 0xFFFFFFFFUL ||
    self.modification_time.as_secs() > 0xFFFFFFFFUL ||
    self.duration > 0xFFFFFFFFUL {
    1U
  } else {
    0U
  }
}

///|
pub impl @box.FullBox for MdhdBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend MdhdBox with @box.FullBox::{full_box_version, full_box_flags}
