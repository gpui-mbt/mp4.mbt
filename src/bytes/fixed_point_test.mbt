///|
test "FixedPointNumber accessors" {
  let fp = @bytes.FixedPointNumber::new(-2, 32768)
  inspect(fp.integer(), content="-2")
  inspect(fp.fraction(), content="32768")
  inspect(fp.to_double(16), content="-1.5")
}

///|
test "FixedPointNumber equality uses both parts" {
  inspect(
    @bytes.FixedPointNumber::new(1, 2) == @bytes.FixedPointNumber::new(1, 2),
    content="true",
  )
  inspect(
    @bytes.FixedPointNumber::new(1, 2) == @bytes.FixedPointNumber::new(2, 1),
    content="false",
  )
}
