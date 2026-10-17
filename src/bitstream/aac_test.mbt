///|
test "aac audio specific config round trips" {
  let config = @bitstream.AudioSpecificConfig::new(
    @bitstream.AacLc,
    @bitstream.SamplingFrequency::from_hz(48000U),
    @bitstream.ChannelConfiguration::new(2U),
  )
  let bytes = @bitstream.encode_audio_specific_config(config)
  let decoded = @bitstream.parse_audio_specific_config(bytes)
  inspect(decoded.sampling_frequency.hz(), content="48000")
  inspect(decoded.channel_configuration.channel_count(), content="2")
}

///|
test "aac wraps and parses an adts frame" {
  let config = @bitstream.AudioSpecificConfig::new(
    @bitstream.AacLc,
    @bitstream.SamplingFrequency::from_hz(48000U),
    @bitstream.ChannelConfiguration::new(2U),
  )
  let raw = b"\x01\x02\x03\x04"
  let frame = @bitstream.wrap_raw_aac_in_adts(
    raw,
    config,
    @bitstream.AdtsEncodeConfig::default(),
  )
  let (header, payload) = @bitstream.parse_adts_frame(frame)
  inspect(header.frame_length, content="11")
  inspect(payload.length(), content="4")
  inspect(header.sampling_frequency_index, content="3")
}

///|
test "aac builds an mp4a box" {
  let asc = @bitstream.AudioSpecificConfig::new(
    @bitstream.AacLc,
    @bitstream.SamplingFrequency::from_hz(48000U),
    @bitstream.ChannelConfiguration::new(2U),
  )
  let config = @bitstream.Mp4aSampleEntryConfig::new(1U, 0U, 128000U, 128000U)
  let box = @bitstream.build_mp4a_box(asc, config)
  let bytes = @bytes.encode_to_bytes(box)
  let decoded : @boxes.Mp4aBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.audio.channelcount, content="2")
  inspect(decoded.audio.samplerate.integer(), content="48000")
}

///|
test "opus builds an Opus sample entry" {
  let config = @bitstream.OpusSampleEntryConfig::new(
    @bitstream.ChannelCount::new(2U),
    312U,
    48000U,
  )
  let box = @bitstream.build_opus_box(config)
  let bytes = @bytes.encode_to_bytes(box)
  let decoded : @boxes.OpusBox = @bytes.decode_from(
    @bytes.ReadCursor::new(bytes),
  )
  inspect(decoded.dops_box.output_channel_count, content="2")
  inspect(decoded.dops_box.pre_skip, content="312")
}
