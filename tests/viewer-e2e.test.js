'use strict';
// End-to-end tests: drive the real viewer page in headless Chrome/Chromium/Edge
// through the DevTools protocol. Node built-ins only (WebSocket, fetch, zlib).
// Skipped when no browser is found. Set CHROME_BIN to choose one.

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');
const { checkerPng } = require('./lib/png.js');

const ROOT = path.resolve(__dirname, '..');
const VIEWER = path.join(ROOT, 'viewer', 'viewer.html');
// Fixtures live in the repo (not /tmp, not a hidden dir) so snap browsers can read them.
const OUT = path.join(ROOT, 'tests', 'out', 'e2e');

function findChrome() {
  if (process.env.CHROME_BIN) return process.env.CHROME_BIN;
  const candidates = [
    'google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser', 'microsoft-edge',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
  ];
  for (const c of candidates) {
    if (path.isAbsolute(c)) { if (fs.existsSync(c)) return c; continue; }
    try { return execFileSync('sh', ['-c', `command -v ${c}`], { encoding: 'utf8' }).trim(); }
    catch (e) { /* not found */ }
  }
  return null;
}

// Same encoding as the launchers: file URL of the viewer + ?src=<encoded absolute path>.
const viewerUrl = (img) =>
  'file://' + VIEWER.split(path.sep).map(encodeURIComponent).join('/').replace(/^\/?/, '/') +
  (img === undefined ? '' : '?src=' + encodeURIComponent(img));

class Cdp {
  constructor(wsUrl) {
    this.ws = new WebSocket(wsUrl);
    this.seq = 0;
    this.pending = new Map();
    this.ws.onmessage = (ev) => {
      const msg = JSON.parse(ev.data);
      const p = msg.id && this.pending.get(msg.id);
      if (!p) return;
      this.pending.delete(msg.id);
      msg.error ? p.reject(new Error(msg.error.message)) : p.resolve(msg.result);
    };
  }
  open() {
    return new Promise((resolve, reject) => { this.ws.onopen = resolve; this.ws.onerror = reject; });
  }
  send(method, params = {}) {
    const id = ++this.seq;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }
  async eval(expr) {
    const r = await this.send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' in: ' + expr);
    return r.result.value;
  }
  close() { this.ws.close(); }
}

const chromeBin = findChrome();
const W = 1000, H = 700, TB = 40, FW = W, FH = H - TB;    // viewport, toolbar, frame

