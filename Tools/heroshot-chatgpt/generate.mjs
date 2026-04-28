/**
 * AltTracker HeroShot – ChatGPT browser automation
 *
 * Usage:
 *   node generate.mjs \
 *     --prompt "Generate a photorealistic portrait of..." \
 *     --output "C:\path\to\output.png" \
 *     [--reference "C:\path\to\ref.png"] \
 *     [--auth-state "C:\path\to\chatgpt-auth.json"] \
 *     [--headless] \
 *     [--timeout 180]
 *
 * Setup: npm install  (in this folder)
 *        Run save-auth.mjs once to capture your ChatGPT session.
 */

import { chromium } from 'playwright';
import { writeFileSync, existsSync, mkdirSync } from 'fs';
import { dirname } from 'path';
import { parseArgs } from 'util';

const { values } = parseArgs({
  options: {
    prompt:              { type: 'string' },
    output:              { type: 'string' },
    reference:           { type: 'string' },
    'auth-state':        { type: 'string' },
    'profile-path':      { type: 'string' },
    'conversation-url':  { type: 'string' },  // navigate to existing conversation instead of homepage
    'conversation-out':  { type: 'string' },  // write final page URL here after generation
    headless:            { type: 'boolean', default: false },
    timeout:             { type: 'string',  default: '180' },
  },
  strict: false,
});

const { prompt, output, reference, headless } = values;
const authState       = values['auth-state'];
const profilePath     = values['profile-path'];
const conversationUrl = values['conversation-url'];
const conversationOut = values['conversation-out'];
const timeoutMs       = parseInt(values.timeout ?? '180') * 1000;

if (!prompt || !output) {
  console.error('[generate] ERROR: --prompt and --output are required');
  process.exit(1);
}

console.log(`[generate] Starting. headless=${headless}, timeout=${timeoutMs / 1000}s`);

// ── Browser launch ────────────────────────────────────────────────────────────
// Prefer persistent profile (launchPersistentContext) — retains cf_clearance
// and ChatGPT session without re-login. Falls back to storageState JSON if no
// profile path is given.

const launchArgs = {
  headless,
  slowMo: headless ? 0 : 60,
  args: ['--disable-blink-features=AutomationControlled', '--no-first-run'],
  ignoreDefaultArgs: ['--enable-automation'],
};

const stealthScript = () => {
  Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  if (!window.chrome) window.chrome = { runtime: {} };
  Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
};

let context;

if (profilePath) {
  console.log(`[generate] Using persistent Chrome profile: ${profilePath}`);
  try {
    context = await chromium.launchPersistentContext(profilePath, { channel: 'chrome', ...launchArgs });
    console.log('[generate] Using real Chrome.');
  } catch {
    console.warn('[generate] Chrome not found, falling back to Playwright Chromium.');
    context = await chromium.launchPersistentContext(profilePath, launchArgs);
  }
  await context.addInitScript(stealthScript);
} else {
  let browser;
  try {
    browser = await chromium.launch({ channel: 'chrome', ...launchArgs });
    console.log('[generate] Using real Chrome (no persistent profile).');
  } catch {
    console.warn('[generate] Chrome not found, using Playwright Chromium.');
    browser = await chromium.launch(launchArgs);
  }
  if (authState && existsSync(authState)) {
    console.log(`[generate] Loading auth state: ${authState}`);
    context = await browser.newContext({ storageState: authState, viewport: { width: 1280, height: 900 } });
  } else {
    console.warn(`[generate] WARN: No profile or auth state found. May need to log in.`);
    context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  }
  await context.addInitScript(stealthScript);
}

const page = await context.newPage();

// Track images already on the page before we send anything
let preExistingImgSrcs = new Set();

