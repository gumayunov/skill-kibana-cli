#!/usr/bin/env node
// Browser-based SSO login for cookie auth mode (KIBANACLI_AUTH=cookie).
//
// Opens a real (headed) Chromium window on KIBANACLI_HOST, lets the user pass
// whatever SSO flow guards the instance (oauth2-proxy, ADFS, SAML, ...), then
// captures the resulting cookies and saves them as a ready-to-use Cookie
// header value. Validation criterion: GET /api/status with the captured
// cookies returns 200.
//
// The browser profile is persistent (~/.config/kibana-cli/browser-profile,
// shared across projects), so subsequent runs usually re-authenticate
// silently — the window flashes and closes without any interaction.
//
// Env file resolution mirrors kibana-cli: $KIBANACLI_ENV, then .kibana-cli/env
// upwards from cwd (per-project config), then ~/.config/kibana-cli/env.
//   KIBANACLI_HOST (required)
//   KIBANACLI_COOKIE_FILE   where to save the header (default: <env dir>/cookie)

import { chromium } from 'playwright';
import { readFileSync, writeFileSync, chmodSync, mkdirSync, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join, dirname } from 'node:path';

const CONFIG_DIR = join(homedir(), '.config', 'kibana-cli');
const TIMEOUT_MS = 5 * 60 * 1000;

function findEnvFile() {
  if (process.env.KIBANACLI_ENV) return process.env.KIBANACLI_ENV;
  let dir = process.cwd();
  while (dir !== dirname(dir)) {
    const candidate = join(dir, '.kibana-cli', 'env');
    if (existsSync(candidate)) return candidate;
    dir = dirname(dir);
  }
  return join(CONFIG_DIR, 'env');
}

const ENV_FILE = findEnvFile();

function loadEnvFile(path) {
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch {
    return {};
  }
  const vars = {};
  for (const line of text.split('\n')) {
    const m = line.match(/^(?:export\s+)?([A-Z_][A-Z0-9_]*)=(.*)$/);
    if (m) vars[m[1]] = m[2].replace(/^(["'])(.*)\1$/, '$2');
  }
  return vars;
}

const fileEnv = loadEnvFile(ENV_FILE);
const HOST = (process.env.KIBANACLI_HOST ?? fileEnv.KIBANACLI_HOST ?? '').replace(/\/$/, '');
const COOKIE_FILE =
  process.env.KIBANACLI_COOKIE_FILE ?? fileEnv.KIBANACLI_COOKIE_FILE ?? join(dirname(ENV_FILE), 'cookie');

if (!HOST) {
  console.error(`browser-login: KIBANACLI_HOST is not set (checked env and ${ENV_FILE})`);
  process.exit(1);
}

mkdirSync(dirname(COOKIE_FILE), { recursive: true });

const ctx = await chromium.launchPersistentContext(join(CONFIG_DIR, 'browser-profile'), {
  headless: false,
  viewport: null,
});

const page = ctx.pages()[0] ?? (await ctx.newPage());
await page.goto(HOST + '/', { waitUntil: 'domcontentloaded' });

console.error(`browser-login: log in to ${HOST} in the browser window (if not signed in automatically)...`);

const deadline = Date.now() + TIMEOUT_MS;
let cookieHeader = null;

while (Date.now() < deadline) {
  const cookies = await ctx.cookies(HOST);
  if (cookies.length > 0) {
    const header = cookies.map((c) => `${c.name}=${c.value}`).join('; ');
    const resp = await ctx.request.get(HOST + '/api/status', {
      headers: { Cookie: header },
      maxRedirects: 0,
      failOnStatusCode: false,
    });
    if (resp.status() === 200) {
      cookieHeader = header;
      break;
    }
  }
  await new Promise((r) => setTimeout(r, 1000));
}

await ctx.close();

if (!cookieHeader) {
  console.error('browser-login: no working session after 5 minutes — run again and complete the login.');
  process.exit(1);
}

writeFileSync(COOKIE_FILE, cookieHeader + '\n');
chmodSync(COOKIE_FILE, 0o600);
console.error(`browser-login: cookie saved to ${COOKIE_FILE}`);
