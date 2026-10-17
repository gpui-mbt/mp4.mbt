// WebCodecs を使った MP4 → MP4 変換デモ。
// demux は既存の mp4dump (MoonBit/JS)、mux は webtranscode (MoonBit/JS)。
// DOM と WebCodecs はこの層に閉じ込める。

import * as dump from "./mp4.js";
import * as tx from "./transcode-core.js";

const $ = (id) => document.getElementById(id);
const fileInput = $("file-input");
const cancelButton = $("cancel-button");
const progress = $("progress");
const codecStatus = $("codec-status");
const resultSection = $("result-section");
const resultInfo = $("result-info");
const errorSection = $("error-section");
const errorBody = $("error-body");

let generation = 0;
let cancelled = false;
let current = null;

function reset() {
  generation += 1;
  cancelled = false;
  current = null;
  resultSection.hidden = true;
  errorSection.hidden = true;
  progress.textContent = "";
  codecStatus.textContent = "";
  cancelButton.disabled = true;
  fileInput.disabled = false;
}

function fail(message) {
  errorSection.hidden = false;
  errorBody.textContent = message;
  progress.textContent = "";
  fileInput.disabled = false;
  cancelButton.disabled = true;
}

function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i += 1) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64(bytes) {
  let out = "";
  for (let i = 0; i < bytes.length; i += 1) out += String.fromCharCode(bytes[i]);
  return btoa(out);
}

function hex2(value) {
  return value.toString(16).padStart(2, "0");
}

function avcCodec(description) {
  if (description && description.length >= 4) {
    return `avc1.${hex2(description[1])}${hex2(description[2])}${hex2(description[3])}`;
  }
  return "avc1.42E01E";
}

async function feedDump(session, file, isCancelled) {
  let req = JSON.parse(dump.mp4dump_next_request(session) || "{}");
  while (req && req.position != null) {
    if (isCancelled()) throw new Error("cancelled");
    const position = BigInt(req.position);
    const size = req.size == null ? file.size - Number(position) : Number(req.size);
    const end = Math.min(file.size, Number(position) + size);
    const buf = new Uint8Array(await file.slice(Number(position), end).arrayBuffer());
    dump.mp4dump_feed(session, buf);
    req = JSON.parse(dump.mp4dump_next_request(session) || "{}");
  }
}

async function samplePayload(file, offset, size) {
  const start = Number(BigInt(offset));
  return new Uint8Array(await file.slice(start, start + size).arrayBuffer());
}

async function collectDecoded(config, samples, file, isCancelled) {
  const frames = [];
  let decodeError = null;
  const decoder = new VideoDecoder({
    output(frame) { frames.push(frame); },
    error(e) { decodeError = e; },
  });
  decoder.configure(config);
  for (const sample of samples) {
    if (isCancelled()) throw new Error("cancelled");
    const data = await samplePayload(file, sample.data_offset, sample.data_size);
    decoder.decode(new EncodedVideoChunk({
      type: sample.keyframe ? "key" : "delta",
      timestamp: Math.round(Number(BigInt(sample.timestamp)) * 1e6 / config.timescale),
      duration: Math.round(sample.duration * 1e6 / config.timescale),
      data,
    }));
  }
  await decoder.flush();
  decoder.close();
  if (decodeError) throw decodeError;
  return frames;
}

async function encodeFrames(frames, width, height, isCancelled) {
  const chunks = [];
  let description = null;
  let encodeError = null;
  const encoder = new VideoEncoder({
    output(chunk, metadata) {
      if (metadata && metadata.decoderConfig && metadata.decoderConfig.description) {
        description = new Uint8Array(metadata.decoderConfig.description);
      }
      const data = new Uint8Array(chunk.byteLength);
      chunk.copyTo(data);
      chunks.push({
        data,
        timestamp: chunk.timestamp,
        duration: chunk.duration ?? 0,
        key: chunk.type === "key",
      });
    },
    error(e) { encodeError = e; },
  });
  const config = {
    codec: "avc1.42001f",
    width,
    height,
    bitrate: 2_000_000,
    framerate: 30,
    avc: { format: "avc" },
  };
  const support = await VideoEncoder.isConfigSupported(config);
  if (!support.supported) {
    throw new Error("H.264 encoder is not supported in this browser");
  }
  encoder.configure(config);
  for (const frame of frames) {
    if (isCancelled()) throw new Error("cancelled");
    encoder.encode(frame, { keyFrame: false });
    frame.close();
  }
  await encoder.flush();
  encoder.close();
  if (encodeError) throw encodeError;
  return { chunks, description };
}

