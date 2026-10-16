///|
/// MSB 先のビット読み取りカーソル。
///
/// NAL / AAC / AV1 / VP9 などのビット列解析で共用する。読み取りは成功した
/// 場合だけ位置を進め、終端を超える読み取りは
/// [`ErrorKind::InvalidInput`]（上流の SPS リーダーと同じ分類）で失敗する。
///
/// 位置は「バッファ先頭からのビット数」で表し、`byte_position * 8 + bit_position`
/// に対応する。`bit_position` は次の読み取り位置の、現在のバイト内での
/// MSB からのオフセット（0..=7）である。
pub struct BitReader {
  data : Bytes
  mut byte_position : Int32
  mut bit_position : Int32
}

///|
/// バッファ全体を読むビットリーダーを作る。
pub fn BitReader::new(data : Bytes) -> BitReader {
  { data, byte_position: 0, bit_position: 0, }
}

///|
/// 読み取り済みのビット数を返す。
pub fn BitReader::position(self : BitReader) -> Int32 {
  self.byte_position * 8 + self.bit_position
}

///|
/// バッファ全体のビット数を返す。
pub fn BitReader::bit_length(self : BitReader) -> Int32 {
  self.data.length() * 8
}

///|
/// 残りのビット数を返す。
pub fn BitReader::remaining_bits(self : BitReader) -> Int32 {
  self.bit_length() - self.position()
}

///|
/// バイト境界に整列しているかどうかを返す。
pub fn BitReader::is_byte_aligned(self : BitReader) -> Bool {
  self.bit_position == 0
}

///|
/// `n` ビット読めることを検査する。
///
/// 短い入力は上流の SPS リーダーと同じ `InvalidInput` として扱う（バイト
/// カーソルの `InsufficientBuffer` と異なり、固定長バッファの解析では追加入力で
/// 回復できない）。
fn BitReader::require(
  self : BitReader,
  n : Int32,
) -> Unit raise @bytes.Mp4Error {
  let available = self.remaining_bits()
  if n > available {
    raise @bytes.Mp4Error::invalid_input(
      "bit stream is truncated: required \{n} bits, but only \{available} bits remain",
    )
  }
}

///|
/// 現在位置のビットを 1 つ消費して次へ進む（終端検査済みであることが前提）。
fn BitReader::consume_bit(self : BitReader) -> UInt32 {
  let bit = (self.data[self.byte_position].to_uint() >> (7 - self.bit_position)) &
    1
  if self.bit_position == 7 {
    self.bit_position = 0
    self.byte_position += 1
  } else {
    self.bit_position += 1
  }
  bit
}

///|
/// 1 ビットを読む（MSB 先、0 または 1）。
pub fn BitReader::read_bit(self : BitReader) -> UInt32 raise @bytes.Mp4Error {
  self.require(1)
  self.consume_bit()
}

///|
/// `n` ビット（0..=32）を MSB 先で読む。
///
/// ```mbt check
/// test {
///   let reader = @bitstream.BitReader::new(b"\xB2")
///   inspect(reader.read_bits(4), content="11")
///   inspect(reader.read_bits(4), content="2")
/// }
/// ```
pub fn BitReader::read_bits(
  self : BitReader,
  n : Int32,
) -> UInt32 raise @bytes.Mp4Error {
  if n < 0 || n > 32 {
    raise @bytes.Mp4Error::invalid_input("bit width must be 0..=32: \{n}")
  }
  self.require(n)
  let mut value : UInt32 = 0
  let mut i = 0
  while i < n {
    value = (value << 1) | self.consume_bit()
    i += 1
  }
  value
}

///|
/// `n` ビット（0..=64）を MSB 先で読む。
pub fn BitReader::read_bits64(
  self : BitReader,
  n : Int32,
) -> UInt64 raise @bytes.Mp4Error {
  if n < 0 || n > 64 {
    raise @bytes.Mp4Error::invalid_input("bit width must be 0..=64: \{n}")
  }
  self.require(n)
  let mut value : UInt64 = 0UL
  let mut i = 0
  while i < n {
    value = (value << 1) | self.consume_bit().to_uint64()
    i += 1
  }
  value
}

///|
/// `n` ビット読み飛ばす。
pub fn BitReader::skip_bits(
  self : BitReader,
  n : Int32,
) -> Unit raise @bytes.Mp4Error {
  if n < 0 {
    raise @bytes.Mp4Error::invalid_input(
      "skip length must be non-negative: \{n}",
    )
  }
  self.require(n)
  let total = self.position() + n
  self.byte_position = total / 8
  self.bit_position = total % 8
}

///|
/// 次のバイト境界まで読み飛ばす（既に整列済みなら何もしない）。
pub fn BitReader::byte_align(self : BitReader) -> Unit {
  if self.bit_position != 0 {
    self.bit_position = 0
    self.byte_position += 1
  }
}
