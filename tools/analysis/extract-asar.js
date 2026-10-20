// Minimal ASAR extractor (no network deps)
const fs = require('fs');
const path = require('path');

function readHeader(buf) {
  // bytes 0..3 = 4 (pickle size of next field)
  // bytes 4..7 = size of header pickle buffer
  const size = buf.readUInt32LE(4);
  const headerBuf = buf.subarray(8, 8 + size);
  const strLen = headerBuf.readUInt32LE(4);
  const json = headerBuf.subarray(8, 8 + strLen).toString('utf8');
  return { header: JSON.parse(json), headerSize: size, dataOffset: 8 + size };
}

function walk(node, base, out) {
  for (const [name, info] of Object.entries(node.files || {})) {
    const p = base ? base + '/' + name : name;
    if (info.files) {
      out.push({ type: 'dir', p });
      walk(info, p, out);
    } else {
      out.push({ type: 'file', p, size: info.size, offset: info.offset, unpacked: info.unpacked });
    }
  }
}

const asarPath = process.argv[2];
const outDir = process.argv[3];
const buf = fs.readFileSync(asarPath);
const { header, headerSize, dataOffset } = readHeader(buf);
console.log('headerSize=' + headerSize, 'dataOffset=' + dataOffset, 'fileSize=' + buf.length);

const entries = [];
walk(header, '', entries);
console.log('entries=' + entries.length);

let n = 0;
for (const e of entries) {
  const target = path.join(outDir, e.p);
  if (e.type === 'dir') {
    fs.mkdirSync(target, { recursive: true });
    continue;
  }
  fs.mkdirSync(path.dirname(target), { recursive: true });
  if (e.unpacked) {
    fs.writeFileSync(target + '.UNPACKED_MARKER', 'unpacked');
    continue;
  }
  const start = dataOffset + Number(e.offset);
  const data = buf.subarray(start, start + Number(e.size));
  fs.writeFileSync(target, data);
  n++;
}
console.log('extracted files=' + n);