try {
  // ── Navigate ────────────────────────────────────────────────────────────────

  const startUrl = conversationUrl ?? 'https://chatgpt.com/';
  if (conversationUrl) {
    console.log(`[generate] Resuming existing conversation: ${conversationUrl}`);
  } else {
    console.log('[generate] Navigating to chatgpt.com (new chat)...');
  }
  await page.goto(startUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});

  // ── Verify login ────────────────────────────────────────────────────────────

  const promptInputSelector = '#prompt-textarea, div[contenteditable="true"][role="textbox"]';
  const promptInput = page.locator(promptInputSelector).first();
  try {
    await promptInput.waitFor({ state: 'visible', timeout: 15000 });
    console.log('[generate] Prompt input found — logged in.');
  } catch {
    throw new Error(
      'ChatGPT prompt input not found after 15 s. ' +
      'Run save-auth.mjs to log in and save your session first.'
    );
  }

  // Snapshot all img srcs currently on the page so we can ignore them later
  preExistingImgSrcs = new Set(
    await page.$$eval('img[src]', imgs => imgs.map(i => i.src))
  );
  console.log(`[generate] Pre-existing images on page: ${preExistingImgSrcs.size}`);

  // ── Upload reference image ──────────────────────────────────────────────────

  if (reference && existsSync(reference)) {
    console.log(`[generate] Attaching reference image: ${reference}`);
    let attached = false;

    // Try attaching via button → file chooser
    const attachSelectors = [
      'button[aria-label*="ttach"]',
      'button[aria-label*="ile"]',
      'button[aria-label*="Add"]',
      'button[aria-label*="add"]',
      '[data-testid*="attach"]',
    ];
    for (const sel of attachSelectors) {
      try {
        const btn = page.locator(sel).first();
        if (await btn.isVisible({ timeout: 1500 })) {
          const [fc] = await Promise.all([
            page.waitForFileChooser({ timeout: 5000 }),
            btn.click(),
          ]);
          await fc.setFiles(reference);
          attached = true;
          console.log(`[generate] Attached via button: ${sel}`);
          break;
        }
      } catch { /* try next */ }
    }

    // Fall back: set files directly on hidden input
    if (!attached) {
      const fileInputs = page.locator('input[type="file"]');
      const count = await fileInputs.count();
      if (count > 0) {
        await fileInputs.first().setInputFiles(reference, { timeout: 5000 });
        attached = true;
        console.log('[generate] Attached via input[type=file]');
      }
    }

    if (!attached) {
      console.warn('[generate] WARN: Could not attach reference image. Proceeding text-only.');
    } else {
      await page.waitForTimeout(2000); // let upload thumbnail render
    }
  }

  // Snapshot images NOW (after any attachment) so uploaded thumbnails are
  // excluded from "new image" detection after generation completes.
  preExistingImgSrcs = new Set(
    await page.$$eval('img[src]', imgs => imgs.map(i => i.src))
  );
  console.log(`[generate] Pre-send image snapshot: ${preExistingImgSrcs.size} images (includes any upload thumbnails)`);

  // ── Type prompt ─────────────────────────────────────────────────────────────

  console.log('[generate] Typing prompt...');
  await promptInput.click();
  await page.keyboard.insertText(prompt);
  await page.waitForTimeout(400);

  // ── Send ────────────────────────────────────────────────────────────────────

  console.log('[generate] Sending...');
  const sendSelectors = [
    'button[data-testid="send-button"]',
    'button[aria-label*="Send"]',
    'button[aria-label*="send"]',
  ];
  let sent = false;
  for (const sel of sendSelectors) {
    try {
      const btn = page.locator(sel).first();
      if (await btn.isEnabled({ timeout: 2000 })) {
        await btn.click();
        sent = true;
        console.log(`[generate] Sent via ${sel}`);
        break;
      }
    } catch { /* try next */ }
  }
  if (!sent) {
    await page.keyboard.press('Enter');
    console.log('[generate] Sent via Enter key');
  }

  // ── Wait for generated image ─────────────────────────────────────────────────
  // Strategy:
  //   1. Hard-wait 8 s minimum (generation physically takes at least that).
  //   2. Try known URL patterns scoped to assistant bubbles first.
  //   3. Fallback: scan ALL img[src] on the page, exclude those inside
  //      [data-message-author-role="user"] bubbles (where the uploaded reference
  //      thumbnail lives), and compare against pre-send snapshot.
  //   This approach survives ChatGPT DOM changes without depending on the
  //   assistant role attribute existing.

  console.log('[generate] Waiting for image to be generated...');
  await page.waitForTimeout(8000); // minimum generation time guard

  const knownImageSelectors = [
    '[data-message-author-role="assistant"] img[src*="oaiusercontent"]',
    '[data-message-author-role="assistant"] img[src*="oaidalle"]',
    '[data-message-author-role="assistant"] img[src*="files.openai"]',
    '[data-message-author-role="assistant"] img[src*="chatgpt.com/backend-api"]',
  ];

  let imgSrc = null;
  const deadline = Date.now() + timeoutMs;
  let pollCount = 0;

  while (!imgSrc && Date.now() < deadline) {
    pollCount++;

    // Pass 1: known URL patterns scoped to assistant bubble (fast)
    for (const sel of knownImageSelectors) {
      try {
        const imgs = page.locator(sel);
        const n = await imgs.count();
        if (n > 0) {
          const src = await imgs.nth(n - 1).getAttribute('src');
          if (src && src.startsWith('http') && !preExistingImgSrcs.has(src)) {
            imgSrc = src;
            console.log(`[generate] Image found via known selector (${sel})`);
            break;
          }
        }
      } catch { /* selector not yet present */ }
    }

    // Pass 2: all images NOT inside a user bubble — survives DOM structure changes
    if (!imgSrc) {
      const allNewSrcs = await page.$$eval('img[src]', (imgs, preExisting) => {
        return imgs
          .filter(img => {
            if (!img.src.startsWith('http') || img.src.length < 60) return false;
            // Skip images inside user message bubbles (uploaded reference lives there)
            if (img.closest('[data-message-author-role="user"]')) return false;
            return !preExisting.includes(img.src);
          })
          .map(img => img.src);
      }, [...preExistingImgSrcs]);

      if (allNewSrcs.length > 0) {
        // Prefer URLs that look like generated image content
        const preferred = allNewSrcs.find(s =>
          s.includes('oaiusercontent') || s.includes('oaidalle') ||
          s.includes('files.openai') || s.includes('estuary') || s.includes('backend-api')
        );
        imgSrc = preferred ?? allNewSrcs[allNewSrcs.length - 1];
        console.log(`[generate] New image found via broad scan (${allNewSrcs.length} candidates)`);
      }
    }

    if (!imgSrc) {
      if (pollCount % 5 === 0) {
        const remaining = Math.round((deadline - Date.now()) / 1000);
        // Log what's currently visible to aid diagnosis
        const counts = await page.$$eval('img[src]', imgs => ({
          total: imgs.length,
          inUser: imgs.filter(i => i.closest('[data-message-author-role="user"]')).length,
          inAssistant: imgs.filter(i => i.closest('[data-message-author-role="assistant"]')).length,
        })).catch(() => ({ total: '?', inUser: '?', inAssistant: '?' }));
        console.log(`[generate] Still waiting... ${remaining}s remaining | imgs total=${counts.total} user=${counts.inUser} assistant=${counts.inAssistant}`);
      }
      await page.waitForTimeout(2000);
    }
  }

  console.log(`[generate] Image URL: ${imgSrc?.slice(0, 100)}...`);

  if (!imgSrc) {
    // Take a screenshot to help debug what the page looks like
    const dbgPath = output.replace(/\.[^.]+$/, '') + '-debug.png';
    await page.screenshot({ path: dbgPath, fullPage: true }).catch(() => {});
    console.error(`[generate] Debug screenshot: ${dbgPath}`);
    throw new Error(`Timed out waiting for generated image after ${timeoutMs / 1000} s`);
  }

  // ── Download image ──────────────────────────────────────────────────────────

  console.log('[generate] Downloading image bytes...');
  let buffer;
  if (imgSrc.startsWith('blob:')) {
    // Blob URLs must be read from within the page context
    buffer = Buffer.from(await page.evaluate(async (blobUrl) => {
      const resp = await fetch(blobUrl);
      const arr = new Uint8Array(await resp.arrayBuffer());
      return Array.from(arr);
    }, imgSrc));
  } else {
    const resp = await context.request.get(imgSrc, { timeout: 30000 });
    if (!resp.ok()) throw new Error(`Image download failed: HTTP ${resp.status()}`);
    buffer = await resp.body();
  }

  if (!buffer || buffer.length < 100) {
    throw new Error(`Downloaded image is empty (${buffer?.length ?? 0} bytes)`);
  }

  mkdirSync(dirname(output), { recursive: true });
  writeFileSync(output, buffer);
  console.log(`[generate] Saved ${Math.round(buffer.length / 1024)} KB → ${output}`);

  // Save the current conversation URL so the next run can resume context
  const finalUrl = page.url();
  if (conversationOut && finalUrl.includes('chatgpt.com')) {
    writeFileSync(conversationOut, finalUrl, 'utf8');
    console.log(`[generate] Conversation URL saved → ${finalUrl}`);
  }

  await context.close();
  process.exit(0);

} catch (err) {
  console.error(`[generate] ERROR: ${err.message}`);
  if (!headless) {
    console.error('[generate] Browser will close in 15 s...');
    await new Promise(r => setTimeout(r, 15000));
  }
  await context.close().catch(() => {});
  process.exit(1);
}
