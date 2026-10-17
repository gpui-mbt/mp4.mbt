///|
/// [`StblBox`] をラップして、その中の情報を簡単かつ効率的に取り出せるようにする
/// ための構造体。
///
/// 上流 `SampleTableAccessor<T>` に対応する。上流の `T: AsRef<StblBox>` と
/// `AsRef` 実装は移植せず、所有する [`StblBox`] を受け取る非ジェネリックな型に
/// する（上流の唯一の実利用も所有値からの構築）。生成時に各テーブルを走査して
/// run-length の prefix-sum（サンプル尺と、必要ならサンプルデータ位置）を
/// 構築し、以降の 1 サンプル参照は O(1) で行う。
///
/// ```mbt check
/// test {
///   let stbl = @boxes.StblBox::new(
///     @boxes.StsdBox::new([
///       @boxes.SampleEntry::Unknown(
///         @boxes.UnknownBox::new(
///           @bytes.BoxType::Normal(
///             @bytes.FourCC::from_bytes(b"test") catch {
///               _ => abort("4 bytes")
///             },
///           ),
///           @box.BoxSize::U32(8),
///           b"",
///         ),
///       ),
///     ]),
///     @boxes.SttsBox::from_sample_deltas([10U, 10U].iter()),
///     None,
///     None,
///     @boxes.StscBox::new([
///       @boxes.StscEntry::new(
///         @bytes.NonZeroU32::one(),
///         2U,
///         @bytes.NonZeroU32::one(),
///       ),
///     ]),
///     @boxes.StszBox::Variable(entry_sizes=[1U, 2U]),
///     @bytes.Either::A(@boxes.StcoBox::new([100U])),
///     None,
///     None,
///     [],
///   )
///   let accessor = @boxes.SampleTableAccessor::new(stbl)
///   inspect(accessor.sample_count(), content="2")
///   inspect(accessor.chunk_count(), content="1")
///   let sample = accessor.get_sample(@bytes.NonZeroU32::one()).unwrap()
///   inspect(sample.data_offset(), content="100")
///   inspect(sample.timestamp(), content="0")
///   let second = accessor.get_sample(@bytes.NonZeroU32::new(2U).unwrap()).unwrap()
///   inspect(second.data_offset(), content="101")
///   inspect(second.timestamp(), content="10")
/// }
/// ```
pub struct SampleTableAccessor {
  priv stbl_box : StblBox
  priv chunk_count : UInt32
  priv sample_count : UInt32
  /// (累計サンプル数, 尺, 累計尺) の run-length エントリー列
  priv sample_durations : Array[(UInt32, UInt32, UInt64)]
  /// (累計サンプル数, オフセット) の run-length エントリー列（`ctts` がない場合は `None`）
  priv sample_composition_offsets : Array[(UInt32, Int64)]?
  /// チャンク先頭のサンプルインデックス（1 始まり）
  priv sample_index_offsets : Array[@bytes.NonZeroU32]
  /// 各サンプルのデータ開始位置（`stsz` が [`StszBox::Variable`] のときだけ構築する）
  priv sample_data_offsets : Array[UInt64]
}

///|
/// `u32` の飽和加算（上流 `NonZeroU32::saturating_add` に対応）。
fn nonzero_u32_saturating_add(
  base : @bytes.NonZeroU32,
  delta : UInt32,
) -> @bytes.NonZeroU32 {
  let sum = base.get().to_uint64() + delta.to_uint64()
  if sum > 0xFFFFFFFFUL {
    @bytes.NonZeroU32::new(0xFFFFFFFFU).unwrap()
  } else {
    @bytes.NonZeroU32::new(sum.to_uint()).unwrap()
  }
}

