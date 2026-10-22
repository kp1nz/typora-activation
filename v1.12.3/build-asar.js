#!/usr/bin/env node
/**
 * Rebuild Typora's resources/app.asar with a boot shim.
 *
 * 1.12.3 ships app.asar with three entries:
 *   atom.compiled.dist.jsc  (V8 bytecode, the real main process)
 *   launch.dist.js          (plaintext bytenode loader — our hook point)
 *   package.json
 *
 * We prepend a require() for the shim to launch.dist.js, then rebuild the
 * asar container with freshly computed SHA-256 integrity fields.
 *
 * Usage:
 *   node build-asar.js <original-app.asar> [output.asar]
 *
 *   --shim <abs path>     override the shim path baked into launch.dist.js
 *                         (default: %LOCALAPPDATA%\TyporaPatch\hook.js)
 *
 * Notes
 *   - Always feed it an *untouched* app.asar (installer copy or the
 *     app.asar.orig-backup made by deploy.ps1). The script refuses to patch
 *     an asar that already contains the shim marker.
 *   - The integrity hashes in the asar header are recomputed, so the file
 *     stays self-consistent. Typora 1.12.3 runs with the Electron fuse
 *     EnableEmbeddedAsarIntegrityValidation disabled, so a modified asar is
 *     still loaded.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const MARKER = 'TyporaPatch';
const args = process.argv.slice(2);

function usage(msg) {
  if (msg) console.error('error: ' + msg + '\n');
  console.error('usage: node build-asar.js <original-app.asar> [output.asar] [--shim <path>]');
  process.exit(1);
}

let shimPath = null;
const positional = [];
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--shim') { shimPath = args[++i]; continue; }
  if (args[i] === '-h' || args[i] === '--help') usage();
  positional.push(args[i]);
}
if (positional.length < 1) usage('missing input asar');
const input = path.resolve(positional[0]);
const output = path.resolve(positional[1] || input.replace(/\.asar$/, '') + '.patched.asar');
if (!fs.existsSync(input)) usage('input not found: ' + input);

// ---------------------------------------------------------------- asar read
function readAsar(file) {
  const b = fs.readFileSync(file);
  const headerRegion = b.readUInt32LE(4);
  const jsonLen = b.readUInt32LE(12);
  const json = JSON.parse(b.toString('utf8', 16, 16 + jsonLen));
  const dataStart = 8 + headerRegion;
  const entries = [];
  for (const [name, e] of Object.entries(json.files)) {
    const off = dataStart + Number(e.offset);
    entries.push({ name, buf: b.subarray(off, off + e.size), integrity: e.integrity });
  }
  return { entries, dataStart, total: b.length };
}

// ---------------------------------------------------------------- asar write
function buildAsar(entries) {
  let offset = 0;
  const files = {};
  const blobs = [];
  for (const e of entries) {
    const h = crypto.createHash('sha256').update(e.buf).digest('hex');
    files[e.name] = {
      size: e.buf.length,
      offset: String(offset),
      integrity: { algorithm: 'SHA256', hash: h, blockSize: 4194304, blocks: [h] }
    };
    offset += e.buf.length;
    blobs.push(e.buf);
  }
  const jsonStr = JSON.stringify({ files });
  const jsonLen = Buffer.byteLength(jsonStr, 'utf8');
  // headerRegion: pickle body length; dataStart = 8 + headerRegion
  const headerRegion = Math.ceil((8 + jsonLen) / 8) * 8;

  const head = Buffer.alloc(8);
  head.writeUInt32LE(4, 0);              // pickle payload size of first element
  head.writeUInt32LE(headerRegion, 4);   // header region size

  const body = Buffer.alloc(headerRegion, 0);
  body.writeUInt32LE(headerRegion - 4, 0);
  body.writeUInt32LE(jsonLen, 4);
  Buffer.from(jsonStr, 'utf8').copy(body, 8);

  return Buffer.concat([head, body, ...blobs]);
}

// ---------------------------------------------------------------- main
const { entries, dataStart, total } = readAsar(input);
console.log('input : ' + input);
console.log('        ' + total + ' bytes, dataStart ' + dataStart);
console.log('entries: ' + entries.map(e => e.name + ' (' + e.buf.length + ')').join(', '));

// sanity: header hashes must match content
let bad = 0;
for (const e of entries) {
  if (!e.integrity || !e.integrity.hash) continue;
  const h = crypto.createHash('sha256').update(e.buf).digest('hex');
  if (h !== e.integrity.hash) { bad++; console.warn('  ! integrity mismatch: ' + e.name); }
}
if (bad) console.warn('  (' + bad + ' mismatched entries — input may already be modified)');

const target = entries.find(e => e.name === 'launch.dist.js');
if (!target) usage('launch.dist.js not found in asar — unsupported Typora build');

const launchSrc = target.buf.toString('utf8');
if (launchSrc.indexOf(MARKER) >= 0) {
  usage('this asar is already patched; use a pristine app.asar (or app.asar.orig-backup)');
}

const shimRequire = shimPath
  ? 'require(' + JSON.stringify(shimPath) + ')'
  : 'require(require("path").join(process.env.LOCALAPPDATA||"C:\\\\ProgramData","TyporaPatch","hook.js"))';

const prefix =
  '"use strict";\n' +
  'try{' + shimRequire + '}' +
  'catch(e){try{require("fs").appendFileSync(require("path").join(process.env.LOCALAPPDATA||"C:\\\\ProgramData","TyporaPatch","boot-err.log"),String(e&&e.stack||e)+"\\n")}catch(_){}}\n';

const body = launchSrc.startsWith('"use strict";') ? launchSrc.slice('"use strict";'.length) : launchSrc;
target.buf = Buffer.from(prefix + body, 'utf8');
console.log('patched launch.dist.js: ' + target.buf.length + ' bytes');

const out = buildAsar(entries);
fs.writeFileSync(output, out);
console.log('output: ' + output + ' (' + out.length + ' bytes)');
console.log('');
console.log('next: run deploy.ps1 -Asar "' + output + '"');
