// Draws the app icons (two linked wedding rings in white on a lavender
// gradient) as PNGs in public/. Uses only Node's zlib, so no image
// library is needed.
// Run with: node scripts/make-icons.mjs
import { writeFileSync } from 'node:fs';
import { deflateSync, crc32 } from 'node:zlib';

// lavender[4] at the top to lavender[6] at the bottom (src/theme.ts).
const TOP = [0xb6, 0x9b, 0xe2];
const BOTTOM = [0x7c, 0x5d, 0xbd];
const WHITE = [0xff, 0xff, 0xff];
const SAMPLES = 5; // supersampling per axis, for smooth edges

// The rings, as shares of the drawing's width: each ring's radius (to the
// middle of its band), half its band's thickness, how far each centre sits
// from the middle, and the gap that shows one ring passing over the other.
const RADIUS = 0.295;
const HALF_BAND = 0.04;
const OFFSET = 0.165;
const GAP = 0.03;

// A diamond sits on top of the left ring, like an engagement ring: a
// flat-topped crown over a pointed base set into the band. Its widest
// line (the girdle) is GIRDLE_V; sizes are half-widths and heights.
const GEM_WIDTH = 0.17;
const GEM_TABLE = 0.095;
const GEM_CROWN = 0.085;
const GEM_BASE = 0.17;
const GIRDLE_V = -RADIUS - GEM_BASE; // the point reaches the band's middle
const FACET = 0.008; // half the thickness of the facet lines

// Distance from (x, y) to the segment from (ax, ay) to (bx, by).
function toSegment(x, y, ax, ay, bx, by) {
  const dx = bx - ax, dy = by - ay;
  const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(x - ax - t * dx, y - ay - t * dy);
}

// The gem's outline, with its facets cut in as thin lines: the girdle,
// lines from the table down to the girdle, and lines meeting at the point.
function inGem(u, v) {
  const gu = Math.abs(u + OFFSET); // the gem is symmetric
  const gv = v - GIRDLE_V;
  if (gv < -GEM_CROWN || gv > GEM_BASE) return false;
  const halfWidth = gv < 0
    ? GEM_TABLE + (GEM_WIDTH - GEM_TABLE) * (gv + GEM_CROWN) / GEM_CROWN
    : GEM_WIDTH * (1 - gv / GEM_BASE);
  if (gu > halfWidth) return false;
  const mid = GEM_WIDTH * 0.42; // where the facets meet the girdle
  const facets = [
    Math.abs(gv),                                                 // girdle
    toSegment(gu, gv, GEM_TABLE * 0.45, -GEM_CROWN, mid, 0),      // crown
    toSegment(gu, gv, mid, 0, 0, GEM_BASE),                       // base
  ];
  return Math.min(...facets) > FACET;
}

// The drawing is taller at the top because of the diamond; this shift
// centres it in the icon.
const LIFT = (GIRDLE_V - GEM_CROWN + RADIUS + HALF_BAND) / 2;

// How far (u, v) is from the middle of the band of the ring centred at cx.
const fromBand = (u, v, cx) => Math.abs(Math.hypot(u - cx, v) - RADIUS);

// True where the rings are white. They link: the left ring passes over the
// right at the top and under it at the bottom, shown by a gap cut into the
// lower ring beside the upper one.
function inRings(u, rawV) {
  const v = rawV + LIFT;
  if (inGem(u, v)) return true;
  const left = fromBand(u, v, -OFFSET);
  const right = fromBand(u, v, OFFSET);
  const [over, under] = v < 0 ? [left, right] : [right, left];
  if (over <= HALF_BAND) return true;
  return under <= HALF_BAND && over > HALF_BAND + GAP;
}

// rings is the drawing's width as a share of the icon; corner is the
// background's corner radius as a share (0 for a full square).
function draw(size, rings, corner) {
  const pixels = Buffer.alloc(size * size * 4);
  const scale = 1 / (rings * size); // drawing units per pixel
  const radius = corner * size;

  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      let bg = 0, ink = 0;
      for (let sy = 0; sy < SAMPLES; sy++) {
        for (let sx = 0; sx < SAMPLES; sx++) {
          const x = px + (sx + 0.5) / SAMPLES;
          const y = py + (sy + 0.5) / SAMPLES;
          if (!insideRoundedSquare(x, y, size, radius)) continue;
          bg++;
          if (inRings((x - size / 2) * scale, (y - size / 2) * scale)) ink++;
        }
      }
      const total = SAMPLES * SAMPLES;
      const i = (py * size + px) * 4;
      const mix = bg ? ink / bg : 0;
      const down = py / (size - 1);
      for (let c = 0; c < 3; c++) {
        const background = TOP[c] * (1 - down) + BOTTOM[c] * down;
        pixels[i + c] = Math.round(background * (1 - mix) + WHITE[c] * mix);
      }
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

// The rings span 2 × (OFFSET + RADIUS + HALF_BAND) = 1 drawing unit wide.
const out = new URL('../public/', import.meta.url);
writeFileSync(new URL('icon-192.png', out), draw(192, 0.64, 0.22));
writeFileSync(new URL('icon-512.png', out), draw(512, 0.64, 0.22));
// Maskable icons may be cropped to a circle, so the rings stay inside the
// middle 80% circle and the background fills the square.
writeFileSync(new URL('icon-maskable-512.png', out), draw(512, 0.5, 0));
// iOS rounds the corners itself.
writeFileSync(new URL('apple-touch-icon.png', out), draw(180, 0.62, 0));
