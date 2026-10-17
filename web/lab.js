// MP4 Diff Lab — Rust/WASM (tools/lab-oracle) と MoonBit/JS (src/webdump) の
// 同一入力差分レポート (issue 0016)。DOM/File API はすべてこのファイルに閉じる。

import * as mp4 from './mp4.js';

const UPSTREAM_SHA = '1282b704f44184ec792e1549b5d31e0c4c54dc59';
const SAMPLE_LIMIT = 100000; // 差分は全件比較 (windowing は dump UI 側の関心事)

const dropZone = document.getElementById('drop-zone');
const fileInput = document.getElementById('file-input');
const faultButton = document.getElementById('fault-button');
const downloadButton = document.getElementById('download-button');
const engineLog = document.getElementById('engine-log');
const enginesSection = document.getElementById('engines');
const verdictSection = document.getElementById('verdict-section');
const verdictEl = document.getElementById('verdict');
const statsEl = document.getElementById('stats');
const diffSection = document.getElementById('diff-section');
const diffTbody = document.getElementById('diff-tbody');
const excludedSection = document.getElementById('excluded-section');
const excludedTbody = document.getElementById('excluded-tbody');
const metaSection = document.getElementById('meta-section');
const metaEl = document.getElementById('meta');

let generation = 0;
let oracleWasm = null;   // null = 未取得 (UNVERIFIED 扱い)
let lastReport = null;
let lastReportName = '';

function log(line) {
  engineLog.textContent += line + '\n';
  enginesSection.hidden = false;
}

async function sha256Hex(buf) {
  const digest = await crypto.subtle.digest('SHA-256', buf);
  return Array.from(new Uint8Array(digest)).map(b => b.toString(16).padStart(2, '0')).join('');
}

// ---- Rust/WASM oracle (全量読みの参照実装) ----
async function loadOracle() {
  if (oracleWasm !== null) return oracleWasm;
  try {
    const res = await fetch('oracle.wasm');
    if (!res.ok) throw new Error(`fetch oracle.wasm: HTTP ${res.status}`);
    const { instance } = await WebAssembly.instantiateStreaming(res);
    oracleWasm = instance.exports;
    log('[oracle] lab_oracle.wasm loaded (Rust reference, pinned ' + UPSTREAM_SHA.slice(0, 8) + ')');
  } catch (e) {
    oracleWasm = null;
    log('[oracle] UNAVAILABLE: ' + e.message);
  }
  return oracleWasm;
}

function oracleReport(bytes, logIt) {
  const ex = oracleWasm;
  const ptr = ex.lab_alloc(bytes.length);
  try {
    new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);
    const out = ex.oracle_dump(ptr, bytes.length);
    const len = ex.lab_vec_len(out);
    const text = new TextDecoder().decode(new Uint8Array(ex.memory.buffer, ex.lab_vec_ptr(out), len));
    ex.lab_vec_free(out);
    logIt(`[oracle] dump ok (${bytes.length} bytes in, ${len} bytes json out)`);
    return text;
  } finally {
    ex.lab_free(ptr, bytes.length);
  }
}

// ---- MoonBit/JS candidate (File.slice の Range I/O) ----
async function candidateReport(file, gen, logIt) {
  const session = mp4.mp4dump_create(file.name, BigInt(file.size), 0n);
  let reads = 0, bytesRead = 0;
  for (;;) {
    if (gen !== generation) { mp4.mp4dump_cancel(session); return null; }
    const reqJson = mp4.mp4dump_next_request(session);
    if (reqJson === '') break;
    const req = JSON.parse(reqJson);
    const pos = BigInt(req.position);
    const size = req.size === null ? file.size - pos : BigInt(req.size);
    const blob = file.slice(Number(pos), Number(pos + size));
    const buf = new Uint8Array(await blob.arrayBuffer());
    mp4.mp4dump_feed(session, buf);
    reads += 1;
    bytesRead += buf.length;
  }
  logIt(`[candidate] ${mp4.mp4dump_state(session)} after ${reads} range reads (${bytesRead}/${file.size} bytes)`);
  if (mp4.mp4dump_state(session) === 'cancelled') return null;
  return mp4.mp4dump_report_json(session, SAMPLE_LIMIT);
}

