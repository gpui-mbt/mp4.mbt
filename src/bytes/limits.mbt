///|
/// 解析時に確保してよい資源の上限。
///
/// 信頼できない入力が宣言する長さをそのまま信じて過大な allocation を行わない
/// ために使う。既定値は [`ParseLimits::DEFAULT_MAX_ALLOCATION_SIZE`] と
/// [`ParseLimits::DEFAULT_MAX_NESTING_DEPTH`] で、[`ParseLimits::new`] で
/// 変更できる。
pub struct ParseLimits {
  max_allocation_size : UInt64
  max_nesting_depth : Int32
} derive(Eq, Debug)

///|
pub extend ParseLimits with Eq::{equal, not_equal}

///|
pub extend ParseLimits with Debug::{to_repr}

///|
/// 1 回の確保で許可する既定の最大バイト数（1 GiB）。
///
/// MoonBit の `Bytes`/`Array` の長さは `Int`（32-bit、正の範囲は約 2 GiB）で
/// 表されるため、この既定値は単一の確保としては実質的に上限に近い。
pub const DEFAULT_MAX_ALLOCATION_SIZE : UInt64 = 1073741824UL

///|
/// box などの入れ子の既定の最大深さ。
pub const DEFAULT_MAX_NESTING_DEPTH : Int32 = 64

///|
/// 上限値を指定して作成する。省略した項目には既定値を使う。
pub fn ParseLimits::new(
  max_allocation_size? : UInt64,
  max_nesting_depth? : Int32,
) -> ParseLimits {
  {
    max_allocation_size: max_allocation_size.unwrap_or(
      DEFAULT_MAX_ALLOCATION_SIZE,
    ),
    max_nesting_depth: max_nesting_depth.unwrap_or(DEFAULT_MAX_NESTING_DEPTH),
  }
}

///|
pub impl Default for ParseLimits with fn default() {
  ParseLimits::new()
}

///|
/// 1 回の確保で許可する最大バイト数を返す。
pub fn ParseLimits::max_allocation_size(self : ParseLimits) -> UInt64 {
  self.max_allocation_size
}

///|
/// box などの入れ子の最大深さを返す。
pub fn ParseLimits::max_nesting_depth(self : ParseLimits) -> Int32 {
  self.max_nesting_depth
}

///|
/// `size` バイトの確保が上限内かを検査する。
///
/// 上限を超える場合は [`ErrorKind::Unsupported`] のエラーを返す。入力が
/// 未取得であること（[`ErrorKind::InsufficientBuffer`]）とは区別する。
#callsite(autofill(loc))
pub fn ParseLimits::check_allocation(
  self : ParseLimits,
  size : UInt64,
  loc~ : SourceLoc,
) -> Unit raise Mp4Error {
  if size > self.max_allocation_size {
    raise Mp4Error::unsupported(
      "allocation of \{size} bytes exceeds ParseLimits.max_allocation_size=\{self.max_allocation_size}",
      loc~,
    )
  }
}

///|
/// 深さ `depth`（トップレベルを 1 とする）が上限内かを検査する。
#callsite(autofill(loc))
pub fn ParseLimits::check_nesting_depth(
  self : ParseLimits,
  depth : Int32,
  loc~ : SourceLoc,
) -> Unit raise Mp4Error {
  if depth > self.max_nesting_depth {
    raise Mp4Error::unsupported(
      "nesting depth \{depth} exceeds ParseLimits.max_nesting_depth=\{self.max_nesting_depth}",
      loc~,
    )
  }
}

///|
pub extend ParseLimits with Default::{default}
