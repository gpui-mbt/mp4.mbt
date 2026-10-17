///|
/// null 終端の UTF-8 文字列。
///
/// 上流 `Utf8String` に対応する。インスタンスは常に有効な UTF-8 であり、
/// 終端の null を含まない（[`Utf8String::new`] が null を含む文字列を拒否し、
/// [`Utf8String::decode`] は終端の null を消費する）。
///
/// ```mbt check
/// test {
///   let s = @bytes.Utf8String::new("hello").unwrap()
///   inspect(s.get(), content="hello")
///   inspect(s.into_null_terminated_bytes() == b"hello\x00", content="true")
///   inspect(@bytes.Utf8String::new("a\u{0}b") is None, content="true")
///   inspect(@bytes.Utf8String::default().get(), content="")
/// }
/// ```
pub struct Utf8String {
  value : String
} derive(Eq, Hash, Debug)

///|
pub extend Utf8String with Eq::{equal, not_equal}

///|
pub extend Utf8String with Hash::{hash, hash_combine}

///|
pub extend Utf8String with Debug::{to_repr}

///|
/// 終端の null を含まない文字列から作成する。
///
/// 引数の文字列に null 文字（`\x00`）が含まれる場合は `None` を返す。
pub fn Utf8String::new(value : String) -> Utf8String? {
  let bytes = @utf8.encode(value)
  for i in 0..<bytes.length() {
    if bytes[i] == b'\x00' {
      return None
    }
  }
  Some({ value, })
}

///|
/// 空文字列を作る（[`Utf8String::default`] と同値）。
pub fn Utf8String::empty() -> Utf8String {
  { value: "", }
}

///|
/// 保持する、null 終端部分を含まない文字列を返す。
pub fn Utf8String::get(self : Utf8String) -> String {
  self.value
}

///|
/// null 終端部分を含むバイト列へ変換する。
pub fn Utf8String::into_null_terminated_bytes(self : Utf8String) -> Bytes {
  let buffer = Buffer::Buffer()
  buffer.write_bytes(@utf8.encode(self.value))
  buffer.write_byte(b'\x00')
  buffer.to_bytes()
}

///|
/// 文字列のバイト列と終端の null を書く。
pub impl Encode for Utf8String with fn encode(
  self : Utf8String,
  cursor : WriteCursor,
) -> Unit raise Mp4Error {
  cursor.write_bytes(@utf8.encode(self.value))
  cursor.write_u8(0)
}

///|
pub extend Utf8String with Encode::{encode}

///|
/// null 終端までのバイト列を読み、UTF-8 として検証する。
///
/// 終端の null が見つからない場合は
/// [`ErrorKind::InvalidInput`]（"Null-terminated string not found"）、
/// UTF-8 として不正な場合は [`ErrorKind::InvalidInput`]
/// （"Invalid UTF-8 string: \[...\]"）で失敗する。
pub impl Decode for Utf8String with fn decode(cursor : ReadCursor) -> Utf8String raise Mp4Error {
  let start = cursor.position()
  errdefer cursor.rewind_to(start)
  let buffer = Buffer::Buffer()
  let mut terminated = false
  while !cursor.is_empty() {
    let byte = cursor.read_u8()
    if byte == 0 {
      terminated = true
      break
    }
    buffer.write_byte(byte.reinterpret_as_int().to_byte())
  }
  if !terminated {
    raise Mp4Error::invalid_input("Null-terminated string not found")
  }
  let bytes = buffer.to_bytes()
  let value = try @utf8.decode(bytes[:]) catch {
    @utf8.Malformed(_) =>
      raise Mp4Error::invalid_input(
        "Invalid UTF-8 string: \{rust_debug_bytes(bytes)}",
      )
  } noraise {
    text => text
  }
  { value, }
}

///|
pub extend Utf8String with Decode::{decode}

///|
/// `Bytes` を Rust の `{:?}`（`[1, 2, 3]` 形式）と同じ十進表記にする。
///
/// 上流 `Utf8String::decode` のエラー理由
/// （`format!("Invalid UTF-8 string: {:?}", e.as_bytes())`）を再現するために使う。
fn rust_debug_bytes(bytes : Bytes) -> String {
  let parts : Array[String] = []
  for i in 0..<bytes.length() {
    parts.push(bytes[i].to_uint().to_string())
  }
  "[\{parts.join(", ")}]"
}

///|
pub impl Default for Utf8String with fn default() {
  { value: "", }
}

///|
pub extend Utf8String with Default::{default}
