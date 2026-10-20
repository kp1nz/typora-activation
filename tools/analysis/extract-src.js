const fs = require('fs');
const s = fs.readFileSync(process.argv[2], 'utf8');
const start = Number(process.argv[3]);
function okch(ch) {
  const c = ch.codePointAt(0);
  return (c >= 32 && c < 127) || c === 10 || c === 13 || c === 9;
}
let end = s.length;
let run = 0;
for (let i = start; i < s.length; i++) {
  if (okch(s[i])) { run = 0; }
  else { run++; if (run > 80) { end = i - run + 1; break; } }
}
console.log('start', start, 'end', end, 'len', end - start);
const src = s.slice(start, end);
fs.writeFileSync(process.argv[4], src, 'utf8');
console.log('saved', process.argv[4]);
