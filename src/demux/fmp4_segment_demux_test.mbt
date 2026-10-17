///|
/// 先頭から最初の `moof` までのバイト数を返す。
fn fmp4_moof_offset(input : Bytes) -> Int32 {
  let mut offset = 0
  while offset < input.length() {
    let cursor = @bytes.ReadCursor::from_view(
      input[offset:],
      offset.to_uint64(),
    )
    let (header, payload) = try
      @box.BoxHeader::decode_header_and_payload(cursor)
    catch {
      _ => abort("fixture box header is invalid")
    } noraise {
      v => v
    }
    if header.box_type().as_bytes() == b"moof" {
      return offset
    }
    offset = offset + header.external_size() + payload.length()
  }
  abort("fixture has no moof")
}

///|
fn fmp4_fixture_bytes() -> Bytes {
  demux_case_named("fixture:black-h264-fmp4.mp4").input
}

///|
fn fmp4_read_remaining(view : BytesView) -> Bytes {
  try @bytes.ReadCursor::from_view(view, 0UL).read_remaining() catch {
    _ => abort("fixture bytes are invalid")
  } noraise {
    v => v
  }
}

///|
fn fmp4_init_segment(input : Bytes) -> Bytes {
  let moof_offset = fmp4_moof_offset(input)
  fmp4_read_remaining(input[:moof_offset])
}

///|
test "segment demuxer rejects tracks before initialization" {
  let demuxer = @demux.Fmp4SegmentDemuxer::new()
  try {
    let _ = demuxer.tracks()
    fail("expected InvalidState")
  } catch {
    @demux.InvalidState(message) =>
      inspect(message.contains("Init segment"), content="true")
    _ => fail("unexpected error")
  }
}

///|
test "segment demuxer processes the fmp4 fixture init and media segment" {
  let input = fmp4_fixture_bytes()
  let demuxer = @demux.Fmp4SegmentDemuxer::new()
  demuxer.handle_init_segment(fmp4_init_segment(input))
  let tracks = demuxer.tracks()
  inspect(tracks.length(), content="1")
  inspect(tracks[0].track_id, content="1")
  inspect(tracks[0].kind is @bytes.TrackKind::Video, content="true")
  inspect(tracks[0].timescale.get(), content="12800")

  // この fixture の tfhd.base_data_offset はファイル先頭からの絶対値なので、
  // セグメント先頭からではなくファイル全体を渡して相対値として解釈させる。
  let samples = demuxer.handle_media_segment(input)
  inspect(samples.length(), content="1")
  inspect(samples[0].track.track_id, content="1")
  inspect(samples[0].sample_entry is Some(_), content="true")
  inspect(samples[0].keyframe, content="true")
  inspect(samples[0].timestamp, content="0")
  inspect(samples[0].duration, content="512")
  // tfhd.base_data_offset=806 + trun.data_offset=120 = 926（ファイル先頭基準）。
  inspect(samples[0].data_offset, content="926")
  inspect(samples[0].data_size, content="796")

  let again = demuxer.handle_media_segment(input)
  inspect(again[0].sample_entry is None, content="true")
}

///|
test "segment demuxer rejects a second init segment" {
  let input = fmp4_fixture_bytes()
  let init = fmp4_init_segment(input)
  let demuxer = @demux.Fmp4SegmentDemuxer::new()
  demuxer.handle_init_segment(init)
  try {
    demuxer.handle_init_segment(init)
    fail("expected InvalidState")
  } catch {
    @demux.InvalidState(_) => ()
    _ => fail("unexpected error")
  }
}

///|
test "segment demuxer rejects a media segment without mdat" {
  let input = fmp4_fixture_bytes()
  let init = fmp4_init_segment(input)
  let demuxer = @demux.Fmp4SegmentDemuxer::new()
  demuxer.handle_init_segment(init)
  let moof_offset = fmp4_moof_offset(input)
  let moof_only = fmp4_read_remaining(input[moof_offset:moof_offset + 112])
  try {
    let _ = demuxer.handle_media_segment(moof_only)
    fail("expected an error")
  } catch {
    @demux.DecodeError(@bytes.Mp4Error(kind~, reason~, ..)) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason.contains("mdat"), content="true")
    }
    _ => fail("unexpected error")
  }
}

///|
test "segment demuxer rejects an empty media segment" {
  let demuxer = @demux.Fmp4SegmentDemuxer::new()
  try {
    let _ = demuxer.handle_media_segment(b"")
    fail("expected an error")
  } catch {
    @demux.DecodeError(@bytes.Mp4Error(kind~, ..)) =>
      inspect(kind.to_string(), content="InvalidInput")
    _ => fail("unexpected error")
  }
}
