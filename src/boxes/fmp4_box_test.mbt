///|
fn test_flags_non_sync() -> @boxes.SampleFlags {
  @boxes.SampleFlags::from_fields(0, 1, 0, 0, 0, true, 0)
}

///|
fn test_flags_sync() -> @boxes.SampleFlags {
  @boxes.SampleFlags::from_fields(0, 2, 0, 0, 0, false, 0)
}

///|
test "sample flags accessors round trip through fields" {
  let flags = @boxes.SampleFlags::from_fields(2, 1, 3, 2, 5, true, 7)
  inspect(flags.is_leading(), content="2")
  inspect(flags.sample_depends_on(), content="1")
  inspect(flags.sample_is_depended_on(), content="3")
  inspect(flags.sample_has_redundancy(), content="2")
  inspect(flags.sample_padding_value(), content="5")
  inspect(flags.sample_is_non_sync_sample(), content="true")
  inspect(flags.sample_degradation_priority(), content="7")
  inspect(flags.get(), content="166395911")
}

///|
test "mvex with mehd and trex round trips" {
  let mvex = @boxes.MvexBox::new(
    Some(@boxes.MehdBox::new(0x1_0000_0000UL)),
    [
      @boxes.TrexBox::new(1U, 1U, 1000U, 256U, test_flags_sync()),
      @boxes.TrexBox::new(2U, 1U, 1024U, 128U, test_flags_non_sync()),
    ],
    [],
  )
  let bytes = @bytes.encode_to_bytes(mvex)
  let decoded : @boxes.MvexBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.trex_boxes.length(), content="2")
  inspect(decoded.trex_boxes[1].track_id, content="2")
  inspect(decoded.mehd_box is Some(_), content="true")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "moov with mvex round trips and exposes mvex accessor" {
  let mvhd = @boxes.MvhdBox::new(
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.Mp4FileTime::from_secs(0UL),
    @bytes.NonZeroU32::new(1000U).unwrap(),
    0UL,
    @boxes.MvhdBox::default_rate(),
    @boxes.MvhdBox::default_volume(),
    @boxes.MvhdBox::default_matrix(),
    1U,
  )
  let mvex = @boxes.MvexBox::new(
    None,
    [@boxes.TrexBox::new(1U, 1U, 0U, 0U, test_flags_sync())],
    [],
  )
  let moov = @boxes.MoovBox::with_mvex(mvhd, [], mvex, [])
  let bytes = @bytes.encode_to_bytes(moov)
  let decoded : @boxes.MoovBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.mvex_box() is Some(_), content="true")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
fn test_tfhd_all_fields() -> @boxes.TfhdBox {
  @boxes.TfhdBox::new(
    3U,
    Some(0x1_0000_0000UL),
    Some(2U),
    Some(1000U),
    Some(64U),
    Some(test_flags_sync()),
    true,
    true,
  )
}

///|
test "tfhd preserves all flag combinations" {
  let tfhd = test_tfhd_all_fields()
  let bytes = @bytes.encode_to_bytes(tfhd)
  let decoded : @boxes.TfhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.track_id, content="3")
  inspect(decoded.base_data_offset.unwrap(), content="4294967296")
  inspect(decoded.sample_description_index.unwrap(), content="2")
  inspect(decoded.default_sample_duration.unwrap(), content="1000")
  inspect(decoded.default_sample_size.unwrap(), content="64")
  inspect(decoded.duration_is_empty, content="true")
  inspect(decoded.default_base_is_moof, content="true")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "tfhd without optional fields writes only the base flags" {
  let tfhd = @boxes.TfhdBox::new(1U, None, None, None, None, None, false, false)
  let bytes = @bytes.encode_to_bytes(tfhd)
  inspect(bytes.length(), content="16")
  let decoded : @boxes.TfhdBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.base_data_offset is None, content="true")
  inspect(decoded.default_sample_flags is None, content="true")
}

///|
fn test_trun(samples : Array[@boxes.TrunSample]) -> @boxes.TrunBox {
  @boxes.TrunBox::new(Some(16), Some(test_flags_sync()), samples)
}

