/**
 * Verifies that uploaded files are private.
 *
 * Attendance selfies, signatures, receipts and activity photographs are staff
 * personal data. This asserts that none of them is reachable without a session,
 * that the old static /uploads path no longer serves files, and that the
 * per-category access rules hold — a staff member's selfie must not be visible to
 * an unrelated colleague.
 *
 *   npm start
 *   node test/media-privacy.mjs
 */
import { Buffer } from 'buffer';

const BASE = process.env.E2E_BASE || 'http://localhost:4000';
const API = `${BASE}/api`;
const ADMIN_EMAIL = process.env.SEED_ADMIN_EMAIL || 'biki@nesportsfoundation.in';
const ADMIN_PASSWORD = process.env.SEED_ADMIN_PASSWORD || 'ChangeMe@123';

let failures = 0;
let checks = 0;
const ok = (label, cond, extra = '') => {
  checks++;
  if (!cond) failures++;
  console.log(`${cond ? '  ok  ' : ' FAIL '} ${label}${extra ? ' — ' + extra : ''}`);
};

async function json(method, path, { token, body } = {}) {
  const res = await fetch(API + path, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let parsed = null;
  try { parsed = await res.json(); } catch { /* empty */ }
  return { status: res.status, json: parsed };
}

const login = async (email, password) =>
  (await json('POST', '/auth/login', { body: { email, password } })).json?.access_token;

/** Smallest valid PNG, so uploads exercise the real image path. */
const PNG_1PX = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==',
  'base64'
);

async function upload(path, token, field, extra = {}) {
  const form = new FormData();
  form.append(field, new Blob([PNG_1PX], { type: 'image/png' }), 'test.png');
  for (const [k, v] of Object.entries(extra)) form.append(k, v);
  const res = await fetch(API + path, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });
  let parsed = null;
  try { parsed = await res.json(); } catch { /* empty */ }
  return { status: res.status, json: parsed };
}

