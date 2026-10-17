///|
test "uint from bits extracts the field range" {
  let value = @bytes.Uint::from_bits(0b1010_1100UL, bits=3, offset=5)
  inspect(value.get(), content="5")
  inspect(value.bits, content="3")
  inspect(value.offset, content="5")
  // 隣接ビットはマスクされる
  inspect(@bytes.Uint::from_bits(0xFFUL, bits=2, offset=0).get(), content="3")
  // 64 ビット全域を取り出せる
  inspect(
    @bytes.Uint::from_bits(0xFFFF_FFFF_FFFF_FFFFUL, bits=64, offset=0).get(),
    content="18446744073709551615",
  )
}

///|
test "uint to bits shifts the value into its field" {
  let value = @bytes.Uint::new(1UL, bits=1, offset=7).unwrap()
  inspect(value.to_bits(), content="128")
  inspect(
    @bytes.Uint::new(0x1FUL, bits=6, offset=2).unwrap().to_bits(),
    content="124",
  )
}

///|
test "uint new validates the descriptor and the value range" {
  inspect(@bytes.Uint::new(3UL, bits=2, offset=0) is Some(_), content="true")
  inspect(@bytes.Uint::new(4UL, bits=2, offset=0) is None, content="true")
  inspect(@bytes.Uint::new(0UL, bits=0, offset=0) is None, content="true")
  inspect(@bytes.Uint::new(1UL, bits=1, offset=63) is Some(_), content="true")
  inspect(@bytes.Uint::new(1UL, bits=2, offset=63) is None, content="true")
  inspect(
    @bytes.Uint::new(0xFFFF_FFFF_FFFF_FFFFUL, bits=64, offset=0) is Some(_),
    content="true",
  )
}

///|
test "uint as bool reports a one bit flag" {
  inspect(
    @bytes.Uint::from_bits(0b1000_0000UL, bits=1, offset=7).as_bool(),
    content="true",
  )
  inspect(
    @bytes.Uint::from_bits(0b0111_1111UL, bits=1, offset=7).as_bool(),
    content="false",
  )
}
