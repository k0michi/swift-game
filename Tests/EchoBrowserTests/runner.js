// Runs EchoBrowserTests in headless Chromium for scripts/emscripten/test-browser.sh.
//
// Usage: node runner.js <directory with EchoBrowserTests.html>
//
// The page prints its results to the console and ends with "All tests passed"
// or "<n> test(s) failed". Audio is muted, and audio contexts may start
// without a user gesture.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';
import { chromium } from 'playwright';

const root = process.argv[2];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = createServer(async (request, response) => {
  try {
    const path = join(root, new URL(request.url, 'http://localhost').pathname);
    const body = await readFile(path);
    response.writeHead(200, { 'Content-Type': types[extname(path)] ?? 'application/octet-stream' });
    response.end(body);
  } catch {
    response.writeHead(404);
    response.end();
  }
});
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));

const browser = await chromium.launch({
  args: ['--mute-audio', '--autoplay-policy=no-user-gesture-required'],
});
const page = await browser.newPage();
let result = '';
let pageFailed = false;
const finished = new Promise((resolve) => {
  page.on('console', (message) => {
    const line = message.text();
    console.log(line);
    if (line === 'All tests passed' || / test\(s\) failed$/.test(line)) {
      result = line;
      resolve();
    }
  });
  page.on('pageerror', (error) => {
    console.log(`FAIL page error: ${error.message}`);
    pageFailed = true;
    resolve();
  });
});
const timeout = new Promise((resolve) => setTimeout(() => {
  console.log('FAIL timed out');
  resolve();
}, 30_000));

await page.goto(`http://127.0.0.1:${server.address().port}/EchoBrowserTests.html`);
await Promise.race([finished, timeout]);
await browser.close();
server.close();
process.exit(result === 'All tests passed' && !pageFailed ? 0 : 1);
