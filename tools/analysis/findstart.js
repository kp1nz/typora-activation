const fs = require('fs');
const s = fs.readFileSync(process.argv[2], 'utf8');
function okch(ch) {
  const c = ch.codePointAt(0);
  return (c >= 32 && c < 127) || c === 10 || c === 13 || c === 9;
}
// find start of long readable run
let start = -1;
for (let i = 780000; i < s.length - 3000; i++) {
  let good = true;
  for (let j = 0; j < 3000; j += 7) { if (!okch(s[i + j])) { good = false; break; } }
  if (good) { start = i; break; }
}
console.log('start =', start);
console.log(JSON.stringify(s.slice(start - 60, start + 400)));
// find end
let end = s.length;
console.log('tail:', JSON.stringify(s.slice(-300)));
