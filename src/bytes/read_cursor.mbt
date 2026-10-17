///|
/// Big Endian の読み取りカーソル。
///
/// - 読み取りは成功した場合だけ `position` を進める。失敗した場合、位置は進まない。
/// - `base_offset` は、このカーソルが指すバッファの先頭がファイル内で持つ位置。
///   エラーの `offset` は `base_offset + position` になる。
/// - [`ParseLimits`] によりコピーを作る読み取り（[`ReadCursor::read_bytes`] など）の
///   確保サイズを制限する。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(b"\x01\x02\x03\x04")
///   inspect(cursor.read_u16(), content="258")
///   inspect(cursor.read_u16(), content="772")
///   inspect(cursor.is_empty(), content="true")
/// }
/// ```
pub struct ReadCursor {
  data : BytesView
  mut position : Int32
  base_offset : UInt64
  limits : ParseLimits
}

///|
/// バッファ全体を読むカーソルを作る（ファイル位置 0、既定の [`ParseLimits`]）。
pub fn ReadCursor::new(bytes : Bytes) -> ReadCursor {
  {
    data: bytes[:],
    position: 0,
    base_offset: 0UL,
    limits: ParseLimits::default(),
  }
}

///|
/// バッファのファイル内位置と上限を指定してカーソルを作る。
pub fn ReadCursor::with_config(
  bytes : Bytes,
  base_offset : UInt64,
  limits : ParseLimits,
) -> ReadCursor {
  { data: bytes[:], position: 0, base_offset, limits, }
}

///|
/// カーソルが読むバッファ全体を返す。
pub fn ReadCursor::data(self : ReadCursor) -> BytesView {
  self.data
}

///|
/// 現在の読み取り位置（バッファ先頭からの相対バイト数）を返す。
pub fn ReadCursor::position(self : ReadCursor) -> Int32 {
  self.position
}

///|
/// このバッファ先頭のファイル内位置を返す。
pub fn ReadCursor::base_offset(self : ReadCursor) -> UInt64 {
  self.base_offset
}

///|
/// 現在位置のファイル内位置を返す。
pub fn ReadCursor::offset(self : ReadCursor) -> UInt64 {
  self.base_offset + self.position.to_uint64()
}

///|
/// バッファ全体の長さを返す。
pub fn ReadCursor::length(self : ReadCursor) -> Int32 {
  self.data.length()
}

///|
/// 残りのバイト数を返す。
pub fn ReadCursor::remaining(self : ReadCursor) -> Int32 {
  self.data.length() - self.position
}

///|
/// 残りが 0 バイトかどうかを返す。
pub fn ReadCursor::is_empty(self : ReadCursor) -> Bool {
  self.position == self.data.length()
}

///|
/// 使用している上限を返す。
pub fn ReadCursor::limits(self : ReadCursor) -> ParseLimits {
  self.limits
}

///|
/// `n` バイト読めることを検査する。読めない場合は
/// [`ErrorKind::InsufficientBuffer`] を返し、位置は変更しない。
fn ReadCursor::require(self : ReadCursor, n : Int32) -> Unit raise Mp4Error {
  if n < 0 {
    raise Mp4Error::invalid_input("read length must be non-negative: \{n}")
  }
  let remaining = self.remaining()
  if n > remaining {
    let error = Mp4Error::insufficient_buffer(
      n.to_uint64(),
      remaining.to_uint64(),
    )
    raise error.with_offset(self.offset())
  }
}

///|
/// 位置を `position` へ戻す（失敗したデコードの巻き戻し用）。
pub fn ReadCursor::rewind_to(
  self : ReadCursor,
  position : Int32,
) -> Unit raise Mp4Error {
  if position < 0 || position > self.data.length() {
    raise Mp4Error::invalid_input(
      "rewind position \{position} is out of range (length=\{self.data.length()})",
    )
  }
  self.position = position
}

///|
/// `n` バイトを読み飛ばす。
pub fn ReadCursor::skip(self : ReadCursor, n : Int32) -> Unit raise Mp4Error {
  self.require(n)
  self.position += n
}

