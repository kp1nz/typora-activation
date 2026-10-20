const fs = require('fs');
const path = require('path');
const dir = process.argv[2];
const needle = process.argv[3] || 'licen';
const ctx = Number(process.argv[4] || 300);
const maxHits = Number(process.argv[5] || 40);

const files = fs.readdirSync(dir).filter(f => f.endsWith('.bin'));
const nb = Buffer.from(needle, 'latin1');
let shown = 0;
for (const f of files) {
  const b = fs.readFileSync(path.join(dir, f));
  let i = 0;
  while (i <= b.length - nb.length && shown < maxHits) {
    const idx = b.indexOf(nb, i);
    if (idx < 0) break;
    const s = Math.max(0, idx - ctx);
    const e = Math.min(b.length, idx + ctx);
    const seg = b.subarray(s, e);
    let printable = 0;
    for (const c of seg) if (c >= 32 && c < 127) printable++;
    const ratio = printable / seg.length;
    if (ratio > 0.85) {
      console.log('\n===== ' + f + ' @0x' + idx.toString(16) + ' ratio=' + ratio.toFixed(2));
      console.log(seg.toString('latin1'));
      shown++;
    }
    i = idx + nb.length;
  }
  if (shown >= maxHits) break;
}
console.log('\nshown=' + shown);
