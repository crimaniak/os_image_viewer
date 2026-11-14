'use strict';
// Minimal RGBA PNG encoder (Node built-ins only) for test fixtures and samples.

const zlib = require('node:zlib');

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

/**
 * encodePng(width, height, pixel) -> Buffer
 * pixel(x, y) returns [r, g, b, a] (0..255).
 */
function encodePng(w, h, pixel) {
  const stride = w * 4 + 1;
  const raw = Buffer.alloc(stride * h);
  for (let y = 0; y < h; y++) {
    let o = y * stride;
    raw[o++] = 0;                       // filter: none
    for (let x = 0; x < w; x++) {
      const p = pixel(x, y);
      raw[o++] = p[0]; raw[o++] = p[1]; raw[o++] = p[2]; raw[o++] = p[3];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0))
  ]);
}

/** Checkerboard with a colored border, handy for seeing zoom and pan. */
function checkerPng(w, h, cell = 16) {
  return encodePng(w, h, (x, y) => {
    if (x < 2 || y < 2 || x >= w - 2 || y >= h - 2) return [220, 40, 40, 255];
    const on = ((Math.floor(x / cell) + Math.floor(y / cell)) & 1) === 0;
    return on ? [60, 110, 200, 255] : [235, 235, 240, 255];
  });
}

module.exports = { encodePng, checkerPng, crc32 };
