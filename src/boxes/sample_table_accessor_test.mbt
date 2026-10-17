///|
/// アクセサーのテスト用に 1 エントリーの `stsd` を持つ `stbl` を組み立てる。
fn accessor_stbl(
  stts : @boxes.SttsBox,
  stsc : @boxes.StscBox,
  stsz : @boxes.StszBox,
  stco_or_co64 : @bytes.Either[@boxes.StcoBox, @boxes.Co64Box],
  stss : @boxes.StssBox?,
  ctts : @boxes.CttsBox?,
) -> @boxes.StblBox raise {
  @boxes.StblBox::new(
    @boxes.StsdBox::new([test_sample_entry()]),
    stts,
    ctts,
    None,
    stsc,
    stsz,
    stco_or_co64,
    stss,
    None,
    [],
  )
}

///|
/// アクセサー生成のエラーを捕捉する（成功時は `None`）。
fn accessor_error(
  stbl_box : @boxes.StblBox,
) -> @boxes.SampleTableAccessorError? {
  let result : Result[
    @boxes.SampleTableAccessor,
    @boxes.SampleTableAccessorError,
  ] = try @boxes.SampleTableAccessor::new(stbl_box) catch {
    err => Err(err)
  } noraise {
    table => Ok(table)
  }
  match result {
    Ok(_) => None
    Err(err) => Some(err)
  }
}

///|
/// 1 エントリー・1 サンプルの最小構成の `stsc`。
fn accessor_stsc(
  first_chunk : @bytes.NonZeroU32,
  sample_per_chunk : UInt32,
) -> @boxes.StscBox {
  @boxes.StscBox::new([
    @boxes.StscEntry::new(
      first_chunk,
      sample_per_chunk,
      @bytes.NonZeroU32::one(),
    ),
  ])
}

