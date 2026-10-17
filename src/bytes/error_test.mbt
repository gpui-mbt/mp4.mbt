///|
test "ErrorKind::to_string uses upstream names" {
  inspect(@bytes.ErrorKind::InvalidInput.to_string(), content="InvalidInput")
  inspect(@bytes.ErrorKind::InvalidData.to_string(), content="InvalidData")
  inspect(
    @bytes.ErrorKind::InsufficientBuffer.to_string(),
    content="InsufficientBuffer",
  )
  inspect(@bytes.ErrorKind::Unsupported.to_string(), content="Unsupported")
}

///|
test "Mp4Error::invalid_input keeps kind, reason and autofilled location" {
  let err = @bytes.Mp4Error::invalid_input("bad structure")
  match err {
    @bytes.Mp4Error(kind~, reason~, offset~, loc~, ..) => {
      inspect(kind.to_string(), content="InvalidInput")
      inspect(reason, content="bad structure")
      inspect(offset is None, content="true")
      let location = "\{loc}"
      inspect(location.contains("error_test.mbt"), content="true")
    }
  }
}

///|
test "Mp4Error::invalid_data and unsupported classify failures" {
  match @bytes.Mp4Error::invalid_data("broken") {
    @bytes.Mp4Error(kind~, reason~, offset~, ..) => {
      inspect(kind.to_string(), content="InvalidData")
      inspect(reason, content="broken")
      inspect(offset is None, content="true")
    }
  }
  match @bytes.Mp4Error::unsupported("unsupported layout") {
    @bytes.Mp4Error(kind~, reason~, offset~, ..) => {
      inspect(kind.to_string(), content="Unsupported")
      inspect(reason, content="unsupported layout")
      inspect(offset is None, content="true")
    }
  }
}

///|
test "Mp4Error::insufficient_buffer reports required and available" {
  let err = @bytes.Mp4Error::insufficient_buffer(4UL, 2UL)
  match err {
    @bytes.Mp4Error(kind~, reason~, offset~, ..) => {
      inspect(kind.to_string(), content="InsufficientBuffer")
      inspect(reason, content="required 4 bytes, but only 2 bytes available")
      inspect(offset is None, content="true")
    }
  }
}

///|
test "Mp4Error::with_offset keeps the first offset" {
  let err = @bytes.Mp4Error::invalid_input("x")
    .with_offset(10UL)
    .with_offset(20UL)
  match err {
    @bytes.Mp4Error(kind~, reason~, offset~, ..) => {
      ignore(kind)
      ignore(reason)
      inspect(offset == Some(10UL), content="true")
    }
  }
}

///|
test "Mp4Error::to_string contains classification, reason and offset" {
  let text = @bytes.Mp4Error::invalid_data("broken")
    .with_offset(42UL)
    .to_string()
  inspect(text.contains("InvalidData: broken"), content="true")
  inspect(text.contains("offset=42"), content="true")
  let no_reason = @bytes.Mp4Error::new(@bytes.ErrorKind::Unsupported, "").to_string()
  inspect(no_reason.contains("Unsupported"), content="true")
}

///|
test "Mp4Error::with_box_type keeps the first box type" {
  let first = @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))
  let second = @bytes.BoxType::Normal(@bytes.FourCC::from_string("moov"))
  let err = @bytes.Mp4Error::invalid_data("x")
    .with_box_type(first)
    .with_box_type(second)
  match err {
    @bytes.Mp4Error(box_type~, ..) =>
      inspect(box_type == Some(first), content="true")
  }
}

///|
test "Mp4Error::to_string prefixes the box type" {
  let ty = @bytes.BoxType::Normal(@bytes.FourCC::from_string("mdat"))
  let text = @bytes.Mp4Error::invalid_data("broken")
    .with_box_type(ty)
    .to_string()
  inspect(text.contains("[mdat] InvalidData: broken"), content="true")
  inspect(text.contains("offset="), content="false")
}
