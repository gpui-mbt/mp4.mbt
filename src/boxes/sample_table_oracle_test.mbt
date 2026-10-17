///|
/// Rust oracle の `sample-tables-cases` が返す `stbl` スナップショット 1 件分
/// （生成データ用）。
///
/// 生成元は `src/boxes/sample_table_oracle_cases_test.mbt`。
struct OracleSampleTableCase {
  name : String
  input : Bytes
  ok : Bool
  snapshot : Array[String]
  error_kind : String
  reason : String
}

///|
/// Rust oracle が fixture から抽出し、上流で再エンコードした `stbl` 1 件分
/// （生成データ用）。
///
/// 生成元は `src/boxes/sample_table_oracle_fixtures_test.mbt`。
struct OracleSampleTableFixture {
  name : String
  track_index : Int32
  stbl : Bytes
  snapshot : Array[String]
}

///|
/// 真偽値を oracle と同じ `true` / `false` にする。
fn sample_table_snapshot_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
/// Rust oracle の `sample-tables` エラー行（`error=accessor` から始まる
/// variant 名とフィールド行）と同じ行を組み立てる。
///
/// フィールド名と値域は `SampleTableAccessorError` の variant 定義に対応する。
fn sample_table_accessor_error_lines(
  error : @boxes.SampleTableAccessorError,
) -> Array[String] {
  let lines : Array[String] = ["error=accessor"]
  match error {
    @boxes.SampleTableAccessorError::InconsistentSampleCount(
      stts_sample_count~,
      other_box_type~,
      other_sample_count~
    ) => {
      lines.push("error.variant=InconsistentSampleCount")
      lines.push("stts_sample_count=\{stts_sample_count}")
      lines.push("other_box_type=\{other_box_type.to_string()}")
      lines.push("other_sample_count=\{other_sample_count}")
    }
    @boxes.SampleTableAccessorError::FirstChunkIndexIsNotOne(
      actual_chunk_index~
    ) => {
      lines.push("error.variant=FirstChunkIndexIsNotOne")
      lines.push("actual_chunk_index=\{actual_chunk_index.get()}")
    }
    @boxes.SampleTableAccessorError::LastChunkIndexIsTooLarge(
      max_chunk_index~,
      last_chunk_index~
    ) => {
      lines.push("error.variant=LastChunkIndexIsTooLarge")
      lines.push("max_chunk_index=\{max_chunk_index.get()}")
      lines.push("last_chunk_index=\{last_chunk_index.get()}")
    }
    @boxes.SampleTableAccessorError::MissingSampleEntry(
      stsc_entry_index~,
      sample_description_index~,
      sample_entry_count~
    ) => {
      lines.push("error.variant=MissingSampleEntry")
      lines.push("stsc_entry_index=\{stsc_entry_index}")
      lines.push("sample_description_index=\{sample_description_index.get()}")
      lines.push("sample_entry_count=\{sample_entry_count}")
    }
    @boxes.SampleTableAccessorError::ChunkIndicesNotMonotonicallyIncreasing =>
      lines.push("error.variant=ChunkIndicesNotMonotonicallyIncreasing")
    @boxes.SampleTableAccessorError::ChunksExistButNoSamples(chunk_count~) => {
      lines.push("error.variant=ChunksExistButNoSamples")
      lines.push("chunk_count=\{chunk_count}")
    }
    @boxes.SampleTableAccessorError::SampleCountOverflow(
      box_type~,
      accumulated_sample_count~,
      entry_sample_count~
    ) => {
      lines.push("error.variant=SampleCountOverflow")
      lines.push("box_type=\{box_type.to_string()}")
      lines.push("accumulated_sample_count=\{accumulated_sample_count}")
      lines.push("entry_sample_count=\{entry_sample_count}")
    }
    @boxes.SampleTableAccessorError::SampleDataOffsetOverflow(
      sample_index~,
      accumulated_offset~,
      sample_data_size~
    ) => {
      lines.push("error.variant=SampleDataOffsetOverflow")
      lines.push("sample_index=\{sample_index.get()}")
      lines.push("accumulated_offset=\{accumulated_offset}")
      lines.push("sample_data_size=\{sample_data_size}")
    }
  }
  lines
}

