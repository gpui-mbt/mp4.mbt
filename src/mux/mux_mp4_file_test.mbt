///|
fn test_file_entry() -> @boxes.SampleEntry {
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
fn test_file_sample(
  kind : @bytes.TrackKind,
  offset : UInt64,
  keyframe : Bool,
  entry : @boxes.SampleEntry?,
) -> @mux.Sample {
  @mux.Sample::new(
    kind,
    entry,
    keyframe,
    @bytes.NonZeroU32::new(1000U).unwrap(),
    1000U,
    None,
    offset,
    4U,
  )
}

///|
/// finalized の差分を元に、payload を含む実際のファイル bytes を組み立てる。
fn build_muxed_file(
  initial : Bytes,
  payload : Bytes,
  finalized : @mux.FinalizedBoxes,
) -> Bytes {
  let payload_start = initial.length()
  let mdat_offset = finalized.mdat_box_offset().to_int()
  let moov_offset = finalized.moov_box_offset().to_int()
  let moov_size = finalized.moov_box_size()
  let total = if moov_offset >= mdat_offset {
    moov_offset + moov_size
  } else {
    payload_start + payload.length()
  }
  let out = FixedArray::make(total, b'\x00')
  let pairs = finalized.offset_and_bytes_pairs()
  for pair in pairs {
    let (offset, bytes) = pair
    let start = offset.to_int()
    for i in 0..<bytes.length() {
      out[start + i] = bytes[i]
    }
  }
  for i in 0..<payload.length() {
    out[payload_start + i] = payload[i]
  }
  Bytes::from_array(out)
}

///|
/// BytesView を Bytes へコピーする。
fn mux_view_bytes(view : BytesView) -> Bytes {
  try @bytes.ReadCursor::from_view(view, 0UL).read_remaining() catch {
    _ => abort("invalid bytes")
  } noraise {
    v => v
  }
}

///|
/// `Mp4FileDemuxer` で全サンプルを取り出す。
fn demux_file_samples(input : Bytes) -> Array[@demux.Sample] {
  let demuxer = @demux.Mp4FileDemuxer::new()
  let samples : Array[@demux.Sample] = []
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
      mux_view_bytes(input[start:end])
    }
    demuxer.handle_input(@demux.Input::{
      position: required.position,
      data: data[:],
    })
    while true {
      let sample = try Ok(demuxer.next_sample()) catch {
        @demux.InputRequired(_) => Err(@demux.InvalidState("need input"))
        e => Err(e)
      } noraise {
        v => v
      }
      match sample {
        Ok(Some(s)) => samples.push(s)
        Ok(None) => break
        Err(@demux.InvalidState(_)) => break
        Err(_) => abort("demux failed")
      }
    }
  }
  samples
}

///|
test "mp4 file muxer round trips a video sample" {
  let entry = test_file_entry()
  let muxer = @mux.Mp4FileMuxer::new()
  let initial = muxer.initial_boxes_bytes()
  let payload = b"\x01\x02\x03\x04"
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      true,
      Some(entry),
    ),
  )
  let finalized = muxer.finalize()
  inspect(finalized.moov_box_size() > 0, content="true")
  let file = build_muxed_file(initial, payload, finalized)
  let samples = demux_file_samples(file)
  inspect(samples.length(), content="1")
  inspect(samples[0].keyframe, content="true")
  inspect(samples[0].data_size, content="4")
  inspect(samples[0].timestamp, content="0")
}

///|
test "mp4 file muxer rejects a position mismatch" {
  let muxer = @mux.Mp4FileMuxer::new()
  try {
    muxer.append_sample(
      test_file_sample(
        @bytes.TrackKind::Video,
        100UL,
        true,
        Some(test_file_entry()),
      ),
    )
    fail("expected PositionMismatch")
  } catch {
    @mux.PositionMismatch(..) => ()
    _ => fail("unexpected error")
  }
}

///|
test "mp4 file muxer rejects double finalize" {
  let muxer = @mux.Mp4FileMuxer::new()
  let initial = muxer.initial_boxes_bytes()
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      true,
      Some(test_file_entry()),
    ),
  )
  let _ = muxer.finalize()
  try {
    let _ = muxer.finalize()
    fail("expected AlreadyFinalized")
  } catch {
    @mux.AlreadyFinalized => ()
    _ => fail("unexpected error")
  }
}

///|
test "mp4 file muxer rejects video without sync samples" {
  let muxer = @mux.Mp4FileMuxer::new()
  let initial = muxer.initial_boxes_bytes()
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      false,
      Some(test_file_entry()),
    ),
  )
  try {
    let _ = muxer.finalize()
    fail("expected NoSyncSamples")
  } catch {
    @mux.NoSyncSamples(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "mp4 file muxer omits stss when all video samples are keyframes" {
  let muxer = @mux.Mp4FileMuxer::new()
  let initial = muxer.initial_boxes_bytes()
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      true,
      Some(test_file_entry()),
    ),
  )
  let finalized = muxer.finalize()
  let stbl = finalized.moov_box().trak_boxes[0].mdia_box.minf_box.stbl_box
  inspect(stbl.stss_box is None, content="true")
}

///|
test "mp4 file muxer writes stss when some video samples are not keyframes" {
  let muxer = @mux.Mp4FileMuxer::new()
  let initial = muxer.initial_boxes_bytes()
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      true,
      Some(test_file_entry()),
    ),
  )
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64() + 4UL,
      false,
      None,
    ),
  )
  let finalized = muxer.finalize()
  let stbl = finalized.moov_box().trak_boxes[0].mdia_box.minf_box.stbl_box
  let stss = match stbl.stss_box {
    Some(stss) => stss
    None => fail("expected stss")
  }
  inspect(stss.sample_numbers.length(), content="1")
  inspect(stss.sample_numbers[0].get(), content="1")
}

///|
test "mp4 file muxer detects a missing advance_position" {
  let muxer = @mux.Mp4FileMuxer::new()
  let initial = muxer.initial_boxes_bytes()
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      true,
      Some(test_file_entry()),
    ),
  )
  let next = initial.length().to_uint64() + 4UL
  muxer.advance_position(3UL)
  try {
    muxer.append_sample(
      test_file_sample(@bytes.TrackKind::Video, next, false, None),
    )
    fail("expected PositionMismatch")
  } catch {
    @mux.PositionMismatch(..) => ()
    _ => fail("unexpected error")
  }
}

///|
test "mp4 file muxer starts a new chunk after advance_position" {
  let muxer = @mux.Mp4FileMuxer::new()
  let initial = muxer.initial_boxes_bytes()
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      true,
      Some(test_file_entry()),
    ),
  )
  muxer.advance_position(4UL)
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64() + 4UL + 4UL,
      true,
      None,
    ),
  )
  let finalized = muxer.finalize()
  let stbl = finalized.moov_box().trak_boxes[0].mdia_box.minf_box.stbl_box
  inspect(stbl.stsc_box.entries.length(), content="2")
}

///|
test "mp4 file muxer uses faststart when reserved space is sufficient" {
  let options = @mux.Mp4FileMuxerOptions::new(
    @mux.estimate_maximum_moov_box_size([4]),
    0UL,
    @mux.TrackMetadataOptions::default(),
  )
  let muxer = @mux.Mp4FileMuxer::with_options(options)
  let initial = muxer.initial_boxes_bytes()
  muxer.append_sample(
    test_file_sample(
      @bytes.TrackKind::Video,
      initial.length().to_uint64(),
      true,
      Some(test_file_entry()),
    ),
  )
  let finalized = muxer.finalize()
  inspect(finalized.is_faststart_enabled(), content="true")
}
