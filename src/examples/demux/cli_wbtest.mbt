// demux CLI のホワイトボックステスト。
// 非公開ヘルパー (引数パース・16進整形) のユニットテスト。

///|

///|
test "parse_positive_int は 0 以上の整数のみ受け付ける" {
  assert_eq(parse_positive_int(raw="0", name="--x"), 0)
  assert_eq(parse_positive_int(raw="42", name="--x"), 42)
  for bad in ["-1", "abc", "", "3.5"] {
    let result = try {
      ignore(parse_positive_int(raw=bad, name="--x"))
      Ok(())
    } catch {
      e => Err(e)
    } noraise {
      v => v
    }
    match result {
      Err(e) => assert_eq(e.exit_code(), 2)
      Ok(_) => fail("expected Usage error for \{bad}")
    }
  }
}

///|
test "parse_buffer_size は 1..2^31-1 の整数のみ受け付ける" {
  assert_eq(parse_buffer_size(raw="1"), 1L)
  assert_eq(parse_buffer_size(raw="1048576"), 1048576L)
  for bad in ["0", "-5", "3000000000", "x", ""] {
    let result = try {
      ignore(parse_buffer_size(raw=bad))
      Ok(())
    } catch {
      e => Err(e)
    } noraise {
      v => v
    }
    match result {
      Err(e) => assert_eq(e.exit_code(), 2)
      Ok(_) => fail("expected Usage error for \{bad}")
    }
  }
}

///|
test "to_hex は小文字 16 進表現を返す" {
  assert_eq(to_hex(0UL), "0")
  assert_eq(to_hex(48UL), "30")
  assert_eq(to_hex(255UL), "ff")
  assert_eq(to_hex(0xdeadbeefUL), "deadbeef")
}

///|
/// テスト用のチェックイン済み fixture パス。
const FIXTURE_VIDEO : String = "tests/fixtures/upstream/black-h264-video.mp4"

///|
const FIXTURE_AUDIO : String = "tests/fixtures/upstream/beep-aac-audio.mp4"

///|
const FIXTURE_FMP4 : String = "tests/fixtures/upstream/black-h264-fmp4.mp4"

///|
async fn run_expect_error(
  path~ : String,
  max_samples~ : Int32,
  max_read~ : Int64,
  json~ : Bool,
) -> CliError {
  let result = try {
    ignore(run(path~, max_samples~, max_read~, json~))
    Ok(())
  } catch {
    e => Err(e)
  } noraise {
    v => v
  }
  match result {
    Err(error) => error
    Ok(_) => fail("expected run() to raise CliError")
  }
}

///|
async test "run は video fixture の track と全サンプルをテキスト出力する" {
  let output = run(
    path=FIXTURE_VIDEO,
    max_samples=10,
    max_read=DEFAULT_BUFFER_SIZE,
    json=false,
  )
  inspect(
    output,
    content=(
      #|Found 1 track
      #|
      #|Track 1:
      #|  Track ID: 1
      #|  Kind: video
      #|  Duration: 512 (timescale: 12800)
      #|
      #|Samples:
      #|  Sample 1:
      #|    Track ID: 1
      #|    Sample entry: avc1
      #|    Keyframe: true
      #|    Timestamp: 0
      #|    Duration: 512
      #|    Composition time offset: none
      #|    Data offset: 0x30
      #|    Data size: 796 bytes
      #|
      #|
    ),
  )
}

///|
async test "run --max-samples で表示件数を制限し打ち切り注記を出す" {
  let output = run(
    path=FIXTURE_AUDIO,
    max_samples=3,
    max_read=DEFAULT_BUFFER_SIZE,
    json=false,
  )
  // 表示したサンプルは正確に 3 件で、残りがあるので注記が出る
  assert_true(output.contains("Sample 1:"))
  assert_true(output.contains("Sample 2:"))
  assert_true(output.contains("Sample 3:"))
  assert_false(output.contains("Sample 4:"))
  assert_true(output.contains("showing first 3 samples"))
}

///|
async test "run --max-samples 0 は track のみ出力する" {
  let output = run(
    path=FIXTURE_AUDIO,
    max_samples=0,
    max_read=DEFAULT_BUFFER_SIZE,
    json=false,
  )
  assert_true(output.contains("Found 1 track"))
  assert_true(output.contains("Samples:"))
  // サンプル行は出さない
  assert_false(output.contains("Sample entry:"))
  // 残りサンプルがあるので打ち切り注記は出る
  assert_true(output.contains("showing first 0 samples"))
}

///|
async test "run --max-samples が全件数を超えると打ち切り注記は出ない" {
  let output = run(
    path=FIXTURE_VIDEO,
    max_samples=100,
    max_read=DEFAULT_BUFFER_SIZE,
    json=false,
  )
  assert_true(output.contains("Sample 1:"))
  assert_false(output.contains("showing first"))
}

