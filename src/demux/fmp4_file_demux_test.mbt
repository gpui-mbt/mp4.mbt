///|
/// BytesView を Bytes へコピーする (テスト用)。
fn fmp4_view_bytes(view : BytesView) -> Bytes {
  try @bytes.ReadCursor::from_view(view, 0UL).read_remaining() catch {
    _ => abort("invalid fixture bytes")
  } noraise {
    v => v
  }
}

///|
/// `required_input()` が要求する範囲を `input` から切り出して供給する。
fn fmp4_feed_all(demuxer : @demux.Fmp4FileDemuxer, input : Bytes) -> Unit {
  while demuxer.required_input() is Some(required) {
    let start = required.position.to_int()
    let end = match required.size {
      Some(size) => {
        let e = start + size.to_int()
        if e > input.length() {
          input.length()
        } else {
          e
        }
      }
      None => input.length()
    }
    let data = if start >= input.length() {
      b""
    } else {
      fmp4_view_bytes(input[start:end])
    }
    demuxer.handle_input(@demux.Input::{
      position: required.position,
      data: data[:],
    })
  }
}

///|
test "file demuxer requests the ftyp header first" {
  let demuxer = @demux.Fmp4FileDemuxer::new()
  match demuxer.required_input() {
    Some(required) => {
      inspect(required.position, content="0")
      inspect(required.size.unwrap(), content="32")
    }
    None => fail("expected an initial request")
  }
}

///|
test "file demuxer requires initialization before tracks" {
  let demuxer = @demux.Fmp4FileDemuxer::new()
  try {
    let _ = demuxer.tracks()
    fail("expected InputRequired")
  } catch {
    @demux.InputRequired(required) => inspect(required.position, content="0")
    _ => fail("unexpected error")
  }
}

///|
test "file demuxer rejects the fixture absolute base_data_offset form" {
  let input = demux_case_named("fixture:black-h264-fmp4.mp4").input
  let demuxer = @demux.Fmp4FileDemuxer::new()
  fmp4_feed_all(demuxer, input)
  try {
    let _ = demuxer.next_sample()
    fail("expected a decode error")
  } catch {
    @demux.DecodeError(@bytes.Mp4Error(kind~, reason~, ..)) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason.contains("base_data_offset"), content="true")
    }
    _ => fail("unexpected error")
  }
}

///|
test "file demuxer reports input position errors" {
  let demuxer = @demux.Fmp4FileDemuxer::new()
  demuxer.handle_input(@demux.Input::{
    position: 100UL,
    data: b"\x00\x00\x00\x08free"[:],
  })
  try {
    let _ = demuxer.tracks()
    fail("expected an error")
  } catch {
    @demux.DecodeError(@bytes.Mp4Error(kind~, ..)) =>
      inspect(kind.to_string(), content="InvalidInput")
    _ => fail("unexpected error")
  }
}

///|
fn fmp4_mux_entry() -> @boxes.SampleEntry {
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
test "file demuxer reads multiple muxed segments in DTS order" {
  let entry = fmp4_mux_entry()
  let muxer = @mux.Fmp4SegmentMuxer::new()
  let first = muxer.create_media_segment_metadata([
    @mux.Sample::new(
      @bytes.TrackKind::Video,
      Some(entry),
      true,
      @bytes.NonZeroU32::new(1000U).unwrap(),
      1000U,
      None,
      0UL,
      4U,
    ),
  ])
  let second = muxer.create_media_segment_metadata([
    @mux.Sample::new(
      @bytes.TrackKind::Video,
      None,
      false,
      @bytes.NonZeroU32::new(1000U).unwrap(),
      1000U,
      None,
      0UL,
      4U,
    ),
  ])
  let init = muxer.init_segment_bytes()
  let file = init + first + b"\x01\x02\x03\x04" + second + b"\x05\x06\x07\x08"
  let demuxer = @demux.Fmp4FileDemuxer::new()
  fmp4_feed_all(demuxer, file)
  let tracks = demuxer.tracks()
  inspect(tracks.length(), content="1")
  let samples : Array[@demux.Sample] = []
  while true {
    let sample = try Ok(demuxer.next_sample()) catch {
      @demux.InputRequired(_) => Err(0)
      @demux.DecodeError(_) => Err(1)
      _ => Err(1)
    } noraise {
      v => v
    }
    match sample {
      Ok(Some(s)) => samples.push(s)
      Ok(None) => break
      Err(0) => fmp4_feed_all(demuxer, file)
      Err(_) => break
    }
  }
  inspect(samples.length(), content="2")
  inspect(samples[0].timestamp, content="0")
  inspect(samples[1].timestamp, content="1000")
  inspect(samples[0].sample_entry is Some(_), content="true")
  inspect(samples[1].sample_entry is None, content="true")
  inspect(samples[0].keyframe, content="true")
  inspect(samples[1].keyframe, content="false")
  inspect(samples[1].data_offset > samples[0].data_offset, content="true")
}
