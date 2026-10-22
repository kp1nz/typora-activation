// ============================================================
//  Typora 1.12.3 — local licence shim
//  Loaded from resources/app.asar → launch.dist.js at boot
//  (build-asar.js inserts the require() line).
//
//  Design notes
//   1.12.3 no longer stores a plaintext licence blob. The value in
//          HKCU\Software\Typora : SLicense
//   is base64(<RSA ciphertext>)#0#<date>; the main process runs
//   crypto.publicDecrypt(<built-in public key>, payload) and rejects
//   anything whose length is not the RSA modulus size. The matching
//   private key stays on Typora's side, so an offline forged blob
//   cannot pass — the shim therefore controls the *result* of the
//   decryption instead of forging the ciphertext.
//
//  What this shim does
//   1. writes a syntactically valid SLicense (24-char code + checksum
//      + real machine fingerprint) before the app reads it
//   2. wraps crypto.publicDecrypt: on failure it returns a licence
//      JSON carrying this machine's fingerprint -> hasL: true
//   3. blocks the "trial expired" startup safety-quit
//      (app.quit from the timer at atom.compiled.dist.jsc:1:76238)
//      while leaving a normal window close / quit untouched
//   4. rewrites the UNREGISTERED badge injection and recycles the
//      trial licence popup
//
//  Log: %LOCALAPPDATA%\TyporaPatch\hook.log
// ============================================================
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const cp = require('child_process');

const BASE = path.join(process.env.LOCALAPPDATA || 'C:\\ProgramData', 'TyporaPatch');
const LOG = path.join(BASE, 'hook.log');
const START = Date.now();
const BOOT_MS = 15000;          // window during which the trial guard is suppressed
const EMAIL = 'local@typora.local';   // shown in the licence dialog, safe to change
const LMARK = 'TYPO-LCS-LOCAL-2026';

try { fs.mkdirSync(BASE, { recursive: true }); } catch (e) {}

function w() {
  try {
    fs.appendFileSync(LOG, '[' + new Date().toISOString().slice(11, 23) + '] ' +
      Array.prototype.join.call(arguments, ' ') + '\r\n');
  } catch (e) {}
}

w('--- shim loaded pid=' + process.pid);

// ---------- 1. machine fingerprint ----------
// fp = base64(sha256(MachineGuid + "typora"))[0..9], then [/=+-] -> 'a'
let FP = null;
try {
  const out = cp.execFileSync('reg',
    ['query', 'HKLM\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid', '/reg:64'],
    { encoding: 'utf8', windowsHide: true });
  const m = out.match(/MachineGuid\s+REG_SZ\s+([0-9a-fA-F-]+)/);
  if (m) FP = crypto.createHash('sha256').update(m[1] + 'typora').digest('base64').slice(0, 10).replace(/[/=+-]/g, 'a');
} catch (e) { w('fingerprint error: ' + e.message); }

// ---------- 2. write SLicense before the app reads it ----------
// code: XXXXXX-XXXXXX-XXXXXX-XXXXXX over L23456789ABCDEFGHJKMNPQRSTUVWXYZ
// checksum: chars 22/23 = sum of alphabet.indexOf(body[n + i]) for i = 0,2,..,14
try {
  const A = 'L23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  let body = '';
  for (let i = 0; i < 22; i++) body += A[Math.floor(Math.random() * A.length)];
  let ck = '';
  for (let n = 0; n < 2; n++) {
    let o = 0;
    for (let i = 0; i < 16; i += 2) o += A.indexOf(body[n + i]);
    ck += A[o % A.length];
  }
  const full = body + ck;
  const code = full.slice(0, 6) + '-' + full.slice(6, 12) + '-' + full.slice(12, 18) + '-' + full.slice(18, 24);
  const json = JSON.stringify({ fingerprint: FP || '', email: EMAIL, license: code, type: '' });
  const d = new Date();
  const dateStr = (d.getMonth() + 1) + '/' + d.getDate() + '/' + d.getFullYear();
  const sLicense = Buffer.from(json, 'utf8').toString('base64') + '#0#' + dateStr;
  cp.execFileSync('reg', ['add', 'HKCU\\Software\\Typora', '/v', 'SLicense', '/t', 'REG_SZ', '/d', sLicense, '/f'],
    { windowsHide: true, stdio: 'ignore' });
  w('SLicense refreshed: ' + code);
} catch (e) { w('SLicense write error: ' + e.message); }

