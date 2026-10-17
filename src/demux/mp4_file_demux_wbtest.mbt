///|
/// 上流 `Duration::from_secs(timestamp) / timescale` 比較キーの固定。
test "timestamp_key divides with exact integer arithmetic" {
  // 30 / 30 = 1s ちょうど
  assert_eq(timestamp_key(30, 30), (1, 0))
  // 48000 / 48000 = 1s ちょうど（timescale が違っても同じキーになる）
  assert_eq(timestamp_key(48000, 48000), (1, 0))
  // 1 / 3 = 0.333...s（繰り上げ・丸めなしの切り捨てで上流の Duration 除算と同じ）
  assert_eq(timestamp_key(1, 3), (0, 333333333))
  // 144000 / 48000 = 3s
  assert_eq(timestamp_key(144000, 48000), (3, 0))
  // 90 / 30 = 3s
  assert_eq(timestamp_key(90, 30), (3, 0))
  // 秒未満の端数: 1 / 30 s = 33_333_333 ns
  assert_eq(timestamp_key(1, 30), (0, 33333333))
}

///|
/// 異なる timescale 同士の比較で浮動小数を使わず順序が正しいこと。
test "timestamp_before orders across different timescales without floats" {
  // 30/30 = 1s と 48000/48000 = 1s は等しい（前でも後でもない）
  assert_false(
    timestamp_before(timestamp_key(30, 30), timestamp_key(48000, 48000)),
  )
  assert_false(
    timestamp_before(timestamp_key(48000, 48000), timestamp_key(30, 30)),
  )
  // 30/30 = 1s < 48001/48000 ≈ 1.00002s
  assert_true(
    timestamp_before(timestamp_key(30, 30), timestamp_key(48001, 48000)),
  )
  // 90/30 = 3s < 144001/48000 ≈ 3.00002s
  assert_true(
    timestamp_before(timestamp_key(90, 30), timestamp_key(144001, 48000)),
  )
  // 秒の桁が違う比較
  assert_true(timestamp_before((0, 999999999), (1, 0)))
  assert_true(timestamp_after((1, 0), (0, 999999999)))
}

///|
/// `Duration` の構築境界（1 秒 = 1_000_000_000 ns）。
test "duration construction enforces the nanos bound" {
  assert_true(Duration::new(0, 0) is Some(_))
  assert_true(Duration::new(0, 999999999) is Some(_))
  assert_true(Duration::new(0, 1000000000) is None)
  let d = Duration::from_millis(1500)
  assert_eq(d.as_secs(), 1)
  assert_eq(d.subsec_nanos(), 500000000)
}

///|
/// 上流 `duration_to_timestamp` の変換とオーバーフロー検出。
test "duration_to_timestamp converts and detects overflow" {
  // 1.5s @ timescale 30 = 30 + 15 = 45
  let d = Duration::{ secs: 1, nanos: 500000000, }
  assert_eq(duration_to_timestamp(d, 30), 45)
  // 0s は常に 0
  assert_eq(duration_to_timestamp(Duration::from_secs(0), 48000), 0)
  // ナノ秒部分の丸め（切り捨て）: 0.999999999s @ 30 = 29
  assert_eq(
    duration_to_timestamp(Duration::{ secs: 0, nanos: 999999999, }, 30),
    29,
  )
  // secs * timescale のオーバーフローは DecodeError になる
  let huge = Duration::{ secs: 0xFFFF_FFFF_FFFF_FFFF / 30 + 1, nanos: 0, }
  let result = try Ok(duration_to_timestamp(huge, 30)) catch {
    e => Err(e)
  } noraise {
    v => v
  }
  match result {
    Err(DemuxError::DecodeError(_)) => ()
    _ => abort("expected a timestamp overflow DecodeError")
  }
}

///|
/// ftyp ヘッダーだけを与えた場合、同じ入力で読める分だけフェーズが連鎖する。
test "phases cascade within a single handle_input call" {
  let demuxer = Mp4FileDemuxer::new()
  // 先頭 32 バイトだけを渡す（ftyp ヘッダー + ftyp ペイロードが両方読める量）
  let ftyp = b"\x00\x00\x00\x20ftypisom\x00\x00\x00\x00isomiso2mp41avc1"
  demuxer.handle_input(Input::{ position: 0, data: ftyp[:], })
  // 1 回の handle_input で ReadFtypBoxHeader → ReadFtypBox → ReadMoovBoxHeader まで進む
  match demuxer.phase {
    ReadMoovBoxHeader(offset~) => assert_eq(offset, 32)
    _ => abort("expected ReadMoovBoxHeader")
  }
  match demuxer.required_input() {
    Some(required) => {
      assert_eq(required.position, 32)
      assert_eq(required.size, Some(32))
    }
    None => abort("expected the moov header request")
  }
}

///|
/// moov 以外のトップレベルボックスは 32 バイトのヘッダーだけで読み飛ばす。
test "non-moov top-level boxes are skipped by their headers" {
  let demuxer = Mp4FileDemuxer::new()
  // ftyp(32) + free(40) とすると、free ボックス分をスキップして
  // 次のヘッダー位置 72 を要求する
  let head = b"\x00\x00\x00\x20ftypisom\x00\x00\x00\x00isomiso2mp41avc1" +
    b"\x00\x00\x00\x28free\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  demuxer.handle_input(Input::{ position: 0, data: head[:], })
  match demuxer.phase {
    ReadMoovBoxHeader(offset~) => assert_eq(offset, 72)
    _ => abort("expected ReadMoovBoxHeader")
  }
  match demuxer.required_input() {
    Some(required) => assert_eq(required.position, 72)
    None => abort("expected the next box header request")
  }
}

///|
/// moov 以外のボックスが size 0（ファイル末尾まで）の場合は moov がないとみなす。
test "a size-0 non-moov box means moov box not found" {
  let demuxer = Mp4FileDemuxer::new()
  let head = b"\x00\x00\x00\x20ftypisom\x00\x00\x00\x00isomiso2mp41avc1" +
    b"\x00\x00\x00\x00mdat" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  demuxer.handle_input(Input::{ position: 0, data: head[:], })
  let result = try Ok(demuxer.tracks()) catch {
    e => Err(e)
  } noraise {
    v => v
  }
  match result {
    Err(DemuxError::DecodeError(e)) => {
      let @bytes.Mp4Error(reason~, ..) = e
      assert_eq(reason.to_string(), "moov box not found")
    }
    _ => abort("expected DecodeError")
  }
}
