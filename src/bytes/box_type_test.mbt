///|
test "Uuid::from_bytes requires exactly 16 bytes" {
  let uuid = @bytes.Uuid::from_bytes(
    b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0A\x0B\x0C\x0D\x0E\x0F",
  )
  inspect(uuid.as_bytes().length(), content="16")
  try @bytes.Uuid::from_bytes(b"\x00\x01") catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="uuid box type must be 16 bytes, but got 2")
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}

///|
test "Uuid::to_string is canonical lower case hex" {
  let uuid = @bytes.Uuid::from_bytes(
    b"\x6B\xC0\xA5\xA1\x8B\x2E\x4A\x71\xB0\x2C\xD0\x5B\x8B\x1B\x3F\x9F",
  )
  inspect(uuid.to_string(), content="6bc0a5a1-8b2e-4a71-b02c-d05b8b1b3f9f")
  let zeros = @bytes.Uuid::from_bytes(
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  inspect(zeros.to_string(), content="00000000-0000-0000-0000-000000000000")
}

///|
test "BoxType exposes raw bytes, sizes and display text" {
  let normal = @bytes.BoxType::Normal(@bytes.FourCC::from_string("ftyp"))
  inspect(normal.external_size(), content="4")
  inspect(normal.as_bytes() == b"ftyp", content="true")
  inspect(normal.to_string(), content="ftyp")
  let uuid = @bytes.BoxType::Uuid(
    @bytes.Uuid::from_bytes(
      b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
    ),
  )
  inspect(uuid.external_size(), content="20")
  inspect(uuid.as_bytes().length(), content="16")
  inspect(uuid.to_string(), content="00010203-0405-0607-0809-0a0b0c0d0e0f")
}

///|
test "BoxType::to_string falls back to hex for non printable types" {
  let ty = @bytes.BoxType::Normal(
    @bytes.FourCC::from_bytes(b"\x00\x01\x02\x03"),
  )
  inspect(ty.to_string(), content="[0x00, 0x01, 0x02, 0x03]")
}

///|
test "BoxType::expect passes for equal types" {
  let ty = @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))
  ty.expect(ty)
}

///|
test "BoxType::expect reports InvalidData with both types" {
  let actual = @bytes.BoxType::Normal(@bytes.FourCC::from_string("ftyp"))
  let expected = @bytes.BoxType::Normal(@bytes.FourCC::from_string("moov"))
  try actual.expect(expected) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Expected box type `moov`, but got `ftyp`")
    }
  } noraise {
    _ => fail("expected InvalidData")
  }
}

///|
test "BoxType equality distinguishes the normal and uuid forms" {
  let normal = @bytes.BoxType::Normal(@bytes.FourCC::from_string("uuid"))
  inspect(
    normal == @bytes.BoxType::Normal(@bytes.FourCC::from_string("uuid")),
    content="true",
  )
  let uuid = @bytes.BoxType::Uuid(
    @bytes.Uuid::from_bytes(
      b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    ),
  )
  inspect(normal == uuid, content="false")
}
