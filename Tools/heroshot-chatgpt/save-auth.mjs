/**
 * AltTracker HeroShot – One-time Chrome profile setup
 *
 * Creates a dedicated Chrome profile that stores your ChatGPT session.
 * Playwright reuses this profile on every generate run, so you only log in once.
 *
 * Usage:
 *   node save-auth.mjs --profile-path "C:\Temp\AltTrackerHeroShot\chrome-profile"
 *
 * What happens:
 *   1. Real Chrome opens with a fresh dedicated profile (no conflict with your main Chrome).
 *   2. Navigate to chatgpt.com. If Cloudflare shows a checkbox — click it.
 *   3. Log in to ChatGPT normally.
 *   4. Press Enter in this terminal once you see the chat interface.
 *   5. Profile is saved. Future generate runs reuse it without re-login.
 *
 * Requirements:
 *   - Google Chrome must be installed.
 */

import { chromium } from 'playwright';
import { createInterface } from 'readline';
import { parseArgs } from 'util';
import { mkdirSync } from 'fs';

const { values } = parseArgs({
  options: {
    'profile-path': { type: 'string', default: '' },
    // Legacy alias kept for backward compat
    'auth-state':   { type: 'string', default: '' },
  },
  strict: false,
});

const profilePath = values['profile-path'] || values['auth-state'] || 'C:\\Temp\\AltTrackerHeroShot\\chrome-profile';
mkdirSync(profilePath, { recursive: true });
console.log(`[save-auth] Chrome profile directory: ${profilePath}`);
console.log('[save-auth] Opening dedicated Chrome instance...');
console.log('[save-auth] NOTE: This is NOT your main Chrome — it uses its own profile folder.');

// launchPersistentContext opens Chrome with the given profile directory.
// Using channel:'chrome' means the real Chrome binary — legitimate fingerprints,
// no automation watermarks in the TLS handshake or JS environment.
let context;
try {
  context = await chromium.launchPersistentContext(profilePath, {
    channel: 'chrome',
    headless: false,
    slowMo: 50,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-first-run',
      '--no-default-browser-check',
    ],
    ignoreDefaultArgs: ['--enable-automation'],
  });
  console.log('[save-auth] Using real Chrome.');
} catch {
  console.warn('[save-auth] Chrome not found, falling back to Playwright Chromium.');
  context = await chromium.launchPersistentContext(profilePath, {
    headless: false,
    slowMo: 50,
    args: ['--disable-blink-features=AutomationControlled'],
    ignoreDefaultArgs: ['--enable-automation'],
  });
}

// Patch automation fingerprints
await context.addInitScript(() => {
  Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
  if (!window.chrome) window.chrome = { runtime: {} };
  Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
});

const page = await context.newPage();

console.log('[save-auth] Navigating to chatgpt.com...');
await page.goto('https://chatgpt.com/', { waitUntil: 'domcontentloaded', timeout: 30000 });

const rl = createInterface({ input: process.stdin, output: process.stdout });
await new Promise(resolve => {
  rl.question(
    '\n👉 Log in to ChatGPT in the Chrome window.\n' +
    '   If you see a "Verify you are human" checkbox — click it.\n' +
    '   Press Enter here once you see the chat interface.\n\n',
    resolve,
  );
});
rl.close();

// Verify we're actually on the chat page before saving
const url = page.url();
if (!url.includes('chatgpt.com') || url.includes('/auth/error')) {
  console.warn(`[save-auth] WARNING: Current URL looks unexpected: ${url}`);
  console.warn('[save-auth] Saving profile anyway. Re-run if generation fails.');
}

// Close the context — this flushes the profile to disk.
await context.close();
console.log(`\n✅ Profile saved to: ${profilePath}`);
console.log('[save-auth] Future generate runs will reuse this session automatically.');
process.exit(0);