///|
test "accessor walks samples, chunks and timestamps like upstream" {
  let durations = [10U, 5U, 5U, 20U, 20U, 20U, 1U, 1U, 1U, 1U]
  let stbl = accessor_stbl(
    @boxes.SttsBox::from_sample_deltas(durations.iter()),
    @boxes.StscBox::new([
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        2U,
        @bytes.NonZeroU32::one(),
      ),
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::new(3U).unwrap(),
        3U,
        @bytes.NonZeroU32::one(),
      ),
    ]),
    @boxes.StszBox::Variable(entry_sizes=[
      1U, 2U, 3U, 4U, 5U, 6U, 7U, 8U, 9U, 10U,
    ]),
    @bytes.Either::A(@boxes.StcoBox::new([100U, 200U, 300U, 400U])),
    Some(
      @boxes.StssBox::new([
        @bytes.NonZeroU32::one(),
        @bytes.NonZeroU32::new(3U).unwrap(),
        @bytes.NonZeroU32::new(5U).unwrap(),
        @bytes.NonZeroU32::new(7U).unwrap(),
        @bytes.NonZeroU32::new(9U).unwrap(),
      ]),
    ),
    None,
  )
  let table = @boxes.SampleTableAccessor::new(stbl)
  inspect(table.sample_count(), content="10")
  inspect(table.chunk_count(), content="4")
  inspect(table.stbl_box() == stbl, content="true")

  let expected_timestamps : Array[UInt64] = [
    0UL, 10UL, 15UL, 20UL, 40UL, 60UL, 80UL, 81UL, 82UL, 83UL,
  ]
  let expected_offsets : Array[UInt64] = [
    100UL, 101UL, 200UL, 203UL, 300UL, 305UL, 311UL, 400UL, 408UL, 417UL,
  ]
  let expected_chunks : Array[UInt32] = [1U, 1U, 2U, 2U, 3U, 3U, 3U, 4U, 4U, 4U]
  let expected_sync_samples : Array[UInt32] = [
    1U, 1U, 3U, 3U, 5U, 5U, 7U, 7U, 9U, 9U,
  ]
  for i in 0..<10 {
    let sample = table
      .get_sample(
        @bytes.NonZeroU32::new((i + 1).reinterpret_as_uint()).unwrap(),
      )
      .unwrap()
    if sample.duration() != durations[i] {
      fail(
        "sample[\{i}].duration が \{durations[i]} ではなく \{sample.duration()} だった",
      )
    }
    if sample.timestamp() != expected_timestamps[i] {
      fail(
        "sample[\{i}].timestamp が \{expected_timestamps[i]} ではなく \{sample.timestamp()} だった",
      )
    }
    if sample.data_size() != (i + 1).reinterpret_as_uint() {
      fail(
        "sample[\{i}].data_size が \{i + 1} ではなく \{sample.data_size()} だった",
      )
    }
    if sample.data_offset() != expected_offsets[i] {
      fail(
        "sample[\{i}].data_offset が \{expected_offsets[i]} ではなく \{sample.data_offset()} だった",
      )
    }
    if sample.is_sync_sample() != ((i + 1) % 2 == 1) {
      fail("sample[\{i}].is_sync_sample が期待と異なっていた")
    }
    let sync = sample.sync_sample().unwrap()
    if sync.index().get() != expected_sync_samples[i] {
      fail(
        "sample[\{i}].sync_sample が \{expected_sync_samples[i]} ではなく \{sync.index().get()} だった",
      )
    }
    if sample.composition_time_offset() is Some(_) {
      fail("ctts なしなのに composition_time_offset が Some だった")
    }
    if sample.chunk().index().get() != expected_chunks[i] {
      fail(
        "sample[\{i}].chunk が \{expected_chunks[i]} ではなく \{sample.chunk().index().get()} だった",
      )
    }
  }
  inspect(
    table.get_sample(@bytes.NonZeroU32::new(11U).unwrap()) is None,
    content="true",
  )

  let expected_sample_counts : Array[UInt32] = [2U, 2U, 3U, 3U]
  let expected_offsets : Array[UInt64] = [100UL, 200UL, 300UL, 400UL]
  for i in 0..<4 {
    let chunk = table
      .get_chunk(@bytes.NonZeroU32::new((i + 1).reinterpret_as_uint()).unwrap())
      .unwrap()
    if chunk.offset() != expected_offsets[i] {
      fail(
        "chunk[\{i}].offset が \{expected_offsets[i]} ではなく \{chunk.offset()} だった",
      )
    }
    if chunk.sample_count() != expected_sample_counts[i] {
      fail(
        "chunk[\{i}].sample_count が \{expected_sample_counts[i]} ではなく \{chunk.sample_count()} だった",
      )
    }
    inspect(chunk.sample_entry_index(), content="0")
    inspect(
      @box.BaseBox::box_type(chunk.sample_entry()).to_string(),
      content="test",
    )
    let samples = chunk.samples()
    let mut count = 0U
    for sample in samples {
      inspect(sample.chunk().index() == chunk.index(), content="true")
      count = count + 1U
    }
    if count != expected_sample_counts[i] {
      fail("chunk[\{i}].samples の個数が不一致だった")
    }
  }
  inspect(
    table.get_chunk(@bytes.NonZeroU32::new(5U).unwrap()) is None,
    content="true",
  )

  let total_duration = 84UL
  for t in 0UL..<total_duration {
    let sample = table.get_sample_by_timestamp(t).unwrap()
    let start = sample.timestamp()
    let end = start + sample.duration().to_uint64()
    if t < start || t >= end {
      fail(
        "timestamp \{t} が sample \{sample.index().get()} の範囲外だった",
      )
    }
  }
  inspect(table.get_sample_by_timestamp(total_duration) is None, content="true")
  inspect(table.get_sample_by_timestamp(100UL) is None, content="true")
}

