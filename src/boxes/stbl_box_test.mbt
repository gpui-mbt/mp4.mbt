///|
/// `stbl` の必須子ボックスの canonical なバイト列。
fn test_stbl_required_children() -> Array[Bytes] raise {
  [
    @bytes.encode_to_bytes(@boxes.StsdBox::new([])),
    @bytes.encode_to_bytes(@boxes.SttsBox::new([])),
    @bytes.encode_to_bytes(@boxes.StscBox::new([])),
    @bytes.encode_to_bytes(@boxes.StszBox::Variable(entry_sizes=[])),
    @bytes.encode_to_bytes(@boxes.StcoBox::new([])),
  ]
}

///|
/// 必須子から 1 つ（`excluded` に一致するもの）を除いた `stbl` を組み立てる。
fn test_stbl_without(excluded : Bytes) -> Bytes raise {
  let mut payload = b""
  for child in test_stbl_required_children() {
    if child != excluded {
      payload = payload + child
    }
  }
  test_box_bytes(b"stbl", payload)
}

///|
/// テストで使う未知ボックス。
fn test_unknown_box() -> @boxes.UnknownBox raise {
  @bytes.decode_from(@bytes.ReadCursor::new(test_unknown_bytes()))
}

///|
test "stbl with all optional boxes round trips" {
  let stbl = @boxes.StblBox::new(
    @boxes.StsdBox::new([test_sample_entry()]),
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    Some(@boxes.CttsBox::new(1U, [@boxes.CttsEntry::new(1U, -1L)])),
    Some(@boxes.CslgBox::new(0U, 1L, -2L, 3L, -4L, 5L)),
    @boxes.StscBox::new([
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        1U,
        @bytes.NonZeroU32::one(),
      ),
    ]),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    Some(@boxes.StssBox::new([@bytes.NonZeroU32::one()])),
    Some(
      @boxes.SdtpBox::new([
        @boxes.SdtpSampleFlags::from_fields(b'\x00', b'\x01', b'\x00', b'\x00'),
      ]),
    ),
    [test_unknown_box()],
  )
  let encoded = @bytes.encode_to_bytes(stbl)
  let cursor = @bytes.ReadCursor::new(encoded)
  let decoded : @boxes.StblBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == stbl, content="true")
  let children = @box.BaseBox::children(decoded)
  let expected : Array[String] = [
    "stsd", "stts", "ctts", "cslg", "stsc", "stsz", "stco", "stss", "sdtp", "zzzz",
  ]
  inspect(children.length(), content="10")
  for i in 0..<children.length() {
    if @box.BaseBox::box_type(children[i]).to_string() != expected[i] {
      fail(
        "children[\{i}] は \{expected[i]} のはずだが \{@box.BaseBox::box_type(children[i]).to_string()} だった",
      )
    }
  }
}

///|
test "stbl decode keeps the first occurrence and retains duplicates as unknown" {
  let stsd_bytes = @bytes.encode_to_bytes(@boxes.StsdBox::new([]))
  let mut payload = b""
  for child in test_stbl_required_children() {
    payload = payload + child
  }
  payload = payload + stsd_bytes
  let bytes = test_box_bytes(b"stbl", payload)
  let decoded : @boxes.StblBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="stsd")
  inspect(decoded.stsd_box.entries.length(), content="0")
}

///|
test "stbl decode keeps stco and consumes co64 when both are present" {
  let mut payload = b""
  for child in test_stbl_required_children() {
    payload = payload + child
  }
  payload = payload +
    @bytes.encode_to_bytes(@boxes.Co64Box::new([0x100000000UL]))
  let bytes = test_box_bytes(b"stbl", payload)
  let decoded : @boxes.StblBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  match decoded.stco_or_co64_box {
    @bytes.Either::A(stco) => inspect(stco.chunk_offsets.length(), content="0")
    @bytes.Either::B(_) => fail("stco が優先されるはず")
  }
  inspect(decoded.unknown_boxes.length(), content="0")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="5")
  inspect(@box.BaseBox::box_type(children[4]).to_string(), content="stco")
}

///|
test "stbl decode fails on a malformed co64 even when stco is present" {
  // co64 は count 1 を宣言しつつオフセットが欠けている。
  let malformed_co64 = test_box_bytes(
    b"co64",
    b"\x00\x00\x00\x00" + b"\x00\x00\x00\x01",
  )
  let mut payload = b""
  for child in test_stbl_required_children() {
    payload = payload + child
  }
  payload = payload + malformed_co64
  let bytes = test_box_bytes(b"stbl", payload)
  let cursor = @bytes.ReadCursor::new(bytes)
  let result : @boxes.StblBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, ..) => {
      inspect(kind.to_string(), content="InsufficientBuffer")
      None
    }
  } noraise {
    stbl => Some(stbl)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "stbl decode requires every mandatory child" {
  let stsd_bytes = @bytes.encode_to_bytes(@boxes.StsdBox::new([]))
  let stts_bytes = @bytes.encode_to_bytes(@boxes.SttsBox::new([]))
  let stsc_bytes = @bytes.encode_to_bytes(@boxes.StscBox::new([]))
  let stsz_bytes = @bytes.encode_to_bytes(
    @boxes.StszBox::Variable(entry_sizes=[]),
  )
  let stco_bytes = @bytes.encode_to_bytes(@boxes.StcoBox::new([]))
  let cases : Array[(Bytes, String)] = [
    (stsd_bytes, "Missing mandatory 'stsd' box in 'stbl' box"),
    (stts_bytes, "Missing mandatory 'stts' box in 'stbl' box"),
    (stsc_bytes, "Missing mandatory 'stsc' box in 'stbl' box"),
    (stsz_bytes, "Missing mandatory 'stsz' box in 'stbl' box"),
    (stco_bytes, "Missing mandatory 'stco' or 'co64' box in 'stbl' box"),
  ]
  for case in cases {
    let (excluded, expected) = case
    let bytes = test_stbl_without(excluded)
    let cursor = @bytes.ReadCursor::new(bytes)
    let result : @boxes.StblBox? = try @bytes.decode_from(cursor) catch {
      @bytes.Mp4Error(kind~, reason~, ..) => {
        inspect(kind.to_string(), content="InvalidData")
        if reason != expected {
          fail(
            "理由文字列が \{expected} ではなく \{reason} だった",
          )
        }
        None
      }
    } noraise {
      stbl => Some(stbl)
    }
    inspect(result is None, content="true")
    // 失敗時はデコード開始位置まで巻き戻す。
    inspect(cursor.position(), content="0")
  }
}

///|
test "stbl decode failure rewinds to the start position of the box" {
  let stco_bytes = @bytes.encode_to_bytes(@boxes.StcoBox::new([]))
  let bytes = test_unknown_bytes() + test_stbl_without(stco_bytes)
  let cursor = @bytes.ReadCursor::new(bytes)
  cursor.skip(8)
  let result : @boxes.StblBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(..) => None
  } noraise {
    stbl => Some(stbl)
  }
  inspect(result is None, content="true")
  // 先頭の未知ボックス分（8 バイト）へ戻る。
  inspect(cursor.position(), content="8")
}
