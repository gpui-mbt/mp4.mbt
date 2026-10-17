///|
fn zeros(n : Int32) -> Bytes {
  Bytes::make(n, 0)
}

///|
fn input_at(position : UInt64, n : Int32) -> @demux.Input {
  @demux.Input::{ position, data: zeros(n)[:], }
}

///|
test "RequiredInput::is_satisfied_by covers upstream rules" {
  // 要求位置・終端ともに入力範囲内
  let req = @demux.RequiredInput::{ position: 32, size: Some(32), }
  assert_true(req.is_satisfied_by(input_at(0, 100)))
  assert_true(req.is_satisfied_by(input_at(32, 32)))
  // 要求位置より前で終わる入力
  assert_false(req.is_satisfied_by(input_at(0, 16)))
  // 要求位置より後ろで始まる入力
  assert_false(req.is_satisfied_by(input_at(64, 32)))
  // 要求の終端を含まない入力
  assert_false(req.is_satisfied_by(input_at(32, 16)))
  assert_false(req.is_satisfied_by(input_at(16, 32)))
  // size が None の要求は位置の包含だけで満たされる（空入力でも可）
  let open_req = @demux.RequiredInput::{ position: 32, size: None, }
  assert_true(open_req.is_satisfied_by(input_at(32, 0)))
  assert_true(open_req.is_satisfied_by(input_at(0, 100)))
  assert_false(open_req.is_satisfied_by(input_at(64, 0)))
}

///|
test "RequiredInput::to_input uses the required position" {
  let req = @demux.RequiredInput::{ position: 16, size: Some(8), }
  let input = req.to_input(zeros(8)[:])
  assert_eq(input.position, 16)
  assert_eq(input.data.length(), 8)
}

///|
test "Input::slice_range mirrors upstream bounds rules" {
  let input = @demux.Input::{ position: 8, data: zeros(32)[8:24], }
  // ちょうどの範囲
  let view = input.slice_range(16, Some(4)).unwrap()
  assert_eq(view.length(), 4)
  assert_eq(view.start_offset(), 16)
  // 入力末尾を超えるサイズは None
  assert_eq(input.slice_range(16, Some(16)), None)
  // 入力開始位置より前の位置は None
  assert_eq(input.slice_range(4, Some(4)), None)
  // 入力終端を超える位置は None
  assert_eq(input.slice_range(32, Some(4)), None)
  // size が None なら末尾まで（空でも Some）
  assert_eq(input.slice_range(8, None).unwrap().length(), 16)
  assert_eq(input.slice_range(24, None).unwrap().length(), 0)
}

///|
test "DemuxError::input_required and to_string" {
  let err = @demux.DemuxError::input_required(16, Some(8))
  match err {
    @demux.InputRequired(req) => {
      assert_eq(req.position, 16)
      assert_eq(req.size, Some(8))
    }
    _ => abort("expected InputRequired")
  }
  assert_eq(err.to_string(), "Need input data: 8 bytes at position 16")
  let open_err = @demux.DemuxError::input_required(64, None)
  assert_eq(
    open_err.to_string(),
    "Need input data: from position 64 to end of file",
  )
}
