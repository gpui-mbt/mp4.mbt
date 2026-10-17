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
/// 失敗を「分類（[`ErrorKind`]）」「理由」「入力中の byte offset」「MP4 ボックス種別」
/// 「発生位置」で表す。`offset` は未確定な場合 `None` になり、
/// [`Mp4Error::with_offset`] は最初に設定された値だけを残す（内側のより正確な位置を
/// 外側が上書きしない）。`box_type` も同様に [`Mp4Error::with_box_type`] の初回設定だけを
/// 残す。
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
    box_type~ : BoxType?,
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
  Mp4Error(kind~, reason=reason.to_owned(), offset=None, box_type=None, loc~)
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
    box_type=None,
    loc~,
  )
}

///|
/// エラーに byte offset を設定する（既に設定済みの場合は変更しない）。
pub fn Mp4Error::with_offset(self : Mp4Error, new_offset : UInt64) -> Mp4Error {
  match self {
    Mp4Error(kind~, reason~, offset~, box_type~, loc~) =>
      if offset is Some(_) {
        self
      } else {
        Mp4Error(kind~, reason~, offset=Some(new_offset), box_type~, loc~)
      }
  }
}

///|
/// エラーに MP4 ボックス種別を設定する（既に設定済みの場合は変更しない）。
pub fn Mp4Error::with_box_type(
  self : Mp4Error,
  new_box_type : BoxType,
) -> Mp4Error {
  match self {
    Mp4Error(kind~, reason~, offset~, box_type~, loc~) =>
      if box_type is Some(_) {
        self
      } else {
        Mp4Error(kind~, reason~, offset~, box_type=Some(new_box_type), loc~)
      }
  }
}

///|
/// `f` の失敗に、まだボックス種別が設定されていなければ `box_type` を付けて返す。
///
/// 型付きボックスのデコードで、失敗の原因となった（最初の）ボックスの種別を
/// エラーへ残すために使う。上流 `shiguredo_mp4::boxes::with_box_type` に対応する。
///
/// ```mbt check
/// test {
///   let box_type = @bytes.BoxType::Normal(
///     @bytes.FourCC::from_bytes(b"moov") catch {
///       _ => abort("4 bytes")
///     },
///   )
///   let run : () -> Unit raise @bytes.Mp4Error = fn() raise @bytes.Mp4Error {
///     raise @bytes.Mp4Error::invalid_data("bad")
///   }
///   @bytes.with_box_type(box_type, run) catch {
///     @bytes.Mp4Error(box_type=Some(_), ..) => ()
///     _ => fail("box type must be attached")
///   }
/// }
/// ```
pub fn[T] with_box_type(
  box_type : BoxType,
  f : () -> T raise Mp4Error,
) -> T raise Mp4Error {
  f() catch {
    error => raise error.with_box_type(box_type)
  }
}

///|
/// エラーを `[{ボックス種別}] {分類}: {理由}{位置} (at {発生位置})` 形式に整形する。
pub fn Mp4Error::to_string(self : Mp4Error) -> String {
  match self {
    Mp4Error(kind~, reason~, offset~, box_type~, loc~) => {
      let prefix = match box_type {
        Some(box_type) => "[\{box_type.to_string()}] "
        None => ""
      }
      let detail = if reason.is_empty() {
        kind.to_string()
      } else {
        "\{kind.to_string()}: \{reason}"
      }
      let position = match offset {
        Some(offset) => " offset=\{offset}"
        None => ""
      }
      "\{prefix}\{detail}\{position} (at \{loc})"
    }
  }
}
