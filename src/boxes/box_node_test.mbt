///|
test "box tree observes top level order and boundaries" {
  let bytes = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomavc1" +
    b"\x00\x00\x00\x08free" +
    b"\x00\x00\x00\x0Cmdat\x11\x22\x33\x44"
  let cursor = @bytes.ReadCursor::new(bytes)
  let nodes = @boxes.build_box_tree(cursor)
  inspect(nodes.length(), content="3")
  inspect(nodes[0].box_type().to_string(), content="ftyp")
  inspect(nodes[0].start(), content="0")
  inspect(nodes[0].header_bytes(), content="8")
  inspect(nodes[0].declared_size(), content="24")
  inspect(nodes[0].total_size(), content="24")
  inspect(nodes[0].end(), content="24")
  inspect(nodes[0].payload_size(), content="16")
  inspect(nodes[0].is_variable_size(), content="false")
  inspect(nodes[1].box_type().to_string(), content="free")
  inspect(nodes[1].start(), content="24")
  inspect(nodes[1].payload_size(), content="0")
  inspect(nodes[2].box_type().to_string(), content="mdat")
  inspect(nodes[2].start(), content="32")
  inspect(nodes[2].payload_start(), content="40")
  inspect(nodes[2].payload_size(), content="4")
  inspect(nodes[2].children().length(), content="0")
  inspect(cursor.is_empty(), content="true")
}

///|
test "box tree recurses into plain containers" {
  let bytes = b"\x00\x00\x00\x18moov" +
    b"\x00\x00\x00\x10trak" +
    b"\x00\x00\x00\x08mdia"
  let nodes = @boxes.build_box_tree(@bytes.ReadCursor::new(bytes))
  inspect(nodes.length(), content="1")
  let moov = nodes[0]
  inspect(moov.children().length(), content="1")
  let trak = moov.children()[0]
  inspect(trak.box_type().to_string(), content="trak")
  inspect(trak.start(), content="8")
  inspect(trak.children().length(), content="1")
  inspect(trak.children()[0].box_type().to_string(), content="mdia")
  inspect(trak.children()[0].start(), content="16")
  let flat = @boxes.flatten_box_tree(nodes)
  inspect(flat.length(), content="3")
  let (d0, n0) = flat[0]
  let (d1, n1) = flat[1]
  let (d2, n2) = flat[2]
  inspect(d0, content="1")
  inspect(n0.box_type().to_string(), content="moov")
  inspect(d1, content="2")
  inspect(n1.box_type().to_string(), content="trak")
  inspect(d2, content="3")
  inspect(n2.box_type().to_string(), content="mdia")
  inspect(n2.children().length(), content="0")
}

///|
test "box tree accepts a top level size zero box" {
  let bytes = b"\x00\x00\x00\x00zzzz\xAA\xBB"
  let nodes = @boxes.build_box_tree(@bytes.ReadCursor::new(bytes))
  inspect(nodes.length(), content="1")
  inspect(nodes[0].is_variable_size(), content="true")
  inspect(nodes[0].declared_size(), content="0")
  inspect(nodes[0].total_size(), content="10")
  inspect(nodes[0].payload_size(), content="2")
}

///|
test "box tree rejects a nested size zero box" {
  let bytes = b"\x00\x00\x00\x10moov" + b"\x00\x00\x00\x00zzzz"
  let cursor = @bytes.ReadCursor::new(bytes)
  let nodes : Array[@boxes.BoxNode]? = try @boxes.build_box_tree(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, box_type~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="size=0 box is only allowed at the top level")
      inspect(offset == Some(8UL), content="true")
      inspect(
        box_type ==
        Some(@bytes.BoxType::Normal(@bytes.FourCC::from_string("zzzz"))),
        content="true",
      )
      None
    }
  } noraise {
    nodes => Some(nodes)
  }
  inspect(nodes is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "box tree rejects a nested declared size below the header" {
  let bytes = b"\x00\x00\x00\x10moov" + b"\x00\x00\x00\x04zzzz"
  let cursor = @bytes.ReadCursor::new(bytes)
  let nodes : Array[@boxes.BoxNode]? = try @boxes.build_box_tree(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="Too small box size: actual=4, expected=8 or more",
      )
      inspect(offset is None, content="true")
      None
    }
  } noraise {
    nodes => Some(nodes)
  }
  inspect(nodes is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "box tree rejects a child that exceeds the parent boundary" {
  let bytes = b"\x00\x00\x00\x10moov" + b"\x00\x00\x00\x0Czzzz"
  let cursor = @bytes.ReadCursor::new(bytes)
  let nodes : Array[@boxes.BoxNode]? = try @boxes.build_box_tree(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, ..) => {
      inspect(kind.to_string(), content="InsufficientBuffer")
      inspect(reason, content="required 12 bytes, but only 8 bytes available")
      inspect(offset == Some(8UL), content="true")
      None
    }
  } noraise {
    nodes => Some(nodes)
  }
  inspect(nodes is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "box tree stops at the depth limit with Unsupported" {
  let bytes = b"\x00\x00\x00\x18moov" +
    b"\x00\x00\x00\x10trak" +
    b"\x00\x00\x00\x08mdia"
  let options = @boxes.BoxTreeOptions::new().with_max_depth(2)
  let cursor = @bytes.ReadCursor::new(bytes)
  let nodes : Array[@boxes.BoxNode]? = try
    @boxes.build_box_tree(cursor, options~)
  catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="nesting depth 3 exceeds BoxTreeOptions.max_depth=2",
      )
      None
    }
  } noraise {
    nodes => Some(nodes)
  }
  inspect(nodes is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "box tree stops at the node limit with Unsupported" {
  let bytes = b"\x00\x00\x00\x08free" +
    b"\x00\x00\x00\x08free" +
    b"\x00\x00\x00\x08free"
  let options = @boxes.BoxTreeOptions::new().with_max_nodes(2)
  let cursor = @bytes.ReadCursor::new(bytes)
  let nodes : Array[@boxes.BoxNode]? = try
    @boxes.build_box_tree(cursor, options~)
  catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="box tree node count exceeds BoxTreeOptions.max_nodes=2",
      )
      None
    }
  } noraise {
    nodes => Some(nodes)
  }
  inspect(nodes is None, content="true")
  inspect(cursor.position(), content="0")
}

