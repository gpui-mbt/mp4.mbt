///|
test "uint64_to_index accepts Int index range" {
  inspect(@bytes.uint64_to_index(0UL, "offset"), content="0")
  inspect(@bytes.uint64_to_index(2147483647UL, "offset"), content="2147483647")
}

///|
test "uint64_to_index rejects values above Int range instead of wrapping" {
  try @bytes.uint64_to_index(2147483648UL, "offset") catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="offset 2147483648 does not fit in an Int index")
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
  try @bytes.uint64_to_index(18446744073709551615UL, "size") catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(kind)
      ignore(offset)
      ignore(loc)
      inspect(
        reason,
        content="size 18446744073709551615 does not fit in an Int index",
      )
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}

///|
test "uint64_to_exact_double accepts values up to 2^53" {
  inspect(@bytes.uint64_to_exact_double(0UL) == 0.0, content="true")
  inspect(
    @bytes.uint64_to_exact_double(@bytes.MAX_EXACT_DOUBLE_INTEGER) ==
    9007199254740992.0,
    content="true",
  )
}

///|
test "uint64_to_exact_double rejects values that would round" {
  try @bytes.uint64_to_exact_double(9007199254740993UL) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="InvalidInput")
      inspect(
        reason,
        content="UInt64 value 9007199254740993 cannot be represented exactly as Double",
      )
    }
  } noraise {
    _ => fail("expected InvalidInput")
  }
}
