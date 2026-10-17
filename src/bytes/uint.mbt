///|
/// 任意のビット数の非負の整数（ビットフィールド値）。
///
/// 上流 `Uint<T, BITS, OFFSET>` に対応する。上流が型パラメータで表す
/// `bits`（値のビット数）と `offset`（親の整数内でのオフセット位置）は
/// 値として保持し、不変条件は「保持する値は常に `bits` ビットで表現できる
/// 範囲（`0..=2^bits - 1`）に収まること」。
///
/// [`Uint::from_bits`] は取り出し専用で常にこの条件を満たし、
/// [`Uint::new`] は入り口で検査する。
///
/// ```mbt check
/// test {
///   // バイトの上位 3 ビットを取り出す
///   let high = @bytes.Uint::from_bits(0b1010_1100UL, bits=3, offset=5)
///   inspect(high.get(), content="5")
///   // 範囲外の値は作れない
///   inspect(@bytes.Uint::new(8UL, bits=3, offset=0) is None, content="true")
/// }
/// ```
pub struct Uint {
  value : UInt64
  bits : Int32
  offset : Int32
} derive(Eq, Hash, Debug)

///|
pub extend Uint with Eq::{equal, not_equal}

///|
pub extend Uint with Hash::{hash, hash_combine}

///|
pub extend Uint with Debug::{to_repr}

///|
/// 値とビット幅・オフセットを指定して作成する。
///
/// `bits < 1`、`offset < 0`、`bits + offset > 64` の場合、または `value` が
/// `bits` ビットに収まらない場合は `None` を返す。上流の `Uint::new` が
/// 呼び出し側に委ねている不変条件を、ここでは入り口で検査する。
pub fn Uint::new(value : UInt64, bits~ : Int32, offset~ : Int32) -> Uint? {
  if bits < 1 || offset < 0 || bits + offset > 64 {
    return None
  }
  if bits < 64 && value >= 1UL << bits {
    return None
  }
  Some({ value, bits, offset, })
}

///|
/// `raw` の `offset` ビット目（LSB 起点）から `bits` ビット分を取り出した値を作る。
///
/// 上流の `Uint::from_bits(v)` に対応し、対象範囲外のビットはマスクされる。
/// `bits` / `offset` の組み合わせが不正な場合（上流なら型パラメータの時点で
/// 弾かれる範囲）はプログラムの誤りとして abort する。
pub fn Uint::from_bits(raw : UInt64, bits~ : Int32, offset~ : Int32) -> Uint {
  if bits < 1 || offset < 0 || bits + offset > 64 {
    abort("invalid Uint field descriptor: bits=\{bits}, offset=\{offset}")
  }
  let mask = if bits >= 64 { 0xFFFFFFFFFFFFFFFFUL } else { (1UL << bits) - 1UL }
  { value: (raw >> offset) & mask, bits, offset, }
}

///|
/// 保持する整数値を返す（上流 `Uint::get`）。
pub fn Uint::get(self : Uint) -> UInt64 {
  self.value
}

///|
/// この値が親の整数内で占めるビット列を返す（`value << offset`）。
///
/// 上流 `Uint::to_bits` に対応する。`offset == 0` の場合は
/// [`Uint::get`] と同じ値になる。
pub fn Uint::to_bits(self : Uint) -> UInt64 {
  self.value << self.offset
}

///|
/// 値が 0 でないかどうかを返す（1 ビットのフラグ用。上流 `Uint::as_bool`）。
pub fn Uint::as_bool(self : Uint) -> Bool {
  self.value != 0UL
}
