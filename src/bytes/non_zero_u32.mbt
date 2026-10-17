///|
/// 0 以外の 32-bit 符号なし整数。
///
/// 上流 `core::num::NonZeroU32` に対応する。`timescale` のように 0 を許すと
/// 暗黙のゼロ除算を招く値に使い、不正な 0 を型の入り口で拒否する。
///
/// ```mbt check
/// test {
///   inspect(@bytes.NonZeroU32::new(48000U).unwrap().get(), content="48000")
///   inspect(@bytes.NonZeroU32::new(0U) is None, content="true")
///   inspect(@bytes.NonZeroU32::default().get(), content="1")
/// }
/// ```
pub struct NonZeroU32 {
  value : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend NonZeroU32 with Eq::{equal, not_equal}

///|
pub extend NonZeroU32 with Hash::{hash, hash_combine}

///|
pub extend NonZeroU32 with Debug::{to_repr}

///|
/// 0 以外の値から作成する。0 の場合は `None` を返す。
pub fn NonZeroU32::new(value : UInt32) -> NonZeroU32? {
  if value == 0 {
    None
  } else {
    Some({ value, })
  }
}

///|
/// 最小値（1）を返す。
pub fn NonZeroU32::one() -> NonZeroU32 {
  { value: 1U, }
}

///|
/// 保持する値を返す。
pub fn NonZeroU32::get(self : NonZeroU32) -> UInt32 {
  self.value
}

///|
/// 32-bit 値として書く。
pub impl Encode for NonZeroU32 with fn encode(
  self : NonZeroU32,
  cursor : WriteCursor,
) -> Unit raise Mp4Error {
  cursor.write_u32(self.value)
}

///|
pub extend NonZeroU32 with Encode::{encode}

///|
/// 32-bit 値を読み、0 の場合は [`ErrorKind::InvalidInput`]
/// （"Expected a non-zero integer, but got 0"）で失敗する。
pub impl Decode for NonZeroU32 with fn decode(cursor : ReadCursor) -> NonZeroU32 raise Mp4Error {
  let value = cursor.read_u32()
  match NonZeroU32::new(value) {
    Some(non_zero) => non_zero
    None =>
      raise Mp4Error::invalid_input("Expected a non-zero integer, but got 0")
  }
}

///|
pub extend NonZeroU32 with Decode::{decode}

///|
pub impl Default for NonZeroU32 with fn default() {
  NonZeroU32::one()
}

///|
pub extend NonZeroU32 with Default::{default}