async function transcode(file) {
  const isCancelled = () => cancelled || generation !== myGeneration;
  const myGeneration = generation;
  reset();
  generation += 1;
  const gen = generation;
  const isStale = () => cancelled || generation !== gen;
  const isCancelledFinal = () => isStale();
  fileInput.disabled = true;
  cancelButton.disabled = false;
  progress.textContent = "解析中…";

  const session = dump.mp4dump_create(file.name, BigInt(file.size), 64n * 1024n * 1024n);
  try {
    await feedDump(session, file, isCancelledFinal);
    const configs = JSON.parse(dump.mp4dump_codec_config_json(session));
    const tracks = JSON.parse(dump.mp4dump_tracks_json(session));
    const videoTrack = tracks.find((t) => t.kind === "video");
    if (!videoTrack) throw new Error("動画トラックが見つかりません");
    const trackConfig = configs.find((c) => c.track_id === videoTrack.track_id);
    if (!trackConfig || !trackConfig.description_b64) {
      throw new Error("動画の codec description を取得できませんでした");
    }
    const description = b64ToBytes(trackConfig.description_b64);
    const samples = JSON.parse(dump.mp4dump_samples_json(session, 0, 1000000));
    if (!samples.items || samples.items.length === 0) throw new Error("サンプルがありません");
    const decodeConfig = {
      codec: avcCodec(description),
      description,
      codedWidth: 0,
      codedHeight: 0,
      optimizeForLatency: true,
    };
    const support = await VideoDecoder.isConfigSupported(decodeConfig);
    if (!support.supported) {
      codecStatus.textContent = `入力 codec ${decodeConfig.codec} はこのブラウザでは decode できません（Disabled）`;
      throw new Error("入力 H.264 decode 非対応");
    }
    progress.textContent = "デコード中…";
    const frames = await collectDecoded(decodeConfig, samples.items, file, isCancelledFinal);
    if (frames.length === 0) throw new Error("デコード結果が空です");
    const width = frames[0].displayWidth;
    const height = frames[0].displayHeight;
    progress.textContent = `エンコード中… (${frames.length} frames)`;
    const { chunks, description: outDescription } = await encodeFrames(frames, width, height, isCancelledFinal);
    if (isCancelledFinal()) throw new Error("cancelled");
    if (!outDescription) throw new Error("エンコーダーの avcC を取得できませんでした");
    progress.textContent = "MP4 を構築中…";
    const muxer = tx.webtranscode_create(width, height, 1_000_000);
    tx.webtranscode_set_avc(muxer, outDescription);
    for (const chunk of chunks) {
      if (isCancelledFinal()) throw new Error("cancelled");
      tx.webtranscode_add_sample(
        muxer,
        chunk.data,
        Math.max(1, Math.round((chunk.duration || 1) * 1_000_000 / 1_000_000)),
        chunk.key,
        null,
      );
      const state = tx.webtranscode_state(muxer);
      if (state === "error") throw new Error(tx.webtranscode_error_json(muxer));
    }
    const base64 = tx.webtranscode_finalize(muxer);
    if (!base64) throw new Error(tx.webtranscode_error_json(muxer) || "mux failed");
    const blob = new Blob([b64ToBytes(base64)], { type: "video/mp4" });
    const url = URL.createObjectURL(blob);
    const link = $("download-link");
    link.href = url;
    resultInfo.innerHTML = "";
    const rows = [
      ["入力", file.name],
      ["出力 codec", "avc1"],
      ["解像度", `${width} × ${height}`],
      ["フレーム数", String(chunks.length)],
      ["出力サイズ", `${blob.size.toLocaleString()} bytes`],
    ];
    for (const [k, v] of rows) {
      const dt = document.createElement("dt");
      dt.textContent = k;
      const dd = document.createElement("dd");
      dd.textContent = v;
      resultInfo.append(dt, dd);
    }
    resultSection.hidden = false;
    progress.textContent = "完了";
    codecStatus.textContent = "";
  } catch (e) {
    if (String(e.message || e).includes("cancelled")) {
      progress.textContent = "キャンセルしました";
    } else {
      fail(String(e.message || e));
    }
  } finally {
    fileInput.disabled = false;
    cancelButton.disabled = true;
  }
}

fileInput.addEventListener("change", () => {
  const file = fileInput.files && fileInput.files[0];
  if (file) transcode(file);
});

cancelButton.addEventListener("click", () => {
  cancelled = true;
  progress.textContent = "キャンセル中…";
});
