// Diff Lab の Node ランナー (issue 0016)。
// tests/fixtures/manifest.json の全 fixture について、
//   - Rust/WASM oracle (tools/lab-oracle の cdylib)
//   - MoonBit/JS candidate (src/webdump の ESM バンドル)
// を同一 bytes で実行し、field path 単位の差分レポート JSON を
// web/lab-out/ に書き出す。CI ではこの出力をアーティファクトとして保存する。
//
// 使い方:
//   node web/run_lab.mjs [out-dir]
//
// 終了コード:
//   0 = 全 fixture が PASS
//   1 = FAIL または UNVERIFIED/NOT_RUN を含む (レポートは残す)
//   2 = 実行基盤エラー (oracle.wasm 不在 / バンドル読み込み失敗 等)

import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..');
const outDir = process.argv[2] ?? join(here, 'lab-out');

const UPSTREAM_SHA = '1282b704f44184ec792e1549b5d31e0c4c54dc59';
const WASM_PATH = join(repo, 'tools/lab-oracle/target/wasm32-unknown-unknown/release/lab_oracle.wasm');
const BUNDLE_PATH = join(repo, 'web/dist/mp4.js');
const MANIFEST_PATH = join(repo, 'tests/fixtures/manifest.json');

// ---- Rust/WASM oracle ----
async function loadOracle() {
  const wasmBytes = readFileSync(WASM_PATH);
  const { instance } = await WebAssembly.instantiate(wasmBytes);
  return instance.exports;
}

function oracleDump(ex, bytes) {
  const ptr = ex.lab_alloc(bytes.length);
  try {
    new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);
    const out = ex.oracle_dump(ptr, bytes.length);
    const len = ex.lab_vec_len(out);
    const text = new TextDecoder().decode(
      new Uint8Array(ex.memory.buffer, ex.lab_vec_ptr(out), len));
    ex.lab_vec_free(out);
    return text;
  } finally {
    ex.lab_free(ptr, bytes.length);
  }
}

// ---- MoonBit/JS candidate: Range I/O シミュレーション ----
// ブラウザの File.slice 相当: メモリ上の bytes から必要区間だけ切り出す。
async function candidateReport(mp4, name, bytes, reads) {
  const session = mp4.mp4dump_create(name, BigInt(bytes.length), 0n);
  for (;;) {
    const reqJson = mp4.mp4dump_next_request(session);
    if (reqJson === '') break;
    const req = JSON.parse(reqJson);
    const pos = BigInt(req.position);
    const size = req.size === null ? BigInt(bytes.length) - pos : BigInt(req.size);
    const chunk = bytes.slice(Number(pos), Number(pos + size));
    reads.push([Number(pos), chunk.length]);
    mp4.mp4dump_feed(session, chunk);
  }
  const state = mp4.mp4dump_state(session);
  if (state !== 'ready' && state !== 'failed') {
    throw new Error(`unexpected session state: ${state}`);
  }
  return mp4.mp4dump_report_json(session, 100000);
}