///|
/// Rust oracle の `sample-tables` スナップショットと同じ行列を組み立てる。
///
/// 行の順序・書式は issue 0009 で凍結されている。`sample[<i>]` / `chunk[<i>]`
/// は 0 始まりの走査順で、`.index=` は 1 始まりの値。アクセサー生成に失敗した
/// 場合は `error=accessor` からの行を返す。
fn sample_table_snapshot(stbl : @boxes.StblBox) -> Array[String] {
  let lines : Array[String] = []
  let accessor : @boxes.SampleTableAccessor? = try
    @boxes.SampleTableAccessor::new(stbl)
  catch {
    error => {
      for line in sample_table_accessor_error_lines(error) {
        lines.push(line)
      }
      None
    }
  } noraise {
    accessor => Some(accessor)
  }
  match accessor {
    None => lines
    Some(table) => {
      lines.push("sample_count=\{table.sample_count()}")
      lines.push("chunk_count=\{table.chunk_count()}")
      let mut chunk_index = 0
      for chunk in table.chunks() {
        lines.push("chunk[\{chunk_index}].index=\{chunk.index().get()}")
        lines.push("chunk[\{chunk_index}].offset=\{chunk.offset()}")
        lines.push("chunk[\{chunk_index}].sample_count=\{chunk.sample_count()}")
        lines.push(
          "chunk[\{chunk_index}].sample_entry_index=\{chunk.sample_entry_index()}",
        )
        chunk_index = chunk_index + 1
      }
      let mut sample_index = 0
      for sample in table.samples() {
        lines.push("sample[\{sample_index}].index=\{sample.index().get()}")
        lines.push("sample[\{sample_index}].timestamp=\{sample.timestamp()}")
        lines.push("sample[\{sample_index}].duration=\{sample.duration()}")
        lines.push(
          "sample[\{sample_index}].data_offset=\{sample.data_offset()}",
        )
        lines.push("sample[\{sample_index}].data_size=\{sample.data_size()}")
        lines.push(
          "sample[\{sample_index}].sync=\{sample_table_snapshot_bool(sample.is_sync_sample())}",
        )
        match sample.composition_time_offset() {
          Some(offset) => lines.push("sample[\{sample_index}].cto=\{offset}")
          None => lines.push("sample[\{sample_index}].cto=none")
        }
        lines.push(
          "sample[\{sample_index}].chunk_index=\{sample.chunk().index().get()}",
        )
        sample_index = sample_index + 1
      }
      lines
    }
  }
}

///|
/// oracle の期待スナップショットと MoonBit 側の [`sample_table_snapshot`] を
/// 比較する。最初に食い違った行だけを報告する。
fn assert_sample_table_snapshot_matches_oracle(
  label : String,
  expected : Array[String],
  stbl : @boxes.StblBox,
) -> Unit raise {
  let actual = sample_table_snapshot(stbl)
  if actual.length() != expected.length() {
    fail(
      "\{label}: snapshot line count differs (oracle=\{expected.length()}, moonbit=\{actual.length()})",
    )
  }
  for i in 0..<actual.length() {
    if actual[i] != expected[i] {
      fail(
        "\{label}: snapshot line \{i} differs (oracle=\{expected[i]}, moonbit=\{actual[i]})",
      )
    }
  }
}

///|
test "sample tables match the rust oracle case table" {
  inspect(oracle_sample_table_cases.length() > 0, content="true")
  for case in oracle_sample_table_cases {
    let cursor = @bytes.ReadCursor::new(case.input)
    let decoded : @boxes.StblBox? = try @bytes.decode_from(cursor) catch {
      @bytes.Mp4Error(kind~, reason~, ..) => {
        if case.ok {
          fail(
            "\{case.name}: oracle succeeded, but moonbit failed with \{oracle_kind_name(kind)}: \{reason}",
          )
        }
        if oracle_kind_name(kind) != case.error_kind {
          fail(
            "\{case.name}: oracle kind \{case.error_kind}, moonbit kind \{oracle_kind_name(kind)} (\{reason})",
          )
        }
        // upstream は insufficient_buffer に理由文を持たない（空文字列）ため、
        // oracle が理由文を持つエラーだけ完全一致を要求する。
        if case.reason != "" && reason != case.reason {
          fail(
            "\{case.name}: oracle reason '\{case.reason}', moonbit reason '\{reason}'",
          )
        }
        None
      }
    } noraise {
      stbl => Some(stbl)
    }
    match decoded {
      Some(stbl) =>
        if case.ok {
          assert_sample_table_snapshot_matches_oracle(
            case.name,
            case.snapshot,
            stbl,
          )
        } else {
          fail(
            "\{case.name}: oracle failed with \{case.error_kind}, but moonbit succeeded",
          )
        }
      None => ()
    }
  }
}

///|
test "sample tables match the rust oracle for fixture stbls" {
  inspect(oracle_sample_table_fixtures.length() > 0, content="true")
  for fixture in oracle_sample_table_fixtures {
    let cursor = @bytes.ReadCursor::new(fixture.stbl)
    let stbl : @boxes.StblBox = @bytes.decode_from(cursor)
    inspect(cursor.is_empty(), content="true")
    assert_sample_table_snapshot_matches_oracle(
      "\{fixture.name} track \{fixture.track_index}",
      fixture.snapshot,
      stbl,
    )
  }
}
