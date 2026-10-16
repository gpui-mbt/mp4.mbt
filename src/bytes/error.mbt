///|
/// エラーの分類。上流 `shiguredo_mp4::ErrorKind` に対応する。
pub(all) enum ErrorKind {
  /// 入力データの形式または構造が無効である
  InvalidInput
  /// データコンテンツが無効または破損している
  InvalidData
  /// 提供されたバッファがエンコード/デコード結果を保持するのに小さすぎる
  InsufficientBuffer
  /// 操作またはデータ形式がサポートされていない
  Unsupported
} derive(Eq, Hash)

///|
pub extend ErrorKind with Eq::{equal, not_equal}

///|
pub extend ErrorKind with Hash::{hash, hash_combine}

///|
/// [`ErrorKind`] を上流と同じ表示名で文字列化する。
pub fn ErrorKind::to_string(self : ErrorKind) -> String {
  match self {
    InvalidInput => "InvalidInput"
    InvalidData => "InvalidData"
    InsufficientBuffer => "InsufficientBuffer"
    Unsupported => "Unsupported"
  }
}

///|
/// MP4 の解析・構築で共通に使うエラー。
///
/// 失敗を「分類（[`ErrorKind`]）」「理由」「入力中の byte offset」「発生位置」で
/// 表す。`offset` は未確定な場合 `None` になり、[`Mp4Error::with_offset`] は
/// 最初に設定された値だけを残す（内側のより正確な位置を外側が上書きしない）。
///
/// `loc` は `#callsite` によって自動補完されるため、呼び出し側が明示する必要はない。
///
/// ```mbt check
/// test {
///   let err = @bytes.Mp4Error::invalid_input("bad structure").with_offset(16UL)
///   inspect(
///     err.to_string().contains("InvalidInput: bad structure"),
///     content="true",
///   )
///   inspect(err.to_string().contains("offset=16"), content="true")
/// }
/// ```
pub(all) suberror Mp4Error {
  Mp4Error(
    kind~ : ErrorKind,
    reason~ : String,
    offset~ : UInt64?,
    loc~ : SourceLoc
  )
}

///|
/// 分類と理由からエラーを作る。
#callsite(autofill(loc))
pub fn Mp4Error::new(
  kind : ErrorKind,
  reason : StringView,
  loc~ : SourceLoc,
) -> Mp4Error {
  Mp4Error(kind~, reason=reason.to_owned(), offset=None, loc~)
}

///|
/// 入力の形式・構造が無効であることを表すエラーを作る。
#callsite(autofill(loc))
pub fn Mp4Error::invalid_input(
  reason : StringView,
  loc~ : SourceLoc,
) -> Mp4Error {
  Mp4Error::new(InvalidInput, reason, loc~)
}

///|
/// 入力の内容が破損していることを表すエラーを作る。
#callsite(autofill(loc))
pub fn Mp4Error::invalid_data(
  reason : StringView,
  loc~ : SourceLoc,
) -> Mp4Error {
  Mp4Error::new(InvalidData, reason, loc~)
}

///|
/// 入力が未対応であることを表すエラーを作る。
#callsite(autofill(loc))
pub fn Mp4Error::unsupported(reason : StringView, loc~ : SourceLoc) -> Mp4Error {
  Mp4Error::new(Unsupported, reason, loc~)
}

///|
/// 読み書きに必要な量のバッファがないことを表すエラーを作る。
///
/// `required` は必要なバイト数、`available` は実際に取得できたバイト数。
#callsite(autofill(loc))
pub fn Mp4Error::insufficient_buffer(
  required : UInt64,
  available : UInt64,
  loc~ : SourceLoc,
) -> Mp4Error {
  Mp4Error(
    kind=InsufficientBuffer,
    reason="required \{required} bytes, but only \{available} bytes available",
    offset=None,
    loc~,
  )
}

///|
/// エラーに byte offset を設定する（既に設定済みの場合は変更しない）。
pub fn Mp4Error::with_offset(self : Mp4Error, new_offset : UInt64) -> Mp4Error {
  match self {
    Mp4Error(kind~, reason~, offset~, loc~) =>
      if offset is Some(_) {
        self
      } else {
        Mp4Error(kind~, reason~, offset=Some(new_offset), loc~)
      }
  }
}

///|
/// エラーを `{分類}: {理由} (at {位置})` 形式に整形する。
pub fn Mp4Error::to_string(self : Mp4Error) -> String {
  match self {
    Mp4Error(kind~, reason~, offset~, loc~) => {
      let detail = if reason.is_empty() {
        kind.to_string()
      } else {
        "\{kind.to_string()}: \{reason}"
      }
      let position = match offset {
        Some(offset) => " offset=\{offset}"
        None => ""
      }
      "\{detail}\{position} (at \{loc})"
    }
  }
}
