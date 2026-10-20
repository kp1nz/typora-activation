const fs = require('fs');
const s = fs.readFileSync(process.argv[2], 'utf8');
const B = 20000;
console.log('len', s.length, 'blocks', Math.ceil(s.length / B));
for (let i = 0; i < s.length; i += B) {
  const seg = s.slice(i, i + B);
  let ok = 0;
  for (const ch of seg) {
    const c = ch.codePointAt(0);
    if ((c >= 32 && c < 127) || c === 10 || c === 13 || c === 9 || (c > 0x2000 && c < 0x3000)) ok++;
  }
  const r = ok / seg.length;
  if (r > 0.5) console.log('block @' + i + ' ratio=' + r.toFixed(2));
}