///|
/// 累計サンプル数をキーにした run-length エントリー列から、キーに対応する
/// エントリー位置を返す。
///
/// `key_of` はエントリーから累計サンプル数を取り出す関数。一致するエントリーが
/// あれば最左の一致位置（決定的）、無ければキーより小さい最後のエントリー位置を
/// 返す（上流の `binary_search_by_key(...).unwrap_or_else(|i| i - 1)` と同じ
/// 選び方。重複キー時の選択だけを決定的に固定する）。
fn[A] run_length_slot(
  entries : Array[A],
  key_of : (A) -> UInt32,
  key : UInt32,
) -> Int32 {
  let mut low = 0
  let mut high = entries.length()
  while low < high {
    let mid = low + (high - low) / 2
    if key_of(entries[mid]) < key {
      low = mid + 1
    } else {
      high = mid
    }
  }
  if low < entries.length() && key_of(entries[low]) == key {
    low
  } else {
    low - 1
  }
}

///|
/// 昇順のサンプル番号列から `index` 以上の最初の位置を返す（lower bound）。
fn sample_number_slot(
  numbers : Array[@bytes.NonZeroU32],
  index : @bytes.NonZeroU32,
) -> Int32 {
  let key = index.get()
  let mut low = 0
  let mut high = numbers.length()
  while low < high {
    let mid = low + (high - low) / 2
    if numbers[mid].get() < key {
      low = mid + 1
    } else {
      high = mid
    }
  }
  low
}

