///|
test "FourCC::from_string round trip" {
  let ftyp = @bytes.FourCC::from_string("ftyp")
  inspect(ftyp.to_string(), content="ftyp")
  debug_inspect(ftyp.as_bytes(), content="<Bytes: [0x66, 0x74, 0x79, 0x70]>")
  assert_true(@bytes.FourCC::from_bytes(b"ftyp") == ftyp)
}

///|
test "FourCC::from_bytes preserves arbitrary bytes" {
  let raw : Bytes = [0xFF, 0x00, 0x80, 0x20]
  let cc = @bytes.FourCC::from_bytes(raw)
  debug_inspect(cc.as_bytes(), content="<Bytes: [0xff, 0x00, 0x80, 0x20]>")
  inspect(cc.to_string(), content="[0xff, 0x00, 0x80, 0x20]")
}

///|
test "FourCC::to_string hex form for non printable values" {
  let cc = @bytes.FourCC::from_string("f\typ")
  inspect(cc.to_string(), content="[0x66, 0x09, 0x79, 0x70]")
  debug_inspect(cc.as_bytes(), content="<Bytes: [0x66, 0x09, 0x79, 0x70]>")
}

///|
test "FourCC::from_string rejects wrong length" {
  try @bytes.FourCC::from_string("ftypx") catch {
    @bytes.InvalidLength(length~) => inspect(length, content="5")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
  try @bytes.FourCC::from_string("") catch {
    @bytes.InvalidLength(length~) => inspect(length, content="0")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "FourCC::from_string rejects non ASCII" {
  try @bytes.FourCC::from_string("f\u{00E9}yp") catch {
    @bytes.NonAsciiByte(value~) => inspect(value, content="233")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}

///|
test "FourCC::from_bytes rejects wrong length" {
  try @bytes.FourCC::from_bytes(b"abc") catch {
    @bytes.InvalidLength(length~) => inspect(length, content="3")
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected to fail")
  }
}
