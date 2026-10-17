///|
test "minimal box has no payload and round trips" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x08mdat")
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  inspect(header.box_size().get(), content="8")
  inspect(header.box_type().to_string(), content="mdat")
  inspect(header.external_size(), content="8")
  inspect(payload.length(), content="0")
  inspect(cursor.is_empty(), content="true")
  inspect(
    @bytes.encode_to_bytes(header) == b"\x00\x00\x00\x08mdat",
    content="true",
  )
}

///|
test "box with payload returns header and payload view" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x10mdat\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11",
  )
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  inspect(header.box_size().get(), content="16")
  inspect(payload.length(), content="8")
  inspect(
    payload.equal_to_bytes(b"\xAA\xBB\xCC\xDD\xEE\xFF\x00\x11"),
    content="true",
  )
  inspect(cursor.is_empty(), content="true")
}

///|
test "largesize box keeps the 64-bit size variant" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x18\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11\x11",
  )
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  inspect(header.box_size() == @box.BoxSize::U64(24UL), content="true")
  inspect(header.box_size().get(), content="24")
  inspect(header.external_size(), content="16")
  inspect(payload.length(), content="8")
  inspect(cursor.remaining(), content="4")
  inspect(
    @bytes.encode_to_bytes(header) ==
    b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x18",
    content="true",
  )
}

///|
test "size zero consumes the rest of the buffer at top level" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x00mdat\xAA\xBB\xCC")
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  inspect(header.box_size() == @box.BoxSize::variable_size(), content="true")
  inspect(header.external_size(), content="8")
  inspect(payload.length(), content="3")
  inspect(payload.equal_to_bytes(b"\xAA\xBB\xCC"), content="true")
  inspect(cursor.is_empty(), content="true")
}

///|
test "size zero with header only yields an empty payload" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x00free")
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  inspect(header.box_size() == @box.BoxSize::variable_size(), content="true")
  inspect(payload.length(), content="0")
}

///|
test "largesize zero is not treated as variable size" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  try @box.BoxHeader::decode_header_and_payload(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, box_type~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="box size is smaller than header size")
      inspect(offset == Some(0UL), content="true")
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))),
        content="true",
      )
    }
  } noraise {
    _ => fail("expected InvalidData")
  }
  inspect(cursor.position(), content="0")
}

///|
test "declared size below the header size is rejected by decode" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x04mdat")
  try @box.BoxHeader::decode_header_and_payload(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="Too small box size: actual=4, expected=8 or more",
      )
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
  inspect(cursor.position(), content="0")
}

///|
test "header decode alone also rejects too small sizes" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x02mdat")
  let header : @box.BoxHeader? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="Too small box size: actual=2, expected=8 or more",
      )
      None
    }
  } noraise {
    header => Some(header)
  }
  inspect(header is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "largesize zero passes the header decode itself" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  let header : @box.BoxHeader = @bytes.decode_from(cursor)
  inspect(header.box_size() == @box.BoxSize::U64(0UL), content="true")
  inspect(cursor.position(), content="16")
}

///|
test "truncated payload fails with InsufficientBuffer and rolls back" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x00\x00\x10mdat\xAA\xBB")
  try @box.BoxHeader::decode_header_and_payload(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, box_type~, ..) => {
      inspect(kind.to_string(), content="InsufficientBuffer")
      inspect(reason, content="required 16 bytes, but only 10 bytes available")
      inspect(offset == Some(0UL), content="true")
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))),
        content="true",
      )
    }
  } noraise {
    _ => fail("expected InsufficientBuffer")
  }
  inspect(cursor.position(), content="0")
}

///|
test "truncated largesize rolls back the whole header" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00",
  )
  let header : @box.BoxHeader? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, ..) => {
      inspect(kind.to_string(), content="InsufficientBuffer")
      None
    }
  } noraise {
    header => Some(header)
  }
  inspect(header is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "uuid box type round trips through the header" {
  let uuid_bytes = b"\x6B\xC0\xA5\xA1\x8B\x2E\x4A\x71\xB0\x2C\xD0\x5B\x8B\x1B\x3F\x9F"
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x20uuid" + uuid_bytes + b"\x00\x00\x00\x00\x00\x00\x00\x08",
  )
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  inspect(header.box_type().external_size(), content="20")
  inspect(header.external_size(), content="24")
  inspect(header.box_size().get(), content="32")
  inspect(payload.length(), content="8")
  inspect(header.box_type().as_bytes() == uuid_bytes, content="true")
  inspect(
    header.box_type().to_string(),
    content="6bc0a5a1-8b2e-4a71-b02c-d05b8b1b3f9f",
  )
  inspect(
    @bytes.encode_to_bytes(header) == b"\x00\x00\x00\x20uuid" + uuid_bytes,
    content="true",
  )
}