///|
/// 引数で渡された [`StblBox`] 用の [`SampleTableAccessor`] を生成する。
///
/// 検査順序は上流と同じ（`stts` の累計 → `stsz` との突き合わせ → `ctts` →
/// チャンク数 → `stsc` の空・開始チャンク・参照先・単調性・最終チャンク →
/// チャンク毎のサンプルインデックス表 → `stsc` と `stts` の合計突き合わせ →
/// オフセットの検証）で、同時に複数の不整合がある場合は先に検査した方が
/// 表面化する。
pub fn SampleTableAccessor::new(
  stbl_box : StblBox,
) -> SampleTableAccessor raise SampleTableAccessorError {
  let mut sample_count : UInt32 = 0U
  let sample_durations : Array[(UInt32, UInt32, UInt64)] = []
  let mut acc_duration : UInt64 = 0UL
  for entry in stbl_box.stts_box.entries {
    sample_durations.push((sample_count, entry.sample_delta, acc_duration))
    // sample_count の加算を acc_duration より先に行うことで、累計サンプル数が
    // u32 に収まる限りで acc_duration の加算が u64 を溢れないことを保証する
    // （この順序自体が仕様）。
    let next_sample_count = sample_count.to_uint64() +
      entry.sample_count.to_uint64()
    if next_sample_count > 0xFFFFFFFFUL {
      raise SampleTableAccessorError::SampleCountOverflow(
        box_type=stts_type(),
        accumulated_sample_count=sample_count,
        entry_sample_count=entry.sample_count,
      )
    }
    sample_count = next_sample_count.to_uint()
    acc_duration = acc_duration +
      entry.sample_delta.to_uint64() * entry.sample_count.to_uint64()
  }
  // Variable / Fixed のいずれでも stts 合計と stsz のサンプル数を突き合わせる。
  // Fixed はワイヤ上の sample_count を、Variable は entry_sizes の長さを使う。
  match stbl_box.stsz_box {
    Variable(entry_sizes~) =>
      if entry_sizes.length().reinterpret_as_uint() != sample_count {
        raise SampleTableAccessorError::InconsistentSampleCount(
          stts_sample_count=sample_count,
          other_box_type=stsz_type(),
          other_sample_count=entry_sizes.length().reinterpret_as_uint(),
        )
      }
    Fixed(sample_size~, sample_count=stsz_sample_count) => {
      ignore(sample_size)
      if stsz_sample_count != sample_count {
        raise SampleTableAccessorError::InconsistentSampleCount(
          stts_sample_count=sample_count,
          other_box_type=stsz_type(),
          other_sample_count=stsz_sample_count,
        )
      }
    }
  }
  let sample_composition_offsets : Array[(UInt32, Int64)]? = match
    stbl_box.ctts_box {
    Some(ctts_box) => {
      let mut ctts_sample_count : UInt32 = 0U
      let offsets : Array[(UInt32, Int64)] = []
      for entry in ctts_box.entries {
        offsets.push((ctts_sample_count, entry.sample_offset))
        let next_ctts_sample_count = ctts_sample_count.to_uint64() +
          entry.sample_count.to_uint64()
        if next_ctts_sample_count > 0xFFFFFFFFUL {
          raise SampleTableAccessorError::SampleCountOverflow(
            box_type=ctts_type(),
            accumulated_sample_count=ctts_sample_count,
            entry_sample_count=entry.sample_count,
          )
        }
        ctts_sample_count = next_ctts_sample_count.to_uint()
      }
      if ctts_sample_count != sample_count {
        raise SampleTableAccessorError::InconsistentSampleCount(
          stts_sample_count=sample_count,
          other_box_type=ctts_type(),
          other_sample_count=ctts_sample_count,
        )
      }
      Some(offsets)
    }
    None => None
  }
  let chunk_count = match stbl_box.stco_or_co64_box {
    @bytes.Either::A(stco_box) =>
      stco_box.chunk_offsets.length().reinterpret_as_uint()
    @bytes.Either::B(co64_box) =>
      co64_box.chunk_offsets.length().reinterpret_as_uint()
  }
  if chunk_count > 0U && stbl_box.stsc_box.entries.length() == 0 {
    // チャンクは存在するのに stsc エントリーが空のケース
    raise SampleTableAccessorError::ChunksExistButNoSamples(chunk_count~)
  }
  let stsc_entries = stbl_box.stsc_box.entries
  if stsc_entries.length() > 0 && stsc_entries[0].first_chunk.get() != 1U {
    raise SampleTableAccessorError::FirstChunkIndexIsNotOne(
      actual_chunk_index=stsc_entries[0].first_chunk,
    )
  }
  let mut i = 0
  while i < stsc_entries.length() {
    if stbl_box.stsd_box.entries.length().reinterpret_as_uint() <
      stsc_entries[i].sample_description_index.get() {
      raise SampleTableAccessorError::MissingSampleEntry(
        stsc_entry_index=i,
        sample_description_index=stsc_entries[i].sample_description_index,
        sample_entry_count=stbl_box.stsd_box.entries
          .length()
          .reinterpret_as_uint(),
      )
    }
    i = i + 1
  }
  let mut i = 1
  while i < stsc_entries.length() {
    if stsc_entries[i - 1].first_chunk.get() >=
      stsc_entries[i].first_chunk.get() {
      raise SampleTableAccessorError::ChunkIndicesNotMonotonicallyIncreasing
    }
    i = i + 1
  }
  if chunk_count > 0U {
    let max_chunk_index = @bytes.NonZeroU32::new(chunk_count).unwrap()
    let last_chunk_index = stsc_entries[stsc_entries.length() - 1].first_chunk
    if max_chunk_index.get() < last_chunk_index.get() {
      raise SampleTableAccessorError::LastChunkIndexIsTooLarge(
        max_chunk_index~,
        last_chunk_index~,
      )
    }
  }
  let sample_index_offsets : Array[@bytes.NonZeroU32] = []
  let mut first_sample_index = @bytes.NonZeroU32::one()
  let mut chunk_index : UInt32 = 0U
  while chunk_index < chunk_count {
    sample_index_offsets.push(first_sample_index)
    // stsc の first_chunk は狭義単調増加で先頭が 1 なので、partition point は
    // 必ず 1 以上になる（0 にはならない）。
    let j = stsc_slot(stsc_entries, chunk_index + 1U) - 1
    first_sample_index = nonzero_u32_saturating_add(
      first_sample_index,
      stsc_entries[j].sample_per_chunk,
    )
    chunk_index = chunk_index + 1U
  }
  if first_sample_index.get() - 1U != sample_count {
    raise SampleTableAccessorError::InconsistentSampleCount(
      stts_sample_count=sample_count,
      other_box_type=stsc_type(),
      other_sample_count=first_sample_index.get() - 1U,
    )
  }
  let this : SampleTableAccessor = {
    stbl_box,
    chunk_count,
    sample_count,
    sample_durations,
    sample_composition_offsets,
    sample_index_offsets,
    sample_data_offsets: [],
  }
  // Fixed はテーブルを持たず overflow 検出のみ。Variable は prefix-sum を構築する。
  match this.stbl_box.stsz_box {
    Fixed(sample_size~, ..) => {
      this.validate_fixed_sample_data_offsets(sample_size)
      this
    }
    Variable(_) => {
      let sample_data_offsets = this.build_variable_sample_data_offsets()
      { ..this, sample_data_offsets, }
    }
  }
}

