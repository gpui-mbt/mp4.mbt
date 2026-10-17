///|
/// [`StsdBox`] に含まれるサンプルエントリー。
///
/// Issue 0009 では未知のエントリーを保持する [`SampleEntry::Unknown`] のみを
/// 型付けする。`avc1` / `mp4a` のような既知のエントリー種別も、この Issue では
/// ペイロードを解釈せず raw の [`UnknownBox`] として保持する（型付き variant は
/// Issue 0010 で追加する）。上流 `SampleEntry` の `Unknown` フォールバックと
/// 同じ挙動である。
///
/// ```mbt check
/// test {
///   let entry : @boxes.SampleEntry = @bytes.decode_from(
///     @bytes.ReadCursor::new(b"\x00\x00\x00\x0Azzzz\xAA\xBB"),
///   )
///   match entry {
///     @boxes.SampleEntry::Unknown(unknown) =>
///       inspect(unknown.box_type.to_string(), content="zzzz")
///   }
/// }
/// ```
pub(all) enum SampleEntry {
  /// 上記のいずれにも該当しない（本 Issue ではすべての）box_type の受け皿
  Unknown(UnknownBox)
} derive(Eq, Hash, Debug)

///|
pub extend SampleEntry with Eq::{equal, not_equal}

///|
pub extend SampleEntry with Hash::{hash, hash_combine}

///|
pub extend SampleEntry with Debug::{to_repr}

///|
/// サンプルエントリーをデコードする。
///
/// Issue 0009 では常に [`SampleEntry::Unknown`] として読む。0010 で既知の
/// エントリー種別ごとの分岐を追加する。
pub impl @bytes.Decode for SampleEntry with fn decode(
  cursor : @bytes.ReadCursor,
) -> SampleEntry raise @bytes.Mp4Error {
  Unknown(@bytes.decode_from(cursor))
}

///|
pub extend SampleEntry with @bytes.Decode::{decode}

///|
pub impl @bytes.Encode for SampleEntry with fn encode(
  self : SampleEntry,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  match self {
    Unknown(inner) => @bytes.Encode::encode(inner, cursor)
  }
}

///|
pub extend SampleEntry with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for SampleEntry with fn box_type(self) {
  match self {
    Unknown(inner) => @box.BaseBox::box_type(inner)
  }
}

///|
/// 0009 ではすべてのエントリーが raw 保持のため常に `true` になる。
pub impl @box.BaseBox for SampleEntry with fn is_unknown_box(_self) {
  true
}

///|
pub impl @box.BaseBox for SampleEntry with fn children(self) {
  match self {
    Unknown(inner) => @box.BaseBox::children(inner)
  }
}

///|
pub extend SampleEntry with @box.BaseBox::{box_type, is_unknown_box, children}