///|
test "accessors keep per-track iteration state independent" {
  let first = @boxes.SampleTableAccessor::new(
    accessor_stbl(
      @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
      accessor_stsc(@bytes.NonZeroU32::one(), 2U),
      @boxes.StszBox::Variable(entry_sizes=[1U, 2U]),
      @bytes.Either::A(@boxes.StcoBox::new([100U])),
      None,
      None,
    ),
  )
  let second = @boxes.SampleTableAccessor::new(
    accessor_stbl(
      @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 7U)]),
      accessor_stsc(@bytes.NonZeroU32::one(), 1U),
      @boxes.StszBox::Fixed(
        sample_size=@bytes.NonZeroU32::new(3U).unwrap(),
        sample_count=1U,
      ),
      @bytes.Either::A(@boxes.StcoBox::new([900U])),
      None,
      None,
    ),
  )
  // 2 つの accessor の Iter を交互に進めても、track ごとの状態は混ざらない。
  let first_samples = first.samples()
  let second_samples = second.samples()
  let a1 = first_samples.next().unwrap()
  let b1 = second_samples.next().unwrap()
  let a2 = first_samples.next().unwrap()
  inspect(a1.index().get(), content="1")
  inspect(b1.index().get(), content="1")
  inspect(a1.data_offset(), content="100")
  inspect(b1.data_offset(), content="900")
  inspect(a1.duration(), content="10")
  inspect(b1.duration(), content="7")
  inspect(a2.index().get(), content="2")
  inspect(a2.data_offset(), content="101")
  inspect(first_samples.next() is None, content="true")
  inspect(second_samples.next() is None, content="true")
}

///|
test "accessor handles a single fixed-size sample" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Fixed(
      sample_size=@bytes.NonZeroU32::new(4U).unwrap(),
      sample_count=1U,
    ),
    @bytes.Either::A(@boxes.StcoBox::new([0xFFFFFFFFU])),
    None,
    None,
  )
  let table = @boxes.SampleTableAccessor::new(stbl)
  inspect(table.sample_count(), content="1")
  inspect(table.chunk_count(), content="1")
  let sample = table.get_sample(@bytes.NonZeroU32::one()).unwrap()
  inspect(sample.duration(), content="10")
  inspect(sample.timestamp(), content="0")
  inspect(sample.data_size(), content="4")
  inspect(sample.data_offset(), content="4294967295")
  inspect(sample.is_sync_sample(), content="true")
  inspect(sample.sync_sample().unwrap().index().get(), content="1")
  inspect(sample.chunk().index().get(), content="1")
  inspect(
    table.get_sample(@bytes.NonZeroU32::new(2U).unwrap()) is None,
    content="true",
  )
  inspect(
    table.get_chunk(@bytes.NonZeroU32::new(2U).unwrap()) is None,
    content="true",
  )
  inspect(table.get_sample_by_timestamp(10UL) is None, content="true")
  inspect(
    table.get_sample_by_timestamp(9UL).unwrap().index().get(),
    content="1",
  )
}

///|
test "accessor treats a zero-sample chunk like upstream" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    @boxes.StscBox::new([
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        0U,
        @bytes.NonZeroU32::one(),
      ),
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::new(2U).unwrap(),
        1U,
        @bytes.NonZeroU32::one(),
      ),
    ]),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U, 200U])),
    None,
    None,
  )
  let table = @boxes.SampleTableAccessor::new(stbl)
  inspect(table.sample_count(), content="1")
  inspect(table.chunk_count(), content="2")
  let first_chunk = table.get_chunk(@bytes.NonZeroU32::one()).unwrap()
  inspect(first_chunk.sample_count(), content="0")
  inspect(first_chunk.samples().to_array().length(), content="0")
  let sample = table.get_sample(@bytes.NonZeroU32::one()).unwrap()
  // 空チャンクを挟んでも実サンプル側のチャンクになる（partition_point 相当）。
  inspect(sample.chunk().index().get(), content="2")
  inspect(sample.data_offset(), content="200")
}

