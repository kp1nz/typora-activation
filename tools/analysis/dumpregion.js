const fs = require('fs');
const dir = process.argv[2];
const outFile = process.argv[3];
const files = fs.readdirSync(dir).filter(f => f.endsWith('.bin'));
let all = '';
for (const f of files) {
  const b = fs.readFileSync(dir + '\\' + f);
  // decode as utf16le, keep printable
  const s = b.toString('utf16le');
  all += '\n\n/* === ' + f + ' === */\n' + s;
}
fs.writeFileSync(outFile, all, 'utf8');
console.log('wrote ' + all.length + ' chars to ' + outFile);
// find license-ish markers
const marks = ['getHasLicense', 'publicKey', 'verify(\u0060', 'BEGIN PUBLIC KEY', 'activation', 'licence', 'licenseKey', 'rsa', 'createVerify', 'node-forge'];
for (const m of marks) {
  const idx = all.indexOf(m);
  console.log(m.padEnd(20), idx < 0 ? 'NOT FOUND' : ('@' + idx));
}
