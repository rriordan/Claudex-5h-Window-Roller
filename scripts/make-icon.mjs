import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const icoPath = resolve(root, 'assets/icon.ico');
const size = 256;

function bgra(x, y) {
  const cx = size / 2;
  const cy = size / 2;
  const dx = x - cx;
  const dy = y - cy;
  const radius = Math.sqrt(dx * dx + dy * dy);
  const angle = Math.atan2(dy, dx);

  const inRoundedRect = x > 0 && y > 0 && x < size && y < size;
  if (!inRoundedRect) return [0, 0, 0, 0];

  let r = 37;
  let g = 97;
  let b = 84;
  const t = (x + y) / (size * 2);
  r = Math.round(r * (1 - t) + 31 * t);
  g = Math.round(g * (1 - t) + 41 * t);
  b = Math.round(b * (1 - t) + 55 * t);

  const ring = radius > 65 && radius < 88 && !(x > 156 && y < 104);
  const arrow = x > 138 && x < 207 && y > 49 && y < 116 && Math.abs((x - 172) - (y - 82)) < 34;
  if (ring || arrow) {
    r = 244;
    g = Math.round(184 + 48 * Math.sin(angle));
    b = 92;
  }

  if (radius < 34) {
    r = 255;
    g = 253;
    b = 248;
  }

  const hand = (Math.abs(x - cx) < 7 && y > 83 && y < 132) || (x > 124 && x < 160 && Math.abs(y - (128 + (x - 128) * 0.58)) < 7);
  if (hand) {
    r = 31;
    g = 41;
    b = 55;
  }

  return [b, g, r, 255];
}

const headerSize = 6;
const dirSize = 16;
const bitmapHeaderSize = 40;
const xorSize = size * size * 4;
const andStride = Math.ceil(size / 32) * 4;
const andSize = andStride * size;
const imageSize = bitmapHeaderSize + xorSize + andSize;
const buffer = Buffer.alloc(headerSize + dirSize + imageSize);

let offset = 0;
buffer.writeUInt16LE(0, offset); offset += 2;
buffer.writeUInt16LE(1, offset); offset += 2;
buffer.writeUInt16LE(1, offset); offset += 2;
buffer.writeUInt8(0, offset++);
buffer.writeUInt8(0, offset++);
buffer.writeUInt8(0, offset++);
buffer.writeUInt8(0, offset++);
buffer.writeUInt16LE(1, offset); offset += 2;
buffer.writeUInt16LE(32, offset); offset += 2;
buffer.writeUInt32LE(imageSize, offset); offset += 4;
buffer.writeUInt32LE(headerSize + dirSize, offset); offset += 4;

buffer.writeUInt32LE(bitmapHeaderSize, offset); offset += 4;
buffer.writeInt32LE(size, offset); offset += 4;
buffer.writeInt32LE(size * 2, offset); offset += 4;
buffer.writeUInt16LE(1, offset); offset += 2;
buffer.writeUInt16LE(32, offset); offset += 2;
buffer.writeUInt32LE(0, offset); offset += 4;
buffer.writeUInt32LE(xorSize + andSize, offset); offset += 4;
buffer.writeInt32LE(2835, offset); offset += 4;
buffer.writeInt32LE(2835, offset); offset += 4;
buffer.writeUInt32LE(0, offset); offset += 4;
buffer.writeUInt32LE(0, offset); offset += 4;

for (let y = size - 1; y >= 0; y--) {
  for (let x = 0; x < size; x++) {
    const pixel = bgra(x, y);
    for (const channel of pixel) buffer.writeUInt8(channel, offset++);
  }
}

mkdirSync(dirname(icoPath), { recursive: true });
writeFileSync(icoPath, buffer);
console.log(`Wrote ${icoPath}`);