///|
/// `first_chunk` をキーにした `stsc` エントリーの partition point を返す。
///
/// `first_chunk > key` となる最初の位置（上流
/// `partition_point(|entry| entry.first_chunk.get() <= key)` と同じ位置選択）。
/// 先頭エントリーの `first_chunk` は 1 で `key >= 1` なので、戻り値は必ず
/// 1 以上になる（0 にはならない）。
fn stsc_slot(entries : Array[StscEntry], key : UInt32) -> Int32 {
  let mut low = 0
  let mut high = entries.length()
  while low < high {
    let mid = low + (high - low) / 2
    if entries[mid].first_chunk.get() <= key {
      low = mid + 1
    } else {
      high = mid
    }
  }
  low
}

///|
/// `stsz` が Fixed のときのチャンク単位オーバーフロー検査。
///
/// 全サンプル同一サイズなので sample_data_offsets テーブルを持たず、
/// 「チャンク内で最初に u64 を超えるサンプル」だけを検出する（上流と同じ）。
fn SampleTableAccessor::validate_fixed_sample_data_offsets(
  self : SampleTableAccessor,
  sample_size : @bytes.NonZeroU32,
) -> Unit raise SampleTableAccessorError {
  let s = sample_size.get().to_uint64()
  let mut chunk_index = 0
  for chunk in self.chunks() {
    let base = chunk.offset()
    let k = chunk.sample_count().to_uint64()
    // チャンク内の floor((u64::MAX - base) / s) + 1 番目（0 始まりの j 番目）で
    // 最初にオーバーフローする。s >= 1 なので除算は安全。
    if k > (0xFFFFFFFFFFFFFFFFUL - base) / s {
      let j = (0xFFFFFFFFFFFFFFFFUL - base) / s
      let sample_index = @bytes.NonZeroU32::new(
        self.sample_index_offsets[chunk_index].get() + j.to_uint(),
      ).unwrap()
      raise SampleTableAccessorError::SampleDataOffsetOverflow(
        sample_index~,
        accumulated_offset=base + j * s,
        sample_data_size=sample_size.get(),
      )
    }
    chunk_index = chunk_index + 1
  }
}

///|
/// `stsz` が Variable のときのサンプルデータ位置 prefix-sum を構築する。
///
/// オフセットの累計が `u64::MAX` を超える場合は、その時点のサンプルで
/// [`SampleTableAccessorError::SampleDataOffsetOverflow`] を返す（上流と同じ）。
fn SampleTableAccessor::build_variable_sample_data_offsets(
  self : SampleTableAccessor,
) -> Array[UInt64] raise SampleTableAccessorError {
  let sample_data_offsets : Array[UInt64] = []
  for chunk in self.chunks() {
    let mut offset = chunk.offset()
    for sample in chunk.samples() {
      sample_data_offsets.push(offset)
      let size = sample.data_size().to_uint64()
      if offset > 0xFFFFFFFFFFFFFFFFUL - size {
        raise SampleTableAccessorError::SampleDataOffsetOverflow(
          sample_index=sample.index(),
          accumulated_offset=offset,
          sample_data_size=sample.data_size(),
        )
      }
      offset = offset + size
    }
  }
  sample_data_offsets
}

///|
/// トラック内のサンプルの数を取得する。
pub fn SampleTableAccessor::sample_count(self : SampleTableAccessor) -> UInt32 {
  self.sample_count
}

///|
/// トラック内のチャンクの数を取得する。
pub fn SampleTableAccessor::chunk_count(self : SampleTableAccessor) -> UInt32 {
  self.chunk_count
}

