// MP4 → fMP4 segment 列 + init segment の CLI。

///|
fn fmp4_bytes(view : BytesView) -> Bytes {
  @bytes.ReadCursor::from_view(view, 0UL).read_remaining() catch {
    _ => abort("invalid bytes")
  }
}

///|
fn fmp4_feed(demuxer : @mp4_demux.Mp4FileDemuxer, data : Bytes) -> Unit {
  while demuxer.required_input() is Some(required) {
    let start = required.position.to_int()
    let end = match required.size {
      Some(size) => {
        let e = start + size.to_int()
        if e > data.length() {
          data.length()
        } else {
          e
        }
      }
      None => data.length()
    }
    let chunk = if start >= data.length() {
      b""
    } else {
      fmp4_bytes(data[start:end])
    }
    demuxer.handle_input(@mp4_demux.Input::{
      position: required.position,
      data: chunk[:],
    })
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 3 {
    @stdio.stderr.write(
      "usage: fmp4 <input.mp4> <output-dir> [--segments <n>]\n",
    )
    return
  }
  let input_path = args[1]
  let output_dir = args[2]
  let mut segment_count = 3
  let mut i = 3
  while i < args.length() {
    if args[i] == "--segments" && i + 1 < args.length() {
      let parsed = @string.parse_int(args[i + 1]) catch { _ => 3 }
      if parsed > 0 {
        segment_count = parsed
      }
      i = i + 1
    }
    i = i + 1
  }
  let input_data = @fs.read_file(input_path) catch {
    _ => {
      @stdio.stderr.write("error: cannot read input\n")
      return
    }
  }
  let input = input_data.binary()
  let demuxer = @mp4_demux.Mp4FileDemuxer::new()
  fmp4_feed(demuxer, input)
  let tracks = demuxer.tracks() catch {
    e => {
      @stdio.stderr.write("error: \{e.to_string()}\n")
      return
    }
  }
  let samples : Array[@mp4_demux.Sample] = []
  while true {
    let next = try demuxer.next_sample() catch {
      @mp4_demux.InputRequired(_) => None
      e => {
        @stdio.stderr.write("error: \{e.to_string()}\n")
        return
      }
    } noraise {
      v => v
    }
    match next {
      Some(sample) => samples.push(sample)
      None => break
    }
  }
  if samples.length() == 0 {
    @stdio.stderr.write("error: no samples\n")
    return
  }
  @fs.mkdir(output_dir, allow_exist=true) catch {
    _ => {
      @stdio.stderr.write("error: cannot create output directory\n")
      return
    }
  }
  let muxer = @mp4_mux.Fmp4SegmentMuxer::new()
  let segment_size = if samples.length() / segment_count < 1 {
    1
  } else {
    samples.length() / segment_count
  }
  let segment_files : Array[String] = []
  let mut start = 0
  let mut segment_index = 0
  while start < samples.length() {
    let end = if start + segment_size > samples.length() {
      samples.length()
    } else {
      start + segment_size
    }
    let mux_samples : Array[@mp4_mux.Sample] = []
    let payloads : Array[Bytes] = []
    let mut payload : Bytes = b""
    let mut sample_index = start
    while sample_index < end {
      let sample = samples[sample_index]
      let data = if sample.data_size == 0U {
        b""
      } else {
        fmp4_bytes(
          input[sample.data_offset.to_int():sample.data_offset.to_int() +
          sample.data_size.reinterpret_as_int()],
        )
      }
      mux_samples.push(
        @mp4_mux.Sample::new(
          sample.track.kind,
          sample.sample_entry,
          sample.keyframe,
          sample.track.timescale,
          sample.duration,
          sample.composition_time_offset,
          payload.length().to_uint64(),
          sample.data_size,
        ),
      )
      payloads.push(data)
      payload = payload + data
      sample_index = sample_index + 1
    }
    let metadata = muxer.create_media_segment_metadata(mux_samples) catch {
      e => {
        @stdio.stderr.write("error: \{e.to_string()}\n")
        return
      }
    }
    let path = output_dir + "/segment-\{segment_index}.m4s"
    @fs.write_file(path, metadata + payload) catch {
      _ => {
        @stdio.stderr.write("error: cannot write segment\n")
        return
      }
    }
    segment_files.push(path)
    start = end
    segment_index = segment_index + 1
  }
  let init = muxer.init_segment_bytes() catch {
    e => {
      @stdio.stderr.write("error: \{e.to_string()}\n")
      return
    }
  }
  @fs.write_file(output_dir + "/init.mp4", init) catch {
    _ => {
      @stdio.stderr.write("error: cannot write init segment\n")
      return
    }
  }
  // 書き戻した init + segments を segment demuxer で読み直す。
  let verify = @mp4_demux.Fmp4SegmentDemuxer::new()
  verify.handle_init_segment(init) catch {
    e => {
      @stdio.stderr.write("error: verify init failed: \{e.to_string()}\n")
      return
    }
  }
  let mut verified = 0
  for path in segment_files {
    let data_file = @fs.read_file(path) catch {
      _ => {
        @stdio.stderr.write("error: cannot read back segment\n")
        return
      }
    }
    let data = data_file.binary()
    let segment_samples = verify.handle_media_segment(data) catch {
      e => {
        @stdio.stderr.write("error: verify segment failed: \{e.to_string()}\n")
        return
      }
    }
    verified = verified + segment_samples.length()
  }
  @stdio.stdout.write(
    "wrote init + \{segment_files.length()} segments to \{output_dir} (tracks=\{tracks.length()}, samples=\{samples.length()}, verified=\{verified})\n",
  )
}
