///|
/// MP4 ファイルの読み込み要求範囲を表す。
///
/// 上流 `RequiredInput` に対応する。`size` が `None` の場合はファイル末尾までを
/// 意味する。
pub(all) struct RequiredInput {
  /// 必要なデータの開始位置（バイト単位）
  position : UInt64
  /// 必要なデータのサイズ（バイト単位。`None` はファイル末尾まで）
  ///
  /// ここで指定されたサイズはあくまでもヒントであり、厳密に一致したサイズの
  /// データを提供する必要はない
  size : UInt64?
} derive(Eq, Hash, Debug)

///|
pub extend RequiredInput with Eq::{equal, not_equal}

///|
pub extend RequiredInput with Hash::{hash, hash_combine}

///|
pub extend RequiredInput with Debug::{to_repr}

///|
/// この要求に対応する [`Input`] を `data` から作る。
pub fn RequiredInput::to_input(self : RequiredInput, data : BytesView) -> Input {
  Input::{ position: self.position, data, }
}

///|
/// 引数の [`Input`] がこの要求を満たしているかどうかを確認する。
///
/// 上流 `RequiredInput::is_satisfied_by` に対応する。要求位置が入力データの
/// 範囲に含まれ、`size` 指定がある場合は要求の終端位置も含まれるかを調べる。
pub fn RequiredInput::is_satisfied_by(
  self : RequiredInput,
  input : Input,
) -> Bool {
  if self.position < input.position {
    // 入力データの開始位置が、要求位置よりも後ろにある
    return false
  }
  let offset = self.position - input.position
  if offset > input.data.length().to_uint64() {
    // 入力データの終端位置が、要求位置よりも前にある
    return false
  }

  // ここまで来たら「要求位置が入力データの範囲に含まれていること」は確実
  match self.size {
    None =>
      // 要求サイズがない場合はここで終了（入力にファイル終端までのデータが
      // 含まれていると想定する）
      true
    Some(required_size) =>
      // `offset` は `input.data.length()` 以下なので `remaining` は負にならず、
      // `offset + required_size` の加算オーバーフローは起こらない
      required_size <= input.data.length().to_uint64() - offset
  }
}

///|
/// `handle_input` 系 API に渡す入力データを表す。
///
/// 上流 `Input<'a>` に対応する。`data` はコピーのないビューを保持する。
pub(all) struct Input {
  /// `data` がファイル内で始まる位置（バイト単位）
  position : UInt64
  /// ファイルデータのバッファ
  data : BytesView
} derive(Eq, Hash, Debug)

///|
pub extend Input with Eq::{equal, not_equal}

///|
pub extend Input with Hash::{hash, hash_combine}

///|
pub extend Input with Debug::{to_repr}

///|
/// ファイル内 `position` から `size`（`None` なら入力末尾まで）の範囲を、
/// この入力データから切り出す。
///
/// 上流 `Input::slice_range` に対応する。範囲が入力に含まれない場合は
/// `None` を返す。
pub fn Input::slice_range(
  self : Input,
  position : UInt64,
  size : UInt64?,
) -> BytesView? {
  if position < self.position {
    return None
  }
  let offset = position - self.position
  if offset > self.data.length().to_uint64() {
    return None
  }
  let len = self.data.length().to_uint64()
  let end = match size {
    Some(size) =>
      // 破損データで size が極端に大きい場合の加算オーバーフローを防ぐ
      if size > len - offset {
        return None
      } else {
        offset + size
      }
    None => len
  }
  self.data.get_view(start=offset.to_int(), end=end.to_int())
}
