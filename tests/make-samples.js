#!/usr/bin/env node
'use strict';
// Generate sample images for the manual checklist (TESTING.md).
// Usage: node tests/make-samples.js [output-dir]     (default: tests/out/samples)

const fs = require('node:fs');
const path = require('node:path');
const { encodePng, checkerPng } = require('./lib/png.js');

const out = path.resolve(process.argv[2] || path.join(__dirname, 'out', 'samples'));
fs.mkdirSync(out, { recursive: true });

const files = {
  'tiny-64x32.png': () => checkerPng(64, 32, 8),
  'huge-6000x4000.png': () => checkerPng(6000, 4000, 100),
  'wide-4000x100.png': () => checkerPng(4000, 100, 25),
  'tall-100x4000.png': () => checkerPng(100, 4000, 25),
  'pixel-art-16x16.png': () => encodePng(16, 16, (x, y) =>
    [(x * 16) & 255, (y * 16) & 255, ((x ^ y) * 16) & 255, 255]),
  'transparent-circle.png': () => encodePng(400, 400, (x, y) => {
    const d = Math.hypot(x - 200, y - 200);
    return d < 180 ? [230, 120, 30, Math.round(255 * (1 - d / 180))] : [0, 0, 0, 0];
  }),
  'sized.svg': () => '<svg xmlns="http://www.w3.org/2000/svg" width="300" height="200" viewBox="0 0 300 200">' +
    '<rect width="300" height="200" fill="#2c6bd6"/><circle cx="150" cy="100" r="70" fill="#f5c542"/></svg>',
  'no-intrinsic-size.svg': () => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 10">' +
    '<rect width="30" height="10" fill="teal"/><text x="2" y="7" font-size="6" fill="white">viewBox only</text></svg>',
  'name with spaces #1 50% + плюс.png': () => checkerPng(320, 240, 20)
};

for (const [name, make] of Object.entries(files)) {
  fs.writeFileSync(path.join(out, name), make());
  console.log(path.join(out, name));
}
console.log(`\n${Object.keys(files).length} samples written. Also try an animated GIF and a large photo of your own.`);
