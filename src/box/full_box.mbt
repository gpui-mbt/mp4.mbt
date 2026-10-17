///|
/// [`FullBox`] の共通ヘッダー（version 1 バイト + flags 3 バイト）。
pub struct FullBoxHeader {
  version : UInt32
  flags : FullBoxFlags
} derive(Eq, Hash, Debug)

///|
pub extend FullBoxHeader with Eq::{equal, not_equal}

///|
pub extend FullBoxHeader with Hash::{hash, hash_combine}

///|
pub extend FullBoxHeader with Debug::{to_repr}

///|
/// FullBox のヘッダーに含まれる 24-bit ビットフラグ。
///
/// 生の `UInt32` を保持し、エンコード時は下位 24-bit だけが書かれる。
pub struct FullBoxFlags {
  value : UInt32
} derive(Eq, Hash, Debug)

///|
pub extend FullBoxFlags with Eq::{equal, not_equal}

///|
pub extend FullBoxFlags with Hash::{hash, hash_combine}

///|
pub extend FullBoxFlags with Debug::{to_repr}

///|
/// version と flags を持つボックス（FullBox）のインターフェース。
pub(open) trait FullBox: BaseBox {
  /// ボックスの version。
  fn full_box_version(Self) -> UInt32

  /// ボックスの flags。
  fn full_box_flags(Self) -> FullBoxFlags
}

///|
/// 全ビットが 0 のフラグを作る。
pub fn FullBoxFlags::empty() -> FullBoxFlags {
  { value: 0, }
}

///|
/// 生の値からフラグを作る。
///
/// 下位 24-bit に収まる値が期待されるが、`new` は値をそのまま保持する
/// （エンコード時に下位 24-bit だけが書かれる）。
///
/// ```mbt check
/// test {
///   let flags = @box.FullBoxFlags::new(0x12_34_56)
///   inspect(flags.get(), content="1193046")
///   inspect(flags.is_set(1), content="true")
/// }
/// ```
pub fn FullBoxFlags::new(flags : UInt32) -> FullBoxFlags {
  { value: flags, }
}

///|
/// `(ビット位置, セットするか)` の列からフラグを作る。
///
/// 32 以上のビット位置は無視する。同じ位置が複数回現れた場合は OR で合成される。
pub fn FullBoxFlags::from_flags(flags : Array[(Int32, Bool)]) -> FullBoxFlags {
  let mut value : UInt32 = 0
  for flag in flags {
    let (position, is_set) = flag
    if is_set && position >= 0 && position < 32 {
      value = value | (1U << position)
    }
  }
  { value, }
}

///|
/// フラグの生値を返す。
pub fn FullBoxFlags::get(self : FullBoxFlags) -> UInt32 {
  self.value
}

///|
/// 指定ビットがセットされているかどうかを返す（32 以上は常に `false`）。
pub fn FullBoxFlags::is_set(self : FullBoxFlags, i : Int32) -> Bool {
  if i < 0 || i >= 32 {
    false
  } else {
    (self.value & (1U << i)) != 0
  }
}

///|
/// version と flags からヘッダーを作る。
pub fn FullBoxHeader::new(
  version : UInt32,
  flags : FullBoxFlags,
) -> FullBoxHeader {
  { version, flags, }
}

///|
/// FullBox 実装からヘッダーを取り出す。
pub fn[F : FullBox] FullBoxHeader::from_box(b : F) -> FullBoxHeader {
  { version: b.full_box_version(), flags: b.full_box_flags(), }
}

///|
/// ボックスの version を返す。
pub fn FullBoxHeader::version(self : FullBoxHeader) -> UInt32 {
  self.version
}

///|
/// ボックスの flags を返す。
pub fn FullBoxHeader::flags(self : FullBoxHeader) -> FullBoxFlags {
  self.flags
}

///|
pub impl @bytes.Decode for FullBoxFlags with fn decode(
  cursor : @bytes.ReadCursor,
) -> FullBoxFlags raise @bytes.Mp4Error {
  FullBoxFlags::new(cursor.read_u24())
}

///|
pub extend FullBoxFlags with @bytes.Decode::{decode}

///|
pub impl @bytes.Encode for FullBoxFlags with fn encode(
  self : FullBoxFlags,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  cursor.write_u24(self.value)
}

///|
pub extend FullBoxFlags with @bytes.Encode::{encode}

///|
pub impl @bytes.Decode for FullBoxHeader with fn decode(
  cursor : @bytes.ReadCursor,
) -> FullBoxHeader raise @bytes.Mp4Error {
  let version = cursor.read_u8()
  let flags = FullBoxFlags::new(cursor.read_u24())
  { version, flags, }
}

///|
pub extend FullBoxHeader with @bytes.Decode::{decode}

///|
pub impl @bytes.Encode for FullBoxHeader with fn encode(
  self : FullBoxHeader,
  cursor : @bytes.WriteCursor,
) -> Unit raise @bytes.Mp4Error {
  cursor.write_u8(self.version)
  cursor.write_u24(self.flags.get())
}

///|
pub extend FullBoxHeader with @bytes.Encode::{encode}
