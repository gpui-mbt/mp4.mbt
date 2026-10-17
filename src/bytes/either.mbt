///|
/// 2 つの型のいずれか一方の値を保持する列挙型。
///
/// 上流 `basic_types::Either` に対応する。各 variant は包む型以外に意味を持たず、
/// 用途は利用側が決める（例: `StblBox` の `stco_or_co64_box`）。
///
/// ```mbt check
/// test {
///   let a : @bytes.Either[Int32, String] = @bytes.Either::A(1)
///   let b : @bytes.Either[Int32, String] = @bytes.Either::B("x")
///   inspect(a is @bytes.Either::A(_), content="true")
///   inspect(b is @bytes.Either::B(_), content="true")
/// }
/// ```
pub(all) enum Either[A, B] {
  /// 型引数 `A` に対応する variant
  A(A)
  /// 型引数 `B` に対応する variant
  B(B)
} derive(Eq, Hash, Debug)

///|
pub extend Either with Eq::{equal, not_equal}

///|
pub extend Either with Hash::{hash, hash_combine}

///|
pub extend Either with Debug::{to_repr}