// ---- レンダリング ----
function renderReport(report, meta, candidateJson) {
  verdictSection.hidden = false;
  const v = report.verdict;
  verdictEl.textContent = v.toUpperCase();
  verdictEl.className = 'verdict verdict-' + v;
  statsEl.textContent =
    `pass=${report.stats.pass} fail=${report.stats.fail} ` +
    `unverified=${report.stats.unverified} not_run=${report.stats.not_run}`;

  diffSection.hidden = false;
  diffTbody.textContent = '';
  for (const e of report.entries) {
    const tr = document.createElement('tr');
    tr.className = 'row-' + e.verdict;
    for (const col of [e.path, e.verdict,
                       e.expected === undefined ? '' : JSON.stringify(e.expected),
                       e.actual === undefined ? '' : JSON.stringify(e.actual),
                       e.note || '']) {
      const td = document.createElement('td');
      td.textContent = col;
      tr.appendChild(td);
    }
    diffTbody.appendChild(tr);
  }

  excludedSection.hidden = report.excluded.length === 0;
  excludedTbody.textContent = '';
  for (const e of report.excluded) {
    const tr = document.createElement('tr');
    for (const col of [e.path, e.reason]) {
      const td = document.createElement('td');
      td.textContent = col;
      tr.appendChild(td);
    }
    excludedTbody.appendChild(tr);
  }

  metaSection.hidden = false;
  metaEl.textContent = JSON.stringify(meta, null, 2);
  downloadButton.disabled = false;
  faultButton.disabled = !(candidateJson && JSON.parse(candidateJson).samples.length > 0);
}

async function analyze(file) {
  const gen = ++generation;
  lastReport = null;
  engineLog.textContent = '';
  verdictSection.hidden = true;
  diffSection.hidden = true;
  excludedSection.hidden = true;
  metaSection.hidden = true;
  downloadButton.disabled = true;
  faultButton.disabled = true;

  log(`[run] ${file.name} (${file.size} bytes)`);
  const sha = await sha256Hex(await file.arrayBuffer());
  const meta = {
    upstream_sha: UPSTREAM_SHA,
    fixture_name: file.name,
    fixture_sha256: sha,
    file_size: String(file.size),
    oracle_engine: 'rust/wasm32 (tools/lab-oracle)',
    candidate_engine: 'moonbit/js (src/webdump)',
    user_agent: navigator.userAgent,
    timestamp: new Date().toISOString(),
  };

  // oracle (全量読み)
  let oracleJson = null;
  const wasm = await loadOracle();
  if (wasm) {
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (gen !== generation) return;
    try {
      oracleJson = oracleReport(bytes, log);
    } catch (e) {
      log('[oracle] crashed: ' + e.message);
      oracleJson = null;
    }
  }

  // candidate (range reads)
  let candidateJson = null;
  try {
    candidateJson = await candidateReport(file, gen, log);
  } catch (e) {
    log('[candidate] crashed: ' + e.message);
    candidateJson = null;
  }
  if (gen !== generation) return; // 古い世代の結果は破棄

  // 故障注入・レポート再生成用に保持する
  window.__lastOracle = oracleJson;
  window.__lastCandidate = candidateJson;
  window.__lastMeta = meta;

  let reportText;
  if (oracleJson === null) {
    reportText = mp4.mp4lab_unverified_json(JSON.stringify(meta), 'oracle wasm unavailable or failed');
  } else if (candidateJson === null) {
    reportText = mp4.mp4lab_unverified_json(JSON.stringify(meta), 'candidate session cancelled or failed');
  } else {
    reportText = mp4.mp4lab_compare_json(oracleJson, candidateJson, JSON.stringify(meta));
  }
  lastReport = reportText;
  lastReportName = file.name;
  renderReport(JSON.parse(reportText), meta, candidateJson);
}

// ---- fault injection (self-test: candidate JSON の1フィールドを改竄して再比較) ----
faultButton.addEventListener('click', async () => {
  if (!lastReport) return;
  // 直前の解析を再実行して改竄版 candidate で再比較するためには oracle JSON を
  // 保持する必要がある。簡潔さのため、保存した candidate/oracle を再利用する。
  // (analyze() で lastOracle/lastCandidate を保持する)
  if (!window.__lastOracle || !window.__lastCandidate) return;
  const cand = JSON.parse(window.__lastCandidate);
  const s0 = cand.samples[0];
  s0.duration = String(Number(s0.duration) + 1);
  const meta = JSON.stringify(window.__lastMeta);
  const text = mp4.mp4lab_compare_json(window.__lastOracle, JSON.stringify(cand), meta);
  lastReport = text;
  renderReport(JSON.parse(text), window.__lastMeta, JSON.stringify(cand));
  log('[fault] injected samples[0].duration+1 into candidate; verdict should be FAIL');
});

downloadButton.addEventListener('click', () => {
  if (!lastReport) return;
  const blob = new Blob([lastReport], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `mp4-diff-report-${lastReportName}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
});

// ---- DnD / 選択 ----
dropZone.addEventListener('click', () => fileInput.click());
dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('dragover'); });
dropZone.addEventListener('dragleave', () => dropZone.classList.remove('dragover'));
dropZone.addEventListener('drop', e => {
  e.preventDefault();
  dropZone.classList.remove('dragover');
  if (e.dataTransfer.files.length > 0) analyze(e.dataTransfer.files[0]);
});
fileInput.addEventListener('change', () => {
  if (fileInput.files.length > 0) analyze(fileInput.files[0]);
});