///|
/// 指定されたサンプルの情報を返す。
///
/// 存在しないサンプルが指定された場合には `None` を返す。
pub fn SampleTableAccessor::get_sample(
  self : SampleTableAccessor,
  sample_index : @bytes.NonZeroU32,
) -> SampleAccessor? {
  if sample_index.get() <= self.sample_count {
    Some(SampleAccessor::{ table: self, index: sample_index, })
  } else {
    None
  }
}

///|
/// 指定されたタイムスタンプ（トラック先頭からの累計尺）を含むサンプルの情報を
/// 返す。
///
/// 該当のサンプルが存在しない場合には `None` を返す（上流と同じ二分探索）。
pub fn SampleTableAccessor::get_sample_by_timestamp(
  self : SampleTableAccessor,
  timestamp : UInt64,
) -> SampleAccessor? {
  let mut low : UInt32 = 0U
  let mut high : UInt32 = self.sample_count
  while high > low {
    let i = (high - low) / 2U + low
    let sample = SampleAccessor::{
      table: self,
      index: nonzero_u32_saturating_add(@bytes.NonZeroU32::one(), i),
    }
    let sample_timestamp = sample.timestamp()
    if timestamp < sample_timestamp {
      high = i
    } else if timestamp == sample_timestamp {
      return Some(sample)
    } else if timestamp < sample_timestamp + sample.duration().to_uint64() {
      return Some(sample)
    } else {
      low = i + 1U
    }
  }
  None
}

///|
/// 指定されたチャンクの情報を返す。
///
/// 存在しないチャンクが指定された場合には `None` を返す。
pub fn SampleTableAccessor::get_chunk(
  self : SampleTableAccessor,
  chunk_index : @bytes.NonZeroU32,
) -> ChunkAccessor? {
  if chunk_index.get() <= self.chunk_count {
    Some(ChunkAccessor::{ table: self, index: chunk_index, })
  } else {
    None
  }
}

///|
/// トラック内のサンプル群の情報を走査するイテレーターを返す。
///
/// 事前に全サンプル分の配列は作らず、1 サンプル分の参照は O(1) で行う。
pub fn SampleTableAccessor::samples(
  self : SampleTableAccessor,
) -> Iter[SampleAccessor] {
  let mut i : UInt32 = 0U
  Iter::new(fn() -> SampleAccessor? {
    if i < self.sample_count {
      let accessor = SampleAccessor::{
        table: self,
        index: nonzero_u32_saturating_add(@bytes.NonZeroU32::one(), i),
      }
      i = i + 1U
      Some(accessor)
    } else {
      None
    }
  })
}

///|
/// トラック内のチャンク群の情報を走査するイテレーターを返す。
pub fn SampleTableAccessor::chunks(
  self : SampleTableAccessor,
) -> Iter[ChunkAccessor] {
  let mut i : UInt32 = 0U
  Iter::new(fn() -> ChunkAccessor? {
    if i < self.chunk_count {
      let accessor = ChunkAccessor::{
        table: self,
        index: nonzero_u32_saturating_add(@bytes.NonZeroU32::one(), i),
      }
      i = i + 1U
      Some(accessor)
    } else {
      None
    }
  })
}

///|
/// このインスタンスが保持している [`StblBox`] を返す（コピー）。
pub fn SampleTableAccessor::stbl_box(self : SampleTableAccessor) -> StblBox {
  self.stbl_box
}

