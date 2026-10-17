///|
/// MP4 のトップレベルに位置するボックス群（上流 `RootBox`）。
///
/// 現時点では `free` / `mdat` / `moov` / 未知種別を型付きで扱う。`moof` / `mfra` /
/// `sidx` の variant は後続 Issue（0017）で追加する。それまでの間、これらは
/// [`RootBox::Unknown`] として保持される。
///
/// ```mbt check
/// test {
///   let cursor = @bytes.ReadCursor::new(
///     b"\x00\x00\x00\x08free\x00\x00\x00\x0Cmdat\x11\x22\x33\x44",
///   )
///   let first : @boxes.RootBox = @bytes.decode_from(cursor)
///   let second : @boxes.RootBox = @bytes.decode_from(cursor)
///   match first {
///     @boxes.RootBox::Free(_) => ()
///     _ => fail("first box must be free")
///   }
///   match second {
///     @boxes.RootBox::Mdat(_) => ()
///     _ => fail("second box must be mdat")
///   }
/// }
/// ```
pub(all) enum RootBox {
  /// `free` ボックス（空き領域埋め）
  Free(FreeBox)
  /// `mdat` ボックス（メディアデータ本体）
  Mdat(MdatBox)
  /// `moov` ボックス（movie 全体のメタデータとトラック群）
  Moov(MoovBox)
  /// 上記以外のボックス（未知種別の受け皿）
  Unknown(UnknownBox)
} derive(Debug)

///|
pub extend RootBox with Debug::{to_repr}

///|
/// デコード時に `free` / `mdat` / `moov` を型付きで扱い、それ以外は
/// [`UnknownBox::decode_top_level`] で保持する。
///
/// `free` / `mdat` は上流と同じく `size==0`（末尾まで）も受理する。失敗した場合は
/// カーソル位置を開始位置へ戻す。
pub impl @bytes.Decode for RootBox with fn decode(cursor : @bytes.ReadCursor) -> RootBox raise @bytes.Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  let header : @box.BoxHeader = @bytes.decode_from(cursor)
  let box_type = header.box_type()
  cursor.rewind_to(start)
  if box_type.as_bytes() == b"free" {
    let inner : FreeBox = @bytes.decode_from(cursor)
    RootBox::Free(inner)
  } else if box_type.as_bytes() == b"mdat" {
    let inner : MdatBox = @bytes.decode_from(cursor)
    RootBox::Mdat(inner)
  } else if box_type.as_bytes() == b"moov" {
    let inner : MoovBox = @bytes.decode_from(cursor)
    RootBox::Moov(inner)
  } else {
    RootBox::Unknown(UnknownBox::decode_top_level(cursor))
  }
}

///|
pub extend RootBox with @bytes.Decode::{decode}

///|
/// 型付きトップレベルボックスを再エンコードする。
///
/// [`RootBox::Mdat`] はペイロードを保持しないため
/// [`@bytes.ErrorKind::Unsupported`] で失敗する（上流との意図的な差）。
/// `size==0` でデコードした [`RootBox::Unknown`] は `size==0` のまま書かれる
/// （wire-preserving）。
pub impl @bytes.Encode for RootBox with fn encode(
  self : RootBox,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  match self {
    Free(b) => @bytes.Encode::encode(b, cursor)
    Moov(b) => @bytes.Encode::encode(b, cursor)
    Unknown(b) => @bytes.Encode::encode(b, cursor)
    Mdat(_) =>
      raise @bytes.Mp4Error::unsupported(
        "mdat payload is not retained; write it from the source range instead",
      )
  }
}

///|
pub extend RootBox with @bytes.Encode::{encode}

///|
pub impl @box.BaseBox for RootBox with fn box_type(self) {
  match self {
    Free(b) => @box.BaseBox::box_type(b)
    Mdat(b) => @box.BaseBox::box_type(b)
    Moov(b) => @box.BaseBox::box_type(b)
    Unknown(b) => @box.BaseBox::box_type(b)
  }
}

///|
pub impl @box.BaseBox for RootBox with fn is_unknown_box(self) {
  match self {
    Unknown(_) => true
    _ => false
  }
}

///|
/// `moov` のときはその子ボックスを返し、それ以外は空を返す。
pub impl @box.BaseBox for RootBox with fn children(self) {
  match self {
    Moov(b) => @box.BaseBox::children(b)
    _ => {
      let empty : Array[&@box.BaseBox] = []
      empty
    }
  }
}

///|
pub extend RootBox with @box.BaseBox::{box_type, is_unknown_box, children}
