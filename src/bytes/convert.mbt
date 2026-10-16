///|
/// `Double` が整数を正確に表せる最大値（2^53）。
pub const MAX_EXACT_DOUBLE_INTEGER : UInt64 = 9007199254740992UL

///|
/// `UInt64` のファイル位置や長さを `Int` のインデックスへ変換する。
///
/// `Int` は 32-bit であり、`Bytes`/`Array` のインデックスとして使えるのは
/// `0..=2^31-1` だけである。範囲外は暗黙に丸めず、[`ErrorKind::InvalidInput`]
/// として失敗する。
#callsite(autofill(loc))
pub fn uint64_to_index(
  value : UInt64,
  what : StringView,
  loc~ : SourceLoc,
) -> Int32 raise Mp4Error {
  if value > 2147483647UL {
    raise Mp4Error::invalid_input(
      "\{what} \{value} does not fit in an Int index",
      loc~,
    )
  }
  value.to_int()
}

///|
/// `UInt64` を `Double` へ変換する。2^53 を超える値は丸めが起き得るため、
/// [`MAX_EXACT_DOUBLE_INTEGER`] を超える場合は失敗する。
///
/// 表示や概算のために丸めを許す場合は呼び出し側で
/// [`UInt64::to_double`] を明示的に使う。
#callsite(autofill(loc))
pub fn uint64_to_exact_double(
  value : UInt64,
  loc~ : SourceLoc,
) -> Double raise Mp4Error {
  if value > MAX_EXACT_DOUBLE_INTEGER {
    raise Mp4Error::invalid_input(
      "UInt64 value \{value} cannot be represented exactly as Double",
      loc~,
    )
  }
  value.to_double()
}
