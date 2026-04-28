import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "playwright";

const args = process.argv.slice(2);
const rootDir = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(rootDir, "out");
const port = 4173;

const runMatrix = args.includes("--matrix");
const runHeadedOnly = args.includes("--headed");
const pageMode = getArgValue("--page") || "spike";
const singleModeName = getArgValue("--mode");
const scenario = getArgValue("--scenario") || "tauren";
const envName = getArgValue("--env") || "live";

const modes = buildModes();
const targetPath = pageMode === "sanity-2d"
  ? "/sanity-2d.html"
  : pageMode === "sanity-webgl"
    ? "/sanity-webgl.html"
    : "/spike.html";

function buildModes() {
  if (runHeadedOnly) {
    return [{ name: "headed-default", headless: false, args: [] }];
  }
  if (runMatrix) {
    const matrix = [
      { name: "headless-default", headless: true, args: [] },
      { name: "headed-default", headless: false, args: [] },
      { name: "headless-desktop-gl", headless: true, args: ["--use-gl=desktop"] },
      { name: "headless-angle-d3d11", headless: true, args: ["--use-gl=angle", "--use-angle=d3d11"] },
      { name: "headless-angle-swiftshader", headless: true, args: ["--use-angle=swiftshader"] },
      { name: "headless-gpu-flags", headless: true, args: ["--enable-webgl", "--ignore-gpu-blocklist", "--disable-gpu-sandbox"] }
    ];
    return singleModeName ? matrix.filter((m) => m.name === singleModeName) : matrix;
  }
  const defaults = [{ name: "headless-default", headless: true, args: [] }];
  return singleModeName ? defaults.filter((m) => m.name === singleModeName) : defaults;
}

function getArgValue(name) {
  const idx = args.indexOf(name);
  if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
  return "";
}

function contentType(filePath) {
  if (filePath.endsWith(".html")) return "text/html; charset=utf-8";
  if (filePath.endsWith(".js") || filePath.endsWith(".mjs")) return "text/javascript; charset=utf-8";
  if (filePath.endsWith(".css")) return "text/css; charset=utf-8";
  if (filePath.endsWith(".json")) return "application/json; charset=utf-8";
  return "application/octet-stream";
}

function safeWriteJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2), "utf8");
}

async function withTimeout(promise, timeoutMs, label) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`Timeout: ${label}`)), timeoutMs);
      })
    ]);
  } finally {
    if (timer) clearTimeout(timer);
  }
}

const server = http.createServer((req, res) => {
  const incomingUrl = req.url || "/";
  const qIndex = incomingUrl.indexOf("?");
  const rawPath = qIndex >= 0 ? incomingUrl.substring(0, qIndex) : incomingUrl;
  const rawQuery = qIndex >= 0 ? incomingUrl.substring(qIndex) : "";

  if (rawPath.startsWith("/proxy/")) {
    const upstreamPath = rawPath.substring("/proxy/".length);
    const upstreamUrl = `https://wow.zamimg.com/${upstreamPath}${rawQuery}`;
    fetch(upstreamUrl)
      .then(async (upstream) => {
        const body = Buffer.from(await upstream.arrayBuffer());
        const headers = {
          "Content-Type": upstream.headers.get("content-type") || "application/octet-stream",
          "Access-Control-Allow-Origin": "*",
          "Cache-Control": "public, max-age=86400"
        };
        res.writeHead(upstream.status, headers);
        res.end(body);
      })
      .catch((error) => {
        res.writeHead(502, { "Content-Type": "text/plain; charset=utf-8" });
        res.end(`Proxy error: ${error?.message || String(error)}`);
      });
    return;
  }

  const safePath = rawPath === "/" ? targetPath : rawPath;
  const filePath = path.join(rootDir, safePath);
  if (!filePath.startsWith(rootDir)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end("Not found");
      return;
    }
    res.writeHead(200, { "Content-Type": contentType(filePath) });
    res.end(data);
  });
});

await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));

fs.mkdirSync(outDir, { recursive: true });
const summary = [];

