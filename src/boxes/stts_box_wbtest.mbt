///|
test "push_sample_delta rejects a sample_count overflow" {
  let entries : Array[SttsEntry] = [SttsEntry::new(0xFFFFFFFFU, 10U)]
  let result : Unit? = try push_sample_delta(entries, 10U) catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="stts sample_count overflow")
      None
    }
  } noraise {
    _ => Some(())
  }
  inspect(result is None, content="true")
  // 失敗してもエントリー列は破壊されない。
  inspect(entries.length(), content="1")
  inspect(entries[0].sample_count, content="4294967295")
}

///|
test "push_sample_delta starts a new run for a different delta" {
  let entries : Array[SttsEntry] = [SttsEntry::new(1U, 10U)]
  push_sample_delta(entries, 20U)
  inspect(entries.length(), content="2")
  inspect(entries[1].sample_count, content="1")
  inspect(entries[1].sample_delta, content="20")
}
