///|
/// バイト列から値をデコードする trait。
///
/// `decode` は [`ReadCursor`] の現在位置から値を読み、成功したときだけ位置を進める
/// 契約にする。失敗時に位置を開始位置へ戻したい場合は [`decode_from`] を使う。
pub(open) trait Decode {
  fn decode(ReadCursor) -> Self raise Mp4Error
}

///|
/// 値をバイト列へエンコードする trait。
///
/// `encode` は [`WriteCursor`] へ書き込む。失敗の余地は原則ないが、`Mp4Error` を
/// 共通の失敗型として揃えるために `raise` する。
pub(open) trait Encode {
  fn encode(Self, WriteCursor) -> Unit raise Mp4Error
}

///|
/// カーソルから `T` をデコードする。
///
/// 失敗した場合はカーソル位置を開始位置へ戻す。ストリーミング入力のリトライで
/// 途中位置が残らないようにするための入口であり、複合的なデコードはこれを通す。
pub fn[T : Decode] decode_from(cursor : ReadCursor) -> T raise Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  Decode::decode(cursor)
}

///|
/// `Encode` を使って値をバイト列へ変換する。
pub fn[T : Encode] encode_to_bytes(value : T) -> Bytes raise Mp4Error {
  let cursor = WriteCursor::new()
  Encode::encode(value, cursor)
  cursor.to_bytes()
}
