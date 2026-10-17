// 決定論的 mutation fuzz の簡易ランナー。

///|
async fn main {
  let args = @env.args()
  let iterations = if args.length() > 1 {
    @string.parse_int(args[1]) catch {
      _ => 200
    }
  } else {
    200
  }
  let fixture = if args.length() > 2 {
    args[2]
  } else {
    "tests/fixtures/upstream/black-h264-video.mp4"
  }
  let data_file = @fs.read_file(fixture) catch {
    _ => {
      println("fuzz: cannot read fixture")
      return
    }
  }
  let data = data_file.binary()
  let mut ok = 0
  let mut errors = 0
  let mut seed = 1U
  while seed <= iterations.reinterpret_as_uint() {
    let mutated = @fuzzlib.mutate_bytes(data, seed)
    try {
      let _ = @boxes.build_box_tree(@bytes.ReadCursor::new(mutated))
      ok = ok + 1
    } catch {
      _ => errors = errors + 1
    }
    seed = seed + 1U
  }
  println(
    "fuzz: fixture=\{fixture} iterations=\{iterations} ok=\{ok} errors=\{errors}",
  )
}
