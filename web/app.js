// mp4.mbt ブラウザデモの UI アダプタ。
// DOM / File API はすべてこの層に閉じ込め、MoonBit 側 (webdump.js) は
// 要求された範囲を返すだけの Sans I/O セッションとして動かす。

import * as mp4 from "./mp4.js";

// 1 回の読み込み要求の上限 (64 MiB)。moov などがこれを超えると
// セッション側が RequestTooLarge で失敗する (CLI の --buffer-size と同じ方針)。
const MAX_READ = 64n * 1024n * 1024n;

// 世代カウンタ: 新しいファイル選択 / キャンセルでインクリメントし、
// 飛行中の非同期 read が古い結果を書き込まないようにする。
let generation = 0;
let currentSession = null;

const ROW_HEIGHT = 28;
const OVERSCAN = 8;

const $ = (id) => document.getElementById(id);

const dropzone = $("dropzone");
const fileInput = $("file-input");
const pickButton = $("pick-button");
const cancelButton = $("cancel-button");
const progress = $("progress");
const sections = {
  error: $("error-section"),
  file: $("file-section"),
  tracks: $("tracks-section"),
  tree: $("tree-section"),
  samples: $("samples-section"),
  log: $("log-section"),
  json: $("json-section"),
};

function resetView() {
  for (const key of Object.keys(sections)) sections[key].hidden = true;
  progress.textContent = "";
  cancelButton.disabled = true;
  const tbody = document.querySelector("#samples-table tbody");
  if (tbody) tbody.textContent = "";
  $("box-tree").textContent = "";
  $("read-log").textContent = "";
  $("json-output").value = "";
}

function showSection(name) {
  sections[name].hidden = false;
}

function renderError(session) {
  const raw = mp4.mp4dump_error_json(session);
  if (!raw) return;
  const err = JSON.parse(raw);
  showSection("error");
  const lines = [`kind: ${err.kind}`, `message: ${err.message}`];
  if (err.position !== null) lines.push(`position: ${err.position}`);
  $("error-body").textContent = lines.join("\n");
}

function renderFileInfo(session, file, report) {
  showSection("file");
  const info = $("file-info");
  const format = report.format === "normal" ? "通常 MP4" :
    report.format === "fragmented" ? "Fragmented MP4" : "不明";
  info.innerHTML = "";
  const rows = [
    ["ファイル名", file.name],
    ["サイズ", `${file.size.toLocaleString()} bytes`],
    ["形式", format],
    ["状態", report.state],
  ];
  for (const [k, v] of rows) {
    const dt = document.createElement("dt");
    dt.textContent = k;
    const dd = document.createElement("dd");
    dd.textContent = v;
    info.append(dt, dd);
  }
  if (report.format === "fragmented") {
    const dt = document.createElement("dt");
    dt.textContent = "備考";
    const dd = document.createElement("dd");
    dd.textContent =
      "fMP4 ではメディアデータは fragment 側にあり、init segment にはサンプルが無いのが通常です。";
    info.append(dt, dd);
  }
}

function renderTracks(session) {
  const tracks = JSON.parse(mp4.mp4dump_tracks_json(session));
  if (!tracks.length) return;
  showSection("tracks");
  const tbody = document.querySelector("#tracks-table tbody");
  tbody.innerHTML = "";
  for (const t of tracks) {
    const tr = document.createElement("tr");
    const cells = [
      t.index,
      t.track_id,
      t.kind,
      t.codec === null ? "(不明)" : t.codec === "unsupported"
        ? "unsupported (構造読み取りのみ)"
        : t.codec,
      t.duration,
      t.timescale,
    ];
    for (const c of cells) {
      const td = document.createElement("td");
      td.textContent = c;
      tr.append(td);
    }
    tbody.append(tr);
  }
}

function renderBoxTree(session) {
  const tree = JSON.parse(mp4.mp4dump_box_tree_json(session));
  if (!tree.length) return;
  showSection("tree");
  const lines = [];
  const walk = (node, depth) => {
    const indent = "  ".repeat(depth);
    const sizeNote =
      node.declared_size === "0" ? `size=0 (to EOF, ${node.size})` : node.size;
    lines.push(
      `${indent}${node.type}  offset=${node.offset} size=${sizeNote} header=${node.header_size}`,
    );
    for (const child of node.children) walk(child, depth + 1);
  };
  for (const node of tree) walk(node, 0);
  $("box-tree").textContent = lines.join("\n");
}