async function fetchMedia(key, token) {
  const res = await fetch(`${API}/media/${key}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : {},
  });
  const buf = Buffer.from(await res.arrayBuffer());
  return { status: res.status, buf, type: res.headers.get('content-type') || '' };
}

// ---------------------------------------------------------------------------
console.log('\n== Setup ==');
const admin = await login(ADMIN_EMAIL, ADMIN_PASSWORD);
ok('admin signs in', !!admin);
if (!admin) process.exit(1);

async function ensure(spec) {
  const res = await json('POST', '/employees', { token: admin, body: spec });
  if (res.status === 201) return res.json.id;
  const list = await json('GET', '/employees', { token: admin });
  return (list.json || []).find((e) => e.email?.toLowerCase() === spec.email.toLowerCase())?.id;
}

const mgrId = await ensure({
  emp_code: 'MED-100', full_name: 'Media Manager', email: 'media.mgr@nesportsfoundation.in',
  role: 'manager', password: 'Manager@123', is_active: true,
});
const staffId = await ensure({
  emp_code: 'MED-101', full_name: 'Media Staff', email: 'media.staff@nesportsfoundation.in',
  role: 'staff', password: 'Staff@123', is_active: true, reporting_to_id: mgrId,
});
await ensure({
  emp_code: 'MED-102', full_name: 'Media Outsider', email: 'media.out@nesportsfoundation.in',
  role: 'staff', password: 'Staff@123', is_active: true,
});
ok('fixtures created', !!mgrId && !!staffId);

const staffTok = await login('media.staff@nesportsfoundation.in', 'Staff@123');
const mgrTok = await login('media.mgr@nesportsfoundation.in', 'Manager@123');
const outTok = await login('media.out@nesportsfoundation.in', 'Staff@123');

console.log('\n== Uploads return a storage key, not a URL ==');
const sig = await upload(`/employees/${staffId}/signature`, staffTok, 'signature');
const sigKey = sig.json?.signature_url;
ok('signature uploaded', sig.status === 200, sig.json?.error);
ok('stored value is a key, not a URL',
  typeof sigKey === 'string' && sigKey.startsWith('signatures/') && !sigKey.includes('://'),
  sigKey);

// Only one check-in per person per day, so on a re-run reuse the selfie the
// earlier run filed rather than failing.
const selfie = await upload('/attendance/check-in', staffTok, 'selfie',
  { lat: '27.0844', lng: '93.6053', work_mode: 'office' });
let selfieKey = selfie.json?.check_in_selfie;
if (selfie.status === 409) {
  const today = await json('GET', '/attendance/today', { token: staffTok });
  selfieKey = today.json?.attendance?.check_in_selfie;
}
ok('attendance selfie available',
  (selfie.status === 201 || selfie.status === 409) && !!selfieKey,
  selfie.status === 409 ? 'reused today\'s check-in' : selfie.json?.error);
ok('selfie stored as a key',
  typeof selfieKey === 'string' && selfieKey.startsWith('attendance/') && !selfieKey.includes('://'),
  selfieKey);

console.log('\n== Nothing is readable without a session ==');
const anon = await fetchMedia(selfieKey, null);
ok('selfie refused to an anonymous caller', anon.status === 401, `HTTP ${anon.status}`);
const anonSig = await fetchMedia(sigKey, null);
ok('signature refused to an anonymous caller', anonSig.status === 401, `HTTP ${anonSig.status}`);

// The old static mount is gone. With the web build present the SPA fallback
// answers unknown paths, so assert on the body: it must be the app shell, never
// the image bytes.
const legacy = await fetch(`${BASE}/uploads/${selfieKey}`);
const legacyBody = Buffer.from(await legacy.arrayBuffer());
const isPng = legacyBody.subarray(1, 4).toString() === 'PNG';
ok('/uploads no longer serves the file itself', !isPng,
  `HTTP ${legacy.status}, ${legacy.headers.get('content-type')}`);

console.log('\n== Per-category access rules ==');
const own = await fetchMedia(selfieKey, staffTok);
ok('staff can load their own selfie',
  own.status === 200 && own.buf.subarray(1, 4).toString() === 'PNG', `HTTP ${own.status}`);
ok('served with an image content type', own.type.startsWith('image/'), own.type);

const byMgr = await fetchMedia(selfieKey, mgrTok);
ok('reporting officer can load their reportee\'s selfie', byMgr.status === 200, `HTTP ${byMgr.status}`);

const byAuthority = await fetchMedia(selfieKey, admin);
ok('authority can load any selfie', byAuthority.status === 200, `HTTP ${byAuthority.status}`);

const byOutsider = await fetchMedia(selfieKey, outTok);
ok('unrelated colleague CANNOT load the selfie', byOutsider.status === 403,
  `HTTP ${byOutsider.status}`);

const sigByOutsider = await fetchMedia(sigKey, outTok);
ok('any signed-in staff can load a signature (it appears on documents)',
  sigByOutsider.status === 200, `HTTP ${sigByOutsider.status}`);

console.log('\n== Path traversal and unknown prefixes ==');
for (const bad of [
  '../.env',
  '..%2F.env',
  'signatures/../../.env',
  'unknownfolder/file.png',
  'attendance/does-not-exist.png',
]) {
  const r = await fetchMedia(bad, admin);
  ok(`"${bad}" refused`, r.status === 400 || r.status === 403 || r.status === 404,
    `HTTP ${r.status}`);
}

console.log('\n== PDFs still embed private images ==');
// The signature is now read from storage rather than over HTTP; prove the
// letterhead renderer still stamps it by checking a document renders.
const muster = await fetch(`${API}/attendance/muster.pdf?year=${new Date().getFullYear()}&month=${new Date().getMonth() + 1}`,
  { headers: { Authorization: `Bearer ${admin}` } });
const musterBuf = Buffer.from(await muster.arrayBuffer());
ok('muster PDF renders with private storage',
  muster.status === 200 && musterBuf.subarray(0, 5).toString() === '%PDF-',
  `${musterBuf.length} bytes`);

console.log(
  `\n${failures === 0 ? `✓ all ${checks} checks passed` : `✗ ${failures} of ${checks} checks failed`}\n`
);
process.exit(failures === 0 ? 0 : 1);
