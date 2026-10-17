// Sans I/O demux の read 回数・I/O バイト数・サンプル数を計測する簡易 harness。
//
//   moon run src/examples/bench --target native -- <fixture> [iterations]
//
// 経過時間と peak memory は外部の `/usr/bin/time -l` 等で測る。この harness は
// 入力 SHA や OS 情報を捏造せず、read 回数と総 I/O バイト数だけを出力する。

///|
fn bench_bytes(view : BytesView) -> Bytes {
  @bytes.ReadCursor::from_view(view, 0UL).read_remaining() catch {
    _ => abort("invalid bytes")
  }
}

///|
fn run_once(data : Bytes) -> (Int32, UInt64, Int32, Int32) {
  let demuxer = @mp4_demux.Mp4FileDemuxer::new()
  let mut reads = 0
  let mut io_bytes : UInt64 = 0UL
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
      bench_bytes(data[start:end])
    }
    reads = reads + 1
    io_bytes = io_bytes + chunk.length().to_uint64()
    demuxer.handle_input(@mp4_demux.Input::{
      position: required.position,
      data: chunk[:],
    })
  }
  let tracks = demuxer.tracks() catch { _ => return (reads, io_bytes, 0, 0) }
  let mut sample_count = 0
  while true {
    let next = try demuxer.next_sample() catch {
      @mp4_demux.InputRequired(_) => None
      _ => None
    } noraise {
      v => v
    }
    match next {
      Some(_) => sample_count = sample_count + 1
      None => break
    }
  }
  (reads, io_bytes, tracks.length(), sample_count)
}

///|
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    println("usage: bench <fixture.mp4> [iterations]")
    return
  }
  let fixture = args[1]
  let iterations = if args.length() > 2 {
    @string.parse_int(args[2]) catch {
      _ => 5
    }
  } else {
    5
  }
  let data_file = @fs.read_file(fixture) catch {
    _ => {
      println("bench: cannot read fixture")
      return
    }
  }
  let data = data_file.binary()
  let mut total_reads = 0
  let mut total_io : UInt64 = 0UL
  let mut tracks = 0
  let mut samples = 0
  let mut i = 0
  while i < iterations {
    let (reads, io, t, s) = run_once(data)
    total_reads = total_reads + reads
    total_io = total_io + io
    tracks = t
    samples = s
    i = i + 1
  }
  println(
    "{\"fixture\":\"\{fixture}\",\"iterations\":\{iterations},\"tracks\":\{tracks},\"samples\":\{samples},\"reads\":\{total_reads},\"io_bytes\":\"\{total_io}\"}",
  )
}