///|
test "trun with all optional fields round trips" {
  let trun = test_trun([
    @boxes.TrunSample::new(
      Some(1000U),
      Some(10U),
      Some(test_flags_sync()),
      Some(-2L),
    ),
    @boxes.TrunSample::new(
      Some(1000U),
      Some(20U),
      Some(test_flags_non_sync()),
      Some(3L),
    ),
  ])
  let bytes = @bytes.encode_to_bytes(trun)
  let decoded : @boxes.TrunBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.samples.length(), content="2")
  inspect(decoded.samples[0].composition_time_offset.unwrap(), content="-2")
  inspect(decoded.data_offset.unwrap(), content="16")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "trun without per-sample fields round trips" {
  let trun = test_trun([
    @boxes.TrunSample::new(None, None, None, None),
    @boxes.TrunSample::new(None, None, None, None),
  ])
  let bytes = @bytes.encode_to_bytes(trun)
  let decoded : @boxes.TrunBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.samples.length(), content="2")
  inspect(decoded.samples[0].duration is None, content="true")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "trun rejects inconsistent optional presence" {
  let trun = test_trun([
    @boxes.TrunSample::new(Some(1000U), Some(10U), None, None),
    @boxes.TrunSample::new(None, Some(20U), None, None),
  ])
  try {
    let _ = @bytes.encode_to_bytes(trun)
    fail("expected an error")
  } catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason.contains("sample 1"), content="true")
      inspect(reason.contains("duration"), content="true")
    }
    _ => fail("unexpected error kind")
  }
}

///|
test "trun rejects composition time offset mixing negative and u32" {
  let trun = test_trun([
    @boxes.TrunSample::new(None, None, None, Some(0x1_0000_0000L)),
    @boxes.TrunSample::new(None, None, None, Some(-1L)),
  ])
  try {
    let _ = @bytes.encode_to_bytes(trun)
    fail("expected an error")
  } catch {
    @bytes.Mp4Error(kind~, reason~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason.contains("composition_time_offset"), content="true")
    }
    _ => fail("unexpected error kind")
  }
}

///|
test "trun version 0 accepts u32 composition time offset" {
  let trun = test_trun([
    @boxes.TrunSample::new(None, None, None, Some(0xFFFFFFFFL)),
  ])
  let bytes = @bytes.encode_to_bytes(trun)
  let decoded : @boxes.TrunBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(
    decoded.samples[0].composition_time_offset.unwrap(),
    content="4294967295",
  )
}

///|
test "tfdt selects version 1 for 64-bit values" {
  let tfdt = @boxes.TfdtBox::new(0U, 0x1_0000_0000UL)
  let bytes = @bytes.encode_to_bytes(tfdt)
  // tfdt header (8) + full header (4) + u64 (8)
  inspect(bytes.length(), content="20")
  let decoded : @boxes.TfdtBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.version, content="1")
  inspect(decoded.base_media_decode_time, content="4294967296")
}

///|
test "tfdt keeps version 1 even when the value fits in u32" {
  let tfdt = @boxes.TfdtBox::new(1U, 5UL)
  let bytes = @bytes.encode_to_bytes(tfdt)
  let decoded : @boxes.TfdtBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.version, content="1")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
fn test_sidx(ept : UInt64, first_offset : UInt64) -> @boxes.SidxBox {
  @boxes.SidxBox::new(7U, 90000U, ept, first_offset, [
    @boxes.SidxReference::new(false, 1000U, 2000U, true, 1U, 0U),
    @boxes.SidxReference::new(true, 3000U, 4000U, false, 0U, 5U),
  ])
}

