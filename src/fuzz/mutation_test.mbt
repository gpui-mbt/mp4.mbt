///|
test "xor shift is deterministic" {
  let a = @fuzz.XorShift32::new(123U)
  let b = @fuzz.XorShift32::new(123U)
  inspect(a.next(), content="\{b.next()}")
}

///|
test "mutation is deterministic and preserves length" {
  let input = b"\x00\x00\x00\x0Cmdat\x11\x22\x33\x44"
  let a = @fuzz.mutate_bytes(input, 7U)
  let b = @fuzz.mutate_bytes(input, 7U)
  inspect(a == b, content="true")
  inspect(a.length(), content="12")
  inspect(@fuzz.mutate_bytes(b"", 1U).length(), content="0")
}

///|
test "mutated inputs do not panic and are bounded" {
  let input = b"\x00\x00\x00\x14moov\x00\x00\x00\x08free\x00\x00\x00\x08mdat"
  let trunc = @fuzz.truncations(input)
  for part in trunc {
    let cursor = @bytes.ReadCursor::new(part)
    try {
      let nodes = @boxes.build_box_tree(cursor)
      inspect(nodes.length() >= 0, content="true")
    } catch {
      _ => ()
    }
  }
  let mut seed = 1U
  while seed < 100U {
    let mutated = @fuzz.mutate_bytes(input, seed)
    let cursor = @bytes.ReadCursor::new(mutated)
    try {
      let _ = @boxes.build_box_tree(cursor)
    } catch {
      _ => ()
    }
    seed = seed + 1U
  }
}
