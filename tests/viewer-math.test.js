'use strict';
// Unit tests for the pure view math in viewer/viewer.js.  Run: node --test tests/

const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('../viewer/viewer.js');

const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} != ${b}`);

test('fit: large image is scaled down and centered', () => {
  const v = M.fitView(4000, 2000, 1000, 800);
  assert.deepEqual(v, { scale: 0.25, x: 0, y: 150 });
});

test('fit: small image is scaled UP to fill the window', () => {
  const v = M.fitView(100, 50, 1000, 800);
  assert.equal(v.scale, 10);
  assert.equal(v.x, 0);
  assert.equal(v.y, 150);
});

test('fit: degenerate sizes give scale 1', () => {
  assert.equal(M.fitScale(0, 0, 1000, 800), 1);
  assert.equal(M.fitScale(100, 100, 0, 0), 1);
});

test('zoom 100% from fit keeps the image centered', () => {
  const fit = M.fitView(4000, 2000, 1000, 800);
  const v = M.zoomTo(fit, 1, 500, 400, 4000, 2000, 1000, 800);
  assert.deepEqual(v, { scale: 1, x: -1500, y: -600 });
});

test('zoom keeps the image point under the cursor fixed', () => {
  const v0 = { scale: 0.8, x: 37, y: -12 };
  const cx = 123, cy = 456;
  const before = [(cx - v0.x) / v0.scale, (cy - v0.y) / v0.scale];
  const v1 = M.zoomBy(v0, 1.7, cx, cy, 4000, 2000, 1000, 800);
  near((cx - v1.x) / v1.scale, before[0]);
  near((cy - v1.y) / v1.scale, before[1]);
});

test('zoom does not re-clamp position (image may stay off-center)', () => {
  const v = M.zoomBy({ scale: 1, x: 900, y: 700 }, 2, 0, 0, 100, 100, 1000, 800);
  assert.deepEqual(v, { scale: 2, x: 1800, y: 1400 });
});

test('scale limits always include fit and 100%', () => {
  const huge = M.scaleLimits(100000, 100000, 1000, 800);       // fit = 0.008
  assert.ok(huge.min <= 0.008 && huge.max >= 1);
  const tiny = M.scaleLimits(2, 2, 1000, 800);                  // fit = 400
  assert.ok(tiny.min <= 1 && tiny.max >= 400);
});

test('zoom is clamped to the limits', () => {
  const v = M.zoomTo({ scale: 1, x: 0, y: 0 }, 1e6, 0, 0, 100, 100, 1000, 800);
  assert.equal(v.scale, M.scaleLimits(100, 100, 1000, 800).max);
  const w = M.zoomTo({ scale: 1, x: 0, y: 0 }, 1e-9, 0, 0, 100, 100, 1000, 800);
  assert.equal(w.scale, M.scaleLimits(100, 100, 1000, 800).min);
});

test('pan has no limits', () => {
  const v = M.panBy({ scale: 0.25, x: 0, y: 150 }, 5000, -3000);
  assert.deepEqual(v, { scale: 0.25, x: 5000, y: -2850 });
});

test('resize keeps the image point at the frame center', () => {
  const v0 = { scale: 2, x: -300, y: -100 };
  const p = [(500 - v0.x) / 2, (400 - v0.y) / 2];               // point at old center
  const v1 = M.recenter(v0, 1000, 800, 4000, 2000, 1400, 600);
  near((700 - v1.x) / 2, p[0]);
  near((300 - v1.y) / 2, p[1]);
});

test('wheel factor: direction, line/page modes, clamping', () => {
  assert.ok(M.wheelFactor(-100, 0) > 1);
  assert.ok(M.wheelFactor(100, 0) < 1);
  near(M.wheelFactor(-3, 1), M.wheelFactor(-48, 0));             // 3 lines = 48 px
  near(M.wheelFactor(-1, 2, 300), M.wheelFactor(-300, 0));       // 1 page
  near(M.wheelFactor(-100000, 0), M.wheelFactor(-300, 0));       // clamped
});

test('resolveSrc: POSIX paths, Windows paths, URLs, relative', () => {
  assert.equal(M.resolveSrc('/home/x/a b#1%.jpg'), 'file:///home/x/a%20b%231%25.jpg');
  assert.equal(M.resolveSrc('/tmp/Фото.png'), 'file:///tmp/%D0%A4%D0%BE%D1%82%D0%BE.png');
  assert.equal(M.resolveSrc('C:\\a b\\x.jpg'), 'file:///C:/a%20b/x.jpg');
  assert.equal(M.resolveSrc('d:/pics/x.png'), 'file:///d:/pics/x.png');
  assert.equal(M.resolveSrc('file:///C:/x.png'), 'file:///C:/x.png');
  assert.equal(M.resolveSrc('https://example.com/a.png'), 'https://example.com/a.png');
  assert.equal(M.resolveSrc('img/a.png'), 'img/a.png');
  assert.equal(M.resolveSrc(''), '');
});

test('fileName: decoded last segment', () => {
  assert.equal(M.fileName('file:///a/%D0%BA%20x.png'), 'к x.png');
  assert.equal(M.fileName('file:///C:/dir/pic.jpg?x=1#y'), 'pic.jpg');
  assert.equal(M.fileName('file:///a/bad%E0.png'), 'bad%E0.png');   // invalid escape kept
});
