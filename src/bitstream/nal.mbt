///|
/// NAL 長フィールドのバイト数。
pub(all) enum LengthSize {
  /// 1 バイト
  One
  /// 2 バイト
  Two
  /// 3 バイト
  Three
  /// 4 バイト
  Four
} derive(Eq, Hash, Debug)

///|
pub extend LengthSize with Eq::{equal, not_equal}

///|
pub extend LengthSize with Hash::{hash, hash_combine}

///|
pub extend LengthSize with Debug::{to_repr}

///|
/// バイト数を返す。
pub fn LengthSize::bytes(self : LengthSize) -> Int32 {
  match self {
    One => 1
    Two => 2
    Three => 3
    Four => 4
  }
}

///|
/// `length_size_minus_one` を返す。
pub fn LengthSize::length_size_minus_one(self : LengthSize) -> UInt32 {
  (self.bytes() - 1).reinterpret_as_uint()
}

///|
/// `length_size_minus_one` から作る。2 (3 バイト) は仕様上 reserved のため拒否する。
pub fn LengthSize::from_length_size_minus_one(
  value : UInt32,
) -> LengthSize raise @bytes.Mp4Error {
  match value {
    0U => One
    1U => Two
    3U => Four
    _ =>
      raise @bytes.Mp4Error::invalid_input(
        "length_size_minus_one must be 0, 1 or 3, got \{value}",
      )
  }
}
