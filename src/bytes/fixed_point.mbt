///|
/// 固定小数点数（integer.fraction）。
///
/// 上流 `FixedPointNumber<I, F>` の integer/fraction を 1 つの型に統合したもの。
/// ビット幅（例: `i16.u16` の 16.16、`i8.u8` の 8.8）は読み書きする API
/// （[`ReadCursor::read_fixed_16_16`] など）が決める。
pub struct FixedPointNumber {
  integer : Int32
  fraction : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend FixedPointNumber with Eq::{equal, not_equal}

///|
pub extend FixedPointNumber with Hash::{hash, hash_combine}

///|
pub extend FixedPointNumber with Debug::{to_repr}

///|
/// 整数部と小数部から作成する。
pub fn FixedPointNumber::new(
  integer : Int32,
  fraction : UInt32,
) -> FixedPointNumber {
  { integer, fraction, }
}

///|
/// 整数部を返す。
pub fn FixedPointNumber::integer(self : FixedPointNumber) -> Int32 {
  self.integer
}

///|
/// 小数部を返す。
pub fn FixedPointNumber::fraction(self : FixedPointNumber) -> UInt32 {
  self.fraction
}

///|
/// `fraction_bits` ビットの小数部として `Double` に変換する。
pub fn FixedPointNumber::to_double(
  self : FixedPointNumber,
  fraction_bits : Int32,
) -> Double {
  self.integer.to_double() +
  self.fraction.to_double() / (1UL << fraction_bits).to_double()
}
