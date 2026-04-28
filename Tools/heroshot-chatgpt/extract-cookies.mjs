/**
 * AltTracker HeroShot – Extract ChatGPT session from your running Chrome
 *
 * Reads Chrome's cookie SQLite database directly (no browser launch needed).
 * Decrypts cookies using Windows DPAPI via PowerShell.
 * Outputs a Playwright-compatible storage state JSON.
 *
 * Usage:
 *   node extract-cookies.mjs --auth-state "C:\Temp\AltTrackerHeroShot\chatgpt-auth.json"
 *
 * Chrome does NOT need to be closed. The script copies the DB before reading it.
 * Supports both Chrome and Edge. Chrome is tried first.
 */

import { execSync } from 'child_process';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { createDecipheriv } from 'crypto';
import { parseArgs } from 'util';
import Database from 'node-sqlite3-wasm';

const { values } = parseArgs({
  options: {
    'auth-state': { type: 'string', default: 'chatgpt-auth.json' },
    browser:      { type: 'string', default: 'auto' }, // auto | chrome | edge
  },
  strict: false,
});

const authStatePath = values['auth-state'];
const browserPref   = values.browser.toLowerCase();
const tmpDir        = join(process.env.TEMP ?? 'C:\\Temp', 'alttracker-cookie-extract');
mkdirSync(tmpDir, { recursive: true });
mkdirSync(dirname(authStatePath), { recursive: true });

// ── Browser profile paths ──────────────────────────────────────────────────
const localAppData = process.env.LOCALAPPDATA ?? '';

const BROWSERS = [
  {
    name: 'Chrome',
    userDataDir: join(localAppData, 'Google', 'Chrome', 'User Data'),
  },
  {
    name: 'Edge',
    userDataDir: join(localAppData, 'Microsoft', 'Edge', 'User Data'),
  },
];

function findBrowser() {
  const candidates = browserPref === 'auto'
    ? BROWSERS
    : BROWSERS.filter(b => b.name.toLowerCase() === browserPref);
  for (const b of candidates) {
    const lsPath = join(b.userDataDir, 'Local State');
    if (existsSync(lsPath)) {
      console.log(`[extract-cookies] Using ${b.name} profile: ${b.userDataDir}`);
      return b;
    }
  }
  throw new Error('No Chrome or Edge installation found. Use --browser chrome|edge to specify.');
}

const browser = findBrowser();
const userDataDir  = browser.userDataDir;
const localStatePath = join(userDataDir, 'Local State');

// Chrome stores cookies in Network\Cookies (Chrome 96+) or Cookies directly
const cookiesCandidates = [
  join(userDataDir, 'Default', 'Network', 'Cookies'),
  join(userDataDir, 'Default', 'Cookies'),
];
const cookiesDbPath = cookiesCandidates.find(existsSync);
if (!cookiesDbPath) {
  throw new Error(`Cookies database not found under ${userDataDir}`);
}

// ── Decrypt the Chrome AES master key via DPAPI ───────────────────────────
console.log('[extract-cookies] Reading Chrome master key from Local State...');
const localState = JSON.parse(readFileSync(localStatePath, 'utf8'));
const encryptedKeyB64 = localState?.os_crypt?.encrypted_key;
if (!encryptedKeyB64) throw new Error('os_crypt.encrypted_key not found in Local State');

// Encoded as base64 of "DPAPI" (5 bytes) + DPAPI-encrypted AES key
const encryptedKeyFull = Buffer.from(encryptedKeyB64, 'base64');
if (encryptedKeyFull.slice(0, 5).toString('ascii') !== 'DPAPI') {
  throw new Error('Unexpected encrypted_key format (missing DPAPI prefix)');
}
const dpApiBytes = encryptedKeyFull.slice(5);

console.log('[extract-cookies] Decrypting master key with DPAPI via PowerShell...');
const dpApiB64 = dpApiBytes.toString('base64');
const psCommand = [
  `Add-Type -AssemblyName System.Security;`,
  `$k=[Convert]::FromBase64String('${dpApiB64}');`,
  `$d=[System.Security.Cryptography.ProtectedData]::Unprotect($k,$null,'CurrentUser');`,
  `Write-Output ([Convert]::ToBase64String($d))`,
].join('');

const aesKeyB64 = execSync(`powershell -NoProfile -Command "${psCommand}"`, { encoding: 'utf8' }).trim();
const aesKey = Buffer.from(aesKeyB64, 'base64');
console.log(`[extract-cookies] Master key decrypted (${aesKey.length} bytes).`);