///|
/// [`SampleTableAccessor::new`] で発生する可能性があるエラー。
///
/// 上流 `SampleTableAccessorError` の variant とフィールド名に対応する。
pub(all) suberror SampleTableAccessorError {
  /// [`SttsBox`] と他のボックスで表現しているサンプル数が異なる
  /// [`SttsBox`] 準拠のサンプル数
  InconsistentSampleCount(
    stts_sample_count~ : UInt32,
    /// [`SttsBox`] とは異なるサンプル数を表しているボックスの種別
    other_box_type~ : @bytes.BoxType,
    /// `other_box_type` 準拠のサンプル数
    other_sample_count~ : UInt32
  )
  /// [`StscBox`] の最初のエントリのチャンクインデックスが 1 ではない
  /// 実際の最初のチャンクインデックスの値
  FirstChunkIndexIsNotOne(actual_chunk_index~ : @bytes.NonZeroU32)
  /// [`StscBox`] の最後のエントリのチャンクインデックスが大きすぎる
  /// [`StcoBox`] ないし [`Co64Box`] が表すチャンクインデックスの最大値
  LastChunkIndexIsTooLarge(
    max_chunk_index~ : @bytes.NonZeroU32,
    /// [`StscBox`] の最後のエントリのチャンクインデックス
    last_chunk_index~ : @bytes.NonZeroU32
  )
  /// [`StscBox`] が存在しないサンプルエントリーを参照している
  /// [`StscEntry`] のインデックス
  MissingSampleEntry(
    stsc_entry_index~ : Int32,
    /// 存在しないサンプルエントリーのインデックス
    sample_description_index~ : @bytes.NonZeroU32,
    /// サンプルエントリーの総数
    sample_entry_count~ : UInt32
  )
  /// [`StscBox`] のチャンクインデックスが単調増加していない
  ChunkIndicesNotMonotonicallyIncreasing
  /// チャンクは存在するのに stsc エントリーが存在しない
  /// チャンク数
  ChunksExistButNoSamples(chunk_count~ : UInt32)
  /// サンプル数の累計が u32 の範囲を超えた
  /// オーバーフローが発生したボックスの種別（`stts` ないし `ctts`）
  SampleCountOverflow(
    box_type~ : @bytes.BoxType,
    /// オーバーフロー直前までの累計サンプル数
    accumulated_sample_count~ : UInt32,
    /// 加算しようとしたエントリのサンプル数
    entry_sample_count~ : UInt32
  )
  /// サンプルデータのバイト位置の累計が u64 の範囲を超えた
  /// オフセットの累計がオーバーフローした時点で処理していたサンプルのインデックス
  SampleDataOffsetOverflow(
    sample_index~ : @bytes.NonZeroU32,
    /// オーバーフロー直前までの累計バイト位置（このサンプルの開始位置）
    accumulated_offset~ : UInt64,
    /// 加算しようとしたサンプルのデータサイズ
    sample_data_size~ : UInt32
  )
}

///|
/// 上流 `Display` と同じ文字列にする。
pub fn SampleTableAccessorError::to_string(
  self : SampleTableAccessorError,
) -> String {
  match self {
    InconsistentSampleCount(
      stts_sample_count~,
      other_box_type~,
      other_sample_count~
    ) =>
      "Sample count in `stts` box is \{stts_sample_count}, but `\{other_box_type.to_string()}` has sample count \{other_sample_count}"
    FirstChunkIndexIsNotOne(actual_chunk_index~) =>
      "First chunk index in `stsc` box is expected to be 1, but got \{actual_chunk_index.get()}"
    LastChunkIndexIsTooLarge(max_chunk_index~, last_chunk_index~) =>
      "Last chunk index in `stsc` box is expected to be `<= \{max_chunk_index.get()}`, but got \{last_chunk_index.get()}"
    MissingSampleEntry(
      stsc_entry_index~,
      sample_description_index~,
      sample_entry_count~
    ) =>
      "\{stsc_entry_index}-th entry in `stsc` box refers to a missing sample entry \{sample_description_index.get()} (sample entry count is \{sample_entry_count})"
    ChunkIndicesNotMonotonicallyIncreasing =>
      "Chunk indices in `stsc` box are not monotonically increasing"
    ChunksExistButNoSamples(chunk_count~) =>
      "Chunks exist (\{chunk_count} chunks) but stsc has no entries"
    SampleCountOverflow(
      box_type~,
      accumulated_sample_count~,
      entry_sample_count~
    ) =>
      "Total sample count in `\{box_type.to_string()}` box overflows u32 (accumulated \{accumulated_sample_count}, adding \{entry_sample_count})"
    SampleDataOffsetOverflow(
      sample_index~,
      accumulated_offset~,
      sample_data_size~
    ) =>
      "Sample data offset overflows u64 at sample \{sample_index.get()} (accumulated \{accumulated_offset}, adding \{sample_data_size})"
  }
}