///|
test "accessor supports co64 offsets beyond u32" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 2U),
    @boxes.StszBox::Variable(entry_sizes=[3U, 2U]),
    @bytes.Either::B(@boxes.Co64Box::new([0x100000000UL])),
    None,
    None,
  )
  let table = @boxes.SampleTableAccessor::new(stbl)
  let first = table.get_sample(@bytes.NonZeroU32::one()).unwrap()
  let second = table.get_sample(@bytes.NonZeroU32::new(2U).unwrap()).unwrap()
  inspect(first.data_offset(), content="4294967296")
  inspect(second.data_offset(), content="4294967299")
  inspect(
    table.get_chunk(@bytes.NonZeroU32::one()).unwrap().offset(),
    content="4294967296",
  )
}

///|
test "accessor distinguishes no ctts from zero offsets" {
  let without_ctts = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let table = @boxes.SampleTableAccessor::new(without_ctts)
  inspect(
    table
    .get_sample(@bytes.NonZeroU32::one())
    .unwrap()
    .composition_time_offset()
    is None,
    content="true",
  )
  let with_zero_ctts = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    Some(@boxes.CttsBox::new(0U, [@boxes.CttsEntry::new(1U, 0L)])),
  )
  let table = @boxes.SampleTableAccessor::new(with_zero_ctts)
  let offset = table
    .get_sample(@bytes.NonZeroU32::one())
    .unwrap()
    .composition_time_offset()
  inspect(offset is Some(0L), content="true")
}

///|
test "accessor applies ctts version 1 offsets per run" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 2U),
    @boxes.StszBox::Variable(entry_sizes=[1U, 1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    Some(
      @boxes.CttsBox::new(1U, [
        @boxes.CttsEntry::new(1U, -1L),
        @boxes.CttsEntry::new(1U, 100L),
      ]),
    ),
  )
  let table = @boxes.SampleTableAccessor::new(stbl)
  let first = table.get_sample(@bytes.NonZeroU32::one()).unwrap()
  let second = table.get_sample(@bytes.NonZeroU32::new(2U).unwrap()).unwrap()
  inspect(first.composition_time_offset() is Some(-1L), content="true")
  inspect(second.composition_time_offset() is Some(100L), content="true")
}

///|
test "accessor sync semantics for missing, empty and partial stss" {
  // stss なし: 全サンプルが同期サンプル。
  let without_stss = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 2U),
    @boxes.StszBox::Variable(entry_sizes=[1U, 1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let table = @boxes.SampleTableAccessor::new(without_stss)
  for sample in table.samples() {
    inspect(sample.is_sync_sample(), content="true")
    inspect(
      sample.sync_sample().unwrap().index() == sample.index(),
      content="true",
    )
  }
  // stss が空: どのサンプルも同期サンプルではなく、前方に同期サンプルも無い。
  let empty_stss = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 2U),
    @boxes.StszBox::Variable(entry_sizes=[1U, 1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    Some(@boxes.StssBox::new([])),
    None,
  )
  let table = @boxes.SampleTableAccessor::new(empty_stss)
  for sample in table.samples() {
    inspect(sample.is_sync_sample(), content="false")
    inspect(sample.sync_sample() is None, content="true")
  }
  // 部分的な stss: 最初のサンプルより前には同期サンプルが無い。
  let partial_stss = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(6U, 10U)]),
    @boxes.StscBox::new([
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        2U,
        @bytes.NonZeroU32::one(),
      ),
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::new(2U).unwrap(),
        2U,
        @bytes.NonZeroU32::one(),
      ),
    ]),
    @boxes.StszBox::Variable(entry_sizes=[1U, 1U, 1U, 1U, 1U, 1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U, 200U, 300U])),
    Some(
      @boxes.StssBox::new([
        @bytes.NonZeroU32::new(3U).unwrap(),
        @bytes.NonZeroU32::new(5U).unwrap(),
      ]),
    ),
    None,
  )
  let table = @boxes.SampleTableAccessor::new(partial_stss)
  inspect(
    table.get_sample(@bytes.NonZeroU32::one()).unwrap().is_sync_sample(),
    content="false",
  )
  inspect(
    table.get_sample(@bytes.NonZeroU32::one()).unwrap().sync_sample() is None,
    content="true",
  )
  inspect(
    table.get_sample(@bytes.NonZeroU32::new(2U).unwrap()).unwrap().sync_sample()
    is None,
    content="true",
  )
  inspect(
    table
    .get_sample(@bytes.NonZeroU32::new(3U).unwrap())
    .unwrap()
    .sync_sample()
    .unwrap()
    .index()
    .get(),
    content="3",
  )
  inspect(
    table
    .get_sample(@bytes.NonZeroU32::new(4U).unwrap())
    .unwrap()
    .sync_sample()
    .unwrap()
    .index()
    .get(),
    content="3",
  )
  inspect(
    table
    .get_sample(@bytes.NonZeroU32::new(5U).unwrap())
    .unwrap()
    .is_sync_sample(),
    content="true",
  )
  inspect(
    table
    .get_sample(@bytes.NonZeroU32::new(6U).unwrap())
    .unwrap()
    .sync_sample()
    .unwrap()
    .index()
    .get(),
    content="5",
  )
}

