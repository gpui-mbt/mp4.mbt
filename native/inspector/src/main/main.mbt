// gpui.mbt Native MP4 Inspector（最小実装）。
// 起動引数の MP4 を読み、box tree / track / sample の先頭行を描画する。

///|
fn inspector_rect(x : Double, y : Double, w : Double, h : Double) -> @primitives.Rect {
  match @primitives.Rect::new(x, y, w, h) {
    Ok(r) => r
    Err(_) => abort("invalid rect")
  }
}

///|
fn inspector_color(r : Int, g : Int, b : Int) -> @primitives.Color {
  match @primitives.Color::rgba(r, g, b, 255) {
    Ok(c) => c
    Err(_) => abort("invalid color")
  }
}

///|
fn text_item(
  id : UInt64,
  x : Double,
  y : Double,
  text : String,
) -> @scene.SceneItem {
  match @scene.SceneItem::text(
    id,
    inspector_rect(x, y, 980.0, 18.0),
    text,
    13.0,
    inspector_color(235, 235, 235),
    @scene.AffineTransform::identity(),
    1.0,
    None,
  ) {
    Ok(item) => item
    Err(_) => abort("invalid text item")
  }
}

///|
fn inspector_scene(
  width : Double,
  height : Double,
  lines : Array[String],
) -> @scene.SceneSnapshot {
  let items : Array[@scene.SceneItem] = [
    match @scene.SceneItem::quad(
      1,
      inspector_rect(0.0, 0.0, width, height),
      inspector_color(24, 26, 30),
      @scene.AffineTransform::identity(),
      1.0,
      None,
    ) {
      Ok(item) => item
      Err(_) => abort("invalid quad item")
    },
  ]
  let mut i = 0
  while i < lines.length() {
    let y = 16.0 + i.to_double() * 18.0
    if y + 18.0 > height {
      break
    }
    items.push(text_item((i + 2).to_uint64(), 16.0, y, lines[i]))
    i = i + 1
  }
  match @scene.SceneSnapshot::new(
    inspector_rect(0.0, 0.0, width, height),
    1.0,
    [],
    [],
    items,
  ) {
    Ok(snapshot) => snapshot
    Err(_) => abort("invalid scene snapshot")
  }
}

///|
async fn read_file_bytes(path : String) -> Bytes raise {
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
        if e > data.length() { data.length() } else { e }
      }
      None => data.length()
    }
    let chunk = if start >= data.length() {
      b""
    } else {
      @bytes.ReadCursor::from_view(data[start:end], 0UL).read_remaining() catch {
        _ => abort("invalid bytes")
      }
    }
    demuxer.handle_input(
      @mp4_demux.Input::{ position: required.position, data: chunk[:] },
    )
  }
}

///|
async fn build_lines(path : String) -> Array[String] {
  let data = read_file_bytes(path) catch {
    _ => return ["cannot read: " + path]
  }
  let lines : Array[String] = ["file: " + path]
  let tree = @boxes.build_box_tree(@bytes.ReadCursor::new(data)) catch {
    _ => []
  }
  for row in @inspect.box_rows(tree) {
    lines.push(row)
  }
  let demuxer = @mp4_demux.Mp4FileDemuxer::new()
  feed_demuxer(demuxer, data)
  let tracks = demuxer.tracks() catch {
    _ => []
  }
  for row in @inspect.track_rows(tracks) {
    lines.push(row)
  }
  let samples : Array[@mp4_demux.Sample] = []
  while true {
    let next = demuxer.next_sample() catch {
      @mp4_demux.InputRequired(_) => None
      _ => None
    } noraise {
      v => v
    }
    match next {
      Some(sample) => samples.push(sample)
      None => break
    }
  }
  for row in @inspect.sample_rows(samples, 0, 40) {
    lines.push(row)
  }
  lines
}

///|
async fn write_status(path : String?, text : String) -> Unit {
  match path {
    Some(path) => @fs.write_file(path, text)
    None => ()
  }
}

///|
async fn run(smoke : Bool, path : String, status_path : String?) -> Unit {
  let lines = build_lines(path)
  let host = match @macos.Host::start() {
    Ok(host) => host
    Err(_) => {
      write_status(status_path, "error: macOS host start failed")
      return
    }
  }
  let window = match host.create_window(
    "mp4.mbt Inspector — " + path,
    1000.0,
    700.0,
  ) {
    Ok(window) => window
    Err(_) => {
      write_status(status_path, "error: window creation failed")
      return
    }
  }
  let snapshot = inspector_scene(1000.0, 700.0, lines)
  match host.present(window, snapshot) {
    Ok(_) => ()
    Err(_) => {
      write_status(status_path, "error: present failed")
      return
    }
  }
  if smoke {
    match host.destroy_window(window) {
      Ok(_) => ()
      Err(_) => ()
    }
    match host.stop() {
      Ok(_) => ()
      Err(_) => ()
    }
    write_status(status_path, "ok rows=\{lines.length()}")
    println("inspector smoke: rows=\{lines.length()}")
    return
  }
  let mut done = false
  while !done {
    let event = match host.next_event() {
      Ok(event) => event
      Err(_) => break
    }
    match event {
      None => ()
      Some(e) => {
        if e.kind is @platform.CloseRequested ||
          e.kind is @platform.Destroyed {
          done = true
        }
        if e.kind is @platform.Input(@primitives.KeyPressed(key=@primitives.Escape, ..)) {
          done = true
        }
      }
    }
  }
  match host.destroy_window(window) {
    Ok(_) => ()
    Err(_) => ()
  }
  match host.stop() {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
async fn main {
  let args = @env.args()
  let smoke = args.contains("--smoke")
  let mut path = ""
  let mut status_path : String? = None
  let mut i = 1
  while i < args.length() {
    if args[i] == "--status" && i + 1 < args.length() {
      status_path = Some(args[i + 1])
      i = i + 1
    } else if args[i] != "--smoke" {
      path = args[i]
    }
    i = i + 1
  }
  if path == "" {
    println("usage: inspector <file.mp4> [--smoke]")
    return
  }
  run(smoke, path, status_path) catch {
    _ => ()
  }
}
