///|
test "mp4 file time holds seconds since 1904" {
  let t = @bytes.Mp4FileTime::from_secs(3600UL)
  inspect(t.as_secs(), content="3600")
  inspect(@bytes.Mp4FileTime::default().as_secs(), content="0")
  inspect(
    @bytes.Mp4FileTime::from_secs(1UL) == @bytes.Mp4FileTime::from_secs(1UL),
    content="true",
  )
  inspect(
    @bytes.Mp4FileTime::from_secs(1UL) == @bytes.Mp4FileTime::from_secs(2UL),
    content="false",
  )
}

///|
test "mp4 file time converts unix epoch seconds" {
  // 1904-01-01 から 1970-01-01 までの経過秒数は 2082844800
  inspect(
    @bytes.Mp4FileTime::from_unix_seconds(0UL).as_secs(),
    content="2082844800",
  )
  inspect(
    @bytes.Mp4FileTime::from_unix_seconds(1UL).as_secs(),
    content="2082844801",
  )
}

///|
test "mp4 file time compares by seconds" {
  let earlier = @bytes.Mp4FileTime::from_secs(10UL)
  let later = @bytes.Mp4FileTime::from_secs(20UL)
  inspect(earlier < later, content="true")
  inspect(later > earlier, content="true")
  inspect(earlier <= earlier, content="true")
  inspect(earlier >= earlier, content="true")
  inspect(earlier.compare(later) < 0, content="true")
  // u32::MAX を超える値も丸めずに比較できる
  let huge = @bytes.Mp4FileTime::from_secs(4294967296UL)
  inspect(huge > @bytes.Mp4FileTime::from_secs(4294967295UL), content="true")
}
