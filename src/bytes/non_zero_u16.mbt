///|
/// 0 以外の 16-bit 符号なし整数。
///
/// 上流 `core::num::NonZeroU16` に対応する。サンプルエントリーの
/// `data_reference_index` のように 0 を許さない 1-based 参照に使い、
/// 不正な 0 を型の入り口で拒否する。
///
/// ```mbt check
/// test {
///   inspect(@bytes.NonZeroU16::new(1U).unwrap().get(), content="1")
///   inspect(@bytes.NonZeroU16::new(0U) is None, content="true")
///   inspect(@bytes.NonZeroU16::default().get(), content="1")
/// }
/// ```
pub struct NonZeroU16 {
  value : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend NonZeroU16 with Eq::{equal, not_equal}

///|
pub extend NonZeroU16 with Hash::{hash, hash_combine}

///|
pub extend NonZeroU16 with Debug::{to_repr}

///|
/// 0 以外の値から作成する。0 の場合は `None` を返す。
///
/// `value` は 16-bit に収まる前提（`0 < value <= 0xFFFF`）。上流
/// `NonZeroU16::new(u16)` は u16 値しか受け取らないため、ここでも
/// 16-bit を超える値は `None` とする。
pub fn NonZeroU16::new(value : UInt32) -> NonZeroU16? {
  if value == 0 || value > 0xFFFF {
    None
  } else {
    Some({ value, })
  }
}

///|
/// 最小値（1）を返す。
pub fn NonZeroU16::one() -> NonZeroU16 {
  { value: 1U, }
}

///|
/// 保持する値を返す。
pub fn NonZeroU16::get(self : NonZeroU16) -> UInt32 {
  self.value
}

///|
/// 16-bit 値として書く。
pub impl Encode for NonZeroU16 with fn encode(
  self : NonZeroU16,
  cursor : WriteCursor,
) -> Unit raise Mp4Error {
  cursor.write_u16(self.value)
}

///|
pub extend NonZeroU16 with Encode::{encode}

///|
/// 16-bit 値を読み、0 の場合は [`ErrorKind::InvalidInput`]
/// （"Expected a non-zero integer, but got 0"）で失敗する。
pub impl Decode for NonZeroU16 with fn decode(cursor : ReadCursor) -> NonZeroU16 raise Mp4Error {
  let value = cursor.read_u16()
  match NonZeroU16::new(value) {
    Some(non_zero) => non_zero
    None =>
      raise Mp4Error::invalid_input("Expected a non-zero integer, but got 0")
  }
}

///|
pub extend NonZeroU16 with Decode::{decode}

///|
pub impl Default for NonZeroU16 with fn default() {
  NonZeroU16::one()
}

///|
pub extend NonZeroU16 with Default::{default}
