///|
/// Big Endian の書き込みカーソル。
///
/// 書き込み先は伸長可能なバッファであり、容量不足のエラーは起きない。
/// 数値は指定幅の下位ビットだけが書かれ（上位ビットは切り捨てられる）、
/// 幅の上限は呼び出し側ではなく型（`UInt` = 32-bit、`UInt64` = 64-bit）で決まる。
///
/// ```mbt check
/// test {
///   let writer = @bytes.WriteCursor::new()
///   writer.write_u16(0x1234)
///   writer.write_u8(0x56)
///   inspect(writer.to_bytes() == b"\x12\x34\x56", content="true")
/// }
/// ```
pub struct WriteCursor {
  buffer : Buffer
}

///|
/// 空の書き込みカーソルを作る。
pub fn WriteCursor::new() -> WriteCursor {
  { buffer: Buffer::Buffer(), }
}

///|
/// これまでに書き込んだバイト数を返す。
pub fn WriteCursor::position(self : WriteCursor) -> Int32 {
  self.buffer.length()
}

///|
/// 書き込んだ内容を `Bytes` として返す。
pub fn WriteCursor::to_bytes(self : WriteCursor) -> Bytes {
  self.buffer.to_bytes()
}

///|
/// 書き込み内容を破棄して空に戻す。
pub fn WriteCursor::reset(self : WriteCursor) -> Unit {
  self.buffer.reset()
}

///|
/// 下位 8-bit を書く。
pub fn WriteCursor::write_u8(self : WriteCursor, value : UInt32) -> Unit {
  self.buffer.write_byte((value & 0xFF).reinterpret_as_int().to_byte())
}

///|
/// 下位 16-bit を Big Endian で書く。
pub fn WriteCursor::write_u16(self : WriteCursor, value : UInt32) -> Unit {
  self.write_u8(value >> 8)
  self.write_u8(value)
}

///|
/// 下位 24-bit を Big Endian で書く。
pub fn WriteCursor::write_u24(self : WriteCursor, value : UInt32) -> Unit {
  self.write_u8(value >> 16)
  self.write_u8(value >> 8)
  self.write_u8(value)
}

///|
/// 32-bit を Big Endian で書く。
pub fn WriteCursor::write_u32(self : WriteCursor, value : UInt32) -> Unit {
  self.write_u8(value >> 24)
  self.write_u8(value >> 16)
  self.write_u8(value >> 8)
  self.write_u8(value)
}

///|
/// 64-bit を Big Endian で書く。
pub fn WriteCursor::write_u64(self : WriteCursor, value : UInt64) -> Unit {
  self.write_u32((value >> 32).to_uint())
  self.write_u32(value.to_uint())
}

///|
/// 8-bit を 2 の補数で書く。
pub fn WriteCursor::write_i8(self : WriteCursor, value : Int32) -> Unit {
  self.write_u8((value & 0xFF).reinterpret_as_uint())
}

///|
/// 16-bit を 2 の補数で Big Endian に書く。
pub fn WriteCursor::write_i16(self : WriteCursor, value : Int32) -> Unit {
  self.write_u16((value & 0xFFFF).reinterpret_as_uint())
}

///|
/// 32-bit を 2 の補数で Big Endian に書く。
pub fn WriteCursor::write_i32(self : WriteCursor, value : Int32) -> Unit {
  self.write_u32(value.reinterpret_as_uint())
}

///|
/// 64-bit を 2 の補数で Big Endian に書く。
pub fn WriteCursor::write_i64(self : WriteCursor, value : Int64) -> Unit {
  self.write_u64(value.reinterpret_as_uint64())
}

///|
/// `i16.u16` の固定小数点数（16.16）を書く。
pub fn WriteCursor::write_fixed_16_16(
  self : WriteCursor,
  value : FixedPointNumber,
) -> Unit {
  self.write_i16(value.integer())
  self.write_u16(value.fraction())
}

///|
/// `i8.u8` の固定小数点数（8.8）を書く。
pub fn WriteCursor::write_fixed_8_8(
  self : WriteCursor,
  value : FixedPointNumber,
) -> Unit {
  self.write_i8(value.integer())
  self.write_u8(value.fraction())
}

///|
/// FourCC の 4 バイトを書く。
pub fn WriteCursor::write_fourcc(self : WriteCursor, value : FourCC) -> Unit {
  self.buffer.write_bytes(value.as_bytes())
}

///|
/// バイト列をそのまま書く。
pub fn WriteCursor::write_bytes(self : WriteCursor, value : Bytes) -> Unit {
  self.buffer.write_bytes(value)
}

///|
/// バイト列の view をそのまま書く。
pub fn WriteCursor::write_bytes_view(
  self : WriteCursor,
  value : BytesView,
) -> Unit {
  self.buffer.write_bytes(value)
}