///|
test "accessor keeps cslg and sdtp but ignores them when indexing" {
  let stbl = @boxes.StblBox::new(
    @boxes.StsdBox::new([test_sample_entry()]),
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    None,
    Some(@boxes.CslgBox::new(0U, 1L, -2L, 3L, -4L, 5L)),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    Some(
      @boxes.SdtpBox::new([
        @boxes.SdtpSampleFlags::from_fields(b'\x00', b'\x01', b'\x00', b'\x00'),
      ]),
    ),
    [],
  )
  let table = @boxes.SampleTableAccessor::new(stbl)
  inspect(table.sample_count(), content="1")
  inspect(table.stbl_box().cslg_box is Some(_), content="true")
  inspect(table.stbl_box().sdtp_box is Some(_), content="true")
}

///|
test "accessor is deterministic with duplicate zero-count stts runs" {
  // 上流の二分探索では未定義な領域。左端の run を選ぶ実装を固定する。
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([
      @boxes.SttsEntry::new(0U, 20U),
      @boxes.SttsEntry::new(1U, 10U),
    ]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let table = @boxes.SampleTableAccessor::new(stbl)
  let sample = table.get_sample(@bytes.NonZeroU32::one()).unwrap()
  inspect(sample.duration(), content="20")
  inspect(sample.timestamp(), content="0")
}

///|
test "accessor rejects an stts and stsz sample count mismatch" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[1U, 2U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::InconsistentSampleCount(
      stts_sample_count~,
      other_box_type~,
      other_sample_count~
    ) => {
      inspect(stts_sample_count, content="1")
      inspect(other_box_type.to_string(), content="stsz")
      inspect(other_sample_count, content="2")
    }
    _ => fail("InconsistentSampleCount のはず")
  }
  inspect(
    error.to_string(),
    content="Sample count in `stts` box is 1, but `stsz` has sample count 2",
  )
}

///|
test "accessor rejects an stts and ctts sample count mismatch" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 2U),
    @boxes.StszBox::Variable(entry_sizes=[1U, 1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    Some(@boxes.CttsBox::new(0U, [@boxes.CttsEntry::new(1U, 0L)])),
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::InconsistentSampleCount(
      stts_sample_count~,
      other_box_type~,
      other_sample_count~
    ) => {
      inspect(stts_sample_count, content="2")
      inspect(other_box_type.to_string(), content="ctts")
      inspect(other_sample_count, content="1")
    }
    _ => fail("InconsistentSampleCount のはず")
  }
  inspect(
    error.to_string(),
    content="Sample count in `stts` box is 2, but `ctts` has sample count 1",
  )
}

