///|
/// ボックスのサイズ表現。
///
/// ISO/IEC 14496-12 の box は 32-bit の `size` フィールドを持つ。値が 1 のときは
/// 32-bit フィールドの後（種別と usertype の後）に 64-bit の `largesize` が続き、
/// 0 のときは「ファイル末尾まで」を意味する。この符号化上の分岐を variant で区別する。
///
/// `size` フィールドは 1 のときも先頭 4 バイトに `1` が書かれ、実際の値は
/// `largesize` 側に持つ（[`U64`] の `get` は `largesize` の値を返す）。
pub(all) enum BoxSize {
  /// 32-bit の `size` フィールドで表されるサイズ
  U32(UInt32)
  /// `size==1` として 64-bit の `largesize` フィールドで表されるサイズ
  U64(UInt64)
} derive(Eq, Hash, Debug)

///|
pub extend BoxSize with Eq::{equal, not_equal}

///|
pub extend BoxSize with Hash::{hash, hash_combine}

///|
pub extend BoxSize with Debug::{to_repr}

///|
/// ファイル末尾に位置する可変長ボックスを表す値（32-bit `size==0`）。
///
/// [`BoxHeader::decode`] は値を許容するだけで、バッファ末尾までの拡張は
/// [`BoxHeader::decode_header_and_payload`] が行う。
pub fn BoxSize::variable_size() -> BoxSize {
  U32(0)
}

///|
/// エンコード用の特別な値（`size==1` + `largesize==0`）。
///
/// 64-bit サイズ符号化でヘッダー幅を確保するために使う。デコードでは
/// [`BoxHeader::decode_header_and_payload`] が可変長として扱わずエラーにする。
pub fn BoxSize::large_variable_size() -> BoxSize {
  U64(0)
}

///|
/// ボックス種別とペイロードサイズから合計サイズを作る。
///
/// `4 + 種別フィールド + payload_size` が 32-bit に収まる場合は [`U32`]、
/// 収まらない場合は largesize 分の 8 バイトを加えた [`U64`] を返す。
/// 合計が 64-bit を超える入力は [`@bytes.ErrorKind::InvalidInput`] で拒否する。
pub fn BoxSize::with_payload_size(
  box_type : @bytes.BoxType,
  payload_size : UInt64,
) -> BoxSize raise @bytes.Mp4Error {
  let base = 4UL + box_type.external_size().to_uint64()
  if payload_size > 0xFFFFFFFFFFFFFFFFUL - base {
    raise @bytes.Mp4Error::invalid_input(
      "box size overflows 64 bits: payload_size=\{payload_size}",
    )
  }
  let size = base + payload_size
  if size <= 0xFFFFFFFFUL {
    U32(size.to_uint())
  } else if size > 0xFFFFFFFFFFFFFFFFUL - 8UL {
    raise @bytes.Mp4Error::invalid_input(
      "box size overflows 64 bits: payload_size=\{payload_size}",
    )
  } else {
    U64(size + 8UL)
  }
}

///|
/// ボックス全体のサイズ値を返す。
pub fn BoxSize::get(self : BoxSize) -> UInt64 {
  match self {
    U32(size) => size.to_uint64()
    U64(size) => size
  }
}

///|
/// ヘッダー内のサイズフィールドのバイト数を返す（[`U32`] は 4、[`U64`] は 4 + 8）。
pub fn BoxSize::external_size(self : BoxSize) -> Int32 {
  match self {
    U32(_) => 4
    U64(_) => 4 + 8
  }
}

///|
/// 最小幅の符号化形式へ正規化したサイズを返す。
///
/// - [`U32`] はそのまま（すでに canonical）。
/// - [`U64`] は largesize 分を除いた payload サイズから
///   [`BoxSize::with_payload_size`] で再計算した形式へ変換する。
/// - [`U64(0)`]（[`BoxSize::large_variable_size`]）はペイロードサイズを持たない
///   プレースホルダのため、そのまま返す。
///
/// [`Encode`][@bytes.Encode] は保持している variant をそのまま書くため
/// デコード直後の再エンコードは入力バイト列を保つ（wire-preserving）。この関数は
/// それとは別に、形式だけを最小幅へ畳む（canonical）。合計サイズがヘッダー長未満の
/// [`U64`] は [`@bytes.ErrorKind::InvalidData`] で拒否する。
pub fn BoxSize::to_canonical(
  self : BoxSize,
  box_type : @bytes.BoxType,
) -> BoxSize raise @bytes.Mp4Error {
  match self {
    U32(_) => self
    U64(0) => self
    U64(size) => {
      let header_size = self.external_size() + box_type.external_size()
      if size < header_size.to_uint64() {
        raise @bytes.Mp4Error::invalid_data(
          "box size is smaller than header size",
        )
      }
      BoxSize::with_payload_size(box_type, size - header_size.to_uint64())
    }
  }
}