///|
/// 符号なし 8-bit を読む。
pub fn ReadCursor::read_u8(self : ReadCursor) -> UInt32 raise Mp4Error {
  self.require(1)
  let value = self.data[self.position].to_uint()
  self.position += 1
  value
}

///|
/// 符号なし 16-bit を Big Endian で読む。
pub fn ReadCursor::read_u16(self : ReadCursor) -> UInt32 raise Mp4Error {
  self.require(2)
  let value = (self.data[self.position].to_uint() << 8) |
    self.data[self.position + 1].to_uint()
  self.position += 2
  value
}

///|
/// 符号なし 24-bit を Big Endian で読む。
pub fn ReadCursor::read_u24(self : ReadCursor) -> UInt32 raise Mp4Error {
  self.require(3)
  let value = (self.data[self.position].to_uint() << 16) |
    (self.data[self.position + 1].to_uint() << 8) |
    self.data[self.position + 2].to_uint()
  self.position += 3
  value
}

///|
/// 符号なし 32-bit を Big Endian で読む。
pub fn ReadCursor::read_u32(self : ReadCursor) -> UInt32 raise Mp4Error {
  self.require(4)
  let value = (self.data[self.position].to_uint() << 24) |
    (self.data[self.position + 1].to_uint() << 16) |
    (self.data[self.position + 2].to_uint() << 8) |
    self.data[self.position + 3].to_uint()
  self.position += 4
  value
}

///|
/// 符号なし 64-bit を Big Endian で読む。
pub fn ReadCursor::read_u64(self : ReadCursor) -> UInt64 raise Mp4Error {
  self.require(8)
  let mut value : UInt64 = 0UL
  for i = 0; i < 8; i = i + 1 {
    value = (value << 8) | self.data[self.position + i].to_uint64()
  }
  self.position += 8
  value
}

///|
/// 既存の [`BytesView`] をバッファとして読むカーソルを作る。
///
/// バイト列はコピーせず view を共有する。`base_offset` には view の先頭が
/// ファイル内で持つ位置を渡す。型付きボックスのペイロードのように、既に切り出された
/// 範囲を追加のコピーなしで読むために使う。`limits` を省略すると既定値になるため、
/// 呼び出し元のカーソルから引き継ぐ場合は明示的に渡す。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::from_view(b"abcd"[:], 16UL)
///   inspect(cursor.offset(), content="16")
///   inspect(cursor.read_u16(), content="24930")
/// }
/// ```
pub fn ReadCursor::from_view(
  view : BytesView,
  base_offset : UInt64,
  limits? : ParseLimits,
) -> ReadCursor {
  {
    data: view,
    position: 0,
    base_offset,
    limits: limits.unwrap_or(ParseLimits::default()),
  }
}

///|
/// 符号付き 8-bit を読む（2 の補数、符号拡張あり）。
pub fn ReadCursor::read_i8(self : ReadCursor) -> Int32 raise Mp4Error {
  let value = self.read_u8()
  if value >= 0x80 {
    value.reinterpret_as_int() - 0x100
  } else {
    value.reinterpret_as_int()
  }
}

///|
/// 符号付き 16-bit を Big Endian で読む（符号拡張あり）。
pub fn ReadCursor::read_i16(self : ReadCursor) -> Int32 raise Mp4Error {
  let value = self.read_u16()
  if value >= 0x8000 {
    value.reinterpret_as_int() - 0x10000
  } else {
    value.reinterpret_as_int()
  }
}

///|
/// 符号付き 32-bit を Big Endian で読む（2 の補数）。
pub fn ReadCursor::read_i32(self : ReadCursor) -> Int32 raise Mp4Error {
  self.read_u32().reinterpret_as_int()
}

///|
/// 符号付き 64-bit を Big Endian で読む（2 の補数）。
pub fn ReadCursor::read_i64(self : ReadCursor) -> Int64 raise Mp4Error {
  self.read_u64().reinterpret_as_int64()
}