///|
test "accessor rejects an stts and stsc sample count mismatch" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[1U, 2U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::InconsistentSampleCount(
      stts_sample_count~,
      other_box_type~,
      other_sample_count~
    ) => {
      inspect(stts_sample_count, content="2")
      inspect(other_box_type.to_string(), content="stsc")
      inspect(other_sample_count, content="1")
    }
    _ => fail("InconsistentSampleCount のはず")
  }
  inspect(
    error.to_string(),
    content="Sample count in `stts` box is 2, but `stsc` has sample count 1",
  )
}

///|
test "accessor rejects chunks without stsc entries" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([]),
    @boxes.StscBox::new([]),
    @boxes.StszBox::Variable(entry_sizes=[]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::ChunksExistButNoSamples(chunk_count~) =>
      inspect(chunk_count, content="1")
    _ => fail("ChunksExistButNoSamples のはず")
  }
  inspect(
    error.to_string(),
    content="Chunks exist (1 chunks) but stsc has no entries",
  )
}

///|
test "accessor rejects a first chunk index other than one" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::new(2U).unwrap(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::FirstChunkIndexIsNotOne(
      actual_chunk_index~
    ) => inspect(actual_chunk_index.get(), content="2")
    _ => fail("FirstChunkIndexIsNotOne のはず")
  }
  inspect(
    error.to_string(),
    content="First chunk index in `stsc` box is expected to be 1, but got 2",
  )
}

///|
test "accessor rejects a missing sample entry reference" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([]),
    @boxes.StscBox::new([
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        1U,
        @bytes.NonZeroU32::new(2U).unwrap(),
      ),
    ]),
    @boxes.StszBox::Variable(entry_sizes=[]),
    @bytes.Either::A(@boxes.StcoBox::new([])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::MissingSampleEntry(
      stsc_entry_index~,
      sample_description_index~,
      sample_entry_count~
    ) => {
      inspect(stsc_entry_index, content="0")
      inspect(sample_description_index.get(), content="2")
      inspect(sample_entry_count, content="1")
    }
    _ => fail("MissingSampleEntry のはず")
  }
  inspect(
    error.to_string(),
    content="0-th entry in `stsc` box refers to a missing sample entry 2 (sample entry count is 1)",
  )
}

///|
test "accessor rejects non-monotonic stsc chunk indices" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([]),
    @boxes.StscBox::new([
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        1U,
        @bytes.NonZeroU32::one(),
      ),
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        1U,
        @bytes.NonZeroU32::one(),
      ),
    ]),
    @boxes.StszBox::Variable(entry_sizes=[]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::ChunkIndicesNotMonotonicallyIncreasing =>
      ()
    _ => fail("ChunkIndicesNotMonotonicallyIncreasing のはず")
  }
  inspect(
    error.to_string(),
    content="Chunk indices in `stsc` box are not monotonically increasing",
  )
}

///|
test "accessor rejects a last chunk index that is too large" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    @boxes.StscBox::new([
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::one(),
        1U,
        @bytes.NonZeroU32::one(),
      ),
      @boxes.StscEntry::new(
        @bytes.NonZeroU32::new(2U).unwrap(),
        1U,
        @bytes.NonZeroU32::one(),
      ),
    ]),
    @boxes.StszBox::Variable(entry_sizes=[1U]),
    @bytes.Either::A(@boxes.StcoBox::new([100U])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::LastChunkIndexIsTooLarge(
      max_chunk_index~,
      last_chunk_index~
    ) => {
      inspect(max_chunk_index.get(), content="1")
      inspect(last_chunk_index.get(), content="2")
    }
    _ => fail("LastChunkIndexIsTooLarge のはず")
  }
  inspect(
    error.to_string(),
    content="Last chunk index in `stsc` box is expected to be `<= 1`, but got 2",
  )
}

