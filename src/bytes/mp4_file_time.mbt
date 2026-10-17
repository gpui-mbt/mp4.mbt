///|
/// MP4 ファイル内で使われる時刻形式（1904-01-01 からの経過秒数）。
///
/// 上流 `Mp4FileTime` に対応する。ISO/IEC 14496-12 の時刻フィールドは
/// 1904-01-01 00:00:00 UTC を起点とする秒数で表され、version 0 では 32-bit、
/// version 1 では 64-bit になる。値は整数のまま保持し、暗黙の float 丸めを
/// 行わない。
///
/// ```mbt check
/// test {
///   let t = @bytes.Mp4FileTime::from_secs(3600UL)
///   inspect(t.as_secs(), content="3600")
///   inspect(
///     @bytes.Mp4FileTime::from_unix_seconds(0UL).as_secs(),
///     content="2082844800",
///   )
///   inspect(@bytes.Mp4FileTime::default().as_secs(), content="0")
/// }
/// ```
pub struct Mp4FileTime {
  seconds : UInt64
} derive(Eq, Hash, Debug)

///|
pub extend Mp4FileTime with Eq::{equal, not_equal}

///|
pub extend Mp4FileTime with Hash::{hash, hash_combine}

///|
pub extend Mp4FileTime with Debug::{to_repr}

///|
/// 1904-01-01 からの経過秒数を指定して作成する。
pub fn Mp4FileTime::from_secs(seconds : UInt64) -> Mp4FileTime {
  { seconds, }
}

///|
/// 1904-01-01 からの経過秒数を返す。
pub fn Mp4FileTime::as_secs(self : Mp4FileTime) -> UInt64 {
  self.seconds
}

///|
/// UNIX EPOCH（1970-01-01 00:00:00 UTC）を起点とした経過秒数から作成する。
///
/// 上流は `Duration` を受け取るが、本実装は秒数（`UInt64`）を受け取る。
/// 1904-01-01 と 1970-01-01 の差 2082844800 秒を加算する。
pub fn Mp4FileTime::from_unix_seconds(unix_seconds : UInt64) -> Mp4FileTime {
  // 1904-01-01 から 1970-01-01 までの経過秒数
  let delta = 2082844800UL
  { seconds: unix_seconds + delta, }
}

///|
/// 時刻の比較（上流の `PartialOrd` / `Ord` に対応）。
pub impl Compare for Mp4FileTime with fn compare(
  self : Mp4FileTime,
  other : Mp4FileTime,
) {
  self.seconds.compare(other.seconds)
}

///|
pub extend Mp4FileTime with Compare::{compare, op_lt, op_gt, op_le, op_ge}

///|
pub impl Default for Mp4FileTime with fn default() {
  { seconds: 0UL, }
}

///|
pub extend Mp4FileTime with Default::{default}
