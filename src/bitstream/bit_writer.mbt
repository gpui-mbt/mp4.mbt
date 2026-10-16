///|
/// MSB 先のビット書き込みカーソル。
///
/// 書き込み先は伸長可能なバッファであり、容量不足のエラーは起きない。
/// [`BitWriter::to_bytes`] は端数を 0 で埋めてバイト列を返す。
pub struct BitWriter {
  buffer : Buffer
  mut pending : UInt32
  mut pending_bits : Int32
}

///|
/// 空のビットライターを作る。
pub fn BitWriter::new() -> BitWriter {
  { buffer: Buffer::Buffer(), pending: 0U, pending_bits: 0, }
}

///|
/// これまでに書き込んだビット数を返す。
pub fn BitWriter::position(self : BitWriter) -> Int32 {
  self.buffer.length() * 8 + self.pending_bits
}

///|
/// 1 ビットを書く（`value` の最下位ビットを使う）。
pub fn BitWriter::write_bit(self : BitWriter, value : UInt32) -> Unit {
  self.pending = (self.pending << 1) | (value & 1)
  self.pending_bits += 1
  if self.pending_bits == 8 {
    self.buffer.write_byte(self.pending.reinterpret_as_int().to_byte())
    self.pending = 0U
    self.pending_bits = 0
  }
}

///|
/// `value` の下位 `n` ビット（0..=32）を MSB 先で書く。
///
/// ```mbt check
/// test {
///   let writer = @bitstream.BitWriter::new()
///   writer.write_bits(0xB2, 8)
///   inspect(writer.to_bytes() == b"\xB2", content="true")
/// }
/// ```
pub fn BitWriter::write_bits(
  self : BitWriter,
  value : UInt32,
  n : Int32,
) -> Unit raise @bytes.Mp4Error {
  if n < 0 || n > 32 {
    raise @bytes.Mp4Error::invalid_input("bit width must be 0..=32: \{n}")
  }
  let mut i = n - 1
  while i >= 0 {
    self.write_bit(value >> i)
    i -= 1
  }
}

///|
/// `value` の下位 `n` ビット（0..=64）を MSB 先で書く。
pub fn BitWriter::write_bits64(
  self : BitWriter,
  value : UInt64,
  n : Int32,
) -> Unit raise @bytes.Mp4Error {
  if n < 0 || n > 64 {
    raise @bytes.Mp4Error::invalid_input("bit width must be 0..=64: \{n}")
  }
  let mut i = n - 1
  while i >= 0 {
    self.write_bit((value >> i).to_uint())
    i -= 1
  }
}

///|
/// 0 ビットを `n` 個書く。
pub fn BitWriter::skip_bits(
  self : BitWriter,
  n : Int32,
) -> Unit raise @bytes.Mp4Error {
  if n < 0 {
    raise @bytes.Mp4Error::invalid_input(
      "skip length must be non-negative: \{n}",
    )
  }
  let mut i = 0
  while i < n {
    self.write_bit(0U)
    i += 1
  }
}

///|
/// 端数を 0 で埋めて次のバイト境界に整列する（既に整列済みなら何もしない）。
pub fn BitWriter::byte_align(self : BitWriter) -> Unit {
  while self.pending_bits != 0 {
    self.write_bit(0U)
  }
}

///|
/// 端数を 0 で埋めて、これまでに書いた内容を `Bytes` として返す。
pub fn BitWriter::to_bytes(self : BitWriter) -> Bytes {
  self.byte_align()
  self.buffer.to_bytes()
}

///|
/// 書き込み内容を破棄して空に戻す。
pub fn BitWriter::reset(self : BitWriter) -> Unit {
  self.buffer.reset()
  self.pending = 0U
  self.pending_bits = 0
}