async function main() {
  const manifest = JSON.parse(readFileSync(MANIFEST_PATH, 'utf8'));
  const fixtures = manifest.fixtures; // [{name, path, sha256, ...}]
  console.log(`[lab] ${fixtures.length} fixtures from manifest`);
  console.log(`[lab] upstream_sha=${UPSTREAM_SHA}`);

  let oracle;
  try {
    oracle = await loadOracle();
  } catch (e) {
    console.error(`[lab] FATAL: oracle wasm unavailable at ${WASM_PATH}: ${e.message}`);
    console.error('[lab] build it with: cargo build --manifest-path tools/lab-oracle/Cargo.toml --release --target wasm32-unknown-unknown');
    process.exit(2);
  }

  const mp4 = await import(BUNDLE_PATH).catch(e => {
    console.error(`[lab] FATAL: candidate bundle unavailable at ${BUNDLE_PATH}: ${e.message}`);
    console.error('[lab] build it with: sh web/build.sh');
    process.exit(2);
  });

  mkdirSync(outDir, { recursive: true });
  const summary = {
    upstream_sha: UPSTREAM_SHA,
    toolchain: {
      rustc: '1.94.0 (tools/lab-oracle/rust-toolchain.toml)',
      node: process.version,
    },
    generated_at: new Date().toISOString(),
    results: [],
  };
  let bad = 0;

  for (const fx of fixtures) {
    const name = fx.name;
    const bytes = readFileSync(join(repo, fx.path));
    const sha = createHash('sha256').update(bytes).digest('hex');
    if (fx.sha256 && sha !== fx.sha256) {
      console.error(`[lab] ${name}: manifest sha256 mismatch (manifest=${fx.sha256} actual=${sha})`);
      bad += 1;
      continue;
    }
    const meta = JSON.stringify({
      upstream_sha: UPSTREAM_SHA,
      fixture_name: name,
      fixture_sha256: sha,
      file_size: String(bytes.length),
      oracle_engine: 'rust/wasm32 (tools/lab-oracle)',
      candidate_engine: 'moonbit/js (src/webdump)',
      runner: 'web/run_lab.mjs',
      node: process.version,
    });

    const reads = [];
    let report;
    let oracleJson = null;
    let candidateJson = null;
    try {
      oracleJson = oracleDump(oracle, bytes);
    } catch (e) {
      console.error(`[lab] ${name}: oracle crashed: ${e.message}`);
    }
    try {
      candidateJson = await candidateReport(mp4, name, bytes, reads);
    } catch (e) {
      console.error(`[lab] ${name}: candidate crashed: ${e.message}`);
    }
    if (oracleJson === null || candidateJson === null) {
      report = mp4.mp4lab_unverified_json(
        meta,
        oracleJson === null ? 'oracle execution failed' : 'candidate execution failed');
    } else {
      report = mp4.mp4lab_compare_json(oracleJson, candidateJson, meta);
    }
    const rm = JSON.parse(report);

    // 故障注入 self-test: 先頭 fixture で samples[0].duration を +1 し、
    // 該当 field path が FAIL になることを確認する (comparator が差分を
    // 実際に検出できることの実行証拠)。
    let faultCheck = 'skipped';
    if (rm.verdict === 'pass' && candidateJson !== null && bad === 0) {
      const cand = JSON.parse(candidateJson);
      if (cand.samples.length > 0) {
        const s0 = cand.samples[0];
        s0.duration = String(BigInt(s0.duration) + 1n);
        const fault = JSON.parse(
          mp4.mp4lab_compare_json(oracleJson, JSON.stringify(cand), meta));
        const hit = fault.entries.find(
          e => e.verdict === 'fail' && e.path === 'samples[0].duration');
        faultCheck = fault.verdict === 'fail' && hit ? 'detected' : `MISSED (verdict=${fault.verdict})`;
        if (faultCheck !== 'detected') bad += 1;
        writeFileSync(join(outDir, `${name}.fault-report.json`), JSON.stringify(fault, null, 2));
      }
    }

    const s = rm.stats;
    console.log(
      `[lab] ${name}: verdict=${rm.verdict} ` +
      `pass=${s.pass} fail=${s.fail} unverified=${s.unverified} ` +
      `not_run=${s.not_run} excluded=${rm.excluded.length} ` +
      `reads=${reads.length} fault_injection=${faultCheck}`);
    if (rm.verdict !== 'pass') bad += 1;

    summary.results.push({
      fixture: name,
      sha256: sha,
      verdict: rm.verdict,
      stats: s,
      excluded: rm.excluded.length,
      range_reads: reads.length,
      bytes_read: reads.reduce((a, [, n]) => a + n, 0),
      file_size: bytes.length,
      fault_injection: faultCheck,
    });
    writeFileSync(join(outDir, `${name}.report.json`), report);
  }

  writeFileSync(join(outDir, 'summary.json'), JSON.stringify(summary, null, 2));
  console.log(`[lab] reports written to ${outDir}`);
  if (bad > 0) {
    console.error(`[lab] ${bad} fixture(s) did not PASS`);
    process.exit(1);
  }
  console.log('[lab] all fixtures PASS');
}

main().catch(e => {
  console.error(`[lab] FATAL: ${e.stack}`);
  process.exit(2);
});
