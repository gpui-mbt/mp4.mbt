///|
test "inspect formats box tree and track rows" {
  let tree = @boxes.build_box_tree(
    @bytes.ReadCursor::new(b"\x00\x00\x00\x10moov\x00\x00\x00\x08free"),
  )
  inspect(@inspect.box_rows(tree).length(), content="2")
  inspect(@inspect.box_rows(tree)[0].contains("moov"), content="true")
  let track = @demux.TrackInfo::{
    track_id: 1U,
    kind: @bytes.TrackKind::Video,
    duration: 100UL,
    timescale: @bytes.NonZeroU32::new(1000U).unwrap(),
  }
  inspect(
    @inspect.track_rows([track])[0].contains("kind=video"),
    content="true",
  )
}

///|
test "inspect sample window is bounded and hex dump is deterministic" {
  let track = @demux.TrackInfo::{
    track_id: 1U,
    kind: @bytes.TrackKind::Video,
    duration: 0UL,
    timescale: @bytes.NonZeroU32::new(1000U).unwrap(),
  }
  let samples : Array[@demux.Sample] = [
    @demux.Sample::{
      track,
      sample_entry: None,
      keyframe: true,
      timestamp: 0UL,
      duration: 1U,
      data_offset: 0UL,
      data_size: 1U,
      composition_time_offset: None,
    },
    @demux.Sample::{
      track,
      sample_entry: None,
      keyframe: false,
      timestamp: 1UL,
      duration: 1U,
      data_offset: 1UL,
      data_size: 1U,
      composition_time_offset: Some(-1L),
    },
  ]
  inspect(@inspect.sample_rows(samples, 1, 1).length(), content="1")
  inspect(
    @inspect.sample_rows(samples, 1, 1)[0].contains("index=1"),
    content="true",
  )
  let dump = @inspect.hex_dump(b"\x01\xAB", 16)
  inspect(dump.length(), content="1")
  inspect(dump[0].contains("01 ab"), content="true")
}
