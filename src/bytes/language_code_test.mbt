///|
test "language code accepts only 3 bytes in 0x60..=0x7f" {
  inspect(@bytes.LanguageCode::new(b"und") is Some(_), content="true")
  inspect(@bytes.LanguageCode::new(b"~~~") is Some(_), content="true")
  // 0x60（`）と 0x7F（DEL）は境界内
  inspect(@bytes.LanguageCode::new(b"`\x7F`") is Some(_), content="true")
  // 範囲外のバイト
  inspect(@bytes.LanguageCode::new(b"ENG") is None, content="true")
  inspect(@bytes.LanguageCode::new(b"eng ") is None, content="true")
  inspect(@bytes.LanguageCode::new(b"en") is None, content="true")
  inspect(@bytes.LanguageCode::new(b"\x5Fng") is None, content="true")
  inspect(@bytes.LanguageCode::new(b"\x80ng") is None, content="true")
}

///|
test "language code from ascii" {
  inspect(@bytes.LanguageCode::from_ascii("eng") is Some(_), content="true")
  inspect(@bytes.LanguageCode::from_ascii("jpn") is Some(_), content="true")
  inspect(@bytes.LanguageCode::from_ascii("ENG") is None, content="true")
  inspect(@bytes.LanguageCode::from_ascii("ab") is None, content="true")
  inspect(@bytes.LanguageCode::from_ascii("abcd") is None, content="true")
  // マルチバイト UTF-8 はバイト長が 3 でないため拒否される
  inspect(@bytes.LanguageCode::from_ascii("日") is None, content="true")
}

///|
test "language code undefined and default" {
  inspect(@bytes.LanguageCode::undefined().to_string(), content="und")
  inspect(
    @bytes.LanguageCode::default() == @bytes.LanguageCode::undefined(),
    content="true",
  )
  inspect(@bytes.LanguageCode::default().as_bytes() == b"und", content="true")
}

///|
test "language code shows three characters" {
  let code = @bytes.LanguageCode::new(b"jpn").unwrap()
  inspect(code.to_string(), content="jpn")
  // Debug 表現は文字列としての 3 文字（`"jpn"`）になる
  inspect(repr(code), content="\"jpn\"")
}

///|
test "language code packs into 5 bit fields" {
  // "eng" = (5 << 10) | (14 << 5) | 7
  inspect(
    @bytes.LanguageCode::from_ascii("eng").unwrap().to_packed(),
    content="5575",
  )
  // "und" = (21 << 10) | (14 << 5) | 4
  inspect(
    @bytes.LanguageCode::from_ascii("und").unwrap().to_packed(),
    content="21956",
  )
  inspect(@bytes.LanguageCode::from_packed(5575).to_string(), content="eng")
  inspect(
    @bytes.LanguageCode::from_packed(5575) ==
    @bytes.LanguageCode::from_ascii("eng").unwrap(),
    content="true",
  )
  // 5 ビットで表現できる全域（{|}~ と 0x7F）も往復する
  let boundary = @bytes.LanguageCode::new(b"~~~").unwrap()
  inspect(
    @bytes.LanguageCode::from_packed(boundary.to_packed()) == boundary,
    content="true",
  )
  let del = @bytes.LanguageCode::new(b"\x7F\x7F\x7F").unwrap()
  inspect(
    @bytes.LanguageCode::from_packed(del.to_packed()) == del,
    content="true",
  )
}
