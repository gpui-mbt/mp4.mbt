///|
/// [ISO/IEC 14496-12] SampleDependencyTypeBox（`sdtp`）の 1 サンプル分のフラグ。
///
/// 生 1 バイトに 2-bit のフィールドを 4 つ詰めたもの。ビット配置は上流
/// `SdtpSampleFlags` と同じ（上位から `is_leading`、`sample_depends_on`、
/// `sample_is_depended_on`、`sample_has_redundancy`）。
///
/// ```mbt check
/// test {
///   let flags = @boxes.SdtpSampleFlags::from_fields(
///     b'\x01', b'\x02', b'\x03', b'\x00',
///   )
///   inspect(flags.get().to_uint(), content="108")
///   inspect(flags.is_leading().to_uint(), content="1")
///   inspect(flags.sample_depends_on().to_uint(), content="2")
///   inspect(flags.sample_is_depended_on().to_uint(), content="3")
///   inspect(flags.sample_has_redundancy().to_uint(), content="0")
/// }
/// ```
pub struct SdtpSampleFlags {
  /// 生 1 バイト値
  value : Byte
} derive(Eq, Hash, Debug)

///|
pub extend SdtpSampleFlags with Eq::{equal, not_equal}

///|
pub extend SdtpSampleFlags with Hash::{hash, hash_combine}

///|
pub extend SdtpSampleFlags with Debug::{to_repr}

///|
/// フィールド値を指定して新しいフラグを作成する。
///
/// 各引数は下位 2 bit だけが使われる（上流と同じマスク）。
pub fn SdtpSampleFlags::from_fields(
  is_leading : Byte,
  sample_depends_on : Byte,
  sample_is_depended_on : Byte,
  sample_has_redundancy : Byte,
) -> SdtpSampleFlags {
  let value = ((is_leading & 0b11) << 6) |
    ((sample_depends_on & 0b11) << 4) |
    ((sample_is_depended_on & 0b11) << 2) |
    (sample_has_redundancy & 0b11)
  { value, }
}

///|
/// 生の 1 バイト値を返す。
pub fn SdtpSampleFlags::get(self : SdtpSampleFlags) -> Byte {
  self.value
}

///|
/// `is_leading` フィールド（2 bits）を返す。
pub fn SdtpSampleFlags::is_leading(self : SdtpSampleFlags) -> Byte {
  self.value >> 6
}

///|
/// `sample_depends_on` フィールド（2 bits）を返す。
pub fn SdtpSampleFlags::sample_depends_on(self : SdtpSampleFlags) -> Byte {
  (self.value >> 4) & 0b11
}

///|
/// `sample_is_depended_on` フィールド（2 bits）を返す。
pub fn SdtpSampleFlags::sample_is_depended_on(self : SdtpSampleFlags) -> Byte {
  (self.value >> 2) & 0b11
}

///|
/// `sample_has_redundancy` フィールド（2 bits）を返す。
pub fn SdtpSampleFlags::sample_has_redundancy(self : SdtpSampleFlags) -> Byte {
  self.value & 0b11
}

///|
/// 1 バイトを読む。
pub impl @bytes.Decode for SdtpSampleFlags with fn decode(
  cursor : @bytes.ReadCursor,
) -> SdtpSampleFlags raise @bytes.Mp4Error {
  { value: cursor.read_u8().to_byte(), }
}

///|
pub extend SdtpSampleFlags with @bytes.Decode::{decode}

///|
/// 1 バイトを書く。
pub impl @bytes.Encode for SdtpSampleFlags with fn encode(
  self : SdtpSampleFlags,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  cursor.write_u8(self.value.to_uint())
}

///|
pub extend SdtpSampleFlags with @bytes.Encode::{encode}

///|
/// [ISO/IEC 14496-12] SampleDependencyTypeBox（`sdtp`）(親: [`StblBox`])。
///
/// サンプル間の依存関係（1 サンプル 1 バイト）を保持する。上流 `SdtpBox` に
/// 対応する。version は 0 固定。
///
/// ```mbt check
/// test {
///   let box = @boxes.SdtpBox::new([
///     @boxes.SdtpSampleFlags::from_fields(b'\x00', b'\x01', b'\x00', b'\x00'),
///   ])
///   let decoded : @boxes.SdtpBox = @bytes.decode_from(
///     @bytes.ReadCursor::new(@bytes.encode_to_bytes(box)),
///   )
///   inspect(decoded.entries.length(), content="1")
///   inspect(decoded.entries[0].get().to_uint(), content="16")
/// }
/// ```
pub struct SdtpBox {
  /// サンプル単位の依存関係フラグ列
  entries : Array[SdtpSampleFlags]
} derive(Eq, Hash, Debug)

///|
pub extend SdtpBox with Eq::{equal, not_equal}

///|
pub extend SdtpBox with Hash::{hash, hash_combine}

///|
pub extend SdtpBox with Debug::{to_repr}

///|
/// エントリー列を指定して作成する。
pub fn SdtpBox::new(entries : Array[SdtpSampleFlags]) -> SdtpBox {
  { entries, }
}

///|
/// `sdtp` をデコードする。
///
/// version が 0 以外の場合は [`@bytes.ErrorKind::InvalidData`]
/// （`"Invalid sdtp box version: {v}"`）で失敗する。エントリーはペイロードの
/// 末尾まで読む（上流と同じ）。
pub impl @bytes.Decode for SdtpBox with fn decode(cursor : @bytes.ReadCursor) -> SdtpBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  @bytes.with_box_type(sdtp_type(), fn() raise @bytes.Mp4Error {
    let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
    header.box_type().expect(sdtp_type())
    let payload_cursor = payload_cursor_of(cursor, payload)
    let full_header : @box.FullBoxHeader = @bytes.decode_from(payload_cursor)
    let version = full_header.version()
    if version != 0U {
      raise @bytes.Mp4Error::invalid_data(
        "Invalid sdtp box version: \{version}",
      )
    }
    let entries : Array[SdtpSampleFlags] = []
    while !payload_cursor.is_empty() {
      entries.push(@bytes.decode_from(payload_cursor))
    }
    { entries, }
  })
}

///|
pub extend SdtpBox with @bytes.Decode::{decode}

///|
/// `sdtp` を canonical な形式でエンコードする。
pub impl @bytes.Encode for SdtpBox with fn encode(
  self : SdtpBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  write_box_with_payload(cursor, sdtp_type(), fn(
    payload,
  ) raise @bytes.Mp4Error {
    @bytes.Encode::encode(@box.FullBoxHeader::from_box(self), payload)
    for entry in self.entries {
      @bytes.Encode::encode(entry, payload)
    }
  })
}

///|
pub extend SdtpBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for SdtpBox with fn box_type(_self) {
  sdtp_type()
}

///|
pub impl @box.BaseBox for SdtpBox with fn children(_self) {
  let empty : Array[&@box.BaseBox] = []
  empty
}

///|
pub extend SdtpBox with @box.BaseBox::{box_type, is_unknown_box, children}

///|
pub impl @box.FullBox for SdtpBox with fn full_box_version(_self) {
  0U
}

///|
pub impl @box.FullBox for SdtpBox with fn full_box_flags(_self) {
  @box.FullBoxFlags::new(0)
}

///|
pub extend SdtpBox with @box.FullBox::{full_box_version, full_box_flags}