///|
test "accessor rejects an stts sample count overflow" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([
      @boxes.SttsEntry::new(0xFFFFFFFFU, 10U),
      @boxes.SttsEntry::new(1U, 10U),
    ]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[]),
    @bytes.Either::A(@boxes.StcoBox::new([])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::SampleCountOverflow(
      box_type~,
      accumulated_sample_count~,
      entry_sample_count~
    ) => {
      inspect(box_type.to_string(), content="stts")
      inspect(accumulated_sample_count, content="4294967295")
      inspect(entry_sample_count, content="1")
    }
    _ => fail("SampleCountOverflow のはず")
  }
  inspect(
    error.to_string(),
    content="Total sample count in `stts` box overflows u32 (accumulated 4294967295, adding 1)",
  )
}

///|
test "accessor rejects a ctts sample count overflow" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(0xFFFFFFFFU, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Fixed(
      sample_size=@bytes.NonZeroU32::one(),
      sample_count=0xFFFFFFFFU,
    ),
    @bytes.Either::A(@boxes.StcoBox::new([])),
    None,
    Some(
      @boxes.CttsBox::new(0U, [
        @boxes.CttsEntry::new(0xFFFFFFFFU, 0L),
        @boxes.CttsEntry::new(1U, 0L),
      ]),
    ),
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::SampleCountOverflow(
      box_type~,
      accumulated_sample_count~,
      entry_sample_count~
    ) => {
      inspect(box_type.to_string(), content="ctts")
      inspect(accumulated_sample_count, content="4294967295")
      inspect(entry_sample_count, content="1")
    }
    _ => fail("SampleCountOverflow のはず")
  }
  inspect(
    error.to_string(),
    content="Total sample count in `ctts` box overflows u32 (accumulated 4294967295, adding 1)",
  )
}

///|
test "accessor rejects a fixed stsz offset overflow" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(2U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 2U),
    @boxes.StszBox::Fixed(sample_size=@bytes.NonZeroU32::one(), sample_count=2U),
    @bytes.Either::B(@boxes.Co64Box::new([0xFFFFFFFFFFFFFFFFUL])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::SampleDataOffsetOverflow(
      sample_index~,
      accumulated_offset~,
      sample_data_size~
    ) => {
      inspect(sample_index.get(), content="1")
      inspect(accumulated_offset, content="18446744073709551615")
      inspect(sample_data_size, content="1")
    }
    _ => fail("SampleDataOffsetOverflow のはず")
  }
  inspect(
    error.to_string(),
    content="Sample data offset overflows u64 at sample 1 (accumulated 18446744073709551615, adding 1)",
  )
}

///|
test "accessor rejects a variable stsz offset overflow" {
  let stbl = accessor_stbl(
    @boxes.SttsBox::new([@boxes.SttsEntry::new(1U, 10U)]),
    accessor_stsc(@bytes.NonZeroU32::one(), 1U),
    @boxes.StszBox::Variable(entry_sizes=[2U]),
    @bytes.Either::B(@boxes.Co64Box::new([0xFFFFFFFFFFFFFFFFUL])),
    None,
    None,
  )
  let error = accessor_error(stbl).unwrap()
  match error {
    @boxes.SampleTableAccessorError::SampleDataOffsetOverflow(
      sample_index~,
      accumulated_offset~,
      sample_data_size~
    ) => {
      inspect(sample_index.get(), content="1")
      inspect(accumulated_offset, content="18446744073709551615")
      inspect(sample_data_size, content="2")
    }
    _ => fail("SampleDataOffsetOverflow のはず")
  }
  inspect(
    error.to_string(),
    content="Sample data offset overflows u64 at sample 1 (accumulated 18446744073709551615, adding 2)",
  )
}