///|
async test "run --json は 64bit 値を十進文字列で出力する" {
  let output = run(
    path=FIXTURE_VIDEO,
    max_samples=10,
    max_read=DEFAULT_BUFFER_SIZE,
    json=true,
  )
  // u64 フィールドが引用符付き十進文字列であることを確認
  assert_true(output.contains("\"duration\": \"512\""))
  assert_true(output.contains("\"timestamp\": \"0\""))
  assert_true(output.contains("\"data_offset\": \"48\""))
  // u32 フィールドは JSON number のまま
  assert_true(output.contains("\"timescale\": 12800"))
  assert_true(output.contains("\"data_size\": 796"))
  assert_true(output.contains("\"track_id\": 1"))
  assert_true(output.contains("\"shown_samples\": 1"))
  assert_true(output.contains("\"truncated\": false"))
}

///|
async test "JSON 出力は厳密なスキーマに一致する" {
  let output = run(
    path=FIXTURE_AUDIO,
    max_samples=1,
    max_read=DEFAULT_BUFFER_SIZE,
    json=true,
  )
  inspect(
    output,
    content=(
      #|{
      #|  "file": "tests/fixtures/upstream/beep-aac-audio.mp4",
      #|  "tracks": [
      #|    {
      #|      "index": 0,
      #|      "track_id": 1,
      #|      "kind": "audio",
      #|      "codec": "mp4a.40.2",
      #|      "duration": "45124",
      #|      "timescale": 44100
      #|    }
      #|  ],
      #|  "samples": [
      #|    {
      #|      "index": 0,
      #|      "track_id": 1,
      #|      "sample_entry": "mp4a",
      #|      "keyframe": true,
      #|      "timestamp": "0",
      #|      "duration": 1024,
      #|      "composition_time_offset": null,
      #|      "data_offset": "44",
      #|      "data_size": 271
      #|    }
      #|  ],
      #|  "shown_samples": 1,
      #|  "truncated": true
      #|}
      #|
    ),
  )
}

///|
async test "fMP4 init segment も track メタデータを読める" {
  // 通常 MP4 demuxer は init segment の moov を読み、stbl が空なので
  // サンプルは列挙されない (upstream demux.rs も同じ動作)
  let output = run(
    path=FIXTURE_FMP4,
    max_samples=10,
    max_read=DEFAULT_BUFFER_SIZE,
    json=false,
  )
  assert_true(output.contains("Found 1 track"))
  assert_true(output.contains("Duration: 0"))
  assert_false(output.contains("Sample entry:"))
}

///|
async test "存在しないファイルは IoError (exit 3)" {
  let error = run_expect_error(
    path="/definitely/missing.mp4",
    max_samples=10,
    max_read=1048576,
    json=false,
  )
  assert_eq(error.exit_code(), 3)
  assert_true(error.message().contains("cannot open file"))
}

///|
async test "空ファイルは UnexpectedEof (exit 3)" {
  // /dev/null は 0 バイトで読める。native CI は Linux のみのため許容する
  let error = run_expect_error(
    path="/dev/null",
    max_samples=10,
    max_read=1048576,
    json=false,
  )
  assert_eq(error.exit_code(), 3)
  assert_true(error.message().contains("unexpected end of file"))
}

///|
async test "要求レンジが上限超過なら RequestTooLarge (exit 4)" {
  // moov ボックス本体 (791B) を上限 100B で切ると契約違反になることを検証する
  let error = run_expect_error(
    path=FIXTURE_VIDEO,
    max_samples=10,
    max_read=100,
    json=false,
  )
  assert_eq(error.exit_code(), 4)
  assert_true(
    error.message().contains("required input range exceeds the read limit"),
  )
}

///|
async test "非 MP4 ファイルは demux エラー (exit 5)" {
  // README は MP4 ではないが 32B 以上あるので ftyp 判定まで進む
  let error = run_expect_error(
    path="README.md",
    max_samples=10,
    max_read=1048576,
    json=false,
  )
  assert_eq(error.exit_code(), 5)
  assert_true(error.message().contains("MP4 decode error"))
}

///|
test "CliError::exit_code の対応表" {
  assert_eq(CliError::Usage("x").exit_code(), 2)
  assert_eq(CliError::IoError("x").exit_code(), 3)
  assert_eq(
    CliError::RequestTooLarge(position=0UL, size=1UL, limit=1UL).exit_code(),
    4,
  )
  assert_eq(
    CliError::UnexpectedEof(position=0UL, expected=1UL, got=0UL).exit_code(),
    3,
  )
  assert_eq(CliError::Demux(@mp4_demux.InvalidState("x")).exit_code(), 5)
}

///|
test "CliError::message は統一された 1 行メッセージを返す" {
  let usage = CliError::Usage("bad --max-samples")
  assert_eq(usage.message(), "bad --max-samples")
  let too_large = CliError::RequestTooLarge(
    position=100UL,
    size=2000UL,
    limit=1024UL,
  )
  assert_true(too_large.message().contains("exceeds the read limit"))
  let eof = CliError::UnexpectedEof(position=10UL, expected=32UL, got=5UL)
  assert_true(eof.message().contains("unexpected end of file"))
  let demux = CliError::Demux(@mp4_demux.InvalidState("broken"))
  assert_true(demux.message().contains("invalid state"))
}
