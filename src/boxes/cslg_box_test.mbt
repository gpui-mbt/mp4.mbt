///|
test "cslg version 0 round trips i32 range values" {
  let cslg = @boxes.CslgBox::new(0U, 1L, -2L, 2147483647L, -2147483648L, 5L)
  let encoded = @bytes.encode_to_bytes(cslg)
  inspect(encoded[8].to_uint(), content="0")
  // header (8) + full box header (4) + 5 * i32 (20)
  inspect(encoded.length(), content="32")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.CslgBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == cslg, content="true")
}

///|
test "cslg version 1 round trips values beyond i32" {
  let cslg = @boxes.CslgBox::new(
    1U, 4294967296L, -4294967297L, 9223372036854775807L, -9223372036854775808L, 5L,
  )
  let encoded = @bytes.encode_to_bytes(cslg)
  inspect(encoded[8].to_uint(), content="1")
  // header (8) + full box header (4) + 5 * i64 (40)
  inspect(encoded.length(), content="52")
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.CslgBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == cslg, content="true")
  inspect(decoded.composition_to_dts_shift, content="4294967296")
  inspect(
    decoded.greatest_decode_to_display_delta,
    content="9223372036854775807",
  )
}

///|
test "cslg encode rejects an unknown version" {
  let cslg = @boxes.CslgBox::new(2U, 0L, 0L, 0L, 0L, 0L)
  let result : Bytes? = try @bytes.encode_to_bytes(cslg) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="Invalid cslg box version: 2")
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
}

///|
test "cslg version 0 encode rejects values outside i32" {
  let too_large = @boxes.CslgBox::new(0U, 2147483648L, 0L, 0L, 0L, 0L)
  let result : Bytes? = try @bytes.encode_to_bytes(too_large) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="cslg version 0 requires composition_to_dts_shift to be in i32 range, got 2147483648",
      )
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
  let too_small = @boxes.CslgBox::new(0U, 0L, 0L, 0L, 0L, -2147483649L)
  let result : Bytes? = try @bytes.encode_to_bytes(too_small) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="cslg version 0 requires composition_end_time to be in i32 range, got -2147483649",
      )
      None
    }
  } noraise {
    bytes => Some(bytes)
  }
  inspect(result is None, content="true")
}

///|
test "cslg decode rejects an unknown version" {
  let bytes = test_box_bytes(b"cslg", b"\x03\x00\x00\x00" + b"\x00\x00\x00\x00")
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.CslgBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Invalid cslg box version: 3")
      None
    }
  } noraise {
    cslg => Some(cslg)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}
