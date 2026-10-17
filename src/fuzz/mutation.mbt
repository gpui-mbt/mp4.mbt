///|
/// 決定的な xorshift32 乱数。
pub struct XorShift32 {
  priv mut state : UInt32
}

///|
/// 種から作る。0 は 1 に置き換える。
pub fn XorShift32::new(seed : UInt32) -> XorShift32 {
  { state: if seed == 0U { 1U } else { seed }, }
}

///|
/// 次の 32-bit 値を返す。
pub fn XorShift32::next(self : XorShift32) -> UInt32 {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  x
}

///|
/// 入力の 1〜4 バイトを決定的に破壊したコピーを返す。
pub fn mutate_bytes(input : Bytes, seed : UInt32) -> Bytes {
  if input.length() == 0 {
    return b""
  }
  let rng = XorShift32::new(seed)
  let out = FixedArray::make(input.length(), b'\x00')
  for i in 0..<input.length() {
    out[i] = input[i]
  }
  let count = (rng.next() % 4U).reinterpret_as_int() + 1
  let mut i = 0
  while i < count {
    let index = (rng.next() % input.length().reinterpret_as_uint()).reinterpret_as_int()
    let mode = rng.next() % 3U
    let value = out[index].to_uint()
    out[index] = if mode == 0U {
      (value ^ (1U << (rng.next() % 8U).reinterpret_as_int()))
      .reinterpret_as_int()
      .to_byte()
    } else if mode == 1U {
      (value + 1U).to_byte()
    } else {
      0U.to_byte()
    }
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// 入力を 1 バイトずつ切り詰めた列を返す。
pub fn truncations(input : Bytes) -> Array[Bytes] {
  let out : Array[Bytes] = []
  let mut i = 0
  while i < input.length() {
    out.push(
      @bytes.ReadCursor::from_view(input[:i], 0UL).read_remaining() catch {
        _ => abort("invalid bytes")
      },
    )
    i = i + 1
  }
  out
}
