// Generates the Forma app icon and platform assets from the in-app brand mark
// (arc + crossbar + dot, see src/components/ui/Brand.tsx) so the launcher icon
// and splash match the product. Pure Node + zlib so it runs without image deps.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'assets');

const BG = [7, 8, 6];
const ACCENT = [199, 250, 79];
const WHITE = [255, 255, 255];

const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
const smoothstep = (edge0, edge1, x) => {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
};
const mix = (a, b, t) => a.map((channel, index) => channel + (b[index] - channel) * t);

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (let i = 0; i < buffer.length; i += 1) c = CRC_TABLE[(c ^ buffer[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

function encodePng(width, height, rgba) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * (stride + 1)] = 0;
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// Mark geometry in the same 48x48 space as Brand.tsx.
const ARC = { cx: 23, cy: 25, r: 11.5, width: 4.2 };
const BAR = { a: [17, 24], b: [27.5, 24], width: 4.2 };
const DOT = { cx: 35.5, cy: 31.5, r: 3.2 };
const ARC_START_DEG = -54.5;
const ARC_END_DEG = 0;

function angleInArc(angleDeg) {
  // The SVG arc runs counter-clockwise from -54.5° through 360° and the gap is
  // the small wedge between -54.5° and 0° on the right side.
  const normalized = ((angleDeg % 360) + 360) % 360;
  return normalized >= 360 + ARC_START_DEG || normalized <= ARC_END_DEG - 0.0001
    ? false
    : true;
}

function render({ size, background, markScale = 0.6, color = ACCENT, monochrome = false }) {
  const rgba = Buffer.alloc(size * size * 4);
  const s = (size * markScale) / 48;
  const offset = (size - 48 * s) / 2;

  for (let y = 0; y < size; y += 1) {
    for (let x = 0; x < size; x += 1) {
      const px = x + 0.5;
      const py = y + 0.5;

      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;

      if (background) {
        const nx = (px - size / 2) / (size / 2);
        const ny = (py - size / 2) / (size / 2);
        const radius = Math.sqrt(nx * nx + ny * ny);
        const glow = (1 - smoothstep(0.05, 0.95, radius)) * 0.085;
        const vignette = 1 - smoothstep(0.62, 1.02, radius) * 0.35;
        const lit = mix(BG, ACCENT, glow);
        r = lit[0] * vignette;
        g = lit[1] * vignette;
        b = lit[2] * vignette;
        a = 255;
      }

      const vx = (px - offset) / s;
      const vy = (py - offset) / s;

      const dxArc = vx - ARC.cx;
      const dyArc = vy - ARC.cy;
      const angle = (Math.atan2(dyArc, dxArc) * 180) / Math.PI;
      const ringDistance = Math.abs(Math.hypot(dxArc, dyArc) - ARC.r) - ARC.width / 2;
      let arcDistance = ringDistance;
      if (!angleInArc(angle)) {
        const endAngle = (ARC_END_DEG * Math.PI) / 180;
        const startAngle = (ARC_START_DEG * Math.PI) / 180;
        const endDistance =
          Math.hypot(vx - (ARC.cx + ARC.r * Math.cos(endAngle)), vy - (ARC.cy + ARC.r * Math.sin(endAngle))) -
          ARC.width / 2;
        const startDistance =
          Math.hypot(vx - (ARC.cx + ARC.r * Math.cos(startAngle)), vy - (ARC.cy + ARC.r * Math.sin(startAngle))) -
          ARC.width / 2;
        arcDistance = Math.min(startDistance, endDistance);
      }

      const barDx = BAR.b[0] - BAR.a[0];
      const barDy = BAR.b[1] - BAR.a[1];
      const barT = clamp(((vx - BAR.a[0]) * barDx + (vy - BAR.a[1]) * barDy) / (barDx * barDx + barDy * barDy), 0, 1);
      const barDistance =
        Math.hypot(vx - (BAR.a[0] + barDx * barT), vy - (BAR.a[1] + barDy * barT)) - BAR.width / 2;

      const dotDistance = Math.hypot(vx - DOT.cx, vy - DOT.cy) - DOT.r;

      const arcAlpha = clamp(0.5 - arcDistance * s, 0, 1);
      const barAlpha = clamp(0.5 - barDistance * s, 0, 1);
      const dotAlpha = clamp(0.5 - dotDistance * s, 0, 1);
      const markAlpha = 1 - (1 - arcAlpha) * (1 - barAlpha) * (1 - dotAlpha);
      const nearest = Math.min(arcDistance, barDistance, dotDistance);
      const halo = Math.exp(-Math.max(0, nearest) * s / 38) * 0.26;

      const tint = monochrome ? WHITE : color;
      const haloAlpha = monochrome ? 0 : halo;
      if (haloAlpha > 0) {
        r = r * (1 - haloAlpha) + tint[0] * haloAlpha;
        g = g * (1 - haloAlpha) + tint[1] * haloAlpha;
        b = b * (1 - haloAlpha) + tint[2] * haloAlpha;
      }
      if (markAlpha > 0) {
        const gradient = clamp(
          ((vx - 8) * 34 + (vy - 6) * 38) / (34 * 34 + 38 * 38),
          0,
          1,
        );
        const strokeFade = 1 - 0.55 * gradient;
        const shapeAlpha = Math.max(
          arcAlpha * strokeFade,
          barAlpha,
          dotAlpha,
        );
        // Rounded caps between arc and bar can overlap; use the strongest alpha.
        r = r * (1 - shapeAlpha) + tint[0] * shapeAlpha;
        g = g * (1 - shapeAlpha) + tint[1] * shapeAlpha;
        b = b * (1 - shapeAlpha) + tint[2] * shapeAlpha;
        a = Math.max(a, Math.round(shapeAlpha * 255));
      }

      const index = (y * size + x) * 4;
      rgba[index] = Math.round(clamp(r, 0, 255));
      rgba[index + 1] = Math.round(clamp(g, 0, 255));
      rgba[index + 2] = Math.round(clamp(b, 0, 255));
      rgba[index + 3] = a;
    }
  }

  return encodePng(size, size, rgba);
}

mkdirSync(OUT, { recursive: true });

writeFileSync(join(OUT, 'icon.png'), render({ size: 1024, background: true, markScale: 0.6 }));
writeFileSync(join(OUT, 'favicon.png'), render({ size: 64, background: true, markScale: 0.72 }));
writeFileSync(
  join(OUT, 'android-icon-foreground.png'),
  render({ size: 1024, background: false, markScale: 0.56 }),
);
writeFileSync(join(OUT, 'android-icon-background.png'), render({ size: 1024, background: true }));
writeFileSync(
  join(OUT, 'android-icon-monochrome.png'),
  render({ size: 1024, background: false, markScale: 0.56, color: WHITE, monochrome: true }),
);
writeFileSync(join(OUT, 'splash-icon.png'), render({ size: 1024, background: false, markScale: 0.6 }));

console.log('Wrote Forma icon assets to assets/');
