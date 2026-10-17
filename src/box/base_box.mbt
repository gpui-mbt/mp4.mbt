///|
/// デコード済みボックスの共通インターフェース。
///
/// すべてのボックスは自分の種別を返し、直下の子ボックスを公開する。ペイロードを
/// 解釈しない未知のボックスは `is_unknown_box` が `true` になり、子を持たない。
pub(open) trait BaseBox {
  /// ボックス種別を返す。
  fn box_type(Self) -> @bytes.BoxType

  /// ペイロードを解釈しない未知のボックスかどうか。
  fn is_unknown_box(Self) -> Bool = _

  /// 直下の子ボックスを返す。
  fn children(Self) -> Array[&BaseBox]
}

///|
/// 既定では既知のボックスとして扱う。
impl BaseBox with fn is_unknown_box(_self) {
  false
}
