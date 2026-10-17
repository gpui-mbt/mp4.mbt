///|
test "mdia round trips" {
  let mdia = test_mdia()
  let bytes = @bytes.encode_to_bytes(mdia)
  let cursor = @bytes.ReadCursor::new(bytes)
  let decoded : @boxes.MdiaBox = @bytes.decode_from(cursor)
  inspect(cursor.is_empty(), content="true")
  inspect(decoded == mdia, content="true")
  inspect(@box.BaseBox::box_type(decoded).to_string(), content="mdia")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="3")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="mdhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="hdlr")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="minf")
}

///|
test "mdia requires mdhd" {
  let payload = @bytes.encode_to_bytes(test_hdlr()) +
    @bytes.encode_to_bytes(test_minf())
  let cursor = @bytes.ReadCursor::new(test_box_bytes(b"mdia", payload))
  let result : @boxes.MdiaBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'mdhd' box in 'mdia' box")
      None
    }
  } noraise {
    mdia => Some(mdia)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "mdia requires hdlr" {
  let payload = @bytes.encode_to_bytes(test_mdhd()) +
    @bytes.encode_to_bytes(test_minf())
  let cursor = @bytes.ReadCursor::new(test_box_bytes(b"mdia", payload))
  let result : @boxes.MdiaBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'hdlr' box in 'mdia' box")
      None
    }
  } noraise {
    mdia => Some(mdia)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "mdia requires minf" {
  let payload = @bytes.encode_to_bytes(test_mdhd()) +
    @bytes.encode_to_bytes(test_hdlr())
  let cursor = @bytes.ReadCursor::new(test_box_bytes(b"mdia", payload))
  let result : @boxes.MdiaBox? = try @bytes.decode_from(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="Missing mandatory 'minf' box in 'mdia' box")
      None
    }
  } noraise {
    mdia => Some(mdia)
  }
  inspect(result is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "mdia keeps the first hdlr and retains later ones as unknown" {
  let mdhd = @bytes.encode_to_bytes(test_mdhd())
  let hdlr = @bytes.encode_to_bytes(test_hdlr())
  let minf = @bytes.encode_to_bytes(test_minf())
  let bytes = test_box_bytes(b"mdia", mdhd + hdlr + hdlr + minf)
  let decoded : @boxes.MdiaBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="hdlr")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="4")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="mdhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="hdlr")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="minf")
  inspect(@box.BaseBox::box_type(children[3]).to_string(), content="hdlr")
  inspect(children[3].is_unknown_box(), content="true")
}

///|
test "mdia retains unknown children in order" {
  let mdhd = @bytes.encode_to_bytes(test_mdhd())
  let hdlr = @bytes.encode_to_bytes(test_hdlr())
  let minf = @bytes.encode_to_bytes(test_minf())
  let other = test_box_bytes(b"yyyy", b"\x01")
  let bytes = test_box_bytes(
    b"mdia",
    test_unknown_bytes() + mdhd + hdlr + minf + other,
  )
  let decoded : @boxes.MdiaBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.unknown_boxes.length(), content="2")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="zzzz")
  inspect(decoded.unknown_boxes[1].box_type.to_string(), content="yyyy")
  let children = @box.BaseBox::children(decoded)
  inspect(children.length(), content="5")
  inspect(@box.BaseBox::box_type(children[0]).to_string(), content="mdhd")
  inspect(@box.BaseBox::box_type(children[1]).to_string(), content="hdlr")
  inspect(@box.BaseBox::box_type(children[2]).to_string(), content="minf")
  inspect(@box.BaseBox::box_type(children[3]).to_string(), content="zzzz")
  inspect(@box.BaseBox::box_type(children[4]).to_string(), content="yyyy")
}
