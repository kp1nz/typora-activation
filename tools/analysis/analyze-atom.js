const fs = require('fs');
const p = 'C:\\Users\\KP1NZ\\Documents\\deepseek-harness\\default-workspace\\typora-re\\ex\\app\\atom.js';
const a = fs.readFileSync(p);
console.log('len', a.length);
const s = a.toString('latin1');
const chars = {};
for (const c of s) chars[c] = (chars[c] || 0) + 1;
const keys = Object.keys(chars).sort();
console.log('alphabet size', keys.length);
console.log('chars', JSON.stringify(keys.join('')));
console.log('count of = :', (s.match(/=/g) || []).length);
console.log('last 60:', JSON.stringify(s.slice(-60)));
const b64 = Buffer.from(s, 'base64');
console.log('b64 decoded len', b64.length);
console.log('first 32 bytes hex', b64.subarray(0, 32).toString('hex'));
console.log('first 64 ascii', JSON.stringify(b64.subarray(0, 64).toString('latin1')));
// entropy
const freq = {};
for (const byte of a) freq[byte] = (freq[byte] || 0) + 1;
let H = 0;
for (const k in freq) { const pr = freq[k] / a.length; H -= pr * Math.log2(pr); }
console.log('byte entropy', H.toFixed(3));
