///|
test "utf8 string rejects embedded nulls" {
  inspect(@bytes.Utf8String::new("hello") is Some(_), content="true")
  inspect(@bytes.Utf8String::new("a\u{0}b") is None, content="true")
  inspect(@bytes.Utf8String::new("\u{0}") is None, content="true")
  inspect(@bytes.Utf8String::new("") is Some(_), content="true")
}

///|
test "utf8 string empty and default are the same value" {
  inspect(
    @bytes.Utf8String::empty() == @bytes.Utf8String::default(),
    content="true",
  )
  inspect(@bytes.Utf8String::empty().get(), content="")
}

///|
test "utf8 string converts to null terminated bytes" {
  let s = @bytes.Utf8String::new("abc").unwrap()
  debug_inspect(
    s.into_null_terminated_bytes(),
    content="<Bytes: [0x61, 0x62, 0x63, 0x00]>",
  )
  debug_inspect(
    @bytes.Utf8String::empty().into_null_terminated_bytes(),
    content="<Bytes: [0x00]>",
  )
}

///|
test "utf8 string encodes as bytes plus null terminator" {
  let s = @bytes.Utf8String::new("hello").unwrap()
  debug_inspect(
    @bytes.encode_to_bytes(s),
    content="<Bytes: [0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00]>",
  )
}

///|
test "utf8 string decodes until the null terminator" {
  let cursor = @bytes.ReadCursor::new(b"hello\x00rest")
  let s : @bytes.Utf8String = @bytes.decode_from(cursor)
  inspect(s.get(), content="hello")
  inspect(cursor.position(), content="6")
  inspect(cursor.read_remaining() == b"rest", content="true")
}

///|
test "utf8 string decodes an empty terminated string" {
  let cursor = @bytes.ReadCursor::new(b"\x00")
  let s : @bytes.Utf8String = @bytes.decode_from(cursor)
  inspect(s.get(), content="")
  inspect(cursor.is_empty(), content="true")
}

///|
test "utf8 string round trips multibyte text" {
  let text = "日本語"
  let s = @bytes.Utf8String::new(text).unwrap()
  let cursor = @bytes.ReadCursor::new(@bytes.encode_to_bytes(s))
  let decoded : @bytes.Utf8String = @bytes.decode_from(cursor)
  inspect(decoded.get(), content=text)
  inspect(decoded == s, content="true")
}

///|
test "utf8 string keeps a leading BOM" {
  let cursor = @bytes.ReadCursor::new(b"\xEF\xBB\xBFx\x00")
  let s : @bytes.Utf8String = @bytes.decode_from(cursor)
  inspect(s.get().length(), content="2")
  inspect(s.get(), content="\u{FEFF}x")
}

///|
test "utf8 string rejects a missing null terminator" {
  let cursor = @bytes.ReadCursor::new(b"hello")
  let result : @bytes.Utf8String? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Null-terminated string not found")
      None
    }
  } noraise {
    s => Some(s)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "utf8 string rejects an empty input" {
  let cursor = @bytes.ReadCursor::new(b"")
  let result : @bytes.Utf8String? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Null-terminated string not found")
      None
    }
  } noraise {
    s => Some(s)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "utf8 string rejects invalid utf8 with the upstream reason" {
  let cursor = @bytes.ReadCursor::new(b"\xff\xfe\x00")
  let result : @bytes.Utf8String? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Invalid UTF-8 string: [255, 254]")
      None
    }
  } noraise {
    s => Some(s)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "utf8 string rejects invalid utf8 without a terminator as not found" {
  // 終端が無い場合は UTF-8 検証より先に終端探索が失敗する（上流と同じ順序）。
  let cursor = @bytes.ReadCursor::new(b"\xff\xfe")
  let result : @bytes.Utf8String? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Null-terminated string not found")
      None
    }
  } noraise {
    s => Some(s)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