// サンプル一覧は件数が多くなり得るので、スクロール位置に応じた範囲だけ
// `mp4dump_samples_json` で取得して描画する簡易仮想リスト。
function renderSampleWindow(session, viewport) {
  const totalEl = $("sample-total");
  const spacer = $("samples-spacer");
  const tbody = document.querySelector("#samples-table tbody");
  const first = JSON.parse(mp4.mp4dump_samples_json(session, 0, 1));
  totalEl.textContent = `(${first.total} 件)`;
  spacer.style.height = `${first.total * ROW_HEIGHT}px`;

  const render = () => {
    const start = Math.max(
      0,
      Math.floor(viewport.scrollTop / ROW_HEIGHT) - OVERSCAN,
    );
    const count = Math.ceil(viewport.clientHeight / ROW_HEIGHT) + 2 * OVERSCAN;
    const win = JSON.parse(mp4.mp4dump_samples_json(session, start, count));
    tbody.innerHTML = "";
    for (const s of win.samples) {
      const tr = document.createElement("tr");
      tr.className = s.keyframe ? "keyframe" : "";
      const cells = [
        s.index,
        s.track_id,
        s.sample_entry === null ? "→" : s.sample_entry,
        s.keyframe ? "●" : "",
        s.timestamp,
        s.duration,
        s.composition_time_offset === null ? "none" : s.composition_time_offset,
        s.data_offset,
        s.data_size,
      ];
      for (const c of cells) {
        const td = document.createElement("td");
        td.textContent = c;
        tr.append(td);
      }
      tbody.append(tr);
    }
    // 先頭行のオフセット分だけテーブルをずらす
    document.querySelector("#samples-table").style.top =
      `${start * ROW_HEIGHT}px`;
  };
  viewport.onscroll = () => requestAnimationFrame(render);
  render();
}

function renderReadLog(session, fileSize) {
  const log = JSON.parse(mp4.mp4dump_read_log_json(session));
  showSection("log");
  const lines = log.requests.map(
    (r) => `read  offset=${r.position}  size=${r.size}`,
  );
  lines.push("");
  lines.push(
    `total: ${Number(log.total_bytes).toLocaleString()} / ` +
      `${Number(fileSize).toLocaleString()} bytes ` +
      `(${(100 * Number(log.total_bytes) / Number(fileSize)).toFixed(1)}%)`,
  );
  $("read-log").textContent = lines.join("\n");
}

function renderJsonExport(session, file) {
  showSection("json");
  const report = mp4.mp4dump_report_json(session, 0);
  $("json-output").value = report;
  $("download-button").onclick = () => {
    const blob = new Blob([report], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${file.name.replace(/\.[^.]*$/, "")}.dump.json`;
    a.click();
    URL.revokeObjectURL(a.href);
  };
}

const PHASE_LABEL = {
  walk: "トップレベルボックスの走査中…",
  detect: "MP4 種別の判定中…",
  demux: "moov の解析中…",
  moov: "moov 部分木の構築中…",
  collect: "サンプル一覧の収集中…",
};

async function analyze(file) {
  const gen = ++generation;
  if (currentSession) mp4.mp4dump_cancel(currentSession);
  const session = mp4.mp4dump_create(
    file.name,
    BigInt(file.size),
    MAX_READ,
  );
  currentSession = session;
  resetView();
  cancelButton.disabled = false;
  progress.textContent = "解析を開始…";

  try {
    while (gen === generation) {
      const reqJson = mp4.mp4dump_next_request(session);
      if (!reqJson) break;
      const req = JSON.parse(reqJson);
      const start = Number(BigInt(req.position));
      const size = Number(BigInt(req.size));
      const buf = await file.slice(start, start + size).arrayBuffer();
      if (gen !== generation) return;
      mp4.mp4dump_feed(session, new Uint8Array(buf));
      progress.textContent =
        `${PHASE_LABEL[mp4.mp4dump_state(session)] ?? "処理中…"} ` +
        `(要求 ${JSON.parse(mp4.mp4dump_read_log_json(session)).requests.length} 件)`;
    }
  } finally {
    // 解析完了後もボタンは有効のまま残す (完了済みセッションに対しては
    // 「結果のクリア」として働く)
    if (gen !== generation) return;
  }
  if (gen !== generation) return;

  const report = JSON.parse(mp4.mp4dump_report_json(session, 0));
  progress.textContent = "";
  renderFileInfo(session, file, report);
  renderError(session);
  if (report.state !== "ready") return;
  renderTracks(session);
  renderBoxTree(session);
  showSection("samples");
  renderSampleWindow(session, $("samples-viewport"));
  renderReadLog(session, file.size);
  renderJsonExport(session, file);
}

function cancel() {
  generation += 1;
  if (currentSession) {
    mp4.mp4dump_cancel(currentSession);
    currentSession = null;
  }
  resetView();
  progress.textContent = "キャンセルしました。";
}

pickButton.addEventListener("click", () => fileInput.click());
dropzone.addEventListener("click", () => fileInput.click());
dropzone.addEventListener("keydown", (e) => {
  if (e.key === "Enter" || e.key === " ") {
    e.preventDefault();
    fileInput.click();
  }
});
fileInput.addEventListener("change", () => {
  if (fileInput.files.length) analyze(fileInput.files[0]);
  fileInput.value = "";
});
cancelButton.addEventListener("click", cancel);

for (const ev of ["dragenter", "dragover"]) {
  dropzone.addEventListener(ev, (e) => {
    e.preventDefault();
    dropzone.classList.add("dragover");
  });
}
for (const ev of ["dragleave", "drop"]) {
  dropzone.addEventListener(ev, (e) => {
    e.preventDefault();
    dropzone.classList.remove("dragover");
  });
}
dropzone.addEventListener("drop", (e) => {
  const file = e.dataTransfer?.files?.[0];
  if (file) analyze(file);
});
