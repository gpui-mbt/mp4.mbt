///|
/// [`MdhdBox`](gpui-mbt/mp4/boxes) の `language` 用の 3 文字言語コード。
///
/// 上流 `LanguageCode` に対応する。各バイトは `0x60..=0x7F` の範囲に収まる
/// 必要がある（ISO/IEC 14496-12 の `unsigned int(5)[3]` パック規約に由来する）。
/// この規約は「各文字を `char - 0x60` した値を 5 ビットにパックする」と定めて
/// おり、範囲外の値を受理してしまうとエンコード時に隣接ビットを破壊するため、
/// [`LanguageCode::new`] / [`LanguageCode::from_ascii`] の入り口で弾く。
///
/// 一方、ISO 639-2/T が定義する文字集合（`a-z`）まで絞る厳格化は行わない。
/// `0x7B..=0x7F`（`{|}~<DEL>`）などは 5 ビット的には有効に符号化できるため受理する。
///
/// ```mbt check
/// test {
///   let code = @bytes.LanguageCode::new(b"und").unwrap()
///   inspect(code.to_string(), content="und")
///   inspect(code.as_bytes() == b"und", content="true")
///   inspect(@bytes.LanguageCode::from_ascii("jpn") is Some(_), content="true")
///   inspect(@bytes.LanguageCode::from_ascii("ENG") is None, content="true")
///   inspect(
///     @bytes.LanguageCode::from_ascii("eng").unwrap().to_packed(),
///     content="5575",
///   )
/// }
/// ```
pub struct LanguageCode {
  bytes : Bytes
} derive(Eq, Hash)

///|
pub extend LanguageCode with Eq::{equal, not_equal}

///|
pub extend LanguageCode with Hash::{hash, hash_combine}

///|
/// 3 文字（`0x60..=0x7F` の 3 バイト）を表示する Debug 表現を返す。
pub impl Debug for LanguageCode with fn to_repr(self : LanguageCode) -> Repr {
  Repr::string(self.to_string())
}

///|
pub extend LanguageCode with Debug::{to_repr}

///|
/// 未定義言語（`"und"`）。
///
/// ISO 639-2 で「未定義」を意味する 3 文字コード。本型は「未指定」と
/// 「利用者が明示的に `und` を指定」を区別しない。
pub fn LanguageCode::undefined() -> LanguageCode {
  { bytes: b"und", }
}

///|
/// 3 バイトから作る。各バイトが `0x60..=0x7F` の範囲外なら `None` を返す。
pub fn LanguageCode::new(bytes : Bytes) -> LanguageCode? {
  if bytes.length() != 3 {
    return None
  }
  for i in 0..<3 {
    let byte = bytes[i].to_uint()
    if byte < 0x60U || byte > 0x7FU {
      return None
    }
  }
  Some({ bytes, })
}

///|
/// 3 バイトの文字列から作る（例: `"eng"`, `"jpn"`）。
///
/// 受理するのは各バイトが `0x60..=0x7F` の範囲に収まる 3 バイトの文字列だけである。
/// ASCII 全域を受理するわけではないため、大文字 `"ENG"` のような範囲外の文字を
/// 含む場合や、バイト長が 3 でない場合（マルチバイト UTF-8 の 1 文字など）は
/// `None` を返す。
pub fn LanguageCode::from_ascii(s : String) -> LanguageCode? {
  LanguageCode::new(@utf8.encode(s))
}

///|
/// 3 バイト配列を返す。
pub fn LanguageCode::as_bytes(self : LanguageCode) -> Bytes {
  self.bytes
}

///|
/// 5 ビットパック表現（ISO/IEC 14496-12 の `unsigned int(5)[3]`）へ変換する。
///
/// [`MdhdBox`](gpui-mbt/mp4/boxes) のエンコードで使う。各バイトの値域は
/// 構築時に検証済みなので、この変換は常に 15 ビットに収まる。
pub fn LanguageCode::to_packed(self : LanguageCode) -> UInt32 {
  let mut language : UInt32 = 0
  for i in 0..<3 {
    let code = self.bytes[i].to_uint() - 0x60U
    language = (language << 5) | code
  }
  language
}

///|
/// 5 ビットパック表現から復元する（decode 側のヘルパー）。
///
/// 5 ビットマスクの結果は常に `0x60..=0x7F` に収まるため、この関数は失敗しない。
pub fn LanguageCode::from_packed(packed : UInt32) -> LanguageCode {
  let bytes = FixedArray::make(3, b'\x00')
  for i in 0..<3 {
    let shift = (2 - i) * 5
    bytes[i] = (((packed >> shift) & 0x1FU) + 0x60U)
      .reinterpret_as_int()
      .to_byte()
  }
  { bytes: Bytes::from_array(bytes), }
}

///|
/// 3 文字を文字列として返す。範囲は構築時に検証済みのため常に成功する。
pub fn LanguageCode::to_string(self : LanguageCode) -> String {
  let builder = StringBuilder()
  for i in 0..<3 {
    builder.write_char(self.bytes[i].to_char())
  }
  builder.to_string()
}

///|
pub impl Default for LanguageCode with fn default() {
  LanguageCode::undefined()
}

///|
pub extend LanguageCode with Default::{default}