///|
test "unknown box type bytes are preserved" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x0C\xFF\x00AB\x00\x01\x02\x03",
  )
  let (header, payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  inspect(header.box_type().as_bytes() == b"\xFF\x00AB", content="true")
  inspect(header.box_type().to_string(), content="[0xff, 0x00, 0x41, 0x42]")
  inspect(payload.length(), content="4")
  inspect(
    @bytes.encode_to_bytes(header) == b"\x00\x00\x00\x0C\xFF\x00AB",
    content="true",
  )
}

///|
test "box header sizes match the documented minimum and maximum" {
  let normal = @box.BoxHeader::new(
    @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat")),
    @box.BoxSize::U32(8),
  )
  inspect(normal.external_size(), content="8")
  inspect(normal.external_size() == @box.MIN_BOX_HEADER_SIZE, content="true")
  let uuid = @box.BoxHeader::new(
    @bytes.BoxType::Uuid(
      @bytes.Uuid::from_bytes(
        b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
      ),
    ),
    @box.BoxSize::U64(32UL),
  )
  inspect(uuid.external_size(), content="32")
  inspect(uuid.external_size() == @box.MAX_BOX_HEADER_SIZE, content="true")
}

///|
test "BoxSize::with_payload_size picks the encoding by the total size" {
  let mdat = @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))
  inspect(
    @box.BoxSize::with_payload_size(mdat, 0UL) == @box.BoxSize::U32(8),
    content="true",
  )
  inspect(
    @box.BoxSize::with_payload_size(mdat, 8UL) == @box.BoxSize::U32(16),
    content="true",
  )
  // 8 + (2^32 - 9) = 2^32 - 1 はまだ 32-bit に収まる
  inspect(
    @box.BoxSize::with_payload_size(mdat, 4294967287UL) ==
    @box.BoxSize::U32(4294967295),
    content="true",
  )
  // 8 + (2^32 - 8) = 2^32 は largesize になる（+8 バイト）
  inspect(
    @box.BoxSize::with_payload_size(mdat, 4294967288UL) ==
    @box.BoxSize::U64(4294967304UL),
    content="true",
  )
}

///|
test "BoxSize::with_payload_size accounts for the uuid header" {
  let uuid_type = @bytes.BoxType::Uuid(
    @bytes.Uuid::from_bytes(
      b"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f",
    ),
  )
  inspect(
    @box.BoxSize::with_payload_size(uuid_type, 0UL) == @box.BoxSize::U32(24),
    content="true",
  )
}

///|
test "BoxSize::with_payload_size rejects 64-bit overflow" {
  let mdat = @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))
  try @box.BoxSize::with_payload_size(mdat, 18446744073709551615UL) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="box size overflows 64 bits: payload_size=18446744073709551615",
      )
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}

///|
test "BoxSize::variable_size and large_variable_size are distinct values" {
  inspect(@box.BoxSize::variable_size() == @box.BoxSize::U32(0), content="true")
  inspect(
    @box.BoxSize::large_variable_size() == @box.BoxSize::U64(0UL),
    content="true",
  )
  inspect(@box.BoxSize::variable_size().get(), content="0")
  inspect(@box.BoxSize::variable_size().external_size(), content="4")
  inspect(@box.BoxSize::large_variable_size().external_size(), content="12")
}

///|
test "FullBoxFlags round trips through 3 bytes" {
  let cursor = @bytes.ReadCursor::new(b"\x00\x12\x34\xFF")
  let flags : @box.FullBoxFlags = @bytes.decode_from(cursor)
  inspect(flags.get(), content="4660")
  inspect(flags.is_set(0), content="false")
  inspect(flags.is_set(2), content="true")
  inspect(flags.is_set(32), content="false")
  inspect(cursor.position(), content="3")
  inspect(@bytes.encode_to_bytes(flags) == b"\x00\x12\x34", content="true")
}

