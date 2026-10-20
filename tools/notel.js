// Toggle Typora telemetry / auto-update flags inside profile.data (hex-encoded JSON)
const fs = require('fs');
const path = require('path');

const file = path.join(process.env.APPDATA, 'Typora', 'profile.data');
const hex = fs.readFileSync(file, 'utf8').trim();
const json = Buffer.from(hex, 'hex').toString('utf8');
const db = JSON.parse(json);

console.log('before:');
console.log('  send_usage_info  =', db.send_usage_info === undefined ? '<absent → true>' : db.send_usage_info);
console.log('  enableAutoUpdate =', db.enableAutoUpdate === undefined ? '<absent → true>' : db.enableAutoUpdate);

db.send_usage_info = false;      // gates Raven (main) + AWS Pinpoint analytics (renderer)
db.enableAutoUpdate = false;     // no surprise updates that could undo activation

const out = Buffer.from(JSON.stringify(db), 'utf8').toString('hex');
fs.writeFileSync(file + '.bak-' + Date.now(), hex, 'utf8');   // keep raw backup
fs.writeFileSync(file, out, 'utf8');

const check = JSON.parse(Buffer.from(fs.readFileSync(file, 'utf8').trim(), 'hex').toString('utf8'));
console.log('after:');
console.log('  send_usage_info  =', check.send_usage_info);
console.log('  enableAutoUpdate =', check.enableAutoUpdate);
console.log('  keys =', Object.keys(check).join(', '));
