///|
fn test_mux_sample_entry() -> @boxes.SampleEntry {
  @boxes.SampleEntry::Unknown(
    @boxes.UnknownBox::new(
      @bytes.BoxType::Normal(
        @bytes.FourCC::from_string("zzzz") catch {
          _ => abort("zzzz is a valid FourCC")
        },
      ),
      @box.BoxSize::U32(8U),
      b"",
    ),
  )
}

///|
fn test_mux_sample(
  offset : UInt64,
  duration : UInt32,
  entry : @boxes.SampleEntry?,
) -> @mux.Sample {
  @mux.Sample::new(
    @bytes.TrackKind::Video,
    entry,
    true,
    @bytes.NonZeroU32::new(1000U).unwrap(),
    duration,
    None,
    offset,
    10U,
  )
}

///|
test "fmp4 segment muxer rejects empty samples and tracks" {
  let muxer = @mux.Fmp4SegmentMuxer::new()
  try {
    let _ = muxer.init_segment_bytes()
    fail("expected EmptyTracks")
  } catch {
    @mux.EmptyTracks => ()
    _ => fail("unexpected error")
  }
  try {
    let _ = muxer.create_media_segment_metadata([])
    fail("expected EmptySamples")
  } catch {
    @mux.EmptySamples => ()
    _ => fail("unexpected error")
  }
}

///|
test "fmp4 segment muxer writes init and media segments that the segment demuxer reads" {
  let entry = test_mux_sample_entry()
  let muxer = @mux.Fmp4SegmentMuxer::new()
  let first = muxer.create_media_segment_metadata([
    test_mux_sample(0UL, 1000U, Some(entry)),
  ])
  let init = muxer.init_segment_bytes()

  let demuxer = @demux.Fmp4SegmentDemuxer::new()
  demuxer.handle_init_segment(init)
  let samples = demuxer.handle_media_segment(
    first + b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  inspect(samples.length(), content="1")
  inspect(samples[0].timestamp, content="0")
  inspect(samples[0].duration, content="1000")
  inspect(samples[0].data_offset, content="104")
  inspect(samples[0].data_size, content="10")
  inspect(samples[0].sample_entry is Some(_), content="true")
}

///|
test "fmp4 segment muxer continues decode time across segments" {
  let entry = test_mux_sample_entry()
  let muxer = @mux.Fmp4SegmentMuxer::new()
  let first = muxer.create_media_segment_metadata([
    test_mux_sample(0UL, 1000U, Some(entry)),
  ])
  let second = muxer.create_media_segment_metadata([
    test_mux_sample(0UL, 1000U, None),
  ])
  let init = muxer.init_segment_bytes()

  let demuxer = @demux.Fmp4SegmentDemuxer::new()
  demuxer.handle_init_segment(init)
  let samples1 = demuxer.handle_media_segment(
    first + b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  ) catch {
    @demux.DecodeError(@bytes.Mp4Error(kind~, reason~, ..)) => {
      println("second media error: \{kind.to_string()} \{reason}")
      fail("media failed")
    }
    _ => fail("media failed")
  }
  let samples2 = demuxer.handle_media_segment(
    second + b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  ) catch {
    @demux.DecodeError(@bytes.Mp4Error(kind~, reason~, ..)) => {
      println("second media error 2: \{kind.to_string()} \{reason}")
      fail("media failed")
    }
    _ => fail("media failed")
  }
  inspect(samples1[0].timestamp, content="0")
  inspect(samples2[0].timestamp, content="1000")
  inspect(samples2[0].sample_entry is None, content="true")
}

///|
test "fmp4 segment muxer rejects missing sample entry" {
  let muxer = @mux.Fmp4SegmentMuxer::new()
  try {
    let _ = muxer.create_media_segment_metadata([
      test_mux_sample(0UL, 1000U, None),
    ])
    fail("expected MissingSampleEntry")
  } catch {
    @mux.MissingSampleEntry(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "fmp4 segment muxer rejects non-contiguous sample data" {
  let entry = test_mux_sample_entry()
  let muxer = @mux.Fmp4SegmentMuxer::new()
  try {
    let _ = muxer.create_media_segment_metadata([
      test_mux_sample(0UL, 1000U, Some(entry)),
      test_mux_sample(100UL, 1000U, None),
    ])
    fail("expected an error")
  } catch {
    @mux.EncodeError(@bytes.Mp4Error(kind~, ..)) =>
      inspect(kind.to_string(), content="InvalidInput")
    _ => fail("unexpected error")
  }
}

///|
test "fmp4 segment muxer rejects a timescale mismatch" {
  let entry = test_mux_sample_entry()
  let muxer = @mux.Fmp4SegmentMuxer::new()
  let _ = muxer.create_media_segment_metadata([
    test_mux_sample(0UL, 1000U, Some(entry)),
  ])
  let other = @mux.Sample::new(
    @bytes.TrackKind::Video,
    None,
    true,
    @bytes.NonZeroU32::new(90000U).unwrap(),
    1000U,
    None,
    0UL,
    10U,
  )
  try {
    let _ = muxer.create_media_segment_metadata([other])
    fail("expected TimescaleMismatch")
  } catch {
    @mux.TimescaleMismatch(..) => ()
    _ => fail("unexpected error")
  }
}