///|
test "FullBoxFlags masks the high byte on encode" {
  let flags = @box.FullBoxFlags::new(0xAB123456)
  inspect(flags.get(), content="2870096982")
  inspect(flags.is_set(1), content="true")
  inspect(@bytes.encode_to_bytes(flags) == b"\x12\x34\x56", content="true")
}

///|
test "FullBoxFlags::from_flags builds and ignores out of range bits" {
  let flags = @box.FullBoxFlags::from_flags([
    (0, true),
    (3, true),
    (3, false),
    (32, true),
  ])
  inspect(flags.get(), content="9")
  inspect(flags.is_set(0), content="true")
  inspect(flags.is_set(3), content="true")
  inspect(@box.FullBoxFlags::empty().get(), content="0")
}

///|
test "FullBoxHeader decodes version and flags" {
  let cursor = @bytes.ReadCursor::new(b"\x01\x00\x00\x05")
  let header : @box.FullBoxHeader = @bytes.decode_from(cursor)
  inspect(header.version(), content="1")
  inspect(header.flags().get(), content="5")
  inspect(cursor.is_empty(), content="true")
  inspect(@bytes.encode_to_bytes(header) == b"\x01\x00\x00\x05", content="true")
}

///|
test "FullBoxHeader::from_box reads the version and flags of a FullBox" {
  let box = TestFullBox::new(
    @bytes.BoxType::Normal(@bytes.FourCC::from_string("test")),
    7,
    @box.FullBoxFlags::new(0x42),
  )
  let header = @box.FullBoxHeader::from_box(box)
  inspect(header.version(), content="7")
  inspect(header.flags().get(), content="66")
  inspect(@box.FullBoxHeader::from_box(box).flags().is_set(1), content="true")
}

///|
/// `FullBoxHeader::from_box` 用のテストダブル（実ボックスは後続 Issue で実装する）。
struct TestFullBox {
  ty : @bytes.BoxType
  version : UInt32
  flags : @box.FullBoxFlags
}

///|
fn TestFullBox::new(
  ty : @bytes.BoxType,
  version : UInt32,
  flags : @box.FullBoxFlags,
) -> TestFullBox {
  { ty, version, flags, }
}

///|
pub impl @box.BaseBox for TestFullBox with fn box_type(self) {
  self.ty
}

///|
pub impl @box.BaseBox for TestFullBox with fn children(_self) {
  []
}

///|
pub impl @box.FullBox for TestFullBox with fn full_box_version(self) {
  self.version
}

///|
pub impl @box.FullBox for TestFullBox with fn full_box_flags(self) {
  self.flags
}

///|
test "to_canonical folds largesize into size32 when the payload fits" {
  let cursor = @bytes.ReadCursor::new(
    b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x18\x11\x11\x11\x11\x11\x11\x11\x11",
  )
  let (header, _payload) = @box.BoxHeader::decode_header_and_payload(cursor)
  let canonical = header.to_canonical()
  inspect(canonical.box_size() == @box.BoxSize::U32(16), content="true")
  inspect(
    @bytes.encode_to_bytes(canonical) == b"\x00\x00\x00\x10mdat",
    content="true",
  )
  // 元の wire 形式は Encode では保たれる（canonical とは別）
  inspect(
    @bytes.encode_to_bytes(header) ==
    b"\x00\x00\x00\x01mdat\x00\x00\x00\x00\x00\x00\x00\x18",
    content="true",
  )
}

///|
test "to_canonical keeps u32 and large_variable_size" {
  let mdat = @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))
  inspect(
    @box.BoxSize::U32(8).to_canonical(mdat) == @box.BoxSize::U32(8),
    content="true",
  )
  inspect(
    @box.BoxSize::large_variable_size().to_canonical(mdat) ==
    @box.BoxSize::large_variable_size(),
    content="true",
  )
}

///|
test "to_canonical rejects a largesize below the header size" {
  let mdat = @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))
  try @box.BoxSize::U64(4UL).to_canonical(mdat) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="box size is smaller than header size")
    }
  } noraise {
    _ => fail("expected InvalidData")
  }
}
