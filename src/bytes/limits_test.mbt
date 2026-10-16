///|
test "default limits are documented constants" {
  let limits = @bytes.ParseLimits::default()
  inspect(limits.max_allocation_size(), content="1073741824")
  inspect(limits.max_nesting_depth(), content="64")
  inspect(@bytes.DEFAULT_MAX_ALLOCATION_SIZE, content="1073741824")
  inspect(@bytes.DEFAULT_MAX_NESTING_DEPTH, content="64")
}

///|
test "custom limits override only the given fields" {
  let limits = @bytes.ParseLimits::new(max_allocation_size=16UL)
  inspect(limits.max_allocation_size(), content="16")
  inspect(limits.max_nesting_depth(), content="64")
  let limits = @bytes.ParseLimits::new(max_nesting_depth=3)
  inspect(limits.max_allocation_size(), content="1073741824")
  inspect(limits.max_nesting_depth(), content="3")
}

///|
test "check_allocation accepts the limit and rejects larger requests" {
  let limits = @bytes.ParseLimits::new(max_allocation_size=4UL)
  limits.check_allocation(4UL)
  try limits.check_allocation(5UL) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="allocation of 5 bytes exceeds ParseLimits.max_allocation_size=4",
      )
    }
  } noraise {
    _ => fail("expected Unsupported")
  }
}

///|
test "check_nesting_depth accepts the limit and rejects deeper nesting" {
  let limits = @bytes.ParseLimits::new(max_nesting_depth=2)
  limits.check_nesting_depth(1)
  limits.check_nesting_depth(2)
  try limits.check_nesting_depth(3) catch {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~) => {
      ignore(offset)
      ignore(loc)
      inspect(kind.to_string(), content="Unsupported")
      inspect(
        reason,
        content="nesting depth 3 exceeds ParseLimits.max_nesting_depth=2",
      )
    }
  } noraise {
    _ => fail("expected Unsupported")
  }
}
