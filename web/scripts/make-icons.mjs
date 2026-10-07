// Draws the app icons (a white heart on the theme color) as PNGs in
// public/. Uses only Node's zlib, so no image library is needed.
// Run with: node scripts/make-icons.mjs
import { writeFileSync } from 'node:fs';
import { deflateSync, crc32 } from 'node:zlib';

const THEME = [0x22, 0x8b, 0xe6]; // Mantine's default primary color, blue[6]
const WHITE = [0xff, 0xff, 0xff];
const SAMPLES = 4; // supersampling per axis, for smooth edges

// The heart curve (x² + y² − 1)³ − x²y³ ≤ 0 spans about x ∈ [-1.14, 1.14],
// y ∈ [-1, 1.25].
function inHeart(x, y) {
  const a = x * x + y * y - 1;
  return a * a * a - x * x * y * y * y <= 0;
}

// heartSize is the heart's width as a share of the icon; corner is the
// background's corner radius as a share (0 for a full square).
function draw(size, heartSize, corner) {
  const pixels = Buffer.alloc(size * size * 4);
  const scale = 2.28 / (heartSize * size); // curve units per pixel
  const radius = corner * size;

  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      let bg = 0, heart = 0;
      for (let sy = 0; sy < SAMPLES; sy++) {
        for (let sx = 0; sx < SAMPLES; sx++) {
          const x = px + (sx + 0.5) / SAMPLES;
          const y = py + (sy + 0.5) / SAMPLES;
          if (!insideRoundedSquare(x, y, size, radius)) continue;
          bg++;
          // Centre the heart, nudged down so it looks balanced.
          const hx = (x - size / 2) * scale;
          const hy = (size / 2 - y) * scale + 0.12;
          if (inHeart(hx, hy)) heart++;
        }
      }
      const total = SAMPLES * SAMPLES;
      const i = (py * size + px) * 4;
      const mix = bg ? heart / bg : 0;
      for (let c = 0; c < 3; c++) pixels[i + c] = Math.round(THEME[c] * (1 - mix) + WHITE[c] * mix);
      pixels[i + 3] = Math.round((bg / total) * 255);
    }
  }
  return png(size, pixels);
}

function insideRoundedSquare(x, y, size, r) {
  if (r === 0) return true;
  const cx = Math.min(Math.max(x, r), size - r);
  const cy = Math.min(Math.max(y, r), size - r);
  return (x - cx) ** 2 + (y - cy) ** 2 <= r * r;
}

function png(size, pixels) {
  const rows = Buffer.alloc(size * (size * 4 + 1));
  for (let y = 0; y < size; y++) {
    rows[y * (size * 4 + 1)] = 0; // filter: none
    pixels.copy(rows, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header.set([8, 6, 0, 0, 0], 8); // 8-bit RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(rows, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

const out = new URL('../public/', import.meta.url);
writeFileSync(new URL('pwa-192x192.png', out), draw(192, 0.62, 0.22));
writeFileSync(new URL('pwa-512x512.png', out), draw(512, 0.62, 0.22));
// Maskable icons may be cropped to a circle, so the heart stays in the
// middle 60% and the background fills the square.
writeFileSync(new URL('maskable-icon-512x512.png', out), draw(512, 0.46, 0));
// iOS rounds the corners itself.
writeFileSync(new URL('apple-touch-icon-180x180.png', out), draw(180, 0.58, 0));
