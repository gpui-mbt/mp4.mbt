// ブラウザ E2E: web/dist をローカル HTTP で配信し、Playwright (Chromium) で
// ファイル選択 → Box Tree / トラック / サンプル表示 → キャンセル・再選択を検証する。
//
// 使い方:
//   sh web/build.sh            # dist を先にビルド
//   NODE_PATH=<playwright の node_modules> node web/e2e/e2e.mjs
//
// 環境変数:
//   E2E_PORT     既定 18080
//   FIXTURE      既定 tests/fixtures/upstream/black-h264-video.mp4
//   HEADFUL=1    非ヘッドレス実行 (デバッグ用)

import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { join, extname, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

// playwright は web/e2e/package.json を npm i するか、
// PLAYWRIGHT_PATH=<node_modules 親パス> で既存のインストールを指す。
// (npx playwright が使える環境では ~/.npm/_npx/<hash>/node_modules)
const require2 = createRequire(
  process.env.PLAYWRIGHT_PATH
    ? join(process.env.PLAYWRIGHT_PATH, "e2e.cjs")
    : import.meta.url,
);
const { chromium } = require2("playwright");

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../..");
const distDir = join(repoRoot, "web/dist");
const port = Number(process.env.E2E_PORT ?? 18080);
const fixture = process.env.FIXTURE ??
  join(repoRoot, "tests/fixtures/upstream/black-h264-video.mp4");
const headless = !process.env.HEADFUL;

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".wasm": "application/wasm",
};

const server = createServer(async (req, res) => {
  try {
    const path = join(distDir, req.url === "/" ? "index.html" : req.url);
    const body = await readFile(path);
    res.writeHead(200, { "content-type": MIME[extname(path)] ?? "text/plain" });
    res.end(body);
  } catch {
    res.writeHead(404).end("not found");
  }
});

const results = [];
const check = (name, ok, detail = "") => {
  results.push({ name, ok, detail });
  console.log(`${ok ? "PASS" : "FAIL"} ${name}${detail ? ` — ${detail}` : ""}`);
};

