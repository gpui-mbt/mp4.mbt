///|
/// 最小構成の MP4（ftyp + free + moov[mvhd]）を組み立てる。
fn minimal_mp4() -> Bytes {
  let ftyp = b"\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isomiso2"
  let freebox = b"\x00\x00\x00\x10free\x00\x00\x00\x00\x00\x00\x00\x00"
  // mvhd v0 の timescale だけ NonZero 必須なので 1 にする
  let mvhd = b"\x00\x00\x00\x6cmvhd" +
    Bytes::repeat(b"\x00", 12) +
    b"\x00\x00\x00\x01" +
    Bytes::repeat(b"\x00", 84)
  let moov = b"\x00\x00\x00\x74moov" + mvhd
  ftyp + freebox + moov
}

///|
/// 状態遷移（`Phase`）を直接検査するホワイトボックステスト。
test "phase transitions mirror required_input" {
  let input = minimal_mp4()
  let moov_offset : UInt64 = 40
  let moov_start = moov_offset.to_int()
  let detector = Mp4FileKindDetector::new()
  assert_true(detector.phase is ReadFtypBoxHeader)

  // ftyp ヘッダー要求に応えると ReadFtypBox に進む
  detector.handle_input(Input::{ position: 0, data: input[:32], })
  let box_size = match detector.phase {
    ReadFtypBox(box_size~) => box_size
    _ => abort("expected ReadFtypBox")
  }
  assert_eq(box_size, 24)
  assert_eq(
    detector.required_input(),
    Some(RequiredInput::{ position: 0, size: Some(24), }),
  )

  // ftyp ボディを読み終わるとトップレベル走査に進む
  detector.handle_input(Input::{ position: 0, data: input[:24], })
  match detector.phase {
    ReadTopLevelBoxHeader(offset~) => assert_eq(offset, 24)
    _ => abort("expected ReadTopLevelBoxHeader")
  }

  // free ボックスのヘッダーを読むと、そのペイロードは読まず次のヘッダーへ進む
  detector.handle_input(Input::{ position: 24, data: input[24:56], })
  match detector.phase {
    ReadTopLevelBoxHeader(offset~) => assert_eq(offset, moov_offset)
    _ => abort("expected ReadTopLevelBoxHeader")
  }
  assert_eq(
    detector.required_input(),
    Some(RequiredInput::{ position: moov_offset, size: Some(32), }),
  )

  // moov ヘッダーを読むと ReadMoovBox に進む
  detector.handle_input(Input::{
    position: moov_offset,
    data: input[moov_start:],
  })
  match detector.phase {
    ReadMoovBox(offset~, box_size~) => {
      assert_eq(offset, moov_offset)
      assert_eq(box_size, Some(input.length().to_uint64() - moov_offset))
    }
    _ => abort("expected ReadMoovBox")
  }

  // moov ボディを読み終わると Detected に確定する
  detector.handle_input(Input::{
    position: moov_offset,
    data: input[moov_start:],
  })
  match detector.phase {
    Detected(kind~) => assert_eq(kind, Mp4FileKind::Mp4)
    _ => abort("expected Detected")
  }
  assert_eq(detector.required_input(), None)
}