///|
/// [`StblBox`] 内の個々のサンプルの情報を取得するための構造体。
pub struct SampleAccessor {
  priv table : SampleTableAccessor
  priv index : @bytes.NonZeroU32
}

///|
/// このサンプルのインデックス（1 始まり）を取得する。
pub fn SampleAccessor::index(self : SampleAccessor) -> @bytes.NonZeroU32 {
  self.index
}

///|
/// サンプルの尺を取得する。
pub fn SampleAccessor::duration(self : SampleAccessor) -> UInt32 {
  let i = run_length_slot(
    self.table.sample_durations,
    fn(entry) { entry.0 },
    self.index.get() - 1U,
  )
  self.table.sample_durations[i].1
}

///|
/// サンプルのタイムスタンプ（累計尺）を取得する。
pub fn SampleAccessor::timestamp(self : SampleAccessor) -> UInt64 {
  let i = run_length_slot(
    self.table.sample_durations,
    fn(entry) { entry.0 },
    self.index.get() - 1U,
  )
  let (base_index_minus_1, duration, base_timestamp) = self.table.sample_durations[i]
  base_timestamp +
  duration.to_uint64() *
  (self.index.get() - 1U - base_index_minus_1).to_uint64()
}

///|
/// サンプルのデータサイズ（バイト数）を取得する。
pub fn SampleAccessor::data_size(self : SampleAccessor) -> UInt32 {
  let i = self.index.get().reinterpret_as_int() - 1
  match self.table.stbl_box.stsz_box {
    Fixed(sample_size~, ..) => sample_size.get()
    Variable(entry_sizes~) => entry_sizes[i]
  }
}

///|
/// サンプルデータのファイル内でのバイト位置を返す。
pub fn SampleAccessor::data_offset(self : SampleAccessor) -> UInt64 {
  let idx = self.index.get().reinterpret_as_int() - 1
  match self.table.stbl_box.stsz_box {
    Fixed(sample_size~, ..) => {
      let chunk = self.chunk()
      let first_sample_index = self.table.sample_index_offsets[chunk
        .index()
        .get()
        .reinterpret_as_int() -
        1]
      chunk.offset() +
      (self.index.get() - first_sample_index.get()).to_uint64() *
      sample_size.get().to_uint64()
    }
    Variable(_) => self.table.sample_data_offsets[idx]
  }
}

///|
/// サンプルが同期サンプルかどうかを判定する。
///
/// `stss` が無い場合は全てのサンプルが同期サンプル扱いになる。
pub fn SampleAccessor::is_sync_sample(self : SampleAccessor) -> Bool {
  match self.table.stbl_box.stss_box {
    None => true
    Some(stss_box) => {
      let i = sample_number_slot(stss_box.sample_numbers, self.index)
      i < stss_box.sample_numbers.length() &&
      stss_box.sample_numbers[i] == self.index
    }
  }
}

///|
/// このサンプルをデコードするために必要となる同期サンプルへの参照を返す。
///
/// 自分自身が同期サンプルの場合には自分が返され、自分よりも前方に同期サンプルが
/// 存在しない場合には `None` が返される。
pub fn SampleAccessor::sync_sample(self : SampleAccessor) -> SampleAccessor? {
  match self.table.stbl_box.stss_box {
    None => Some(SampleAccessor::{ table: self.table, index: self.index, })
    Some(stss_box) => {
      let i = sample_number_slot(stss_box.sample_numbers, self.index)
      if i < stss_box.sample_numbers.length() &&
        stss_box.sample_numbers[i] == self.index {
        Some(SampleAccessor::{ table: self.table, index: self.index, })
      } else if i == 0 {
        None
      } else {
        Some(SampleAccessor::{
          table: self.table,
          index: stss_box.sample_numbers[i - 1],
        })
      }
    }
  }
}

