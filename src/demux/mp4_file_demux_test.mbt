///|
/// `oracle_demux_cases` から名前で 1 件取り出す。
fn demux_case_named(name : String) -> OracleDemuxCase {
  for case in oracle_demux_cases {
    if case.name == name {
      return case
    }
  }
  abort("missing oracle case: \{name}")
}

///|
test "required_input starts with the 32 byte box header" {
  let demuxer = @demux.Mp4FileDemuxer::new()
  match demuxer.required_input() {
    Some(required) => {
      assert_eq(required.position, 0)
      assert_eq(required.size, Some(32))
    }
    None => abort("expected an initial input requirement")
  }
}

///|
/// `tracks` の呼び出しを `Result` に写すヘルパー。
fn tracks_result(
  demuxer : @demux.Mp4FileDemuxer,
) -> Result[ArrayView[@demux.TrackInfo], @demux.DemuxError] {
  try Ok(demuxer.tracks()) catch {
    e => Err(e)
  } noraise {
    v => v
  }
}

///|
test "tracks and samples require initialization input" {
  let demuxer = @demux.Mp4FileDemuxer::new()
  match tracks_result(demuxer) {
    Err(@demux.InputRequired(required)) => {
      assert_eq(required.position, 0)
      assert_eq(required.size, Some(32))
    }
    _ => abort("expected InputRequired")
  }
  match next_sample_result(demuxer) {
    Err(@demux.InputRequired(_)) => ()
    _ => abort("expected InputRequired")
  }
  match prev_sample_result(demuxer) {
    Err(@demux.InputRequired(_)) => ()
    _ => abort("expected InputRequired")
  }
}

///|
test "unsatisfied input is reported once as DecodeError then InputRequired" {
  let demuxer = @demux.Mp4FileDemuxer::new()
  // 要求位置と合わない入力を渡すとエラー状態になる
  demuxer.handle_input(@demux.Input::{ position: 64, data: b"abc"[:], })

  // エラー保持中は required_input が出ない（上流と同じ）
  assert_eq(demuxer.required_input(), None)

  // エラーは一度だけ取り出される（上流の take() と同じ挙動）
  match tracks_result(demuxer) {
    Err(@demux.DecodeError(_)) => ()
    _ => abort("expected the stored DecodeError")
  }
  // 2 回目以降は required_input の状態から InputRequired になる
  match tracks_result(demuxer) {
    Err(@demux.InputRequired(required)) => assert_eq(required.position, 0)
    _ => abort("expected InputRequired after the error was taken")
  }
  assert_true(demuxer.required_input() is Some(_))
}

///|
test "a single input covering the whole file initializes the demuxer" {
  // `moov` が末尾にあるファイルでも、ファイル全体を一度に渡せば
  // 途中のフェーズが連鎖して初期化まで進む（上流の再帰呼び出しと同じ）
  let case = demux_case_named("muxed_empty")
  let demuxer = @demux.Mp4FileDemuxer::new()
  demuxer.handle_input(@demux.Input::{ position: 0, data: case.input[:], })
  assert_eq(demuxer.required_input(), None)
  match tracks_result(demuxer) {
    Ok(found) => assert_eq(found.length(), 0)
    _ => abort("expected successful initialization")
  }
  // トラックがないのでサンプルも即座に空になる
  match next_sample_result(demuxer) {
    Ok(None) => ()
    _ => abort("expected no samples")
  }
}

///|
test "next_sample walks every sample once then returns None" {
  let case = demux_case_named("muxed_video_audio")
  let demuxer = @demux.Mp4FileDemuxer::new()
  demuxer.handle_input(@demux.Input::{ position: 0, data: case.input[:], })
  let tracks = demuxer.tracks()
  assert_eq(tracks.length(), 2)
  assert_eq(tracks[0].track_id, 1)
  assert_eq(tracks[0].kind, @bytes.TrackKind::Video)
  assert_eq(tracks[1].kind, @bytes.TrackKind::Audio)

  // 上流 oracle と同じ 7 サンプルを DTS 順で返す
  let mut count = 0
  let mut first_entry_seen = false
  while true {
    match demuxer.next_sample() {
      Some(sample) => {
        count = count + 1
        if count == 1 {
          assert_eq(sample.timestamp, 0)
          assert_true(sample.keyframe)
          assert_true(sample.sample_entry is Some(_))
          first_entry_seen = true
        }
        // ファイル絶対オフセットとサイズが埋められている
        assert_true(sample.data_offset > 0)
        assert_true(sample.data_size > 0)
      }
      None => break
    }
  }
  assert_true(first_entry_seen)
  assert_eq(count, 7)
  match next_sample_result(demuxer) {
    Ok(None) => ()
    _ => abort("expected the sample stream to stay exhausted")
  }
}

///|
test "demux reads headers and moov without mdat payload" {
  let input = demux_case_named("fixture:black-h264-video.mp4").input
  let demuxer = @demux.Mp4FileDemuxer::new()
  let mut reads = 0
  let mut bytes = 0UL
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
    let chunk = if start >= input.length() {
      b""
    } else {
      @bytes.ReadCursor::from_view(input[start:end], 0UL).read_remaining() catch {
        _ => b""
      }
    }
    reads = reads + 1
    bytes = bytes + chunk.length().to_uint64()
    demuxer.handle_input(@demux.Input::{
      position: required.position,
      data: chunk[:],
    })
  }
  inspect(reads <= 10, content="true")
  inspect(bytes < input.length().to_uint64(), content="true")
}
