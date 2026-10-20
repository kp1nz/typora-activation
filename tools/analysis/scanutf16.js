const fs = require('fs');
const dir = process.argv[2];
const needle = process.argv[3];
const enc = process.argv[4] === 'utf16' ? 'utf16le' : 'latin1';
const ctx = Number(process.argv[5] || 400);
const maxHits = Number(process.argv[6] || 10);
const files = fs.readdirSync(dir).filter(f => f.endsWith('.bin'));
const nb = Buffer.from(needle, enc);
let shown = 0;
for (const f of files) {
  const b = fs.readFileSync(dir + '\\' + f);
  let i = 0;
  while (i <= b.length - nb.length && shown < maxHits) {
    const idx = b.indexOf(nb, i);
    if (idx < 0) break;
    const s = Math.max(0, idx - ctx), e = Math.min(b.length, idx + ctx);
    const seg = b.subarray(s, e);
    console.log('\n===== ' + f + ' @0x' + idx.toString(16));
    console.log(seg.toString(enc).replace(/\u0000/g, '.'));
    shown++;
    i = idx + nb.length;
  }
  if (shown >= maxHits) break;
}
console.log('\nshown=' + shown);