///|
/// サンプルのコンポジション時間オフセットを取得する。
///
/// `ctts` が存在する場合にこのサンプルに対応するオフセット値を返し、存在しない
/// 場合は `None` を返す（0 のオフセットと `ctts` なしを区別する）。
pub fn SampleAccessor::composition_time_offset(self : SampleAccessor) -> Int64? {
  match self.table.sample_composition_offsets {
    None => None
    Some(offsets) => {
      let i = run_length_slot(
        offsets,
        fn(entry) { entry.0 },
        self.index.get() - 1U,
      )
      Some(offsets[i].1)
    }
  }
}

///|
/// サンプルが属するチャンクの情報を返す。
///
/// `sample_per_chunk == 0` のチャンクがあるとチャンク先頭サンプルインデックスに
/// 同一値が連続するため、`index` 以下の最右要素を明示的に選ぶ（空チャンクを
/// 挟んでも実サンプル側のチャンクになる）。
pub fn SampleAccessor::chunk(self : SampleAccessor) -> ChunkAccessor {
  let offsets = self.table.sample_index_offsets
  let key = self.index.get()
  let mut low = 0
  let mut high = offsets.length()
  while low < high {
    let mid = low + (high - low) / 2
    if offsets[mid].get() <= key {
      low = mid + 1
    } else {
      high = mid
    }
  }
  let i = low - 1
  let chunk_index = nonzero_u32_saturating_add(
    @bytes.NonZeroU32::one(),
    i.reinterpret_as_uint(),
  )
  self.table.get_chunk(chunk_index).unwrap()
}

///|
/// [`StblBox`] 内の個々のチャンクの情報を取得するための構造体。
pub struct ChunkAccessor {
  priv table : SampleTableAccessor
  priv index : @bytes.NonZeroU32
}

///|
/// このチャンクのインデックス（1 始まり）を取得する。
pub fn ChunkAccessor::index(self : ChunkAccessor) -> @bytes.NonZeroU32 {
  self.index
}

///|
/// チャンクのファイル内でのバイト位置を返す。
pub fn ChunkAccessor::offset(self : ChunkAccessor) -> UInt64 {
  let i = self.index.get().reinterpret_as_int() - 1
  match self.table.stbl_box.stco_or_co64_box {
    @bytes.Either::A(stco_box) => stco_box.chunk_offsets[i].to_uint64()
    @bytes.Either::B(co64_box) => co64_box.chunk_offsets[i]
  }
}

///|
/// このチャンクが参照するサンプルエントリーのインデックス（0 ベース）を取得する。
pub fn ChunkAccessor::sample_entry_index(self : ChunkAccessor) -> Int32 {
  self.stsc_entry().sample_description_index.get().reinterpret_as_int() - 1
}

///|
/// チャンクが参照するサンプルエントリーを返す（コピー）。
pub fn ChunkAccessor::sample_entry(self : ChunkAccessor) -> SampleEntry {
  self.table.stbl_box.stsd_box.entries[self.sample_entry_index()]
}

///|
/// チャンクに属するサンプルの数を返す。
pub fn ChunkAccessor::sample_count(self : ChunkAccessor) -> UInt32 {
  self.stsc_entry().sample_per_chunk
}

///|
/// チャンクに属するサンプル群を走査するイテレーターを返す。
pub fn ChunkAccessor::samples(self : ChunkAccessor) -> Iter[SampleAccessor] {
  let count = self.sample_count()
  let sample_index_offset = self.table.sample_index_offsets[self.index
    .get()
    .reinterpret_as_int() -
    1]
  let mut i : UInt32 = 0U
  Iter::new(fn() -> SampleAccessor? {
    if i < count {
      let sample_index = nonzero_u32_saturating_add(sample_index_offset, i)
      i = i + 1U
      self.table.get_sample(sample_index)
    } else {
      None
    }
  })
}

///|
/// このチャンクに適用される `stsc` エントリーを返す。
fn ChunkAccessor::stsc_entry(self : ChunkAccessor) -> StscEntry {
  let entries = self.table.stbl_box.stsc_box.entries
  let i = stsc_slot(entries, self.index.get()) - 1
  entries[i]
}
