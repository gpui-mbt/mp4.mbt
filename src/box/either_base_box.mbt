///|
/// [`@bytes.Either`] に包まれたボックスの [`BaseBox`] 実装を透過させる。
///
/// 上流 `basic_types::Either` の `BaseBox` 実装に対応する。`Either` は `src/bytes`
/// にあるが、`BaseBox` の実装は trait と同じパッケージ（`src/box`）にしか置けない
/// ためここで定義する。`children` は包まれたボックスの子をそのまま返す。
pub impl[A : BaseBox, B : BaseBox] BaseBox for @bytes.Either[A, B] with fn box_type(
  self,
) {
  match self {
    A(inner) => BaseBox::box_type(inner)
    B(inner) => BaseBox::box_type(inner)
  }
}

///|
pub impl[A : BaseBox, B : BaseBox] BaseBox for @bytes.Either[A, B] with fn is_unknown_box(
  self,
) {
  match self {
    A(inner) => BaseBox::is_unknown_box(inner)
    B(inner) => BaseBox::is_unknown_box(inner)
  }
}

///|
/// メソッド構文 `either.box_type()` は提供しない（`extend` は自パッケージの型に
/// しか書けない）。呼び出し側は `@box.BaseBox::box_type(either)` を使う。
pub impl[A : BaseBox, B : BaseBox] BaseBox for @bytes.Either[A, B] with fn children(
  self,
) {
  match self {
    A(inner) => BaseBox::children(inner)
    B(inner) => BaseBox::children(inner)
  }
}
