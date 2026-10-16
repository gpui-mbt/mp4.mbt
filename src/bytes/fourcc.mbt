///|
/// FourCC（4 文字コード）の長さ・内容が不正であることを表すエラー。
pub(all) suberror FourCCError {
  /// 4 バイト（4 文字）以外の長さが渡された
  InvalidLength(length~ : Int32)
  /// ASCII 範囲外の文字が渡された
  NonAsciiByte(value~ : Int32)
}

///|
/// 4 バイトで表現される識別子（FourCC）。
///
/// MP4 のボックス種別やブランドなど、ISO BMFF の広い箇所で使われる。
/// 生のバイト列をそのまま保持するため、非 ASCII・制御文字を含む値でも
/// 文字列変換によって内容を失わない（[`FourCC::to_string`] は表示専用）。
///
/// # Example
///
/// ```mbt check
/// test {
///   let ftyp = @bytes.FourCC::from_string("ftyp")
///   inspect(ftyp.to_string(), content="ftyp")
///   inspect(ftyp.as_bytes().length(), content="4")
/// }
/// ```
pub struct FourCC {
  bytes : Bytes
} derive(Eq, Hash, Debug)

///|
pub extend FourCC with Eq::{equal, not_equal}

///|
pub extend FourCC with Hash::{hash, hash_combine}

///|
pub extend FourCC with Debug::{to_repr}

///|
/// 4 バイト値から [`FourCC`] を作成する。
///
/// 任意のバイト列を受け付け、長さが 4 でない場合だけ
/// [`FourCCError::InvalidLength`] を返す。
pub fn FourCC::from_bytes(bytes : Bytes) -> FourCC raise FourCCError {
  if bytes.length() != 4 {
    raise FourCCError::InvalidLength(length=bytes.length())
  }
  { bytes, }
}

///|
/// 4 文字の ASCII 文字列から [`FourCC`] を作成する。
///
/// 長さが 4 でない場合は [`FourCCError::InvalidLength`]、
/// ASCII 範囲外の文字を含む場合は [`FourCCError::NonAsciiByte`] を返す。
pub fn FourCC::from_string(s : StringView) -> FourCC raise FourCCError {
  let chars = s.to_array()
  if chars.length() != 4 {
    raise FourCCError::InvalidLength(length=chars.length())
  }
  let buf = FixedArray::make(4, b'\x00')
  for i, c in chars {
    let v = c.to_int()
    if v > 0x7F {
      raise FourCCError::NonAsciiByte(value=v)
    }
    buf[i] = v.to_byte()
  }
  { bytes: Bytes::from_array(buf), }
}

///|
/// 生の 4 バイトを返す。
pub fn FourCC::as_bytes(self : FourCC) -> Bytes {
  self.bytes
}

///|
/// 表示用の文字列を返す。
///
/// 4 バイトすべてが印字可能 ASCII（`0x20`–`0x7E`）の場合はその文字列、
/// それ以外は `"[0x00, 0x01, 0x02, 0x03]"` 形式の 16 進表記を返す。
/// この変換は表示専用であり、[`FourCC::as_bytes`] の値は変化しない。
pub fn FourCC::to_string(self : FourCC) -> String {
  let mut printable = true
  for i in 0..<4 {
    let b = self.bytes[i]
    if b < 0x20 || b > 0x7E {
      printable = false
    }
  }
  if printable {
    let sb = StringBuilder()
    for i in 0..<4 {
      sb.write_char(self.bytes[i].to_char())
    }
    sb.to_string()
  } else {
    let parts = []
    for i in 0..<4 {
      parts.push("0x\{self.bytes[i].to_hex()}")
    }
    "[\{parts.join(", ")}]"
  }
}