test('viewer in a real browser', { skip: chromeBin ? false : 'no Chrome/Chromium/Edge found' }, async (t) => {
  fs.mkdirSync(OUT, { recursive: true });
  const img = path.join(OUT, 'landscape 400x200.png');
  fs.writeFileSync(img, checkerPng(400, 200));
  const oddName = path.join(OUT, 'Фото #1 a+b 50%.png');
  fs.writeFileSync(oddName, checkerPng(30, 60));
  fs.writeFileSync(path.join(OUT, 'no-size.svg'),
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"><rect width="40" height="20" fill="teal"/></svg>');

  // Chrome puts a Unix socket in TMPDIR; a long TMPDIR makes it fail
  // ("Socket path too long"), so fall back to /tmp then.
  let tmp = os.tmpdir();
  if (process.platform !== 'win32' && tmp.length > 60 && fs.existsSync('/tmp')) tmp = '/tmp';
  const profile = fs.mkdtempSync(path.join(tmp, 'iv-e2e-'));
  const proc = spawn(chromeBin, [
    '--headless=new', '--remote-debugging-port=0', `--user-data-dir=${profile}`,
    '--no-first-run', '--no-default-browser-check', '--disable-gpu', `--window-size=${W},${H}`,
    'about:blank'
  ], { stdio: ['ignore', 'ignore', 'pipe'], env: { ...process.env, TMPDIR: tmp } });

  let cdp;
  try {
    const wsBrowser = await new Promise((resolve, reject) => {
      let buf = '';
      const timer = setTimeout(() => reject(new Error('browser did not start: ' + buf)), 20000);
      proc.stderr.on('data', (d) => {
        buf += d;
        const m = /DevTools listening on (ws:\/\/\S+)/.exec(buf);
        if (m) { clearTimeout(timer); resolve(m[1]); }
      });
      proc.on('exit', (code) => reject(new Error('browser exited: ' + code + ' ' + buf)));
    });
    const port = new URL(wsBrowser).port;
    const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    cdp = new Cdp(targets.find((x) => x.type === 'page').webSocketDebuggerUrl);
    await cdp.open();
    await cdp.send('Page.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });

    const frames = () => cdp.eval('new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))');
    async function load(url) {
      await cdp.send('Page.navigate', { url });
      for (let i = 0; i < 200; i++) {
        const ready = await cdp.eval(`document.readyState === 'complete' &&
          (!document.getElementById('image').hidden || !document.getElementById('message').hidden)`);
        if (ready) { await frames(); return; }
        await new Promise((r) => setTimeout(r, 25));
      }
      throw new Error('page did not finish loading: ' + url);
    }
    const state = () => cdp.eval(`(() => {
      const t = document.getElementById('image').style.transform;
      const m = /translate\\(([-\\d.e]+)px,\\s*([-\\d.e]+)px\\)\\s*scale\\(([-\\d.e]+)\\)/.exec(t) || [];
      const $ = (id) => document.getElementById(id);
      return { x: +m[1], y: +m[2], s: +m[3], zoom: $('info-zoom').textContent,
               name: $('info-name').textContent, dims: $('info-dims').textContent,
               fit: $('btn-fit').getAttribute('aria-pressed') === 'true',
               actual: $('btn-actual').getAttribute('aria-pressed') === 'true',
               message: $('message').hidden ? '' : $('message').textContent,
               title: document.title };
    })()`);
    async function key(k, { code = k, vk = 0, shift = false, ctrl = false } = {}) {
      const modifiers = (shift ? 8 : 0) | (ctrl ? 2 : 0);
      const printable = k.length === 1;
      await cdp.send('Input.dispatchKeyEvent', {
        type: printable ? 'keyDown' : 'rawKeyDown', key: k, code, windowsVirtualKeyCode: vk,
        text: printable && !ctrl ? k : undefined, modifiers });
      await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: k, code, windowsVirtualKeyCode: vk, modifiers });
      await frames();
    }
    async function mouse(type, x, y, button = 'none', buttons = 0) {
      await cdp.send('Input.dispatchMouseEvent', { type, x, y, button, buttons, clickCount: type === 'mouseMoved' ? 0 : 1 });
    }
    const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 0.01, `${msg}: ${a} != ${b}`);

    await load(viewerUrl(img));

    await t.test('small image opens fitted (upscaled) and centered', async () => {
      const s = await state();
      near(s.s, 2.5, 'scale'); near(s.x, 0, 'x'); near(s.y, (FH - 500) / 2, 'y');
      assert.equal(s.zoom, '250%');
      assert.equal(s.fit, true);
      assert.equal(s.dims, '400 × 200');
      assert.equal(s.title, 'landscape 400x200.png');
    });

    await t.test("'1' zooms to 100% centered", async () => {
      await key('1', { code: 'Digit1', vk: 49 });
      const s = await state();
      near(s.s, 1, 'scale'); near(s.x, 300, 'x'); near(s.y, (FH - 200) / 2, 'y');
      assert.equal(s.actual, true); assert.equal(s.fit, false);
    });

    await t.test("'+' and '-' zoom around the frame center", async () => {
      await key('+', { code: 'Equal', vk: 187 });
      let s = await state();
      near(s.s, 1.25, 'scale'); near(s.x, 500 - 200 * 1.25, 'x');
      await key('-', { code: 'Minus', vk: 189 });
      s = await state();
      near(s.s, 1, 'scale'); near(s.x, 300, 'x');
    });

    await t.test('Ctrl+key is left to the browser', async () => {
      await key('+', { code: 'Equal', vk: 187, ctrl: true });
      near((await state()).s, 1, 'scale');
    });

    await t.test("'a' fits again", async () => {
      await key('a', { code: 'KeyA', vk: 65 });
      const s = await state();
      near(s.s, 2.5, 'scale'); assert.equal(s.fit, true);
    });

    await t.test('wheel zooms at the cursor', async () => {
      const before = await state();
      const cx = 100, cy = 140;                            // frame coordinates
      await cdp.send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: cx, y: cy + TB, deltaX: 0, deltaY: -100 });
      await frames();
      const s = await state();
      assert.ok(s.s > before.s, 'zoomed in');
      near((cx - s.x) / s.s, (cx - before.x) / before.s, 'image x under cursor');
      near((cy - s.y) / s.s, (cy - before.y) / before.s, 'image y under cursor');
      assert.equal(s.fit, false);
    });

    await t.test('left drag pans, without limits', async () => {
      const b = await state();
      await mouse('mousePressed', 500, 400, 'left', 1);
      await mouse('mouseMoved', 600, 450, 'left', 1);
      await mouse('mouseMoved', -4000, 450, 'left', 1);
      await mouse('mouseReleased', -4000, 450, 'left', 0);
      await frames();
      const s = await state();
      near(s.x, b.x - 4500, 'x'); near(s.y, b.y + 50, 'y');
    });

    await t.test('arrow keys pan (Shift = bigger step)', async () => {
      const b = await state();
      await key('ArrowRight', { vk: 39 });
      let s = await state();
      near(s.x, b.x - FW * 0.1, 'x');
      await key('ArrowDown', { vk: 40, shift: true });
      s = await state();
      near(s.y, b.y - FH * 0.4, 'y');
    });

    await t.test('middle click fits', async () => {
      await mouse('mousePressed', 300, 300, 'middle', 4);
      await mouse('mouseReleased', 300, 300, 'middle', 0);
      await frames();
      const s = await state();
      near(s.s, 2.5, 'scale'); near(s.x, 0, 'x'); assert.equal(s.fit, true);
    });

    await t.test('toolbar buttons work', async () => {
      const click = async (id) => {
        const r = await cdp.eval(`(() => { const b = document.getElementById('${id}').getBoundingClientRect();
          return [b.x + b.width / 2, b.y + b.height / 2]; })()`);
        await mouse('mousePressed', r[0], r[1], 'left', 1);
        await mouse('mouseReleased', r[0], r[1], 'left', 0);
        await frames();
      };
      await click('btn-actual');  near((await state()).s, 1, '1:1');
      await click('btn-zoom-in'); near((await state()).s, 1.25, 'zoom in');
      await click('btn-zoom-out'); near((await state()).s, 1, 'zoom out');
      await click('btn-fit');     near((await state()).s, 2.5, 'fit');
    });

    await t.test('resize re-fits while in fit mode', async () => {
      await cdp.send('Emulation.setDeviceMetricsOverride', { width: 800, height: 600, deviceScaleFactor: 1, mobile: false });
      await frames(); await frames();
      near((await state()).s, Math.min(800 / 400, (600 - TB) / 200), 'scale');
      await cdp.send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
      await frames(); await frames();
    });

    await t.test('file name with Cyrillic, #, + and % loads', async () => {
      await load(viewerUrl(oddName));
      const s = await state();
      assert.equal(s.message, '');
      assert.equal(s.name, 'Фото #1 a+b 50%.png');
      assert.equal(s.dims, '30 × 60');
    });

    await t.test('SVG without intrinsic size loads', async () => {
      await load(viewerUrl(path.join(OUT, 'no-size.svg')));
      const s = await state();
      assert.equal(s.message, '');
      assert.ok(s.s > 0);
    });

    await t.test('window.SRC fallback page works', async () => {
      const page = path.join(OUT, 'redirect.html');
      const base = 'file://' + path.dirname(VIEWER).split(path.sep).map(encodeURIComponent).join('/') + '/';
      fs.writeFileSync(page, fs.readFileSync(VIEWER, 'utf8').replace('<head>',
        `<head><base href="${base}"><script>window.SRC=${JSON.stringify('file://' + img.split(path.sep).map(encodeURIComponent).join('/'))};</script>`));
      await load('file://' + page.split(path.sep).map(encodeURIComponent).join('/'));
      const s = await state();
      assert.equal(s.dims, '400 × 200');
    });

    await t.test('missing file shows an error', async () => {
      await load(viewerUrl(path.join(OUT, 'does-not-exist.png')));
      assert.match((await state()).message, /Cannot load image/);
    });

    await t.test('no src shows help', async () => {
      await load(viewerUrl());
      assert.match((await state()).message, /No image/);
    });
  } finally {
    if (cdp) cdp.close();
    proc.kill();
    await new Promise((r) => proc.once('exit', r).once('error', r) && setTimeout(r, 2000));
    fs.rmSync(profile, { recursive: true, force: true });
  }
});