// ── Copy cookies DB + WAL files (Chrome holds an exclusive lock) ──────────
// Chrome uses WAL mode: actual data lives in Cookies-wal, not the main file.
// We must copy all three WAL companions so better-sqlite3 sees the full DB.
const tmpCookiesPath = join(tmpDir, 'Cookies_copy');
console.log(`[extract-cookies] Copying cookies DB + WAL: ${cookiesDbPath}`);

function copyLocked(src, dst) {
  if (!existsSync(src)) return;
  const ps = [
    `$s=[System.IO.File]::Open('${src.replace(/'/g, "''")}',`,
    `[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite);`,
    `$d=[System.IO.File]::Create('${dst.replace(/'/g, "''")}');`,
    `$s.CopyTo($d);$s.Close();$d.Close()`,
  ].join('');
  execSync(`powershell -NoProfile -Command "${ps}"`);
}

copyLocked(cookiesDbPath,           tmpCookiesPath);
copyLocked(cookiesDbPath + '-wal',  tmpCookiesPath + '-wal');
copyLocked(cookiesDbPath + '-shm',  tmpCookiesPath + '-shm');

// ── Read cookies with node-sqlite3-wasm (real fs, handles WAL automatically) ─
const db = new Database(tmpCookiesPath);
const rows = db.prepare(`
  SELECT host_key, name, path, value, encrypted_value,
         expires_utc, is_secure, is_httponly, samesite
  FROM   cookies
  WHERE  host_key LIKE '%openai.com%'
      OR host_key LIKE '%chatgpt.com%'
  ORDER BY host_key, name
`).all();
db.close();

// ── Decrypt individual cookie values ─────────────────────────────────────
function decryptCookieValue(encBuf) {
  // Chrome 80+ format: b"v10" + 12-byte IV + ciphertext + 16-byte GCM tag
  if (!encBuf || encBuf.length < 31) return null;
  const prefix = encBuf.slice(0, 3).toString('ascii');
  if (prefix !== 'v10' && prefix !== 'v11') return null;

  const iv         = encBuf.slice(3, 15);
  const ciphertext = encBuf.slice(15, encBuf.length - 16);
  const authTag    = encBuf.slice(encBuf.length - 16);

  const decipher = createDecipheriv('aes-256-gcm', aesKey, iv);
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(ciphertext), decipher.final()]).toString('utf8');
}

// Chrome epoch: microseconds since 1601-01-01; convert to Unix seconds
function chromeTimeToUnix(t) {
  if (!t || t === 0) return -1;
  return Math.floor((Number(t) - 11_644_473_600_000_000) / 1_000_000);
}

const sameSiteMap = { 0: 'None', 1: 'Lax', 2: 'Strict' };

const cookies = [];
for (const r of rows) {
  let cookieValue = r.value ?? '';

  if (!cookieValue && r.encrypted_value) {
    // node-sqlite3-wasm returns BLOBs as Uint8Array
    const encBuf = r.encrypted_value instanceof Uint8Array
      ? Buffer.from(r.encrypted_value)
      : Buffer.isBuffer(r.encrypted_value)
        ? r.encrypted_value
        : Buffer.from(r.encrypted_value);
    try {
      cookieValue = decryptCookieValue(encBuf) ?? '';
    } catch (e) {
      console.warn(`[extract-cookies] Could not decrypt ${r.name} on ${r.host_key}: ${e.message}`);
      continue;
    }
  }

  if (!cookieValue) continue;

  cookies.push({
    name:     r.name,
    value:    cookieValue,
    domain:   r.host_key,
    path:     r.path ?? '/',
    expires:  chromeTimeToUnix(r.expires_utc),
    httpOnly: r.is_httponly === 1,
    secure:   r.is_secure === 1,
    sameSite: sameSiteMap[r.samesite] ?? 'None',
  });
}

console.log(`[extract-cookies] Extracted ${cookies.length} cookies for openai.com / chatgpt.com`);
if (cookies.length === 0) {
  console.error('[extract-cookies] ERROR: No cookies found. Make sure you are logged into ChatGPT in Chrome.');
  process.exit(1);
}

// Print key cookies for confirmation (values truncated)
for (const c of cookies) {
  if (['__Secure-next-auth.session-token', '__cf_bm', 'cf_clearance', 'oai-did'].includes(c.name)) {
    console.log(`  ✓ ${c.name} on ${c.domain} = ${c.value.slice(0, 20)}...`);
  }
}

const storageState = { cookies, origins: [] };
writeFileSync(authStatePath, JSON.stringify(storageState, null, 2), 'utf8');
console.log(`[extract-cookies] Saved to: ${authStatePath}`);