async function main() {
  await stat(join(distDir, "mp4.js")).catch(() => {
    throw new Error("web/dist/mp4.js がありません。先に `sh web/build.sh` を実行してください");
  });
  const fixtureStat = await stat(fixture);

  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  const browser = await chromium.launch({ headless });
  const page = await browser.newPage();
  page.on("pageerror", (e) => console.log("pageerror:", e.message));

  await page.goto(`http://127.0.0.1:${port}/`);

  // 1. ファイル選択で解析が走り各セクションが表示される
  await page.setInputFiles("#file-input", fixture);
  await page.waitForSelector("#file-section:not([hidden])", { timeout: 30000 });
  check("file section appears after selection", true);

  await page.waitForSelector("#tracks-section:not([hidden])", { timeout: 10000 });
  const trackCells = await page.$$eval("#tracks-table tbody td", (els) =>
    els.map((e) => e.textContent));
  check("track row rendered", trackCells.length >= 6, trackCells.join(","));
  check(
    "codec cell shows avc1",
    trackCells.some((c) => c.includes("avc1.64001e")),
    trackCells[3],
  );

  const treeText = await page.textContent("#box-tree");
  check("box tree shows moov/trak", treeText.includes("moov") && treeText.includes("trak"));
  check(
    "box tree shows mdat as leaf (no children)",
    /mdat\s+offset=\d+ size=\d+/.test(treeText),
  );

  const total = await page.textContent("#sample-total");
  check("sample total shown", total.includes("1"), total.trim());
  const firstRow = await page.$$eval("#samples-table tbody td", (els) =>
    els.map((e) => e.textContent));
  check("sample row has data_offset", firstRow.includes("48"), firstRow.join(","));

  // 2. 範囲読み込みログ: mdat ペイロード (804B) を読んでいない
  const logText = await page.textContent("#read-log");
  check("read log present", logText.includes("read  offset=0"));
  // mdat ヘッダー (offset=40, size=32) は読むが、そのペイロード
  // (offset=48 以降 804B) は要求されない。total バイト数がファイルより
  // 小さいことで確認する。
  const totalMatch = logText.match(/total: ([\d,]+) \/ ([\d,]+)/);
  const readTotal = totalMatch ? Number(totalMatch[1].replaceAll(",", "")) : -1;
  check(
    "mdat payload not read (read total < file size)",
    readTotal > 0 && readTotal < fixtureStat.size,
    `read=${readTotal} file=${fixtureStat.size}`,
  );

  // 3. JSON エクスポート: canonical schema
  const json = await page.inputValue("#json-output");
  const doc = JSON.parse(json);
  check(
    "JSON has canonical fields in order",
    doc.file && Array.isArray(doc.tracks) && Array.isArray(doc.samples) &&
      "shown_samples" in doc && "truncated" in doc && "box_tree" in doc &&
      doc.format === "normal",
  );
  check("64bit duration is decimal string", doc.tracks[0].duration === "512");

  // 4. スクリーンショット (成果物)
  await page.screenshot({ path: join(distDir, "../e2e-screenshot.png"), fullPage: true });

  // 5. キャンセル (結果クリア) → 再選択 (世代管理: 古いセッションが上書きしない)
  await page.click("#cancel-button");
  const progressText = await page.textContent("#progress");
  check("cancel reports", progressText.includes("キャンセル"));
  check(
    "cancel hides result sections",
    await page.$eval("#tracks-section", (e) => e.hidden),
  );
  await page.setInputFiles("#file-input", fixture);
  await page.waitForSelector("#tracks-section:not([hidden])", { timeout: 10000 });
  const reTree = await page.textContent("#box-tree");
  check("re-selection renders fresh tree", reTree.includes("moov"));

  // ---- Diff Lab (issue 0016) ----
  await page.goto(`http://127.0.0.1:${port}/lab.html`);
  await page.setInputFiles("#file-input", fixture);
  await page.waitForSelector("#verdict-section:not([hidden])", { timeout: 30000 });

  const verdict = await page.textContent("#verdict");
  check("lab verdict is PASS", verdict.trim() === "PASS", verdict.trim());

  const engineLog = await page.textContent("#engine-log");
  check(
    "lab ran both engines",
    engineLog.includes("[oracle] dump ok") && engineLog.includes("[candidate]"),
    engineLog.trim().split("\n").join(" | "),
  );

  const stats = await page.textContent("#stats");
  check("lab stats: 0 fail", stats.includes("fail=0"), stats.trim());

  const meta = JSON.parse(await page.textContent("#meta"));
  check(
    "lab meta pins upstream sha",
    meta.upstream_sha === "1282b704f44184ec792e1549b5d31e0c4c54dc59" &&
      meta.oracle_engine.includes("rust/wasm32") &&
      meta.candidate_engine.includes("moonbit/js"),
  );

  // 故障注入: candidate の samples[0].duration を +1 → samples[0].duration が FAIL
  await page.click("#fault-button");
  await page.waitForSelector("#verdict-section:not([hidden])", { timeout: 10000 });
  const faultVerdict = await page.textContent("#verdict");
  check("fault injection yields FAIL", faultVerdict.trim() === "FAIL", faultVerdict.trim());
  const faultPaths = await page.$$eval("#diff-tbody tr.row-fail td:first-child",
    (els) => els.map((e) => e.textContent));
  check(
    "fault lands on samples[0].duration",
    faultPaths.includes("samples[0].duration"),
    faultPaths.join(","),
  );
  await page.screenshot({ path: join(distDir, "../e2e-screenshot-lab.png"), fullPage: true });

  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed`);
  await browser.close();
  server.close();
  if (failed) process.exit(1);
}

main().catch((e) => {
  console.error("E2E error:", e);
  process.exit(1);
});
