const fs = require('fs');
const files = process.argv.slice(3);
const needle = process.argv[2];
const ctx = 200;
for (const p of files) {
  let b;
  try { b = fs.readFileSync(p); } catch (e) { continue; }
  const s = b.toString('latin1');
  let i = 0, n = 0;
  while ((i = s.toLowerCase().indexOf(needle.toLowerCase(), i)) !== -1 && n < 12) {
    console.log('\n===== ' + p + ' @' + i);
    console.log(s.slice(Math.max(0, i - ctx), i + ctx).replace(/[\r\n]+/g, ' '));
    i += needle.length; n++;
  }
  if (n === 0) console.log('(no hit) ' + p);
}
