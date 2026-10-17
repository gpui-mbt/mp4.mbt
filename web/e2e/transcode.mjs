// WebCodecs transcode E2E。web/dist を配信し、ローカル MP4 を変換して
// 出力 MP4 を保存する。H.264 非対応のブラウザでは Disabled 表示を確認する。
//
//   sh web/build.sh
//   PLAYWRIGHT_PATH=<dir> node web/e2e/transcode.mjs

import { createServer } from "node:http";
import { readFile, writeFile, stat } from "node:fs/promises";
import { join, extname, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";

const require2 = createRequire(
  process.env.PLAYWRIGHT_PATH
    ? join(process.env.PLAYWRIGHT_PATH, "e2e.cjs")
    : import.meta.url,
);
const { chromium } = require2("playwright");

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../..");
const distDir = join(repoRoot, "web/dist");
const port = Number(process.env.E2E_PORT ?? 18081);
const fixture = process.env.FIXTURE ??
  join(repoRoot, "tests/fixtures/upstream/black-h264-video.mp4");
const outPath = process.env.OUT ?? "/tmp/transcoded.mp4";
const headless = !process.env.HEADFUL;

const MIME = {
  ".html": "text/html",
  ".js": "text/javascript",
  ".css": "text/css",
  ".json": "application/json",
  ".wasm": "application/wasm",
  ".mp4": "video/mp4",
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
  await stat(join(distDir, "transcode.html")).catch(() => {
    throw new Error("web/dist/transcode.html がありません。先に `sh web/build.sh` を実行してください");
  });
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  const launchOptions = { headless };
  if (process.env.CHANNEL) launchOptions.channel = process.env.CHANNEL;
  const browser = await chromium.launch(launchOptions);
  const page = await browser.newPage();
  page.on("pageerror", (e) => console.log("pageerror:", e.message));
  page.on("console", (m) => console.log("console:", m.text()));
  await page.goto(`http://127.0.0.1:${port}/transcode.html`);

  const support = await page.evaluate(async () => {
    if (!("VideoEncoder" in window) || !("VideoDecoder" in window)) {
      return { codec: false, reason: "WebCodecs unavailable" };
    }
    const enc = await VideoEncoder.isConfigSupported({
      codec: "avc1.42001f",
      width: 640,
      height: 480,
      bitrate: 2_000_000,
      framerate: 30,
      avc: { format: "avc" },
    });
    return { codec: enc.supported, reason: enc.supported ? "" : "H.264 encoder unsupported" };
  });
  if (!support.codec) {
    check("codec-disabled path is explicit", true, support.reason);
    await page.setInputFiles("#file-input", fixture);
    await page.waitForTimeout(3000);
    const status = await page.textContent("#codec-status");
    const err = await page.textContent("#error-body").catch(() => "");
    check(
      "disabled reason is shown",
      (status || err || "").toLowerCase().includes("disabled") ||
        (err || "").toLowerCase().includes("非対応") ||
        (err || "").toLowerCase().includes("not supported"),
      `${status} ${err}`,
    );
    await browser.close();
    server.close();
    const failed = results.filter((r) => !r.ok).length;
    console.log(`${results.length - failed}/${results.length} passed (codec disabled)`);
    process.exit(failed === 0 ? 0 : 1);
  }

  await page.setInputFiles("#file-input", fixture);
  await page.waitForSelector("#result-section:not([hidden]), #error-section:not([hidden])", {
    timeout: 120000,
  });
  const errorVisible = await page.isVisible("#error-section");
  if (errorVisible) {
    const err = await page.textContent("#error-body");
    check("transcode completes", false, err);
  } else {
    check("transcode completes", true);
    const sizeText = await page.textContent("#result-info");
    check("result metadata rendered", sizeText.includes("フレーム数"), sizeText.trim());
    const href = await page.getAttribute("#download-link", "href");
    const bytes = await page.evaluate(async (url) => {
      const response = await fetch(url);
      const buffer = await response.arrayBuffer();
      return Array.from(new Uint8Array(buffer));
    }, href);
    await writeFile(outPath, Uint8Array.from(bytes));
    check("output MP4 written", bytes.length > 32, `${outPath} ${bytes.length} bytes`);
  }
  await browser.close();
  server.close();
  const failed = results.filter((r) => !r.ok).length;
  console.log(`${results.length - failed}/${results.length} passed`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error(e);
  server.close();
  process.exit(1);
});
