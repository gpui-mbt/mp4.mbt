///|
/// ISO/IEC 14496-12 の `uuid` 拡張ボックス種別（16 バイトの usertype）。
///
/// 生 16 バイトをそのまま保持し、文字列化した結果からは復元しない
/// （不明な usertype も lossless に扱えるようにするため）。
pub struct Uuid {
  bytes : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend Uuid with Eq::{equal, not_equal}

///|
pub extend Uuid with Hash::{hash, hash_combine}

///|
pub extend Uuid with Debug::{to_repr}

///|
/// 16 バイトから UUID 種別を作る。
///
/// ```mbt check
/// test {
///   let uuid = @bytes.Uuid::from_bytes(
///     b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
///   )
///   inspect(uuid.to_string(), content="00010203-0405-0607-0809-0a0b0c0d0e0f")
///   inspect(uuid.as_bytes().length(), content="16")
/// }
/// ```
pub fn Uuid::from_bytes(bytes : Bytes) -> Uuid raise Mp4Error {
  if bytes.length() != 16 {
    raise Mp4Error::invalid_input(
      "uuid box type must be 16 bytes, but got \{bytes.length()}",
    )
  }
  { bytes, }
}

///|
/// 生 16 バイトを返す。
pub fn Uuid::as_bytes(self : Uuid) -> Bytes {
  self.bytes
}

///|
/// RFC 4122 の 8-4-4-4-12 形式（小文字 hex）で表す。
///
/// この形式は表示専用であり、[`Uuid::from_bytes`] へ戻すためのものではない。
pub fn Uuid::to_string(self : Uuid) -> String {
  let buffer = StringBuilder::StringBuilder()
  for i = 0; i < 16; i = i + 1 {
    if i == 4 || i == 6 || i == 8 || i == 10 {
      buffer.write_string("-")
    }
    buffer.write_string(self.bytes[i].to_hex())
  }
  buffer.to_string()
}

///|
/// ボックスの種別。
///
/// 通常の 4 文字種別は [`FourCC`] で、`uuid` 拡張は [`Uuid`] で保持する。
/// どちらの場合も生バイトを保持し、文字列化で失われない。
pub(all) enum BoxType {
  /// 4 文字で表現される通常のボックス種別
  Normal(FourCC)
  /// `uuid` 拡張の 16 バイト種別
  Uuid(Uuid)
} derive(Eq, Hash, Debug)

///|
pub extend BoxType with Eq::{equal, not_equal}

///|
pub extend BoxType with Hash::{hash, hash_combine}

///|
pub extend BoxType with Debug::{to_repr}

///|
/// 種別を表す生バイト列を返す（通常 4 バイト、uuid 16 バイト）。
pub fn BoxType::as_bytes(self : BoxType) -> Bytes {
  match self {
    Normal(fourcc) => fourcc.as_bytes()
    Uuid(uuid) => uuid.as_bytes()
  }
}

///|
/// ヘッダー内の種別フィールドのバイト数を返す（通常 4、uuid 4 + 16）。
pub fn BoxType::external_size(self : BoxType) -> Int32 {
  match self {
    Normal(_) => 4
    Uuid(_) => 4 + 16
  }
}

///|
/// 自分が `expected` と同じ種別であることを検査する。
///
/// 異なる場合は [`ErrorKind::InvalidData`] で失敗する（上流と同じ分類）。
pub fn BoxType::expect(
  self : BoxType,
  expected : BoxType,
) -> Unit raise Mp4Error {
  if self != expected {
    raise Mp4Error::invalid_data(
      "Expected box type `\{expected.to_string()}`, but got `\{self.to_string()}`",
    )
  }
}

///|
/// 種別を表示用の文字列にする。
///
/// 通常の 4 文字種別は [`FourCC::to_string`] に従い、表示不能なバイトは hex 形式に
/// なる。uuid は `Uuid::to_string` の 8-4-4-4-12 形式になる。
pub fn BoxType::to_string(self : BoxType) -> String {
  match self {
    Normal(fourcc) => fourcc.to_string()
    Uuid(uuid) => uuid.to_string()
  }
}
