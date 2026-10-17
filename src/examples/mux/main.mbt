// 通常 MP4 の demux → mux roundtrip CLI。
//
// 入力 MP4 を `Mp4FileDemuxer` で読み、`Mp4FileMuxer` で書き直す。
// payload のコピーとファイル I/O はこの実行パッケージだけが行う。

///|
async fn read_all(path : String) -> Bytes {
  let data = @fs.read_file(path)
  data.binary()
}

///|
fn feed_demuxer(demuxer : @mp4_demux.Mp4FileDemuxer, data : Bytes) -> Unit {
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
      mux_example_bytes(data[start:end])
    }
    demuxer.handle_input(@mp4_demux.Input::{
      position: required.position,
      data: chunk[:],
    })
  }
}

///|
fn mux_example_bytes(view : BytesView) -> Bytes {
  @bytes.ReadCursor::from_view(view, 0UL).read_remaining() catch {
    _ => abort("invalid bytes")
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 3 {
    @stdio.stderr.write(
      "usage: mux <input.mp4> <output.mp4> [--faststart] [--reserve-moov <bytes>]\n",
    )
    return
  }
  let input_path = args[1]
  let output_path = args[2]
  let mut faststart = false
  let mut reserve : UInt64 = 0UL
  let mut i = 3
  while i < args.length() {
    if args[i] == "--faststart" {
      faststart = true
    } else if args[i] == "--reserve-moov" && i + 1 < args.length() {
      let parsed = @string.parse_int64(args[i + 1]) catch { _ => 0L }
      if parsed > 0L {
        reserve = parsed.reinterpret_as_uint64()
      }
      i = i + 1
    }
    i = i + 1
  }
  let input = read_all(input_path) catch {
    _ => {
      @stdio.stderr.write("error: cannot read input\n")
      return
    }
  }
  let demuxer = @mp4_demux.Mp4FileDemuxer::new()
  feed_demuxer(demuxer, input)
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
  let options = @mp4_mux.Mp4FileMuxerOptions::new(
    if faststart {
      @mp4_mux.estimate_maximum_moov_box_size([samples.length()])
    } else {
      reserve
    },
    0UL,
    @mp4_mux.TrackMetadataOptions::default(),
  )
  let muxer = @mp4_mux.Mp4FileMuxer::with_options(options) catch {
    e => {
      @stdio.stderr.write("error: \{e.to_string()}\n")
      return
    }
  }
  let initial = muxer.initial_boxes_bytes()
  let payloads : Array[Bytes] = []
  let mut payload_bytes : Bytes = b""
  let mut index = 0
  while index < samples.length() {
    let sample = samples[index]
    let payload = if sample.data_size == 0U {
      b""
    } else {
      let start = sample.data_offset.to_int()
      let end = start + sample.data_size.reinterpret_as_int()
      if end > input.length() {
        abort("sample payload is outside the input")
      }
      mux_example_bytes(input[start:end])
    }
    let mux_sample = @mp4_mux.Sample::new(
      sample.track.kind,
      sample.sample_entry,
      sample.keyframe,
      sample.track.timescale,
      sample.duration,
      sample.composition_time_offset,
      initial.length().to_uint64() + payload_bytes.length().to_uint64(),
      sample.data_size,
    )
    muxer.append_sample(mux_sample) catch {
      e => {
        @stdio.stderr.write("error: \{e.to_string()}\n")
        return
      }
    }
    payloads.push(payload)
    payload_bytes = payload_bytes + payload
    index = index + 1
  }
  let finalized = muxer.finalize() catch {
    e => {
      @stdio.stderr.write("error: \{e.to_string()}\n")
      return
    }
  }
  let file = build_output(initial, payload_bytes, finalized)
  @fs.write_file(output_path, file) catch {
    _ => {
      @stdio.stderr.write("error: cannot write output\n")
      return
    }
  }
  @stdio.stdout.write(
    "muxed \{samples.length()} samples into \{output_path} (tracks=\{tracks.length()}, faststart=\{finalized.is_faststart_enabled()})\n",
  )
}

///|
fn build_output(
  initial : Bytes,
  payload : Bytes,
  finalized : @mp4_mux.FinalizedBoxes,
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
  for pair in finalized.offset_and_bytes_pairs() {
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