// ---------- 3. licence payload returned in place of a valid RSA block ----------
const PAYLOAD = Buffer.from(JSON.stringify({
  fingerprint: FP || '',
  email: EMAIL,
  license: LMARK,
  type: '1'
}), 'utf8');

try {
  const origPD = crypto.publicDecrypt;
  Object.defineProperty(crypto, 'publicDecrypt', {
    value: function () {
      try { return origPD.apply(crypto, arguments); }
      catch (e) { w('publicDecrypt fallback -> local payload'); return Buffer.from(PAYLOAD); }
    },
    writable: true, configurable: true, enumerable: true
  });
} catch (e) { w('publicDecrypt hook error: ' + e.message); }

// ---------- 4. electron-side patches ----------
let electron = null;
try { electron = require('electron'); } catch (e) { w('electron require error: ' + e.message); }

if (electron && electron.app) {
  const app = electron.app;

  // 4a. trial-expired safety quit (normal quit still forwarded)
  const origQuit = app.quit.bind(app);
  app.quit = function () {
    const age = Date.now() - START;
    let st = '';
    try { st = new Error().stack || ''; } catch (e) {}
    const trialGuard = /atom\.compiled\.dist\.jsc:1:76238/.test(st);
    if (trialGuard || age < BOOT_MS) { w('quit suppressed (age=' + age + ' trialGuard=' + trialGuard + ')'); return; }
    return origQuit.apply(app, arguments);
  };

  // 4b. renderer badge rewrite + trial popup bookkeeping
  const trialWins = new Set();

  function patchWc(wc) {
    try {
      const origExec = wc.executeJavaScript.bind(wc);
      wc.executeJavaScript = function (code, ug) {
        try {
          if (typeof code === 'string' && code.indexOf('hasLicense = false') >= 0) {
            w('badge script rewritten');
            code = '(function(){try{' +
              'if(window.File&&window.File.option){File.option.hasLicense=true;' +
              'if(window.File.megaMenu)File.megaMenu.forceReload();}' +
              'var n=document.querySelectorAll("[class*=unreg]");' +
              'for(var i=0;i<n.length;i++)n[i].remove();}catch(e){}})();';
          }
        } catch (e) {}
        return origExec(code, ug);
      };
    } catch (e) { w('wc patch error: ' + e.message); }

    try {
      const url = (wc.getURL && wc.getURL()) || '';
      if (/license\.html/i.test(url)) {
        const win = wc.getOwnerBrowserWindow && wc.getOwnerBrowserWindow();
        if (win) { trialWins.add(win); w('trial popup registered: ' + url.slice(0, 60)); }
      }
    } catch (e) {}
  }

  app.on('web-contents-created', function (ev, wc) { patchWc(wc); });
  try { for (const wc of electron.webContents.getAllWebContents()) patchWc(wc); } catch (e) {}

  app.on('browser-window-created', function (ev, win) {
    try {
      win.webContents.on('did-finish-load', function () {
        try {
          const u = win.webContents.getURL();
          if (/license\.html/i.test(u) && Date.now() - START < BOOT_MS) {
            trialWins.add(win);
            w('hiding trial popup');
            setTimeout(function () { try { win.hide(); } catch (e) {} }, 200);
          }
        } catch (e) {}
      });
    } catch (e) {}
  });

  // 4c. recycle hidden trial popups once the editor window is up
  setTimeout(function () {
    for (const win of trialWins) {
      try {
        if (!win.isDestroyed()) { w('disposing hidden trial popup'); win.destroy(); }
      } catch (e) {}
    }
    trialWins.clear();
  }, BOOT_MS + 8000);
}

w('--- shim ready');