///|
test "box tree default depth follows the cursor parse limits" {
  let bytes = b"\x00\x00\x00\x18moov" +
    b"\x00\x00\x00\x10trak" +
    b"\x00\x00\x00\x08mdia"
  let limits = @bytes.ParseLimits::new(max_nesting_depth=2)
  let cursor = @bytes.ReadCursor::with_config(bytes, 0UL, limits)
  let nodes : Array[@boxes.BoxNode]? = try @boxes.build_box_tree(cursor) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="nesting depth 3 exceeds BoxTreeOptions.max_depth=2",
      )
      None
    }
  } noraise {
    nodes => Some(nodes)
  }
  inspect(nodes is None, content="true")
}

///|
test "box tree walks a large mdat without copying the payload" {
  let writer = @bytes.WriteCursor::new()
  writer.write_u32(8U + 65536U)
  writer.write_bytes(b"mdat")
  writer.write_bytes(b"\x11".repeat(65536))
  let limits = @bytes.ParseLimits::new(max_allocation_size=16UL)
  let cursor = @bytes.ReadCursor::with_config(writer.to_bytes(), 0UL, limits)
  let nodes = @boxes.build_box_tree(cursor)
  inspect(nodes.length(), content="1")
  inspect(nodes[0].payload_start(), content="8")
  inspect(nodes[0].payload_size(), content="65536")
  inspect(nodes[0].children().length(), content="0")
  inspect(cursor.is_empty(), content="true")
}

///|
test "box tree container predicate can be replaced" {
  let bytes = b"\x00\x00\x00\x10cust" + b"\x00\x00\x00\x08free"
  let options = @boxes.BoxTreeOptions::new().with_container_predicate(fn(
    box_type,
  ) {
    box_type.as_bytes() == b"cust"
  })
  let nodes = @boxes.build_box_tree(@bytes.ReadCursor::new(bytes), options~)
  inspect(nodes.length(), content="1")
  inspect(nodes[0].box_type().to_string(), content="cust")
  inspect(nodes[0].children().length(), content="1")
  inspect(nodes[0].children()[0].box_type().to_string(), content="free")
  inspect(
    @boxes.is_plain_container_box_type(
      @bytes.BoxType::Normal(@bytes.FourCC::from_string("moov")),
    ),
    content="true",
  )
  inspect(
    @boxes.is_plain_container_box_type(
      @bytes.BoxType::Normal(@bytes.FourCC::from_string("stsd")),
    ),
    content="false",
  )
}

///|
test "box tree dump lines show depth type position and size" {
  let bytes = b"\x00\x00\x00\x10moov" +
    b"\x00\x00\x00\x08trak" +
    b"\x00\x00\x00\x0Azzzz\xAA\xBB"
  let nodes = @boxes.build_box_tree(@bytes.ReadCursor::new(bytes))
  let flat = @boxes.flatten_box_tree(nodes)
  inspect(flat.length(), content="3")
  let (d0, n0) = flat[0]
  let (d1, n1) = flat[1]
  let (d2, n2) = flat[2]
  inspect(
    n0.dump_line(d0),
    content="d=1 moov start=0 size=16 header=8 payload=8",
  )
  inspect(
    n1.dump_line(d1),
    content="d=2 trak start=8 size=8 header=8 payload=0",
  )
  inspect(
    n2.dump_line(d2),
    content="d=1 zzzz start=16 size=10 header=8 payload=2",
  )
}

///|
test "box tree dump marks a variable size box" {
  let nodes = @boxes.build_box_tree(
    @bytes.ReadCursor::new(b"\x00\x00\x00\x00zzzz\xAA\xBB"),
  )
  inspect(
    nodes[0].dump_line(1),
    content="d=1 zzzz start=0 size=10 (to end) header=8 payload=2",
  )
}