///|
/// `i16.u16` の固定小数点数（16.16）を読む。
pub fn ReadCursor::read_fixed_16_16(
  self : ReadCursor,
) -> FixedPointNumber raise Mp4Error {
  let integer = self.read_i16()
  let fraction = self.read_u16()
  FixedPointNumber::new(integer, fraction)
}

///|
/// `i8.u8` の固定小数点数（8.8）を読む。
pub fn ReadCursor::read_fixed_8_8(
  self : ReadCursor,
) -> FixedPointNumber raise Mp4Error {
  let integer = self.read_i8()
  let fraction = self.read_u8()
  FixedPointNumber::new(integer, fraction)
}

///|
/// `u8.u8` の固定小数点数（8.8、符号なし整数部）を読む。
///
/// [`SmhdBox::balance`](gpui-mbt/mp4/boxes) のように整数部が符号なしの 8.8 に使う。
/// 整数部は生バイトをそのまま `0..=255` として読む。
pub fn ReadCursor::read_fixed_8_8_unsigned(
  self : ReadCursor,
) -> FixedPointNumber raise Mp4Error {
  let integer = self.read_u8()
  let fraction = self.read_u8()
  FixedPointNumber::new(integer.reinterpret_as_int(), fraction)
}

///|
/// `u16.u16` の固定小数点数（16.16、符号なし整数部）を読む。
///
/// サンプルエントリーの `horizresolution` / `samplerate` のように整数部が
/// 符号なしの 16.16 に使う。整数部は `0..=65535` として読む。
pub fn ReadCursor::read_fixed_16_16_unsigned(
  self : ReadCursor,
) -> FixedPointNumber raise Mp4Error {
  let integer = self.read_u16()
  let fraction = self.read_u16()
  FixedPointNumber::new(integer.reinterpret_as_int(), fraction)
}

///|
/// FourCC（生 4 バイト）を読む。
pub fn ReadCursor::read_fourcc(self : ReadCursor) -> FourCC raise Mp4Error {
  let bytes = self.read_bytes(4)
  { bytes, }
}

///|
/// `n` バイトをコピーして読む。
///
/// コピーの確保サイズが [`ParseLimits::max_allocation_size`] を超える場合は
/// [`ErrorKind::Unsupported`] で失敗し、過大な allocation を行わない。
pub fn ReadCursor::read_bytes(
  self : ReadCursor,
  n : Int32,
) -> Bytes raise Mp4Error {
  self.require(n)
  self.limits.check_allocation(n.to_uint64())
  let bytes = self.data[self.position:self.position + n].to_owned()
  self.position += n
  bytes
}

///|
/// `n` バイトの view を読む（コピーしない）。
pub fn ReadCursor::read_bytes_view(
  self : ReadCursor,
  n : Int32,
) -> BytesView raise Mp4Error {
  self.require(n)
  let view = self.data[self.position:self.position + n]
  self.position += n
  view
}

///|
/// 残り全部の view を読む（コピーしない）。
pub fn ReadCursor::read_remaining_view(self : ReadCursor) -> BytesView {
  let view = self.data[self.position:]
  self.position = self.data.length()
  view
}

///|
/// 残り全部をコピーして読む。
pub fn ReadCursor::read_remaining(self : ReadCursor) -> Bytes raise Mp4Error {
  let n = self.remaining()
  self.limits.check_allocation(n.to_uint64())
  let bytes = self.data[self.position:].to_owned()
  self.position = self.data.length()
  bytes
}

///|
/// `n` バイトを読み進めて、その範囲を読む新しいカーソルを返す。
///
/// 新しいカーソルの `base_offset` はこのカーソルの現在位置になり、
/// `ParseLimits` は引き継がれる。バイト列はコピーしない。
pub fn ReadCursor::sub_cursor(
  self : ReadCursor,
  n : Int32,
) -> ReadCursor raise Mp4Error {
  self.require(n)
  let view = self.data[self.position:self.position + n]
  let cursor : ReadCursor = {
    data: view,
    position: 0,
    base_offset: self.offset(),
    limits: self.limits,
  }
  self.position += n
  cursor
}