///|
test "sidx version 0 round trips reference bit fields" {
  let sidx = test_sidx(0UL, 0UL)
  let bytes = @bytes.encode_to_bytes(sidx)
  let decoded : @boxes.SidxBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.references.length(), content="2")
  inspect(decoded.references[0].starts_with_sap, content="true")
  inspect(decoded.references[1].reference_type, content="true")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "sidx selects version 1 for 64-bit presentation time" {
  let sidx = test_sidx(0x1_0000_0000UL, 0UL)
  let bytes = @bytes.encode_to_bytes(sidx)
  let decoded : @boxes.SidxBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.earliest_presentation_time, content="4294967296")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "mfra with tfra and mfro round trips" {
  let tfra = @boxes.TfraBox::new(0U, 1U, 0U, 0U, 0U, [
    @boxes.TfraEntry::new(0UL, 100UL, 1U, 1U, 1U),
    @boxes.TfraEntry::new(1000UL, 200UL, 2U, 1U, 1U),
  ])
  let mfra = @boxes.MfraBox::new([tfra], @boxes.MfroBox::new(0U))
  let bytes = @bytes.encode_to_bytes(mfra)
  let decoded : @boxes.MfraBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.tfra_boxes.length(), content="1")
  inspect(decoded.tfra_boxes[0].entries[1].traf_number, content="2")
  inspect(decoded.mfro_box.size, content="0")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}

///|
test "tfra selects version 1 for 64-bit entries" {
  let tfra = @boxes.TfraBox::new(0U, 1U, 0U, 0U, 0U, [
    @boxes.TfraEntry::new(0x1_0000_0000UL, 100UL, 1U, 1U, 1U),
  ])
  let bytes = @bytes.encode_to_bytes(tfra)
  let decoded : @boxes.TfraBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.version, content="1")
  inspect(decoded.entries[0].time, content="4294967296")
}

///|
test "root box recognizes ftyp, moof, sidx and mfra" {
  let tfhd = @boxes.TfhdBox::new(
    1U,
    None,
    None,
    Some(1000U),
    Some(10U),
    None,
    false,
    true,
  )
  let trun = test_trun([@boxes.TrunSample::new(None, None, None, None)])
  let traf = @boxes.TrafBox::new(tfhd, None, [trun], [])
  let moof = @boxes.MoofBox::new(@boxes.MfhdBox::new(1U), [traf], [])
  let sidx = test_sidx(0UL, 0UL)
  let mfra = @boxes.MfraBox::new([], @boxes.MfroBox::new(0U))
  let ftyp = @boxes.FtypBox::new(@bytes.FourCC::from_string("iso5"), 0U, [
    @bytes.FourCC::from_string("iso6"),
  ])
  let bytes = @bytes.encode_to_bytes(ftyp) +
    @bytes.encode_to_bytes(moof) +
    @bytes.encode_to_bytes(sidx) +
    @bytes.encode_to_bytes(mfra)
  let cursor = @bytes.ReadCursor::new(bytes)
  let first : @boxes.RootBox = @bytes.decode_from(cursor)
  let second : @boxes.RootBox = @bytes.decode_from(cursor)
  let third : @boxes.RootBox = @bytes.decode_from(cursor)
  let fourth : @boxes.RootBox = @bytes.decode_from(cursor)
  inspect(first is @boxes.RootBox::Ftyp(_), content="true")
  inspect(second is @boxes.RootBox::Moof(_), content="true")
  inspect(third is @boxes.RootBox::Sidx(_), content="true")
  inspect(fourth is @boxes.RootBox::Mfra(_), content="true")
  inspect(cursor.is_empty(), content="true")
  inspect(
    @bytes.encode_to_bytes(first) == @bytes.encode_to_bytes(ftyp),
    content="true",
  )
}

///|
test "unknown fmp4 children are retained without changing known fields" {
  let unknown = @boxes.UnknownBox::new(
    @bytes.BoxType::Normal(@bytes.FourCC::from_string("zzzz")),
    @box.BoxSize::U32(10U),
    b"\xAA\xBB",
  )
  let moof = @boxes.MoofBox::new(@boxes.MfhdBox::new(9U), [], [unknown])
  let bytes = @bytes.encode_to_bytes(moof)
  let decoded : @boxes.MoofBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.mfhd_box.sequence_number, content="9")
  inspect(decoded.unknown_boxes.length(), content="1")
  inspect(decoded.unknown_boxes[0].box_type.to_string(), content="zzzz")
  inspect(@bytes.encode_to_bytes(decoded) == bytes, content="true")
}
