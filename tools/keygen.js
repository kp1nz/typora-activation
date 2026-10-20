// Typora local activation keygen (offline activation proof-of-concept)
// Model recovered from atom.js:
//   fingerprint = sha256(MachineGuid + "typora").digest("base64").substr(0,10).replace(/[/=+-]/g,"a")
//   code        = 24 chars, 4 groups of 6, alphabet "L23456789ABCDEFGHJKMNPQRSTUVWXYZ"
//                 chars 22,23 are checksums over chars 0..15 (see below)
//   SLicense    = base64(JSON{fingerprint,email,license,type}) + "#0#" + date(en-US)
const crypto = require('crypto');
const { execSync } = require('child_process');

const ALPHABET = 'L23456789ABCDEFGHJKMNPQRSTUVWXYZ';

// --- 1. machine guid (64-bit view) ---
function machineGuid() {
  const key = 'HKLM\\SOFTWARE\\Microsoft\\Cryptography';
  const out = execSync(`reg query "${key}" /v MachineGuid /reg:64`, { encoding: 'utf8' });
  const m = out.match(/MachineGuid\s+REG_SZ\s+(\S+)/i);
  if (!m) throw new Error('MachineGuid not found:\n' + out);
  return m[1].trim();
}

// --- 2. fingerprint, mirrors M() in atom.js ---
function fingerprint(guid) {
  return crypto.createHash('sha256')
    .update(guid).update('typora')
    .digest('base64')
    .substr(0, 10)
    .replace(/[/=+-]/g, 'a');
}

// --- 3. checksum, mirrors Y() in atom.js ---
function checksum(body16) {
  let t = '';
  for (let n = 0; n < 2; n++) {
    let o = 0;
    for (let i = 0; i < 16; i += 2) o += ALPHABET.indexOf(body16[n + i]);
    o %= ALPHABET.length;
    t += ALPHABET[o];
  }
  return t;
}

function makeLicense() {
  let body = '';
  for (let i = 0; i < 22; i++) body += ALPHABET[crypto.randomInt(ALPHABET.length)];
  const code = body + checksum(body);
  return code.match(/.{6}/g).join('-');
}

// --- 4. verify a code the same way Y() does ---
function verifyCode(code) {
  if (!/^([A-Z0-9]{6}-){3}[A-Z0-9]{6}$/.exec(code)) return false;
  const e = code.replace(/-/g, '');
  const tail = e.substr(22);
  if (e.replace(/[L23456789ABCDEFGHJKMNPQRSTUVWXYZ]/g, '')) return false;
  return tail === checksum(e);
}

const guid = machineGuid();
const fp = fingerprint(guid);
const email = process.argv[2] || 'licence@local.host';
const license = makeLicense();

const payload = Buffer.from(JSON.stringify({
  fingerprint: fp,
  email: email,
  license: license,
  type: '',
}), 'utf8').toString('base64');

const date = new Date().toLocaleDateString('en-US');
const sLicense = payload + '#0#' + date;

console.log('MachineGuid  :', guid);
console.log('fingerprint  :', fp);
console.log('license code :', license, '  (verify:', verifyCode(license) + ')');
console.log('email        :', email);
console.log('payload b64  :', payload);
console.log('SLicense     :', sLicense);
require('fs').writeFileSync(__dirname + '\\slicense.txt', sLicense, 'utf8');
console.log('\nwritten to slicense.txt');
