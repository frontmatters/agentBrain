// Headless render check for a decision page. Usage:
//   node check.mjs <page.html> [--out <dir>]
// Prints radios per decision, fails (exit 1) on horizontal scroll or clipped
// card/table text, and writes a screenshot per h2 into --out (default: next
// to the page under .check/). Playwright is resolved from PLAYWRIGHT_DIR or
// from the current directory's node_modules.
import { resolve, dirname, join } from 'node:path';
import { mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';

const args = process.argv.slice(2);
const page = args.find((a) => !a.startsWith('--'));
if (!page) { console.error('usage: node check.mjs <page.html> [--out <dir>]'); process.exit(2); }
const outIdx = args.indexOf('--out');
const out = outIdx >= 0 ? args[outIdx + 1] : join(dirname(resolve(page)), '.check');
mkdirSync(out, { recursive: true });

const require = createRequire(join(process.cwd(), 'package.json'));
const pwDir = process.env.PLAYWRIGHT_DIR ?? dirname(require.resolve('playwright/package.json'));
const { chromium } = await import(join(pwDir, 'index.mjs'));

const browser = await chromium.launch();
const p = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await p.goto('file://' + resolve(page)); await p.waitForTimeout(300);
const info = await p.evaluate(() => {
  const per = [...document.querySelectorAll('.choice')].map((k) => k.dataset.decision + ': ' + k.querySelectorAll('input[type=radio]').length);
  const wide = document.documentElement.scrollWidth > document.documentElement.clientWidth;
  const clipped = [...document.querySelectorAll('.option, .compare td, .compare th')].filter((e) => e.scrollWidth > e.clientWidth + 1).length;
  return { per, options: document.querySelectorAll('.option').length, tables: document.querySelectorAll('.compare').length, wide, clipped, height: document.documentElement.scrollHeight };
});
console.log(JSON.stringify(info, null, 1));
const heads = await p.locator('h2').all();
for (const [i, h] of heads.entries()) { await h.scrollIntoViewIfNeeded(); await p.screenshot({ path: join(out, `section-${i + 1}.png`) }); }
await p.screenshot({ path: join(out, 'page.png'), fullPage: true });
await browser.close();
if (info.wide || info.clipped) { console.error('FAIL: horizontal scroll or clipped text'); process.exit(1); }
