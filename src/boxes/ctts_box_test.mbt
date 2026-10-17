///|
test "ctts version 0 round trips non-negative offsets" {
  let ctts = @boxes.CttsBox::new(0U, [
    @boxes.CttsEntry::new(2U, 0L),
    @boxes.CttsEntry::new(1U, 4294967295L),
  ])
  let encoded = @bytes.encode_to_bytes(ctts)
  inspect(encoded[8].to_uint(), content="0")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.CttsBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == ctts, content="true")
  inspect(decoded.entries[0].sample_offset, content="0")
  inspect(decoded.entries[1].sample_offset, content="4294967295")
}

///|
test "ctts version 1 round trips negative and i32 max offsets" {
  let ctts = @boxes.CttsBox::new(1U, [
    @boxes.CttsEntry::new(1U, -2147483648L),
    @boxes.CttsEntry::new(1U, 2147483647L),
  ])
  let encoded = @bytes.encode_to_bytes(ctts)
  inspect(encoded[8].to_uint(), content="1")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.CttsBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == ctts, content="true")
  inspect(decoded.entries[0].sample_offset, content="-2147483648")
  inspect(decoded.entries[1].sample_offset, content="2147483647")
}

///|
test "ctts with no entries keeps its version" {
  let ctts = @boxes.CttsBox::new(1U, [])
  let encoded = @bytes.encode_to_bytes(ctts)
  inspect(encoded.length(), content="16")
  let decoded : @boxes.CttsBox = @bytes.decode_from(
    @bytes.ReadCursor::new(encoded),
  )
  inspect(decoded.version, content="1")
  inspect(decoded.entries.length(), content="0")
}

///|
test "ctts encode rejects a negative offset in version 0" {
  let ctts = @boxes.CttsBox::new(0U, [@boxes.CttsEntry::new(1U, -1L)])
  let result : Bytes? = try @bytes.encode_to_bytes(ctts) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="ctts version 0 requires non-negative sample_offset, got -1",
      )
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
}

///|
test "ctts encode rejects an offset above u32 in version 0" {
  let ctts = @boxes.CttsBox::new(0U, [@boxes.CttsEntry::new(1U, 4294967296L)])
  let result : Bytes? = try @bytes.encode_to_bytes(ctts) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="ctts version 0 requires non-negative sample_offset, got 4294967296",
      )
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
}

///|
test "ctts encode rejects offsets outside i32 in version 1" {
  let too_small = @boxes.CttsBox::new(1U, [
    @boxes.CttsEntry::new(1U, -2147483649L),
  ])
  let result : Bytes? = try @bytes.encode_to_bytes(too_small) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="ctts version 1 requires sample_offset to be in i32 range, got -2147483649",
      )
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
  let too_large = @boxes.CttsBox::new(1U, [
    @boxes.CttsEntry::new(1U, 2147483648L),
  ])
  let result : Bytes? = try @bytes.encode_to_bytes(too_large) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="ctts version 1 requires sample_offset to be in i32 range, got 2147483648",
      )
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
}

///|
test "ctts encode rejects an unknown version" {
  let ctts = @boxes.CttsBox::new(2U, [])
  let result : Bytes? = try @bytes.encode_to_bytes(ctts) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Invalid ctts box version: 2")
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
}

///|
test "ctts decode rejects an unknown version" {
  let bytes = test_box_bytes(b"ctts", b"\x02\x00\x00\x00" + b"\x00\x00\x00\x00")
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.CttsBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Invalid ctts box version: 2")
      None
    }
  } noraise {
    ctts => Some(ctts)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