try {
  for (const mode of modes) {
    const runId = `${pageMode}-${scenario}-${envName}-${mode.name}`;
    const runDir = path.join(outDir, runId);
    fs.mkdirSync(runDir, { recursive: true });

    const browserLogs = [];
    const requestFailures = [];
    const statusErrors = [];
    let pageError = "";

    console.log(`\n=== Running mode: ${runId} ===`);
    let browser = null;
    try {
      browser = await chromium.launch({
        headless: mode.headless,
        args: mode.args
      });
      const page = await browser.newPage({ viewport: { width: 700, height: 780 } });

    let consoleLogCount = 0;
      page.on("console", (msg) => {
      const text = `[browser:${msg.type()}] ${msg.text()}`;
      browserLogs.push(text);
      // Keep terminal output minimal; full log goes to browser.log.
      consoleLogCount++;
    });
      page.on("pageerror", (err) => {
      pageError = err.message;
      console.log(`[pageerror] ${err.message}`);
    });
      page.on("requestfailed", (request) => {
      const detail = `${request.method()} ${request.url()} => ${request.failure()?.errorText || "failed"}`;
      requestFailures.push(detail);
    });
      page.on("response", (response) => {
      if (response.status() >= 400) {
        const detail = `${response.status()} ${response.url()}`;
        statusErrors.push(detail);
      }
    });

      const params = new URLSearchParams();
      if (pageMode === "spike") {
        params.set("contentPath", `http://127.0.0.1:${port}/proxy/modelviewer/${envName}/`);
        params.set("preserveDrawingBuffer", "1");
        params.set("scenario", scenario);
        params.set("env", envName);
      }
      const url = `http://127.0.0.1:${port}${targetPath}${params.toString() ? `?${params.toString()}` : ""}`;

      await withTimeout(page.goto(url, { waitUntil: "domcontentloaded", timeout: 120000 }), 130000, "page.goto");

      await withTimeout(page.waitForFunction(
      () => {
        const canvases = Array.from(document.querySelectorAll("canvas"));
        const hasSizedCanvas = canvases.some((c) => c.width > 0 && c.height > 0 && c.clientWidth > 0 && c.clientHeight > 0);
        const ready = window.__renderReady === true;
        const err = typeof window.__renderError === "string" && window.__renderError.length > 0;
        return hasSizedCanvas && (ready || err);
      },
      null,
      { timeout: 120000 }
      ), 130000, "waitForFunction render");

      await withTimeout(page.waitForTimeout(5000), 10000, "waitForTimeout");
      await withTimeout(page.evaluate(
      () =>
        new Promise((resolve) => {
          let done = false;
          let frames = 0;
          const timeout = setTimeout(() => {
            if (!done) {
              done = true;
              resolve();
            }
          }, 4000);
          const pump = () => {
            if (done) return;
            frames++;
            if (frames >= 120) {
              done = true;
              clearTimeout(timeout);
              resolve();
              return;
            }
            requestAnimationFrame(pump);
          };
          requestAnimationFrame(pump);
        })
      ), 10000, "raf settle");

      const diagnostics = await withTimeout(page.evaluate(() => {
      const canvases = Array.from(document.querySelectorAll("canvas"));
      const canvas = canvases[0] || null;
      let dataUrlLength = 0;
      let dataUrlPrefix = "";
      let dataUrlError = "";
      let sample2D = null;
      let sampleWebGl = null;
      let sampleWebGlError = "";

      if (canvas) {
        try {
          const dataUrl = canvas.toDataURL("image/png");
          dataUrlLength = dataUrl.length;
          dataUrlPrefix = dataUrl.substring(0, 48);
        } catch (e) {
          dataUrlError = e?.message || String(e);
        }

        try {
          const ctx2d = canvas.getContext("2d");
          if (ctx2d) {
            const pixel = ctx2d.getImageData(Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1).data;
            sample2D = Array.from(pixel);
          }
        } catch {
          // ignore
        }

        try {
          const gl = canvas.getContext("webgl") || canvas.getContext("experimental-webgl");
          if (gl) {
            const px = new Uint8Array(4);
            gl.readPixels(Math.floor(canvas.width / 2), Math.floor(canvas.height / 2), 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
            sampleWebGl = Array.from(px);
          }
        } catch (e) {
          sampleWebGlError = e?.message || String(e);
        }
      }

      return {
        renderReady: window.__renderReady === true,
        renderError: window.__renderError || "",
        renderStatus: window.__renderStatus || "",
        preservePatchEnabled: !!window.__preservePatchEnabled,
        modelState: {
          actorCount: window.__model?.renderer?.actors?.length || 0,
          distance: window.__model?.renderer?.distance ?? null,
          azimuth: window.__model?.renderer?.azimuth ?? null,
          zenith: window.__model?.renderer?.zenith ?? null
        },
        canvases: canvases.map((c, index) => ({
          index,
          width: c.width,
          height: c.height,
          clientWidth: c.clientWidth,
          clientHeight: c.clientHeight
        })),
        canvasDataUrlLength: dataUrlLength,
        canvasDataUrlPrefix: dataUrlPrefix,
        canvasDataUrlError: dataUrlError,
        sample2D,
        sampleWebGl,
        sampleWebGlError
      };
      }), 15000, "diagnostics evaluate");

      await withTimeout(page.screenshot({ path: path.join(runDir, "page.png"), fullPage: true, timeout: 30000 }), 35000, "page screenshot");
      const stageLocator = page.locator("#stage");
      if (await stageLocator.count()) {
        await withTimeout(stageLocator.first().screenshot({ path: path.join(runDir, "stage.png"), timeout: 30000 }), 35000, "stage screenshot");
      }
      const canvasLocator = page.locator("canvas");
      if (await canvasLocator.count()) {
        await withTimeout(canvasLocator.first().screenshot({ path: path.join(runDir, "canvas.png"), timeout: 30000 }), 35000, "canvas screenshot");
      }

      const canvasDataUrl = await withTimeout(page.evaluate(() => {
      const canvas = document.querySelector("canvas");
      if (!canvas) return "";
      try {
        return canvas.toDataURL("image/png");
      } catch {
        return "";
      }
      }), 15000, "canvas toDataURL");
      if (canvasDataUrl.startsWith("data:image/png;base64,")) {
        const base64 = canvasDataUrl.substring("data:image/png;base64,".length);
        fs.writeFileSync(path.join(runDir, "canvas-dataurl.png"), Buffer.from(base64, "base64"));
      }

      safeWriteJson(path.join(runDir, "diagnostics.json"), {
        mode,
        pageMode,
        scenario,
        envName,
        url,
        pageError,
        requestFailures,
        statusErrors,
        diagnostics
      });
      fs.writeFileSync(path.join(runDir, "browser.log"), browserLogs.join("\n"), "utf8");

      summary.push({
        runId,
        ok: true,
        renderReady: diagnostics.renderReady,
        renderError: diagnostics.renderError,
        renderStatus: diagnostics.renderStatus,
        actorCount: diagnostics.modelState.actorCount,
        canvasCount: diagnostics.canvases.length,
        sample2D: diagnostics.sample2D,
        sampleWebGl: diagnostics.sampleWebGl,
        canvasDataUrlLength: diagnostics.canvasDataUrlLength,
        statusErrors: statusErrors.length,
        requestFailures: requestFailures.length
      });
      console.log(`[mode-ok] ${runId}`);
    } catch (error) {
      const message = error?.message || String(error);
      fs.writeFileSync(path.join(runDir, "browser.log"), browserLogs.join("\n"), "utf8");
      safeWriteJson(path.join(runDir, "diagnostics.json"), {
        mode,
        pageMode,
        scenario,
        envName,
        error: message,
        pageError,
        requestFailures,
        statusErrors
      });
      summary.push({
        runId,
        ok: false,
        error: message,
        statusErrors: statusErrors.length,
        requestFailures: requestFailures.length
      });
      console.log(`[mode-error] ${runId}: ${message}`);
    } finally {
      if (browser) {
        try {
          await withTimeout(browser.close(), 15000, "browser close");
        } catch {
          // ignore close failures during spike diagnostics
        }
      }
    }
  }

  safeWriteJson(path.join(outDir, `summary-${pageMode}.json`), summary);
  console.log(`\nSummary written: ${path.join(outDir, `summary-${pageMode}.json`)}`);
} finally {
  await new Promise((resolve) => server.close(resolve));
}
