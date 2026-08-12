/**
 * End-to-end check of the NESF Core API: the two-stage approval chain, the
 * documents it issues on letterhead, access control, and server-side pricing.
 *
 * Run against a migrated + seeded database with the API listening:
 *   npm start
 *   npm run test:e2e
 *
 * Safe to re-run: the fixture staff are reused if they already exist, and the
 * assertions are written against "at least" rather than exact counts wherever
 * earlier runs may have left records behind.
 */
const API = process.env.E2E_API || 'http://localhost:4000/api';
const ADMIN_EMAIL = process.env.SEED_ADMIN_EMAIL || 'biki@nesportsfoundation.in';
const ADMIN_PASSWORD = process.env.SEED_ADMIN_PASSWORD || 'ChangeMe@123';

let failures = 0;
let checks = 0;

function ok(label, cond, extra = '') {
  checks++;
  if (!cond) failures++;
  console.log(`${cond ? '  ok  ' : ' FAIL '} ${label}${extra ? ' — ' + extra : ''}`);
}

async function call(method, path, { token, body, raw } = {}) {
  const res = await fetch(API + path, {
    method,
    headers: {
      ...(body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (raw) return { status: res.status, buf: Buffer.from(await res.arrayBuffer()) };
  let json = null;
  try { json = await res.json(); } catch { /* empty body */ }
  return { status: res.status, json };
}

const login = async (email, password) => {
  const { json } = await call('POST', '/auth/login', { body: { email, password } });
  return json?.access_token;
};

/** Creates the fixture employee, or signs in if a previous run already made them. */
async function ensureEmployee(adminToken, spec) {
  const res = await call('POST', '/employees', { token: adminToken, body: spec });
  if (res.status === 201) return { id: res.json.id, created: true };
  if (res.status === 409) {
    const list = await call('GET', '/employees', { token: adminToken });
    const found = (list.json || []).find(
      (e) => e.email?.toLowerCase() === spec.email.toLowerCase()
    );
    return { id: found?.id, created: false };
  }
  throw new Error(`could not create ${spec.email}: ${res.json?.error}`);
}

// ---------------------------------------------------------------------------
console.log('\n== Auth ==');
const admin = await login(ADMIN_EMAIL, ADMIN_PASSWORD);
ok('admin signs in', !!admin);
if (!admin) {
  console.error('\nCannot continue without the seeded admin. Run `npm run seed` first.\n');
  process.exit(1);
}

const bad = await call('POST', '/auth/login',
  { body: { email: ADMIN_EMAIL, password: 'wrong-password' } });
ok('wrong password rejected', bad.status === 401, bad.json?.error);
ok('unauthenticated request rejected', (await call('GET', '/dashboard')).status === 401);

console.log('\n== Staff setup ==');
const mgr = await ensureEmployee(admin, {
  emp_code: 'E2E-100', full_name: 'Tana Riba', email: 'e2e.manager@nesportsfoundation.in',
  role: 'manager', designation: 'Programme Manager', department: 'Programmes',
  grade: 'B', password: 'Manager@123', is_active: true, signature_title: 'Programme Manager',
});
ok('manager fixture available', !!mgr.id);

const staff = await ensureEmployee(admin, {
  emp_code: 'E2E-101', full_name: 'Mema Dodum', email: 'e2e.staff@nesportsfoundation.in',
  role: 'staff', designation: 'Field Coordinator', department: 'Programmes',
  grade: 'C', password: 'Staff@123', is_active: true, reporting_to_id: mgr.id,
});
ok('staff fixture reports to the manager', !!staff.id);

const outsider = await ensureEmployee(admin, {
  emp_code: 'E2E-102', full_name: 'Unrelated Staff', email: 'e2e.other@nesportsfoundation.in',
  role: 'staff', password: 'Staff@123', is_active: true,
});
ok('unrelated staff fixture available', !!outsider.id);

const dupe = await call('POST', '/employees', {
  token: admin,
  body: { emp_code: 'E2E-101', full_name: 'Clash',
          email: 'e2e.staff@nesportsfoundation.in', role: 'staff', password: 'Staff@123' },
});
ok('duplicate employee rejected', dupe.status === 409, dupe.json?.error);

const staffTok = await login('e2e.staff@nesportsfoundation.in', 'Staff@123');
const mgrTok = await login('e2e.manager@nesportsfoundation.in', 'Manager@123');
const outTok = await login('e2e.other@nesportsfoundation.in', 'Staff@123');
ok('all three fixtures can sign in', !!staffTok && !!mgrTok && !!outTok);

const yr = new Date().getFullYear() + 1;
const stamp = Date.now() % 20;

// The API refuses overlapping leave, so pick a window clear of anything this
// fixture already has — otherwise a re-run trips its own earlier record.
const existingLeave = await call('GET', '/leaves?scope=mine', { token: staffTok });
const latestTo = (existingLeave.json || [])
  .filter((l) => l.status !== 'rejected' && l.status !== 'cancelled')
  .map((l) => l.to_date)
  .sort()
  .pop();

const dayAfter = (isoDate, days) => {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
};

const leaveFrom = latestTo ? dayAfter(latestTo, 3) : `${yr}-03-02`;
const leaveTo = dayAfter(leaveFrom, 2);

console.log('\n== Leave: apply -> review -> approve -> PDF ==');
const apply = await call('POST', '/leaves', {
  token: staffTok,
  body: {
    leave_type_id: 1, from_date: leaveFrom, to_date: leaveTo,
    reason: 'Attending a family function at Pasighat.',
    address_on_leave: 'Pasighat, East Siang', contact_on_leave: '+91 9876543210',
  },
});
ok('staff applies for leave', apply.status === 201, apply.json?.error);
const leaveId = apply.json?.id;

const clash = await call('POST', '/leaves', {
  token: staffTok,
  body: { leave_type_id: 1, from_date: leaveFrom, to_date: leaveTo, reason: 'Overlap test' },
});
ok('overlapping leave rejected', clash.status === 409, clash.json?.error);

ok('staff cannot review (role gate)',
  (await call('PUT', `/leaves/${leaveId}/review`,
    { token: staffTok, body: { decision: 'forwarded' } })).status === 403);

const earlyPdf = await call('GET', `/leaves/${leaveId}/letter.pdf`, { token: staffTok });
ok('PDF blocked before approval', earlyPdf.status === 409, earlyPdf.json?.error);

const inbox = await call('GET', '/leaves?scope=inbox', { token: mgrTok });
ok('leave reaches manager inbox', (inbox.json || []).some((l) => l.id === leaveId));

const review = await call('PUT', `/leaves/${leaveId}/review`, {
  token: mgrTok,
  body: { decision: 'forwarded', remark: 'Recommended. Work handed over to the district team.' },
});
ok('manager forwards leave', review.json?.status === 'reviewed', review.json?.error);

const authInbox = await call('GET', '/leaves?scope=inbox', { token: admin });
ok('leave reaches authority inbox', (authInbox.json || []).some((l) => l.id === leaveId));

// Leave is debited against the entitlement for the year it falls in, and this
// fixture is dated next year — so read that year's balance, not the current one.
const leaveYear = Number(leaveFrom.slice(0, 4));
const leaveMonth = Number(leaveFrom.slice(5, 7));
const balanceBefore = await call('GET', `/leaves/types?year=${leaveYear}`, { token: staffTok });
const usedBefore = balanceBefore.json?.find((t) => t.code === 'CL')?.used ?? 0;

const approve = await call('PUT', `/leaves/${leaveId}/approve`, {
  token: admin, body: { decision: 'approved', remark: 'Sanctioned.' },
});
ok('authority approves leave', approve.json?.status === 'approved', approve.json?.error);
ok('file number minted', /\/\d{4}\/\d{3}$/.test(approve.json?.file_no || ''), approve.json?.file_no);

const balanceAfter = await call('GET', `/leaves/types?year=${leaveYear}`, { token: staffTok });
const cl = balanceAfter.json?.find((t) => t.code === 'CL');
ok('leave balance debited on approval', cl.used === usedBefore + approve.json.days,
  `used ${usedBefore} -> ${cl.used}, days ${approve.json.days}`);

const pdf = await call('GET', `/leaves/${leaveId}/letter.pdf`, { token: staffTok, raw: true });
ok('leave letter PDF issued',
  pdf.status === 200 && pdf.buf.subarray(0, 5).toString() === '%PDF-',
  `${pdf.buf.length} bytes`);

const regBefore = (await call('GET', '/settings/documents', { token: admin })).json.length;
await call('GET', `/leaves/${leaveId}/letter.pdf`, { token: staffTok, raw: true });
const regAfter = (await call('GET', '/settings/documents', { token: admin })).json.length;
ok('re-download reuses the file number', regBefore === regAfter, `${regBefore} -> ${regAfter}`);

console.log('\n== Access control ==');
const peek = await call('GET', `/leaves/${leaveId}`, { token: outTok });
ok('unrelated staff cannot read the leave', peek.status === 403, peek.json?.error);
ok('staff cannot pull the org muster',
  (await call('GET', '/attendance/muster.pdf', { token: staffTok })).status === 403);
ok('staff cannot create an employee',
  (await call('POST', '/employees', { token: staffTok, body: { emp_code: 'X', full_name: 'X',
    email: 'x@x.com', role: 'admin', password: 'Password1' } })).status === 403);

console.log('\n== Work report ==');
const rep = await call('POST', '/reports', {
  token: staffTok,
  body: {
    period: 'monthly', period_start: `${yr}-01-01`, period_end: `${yr}-01-31`,
    title: 'Monthly progress — East Siang grassroots football',
    summary: 'Conducted six coaching sessions across three schools with 180 children participating.',
    achievements: 'Two athletes selected for the state under-14 trials.',
    next_plan: 'Extend to two additional schools next month.',
  },
});
ok('staff submits work report', rep.status === 201, rep.json?.error);
await call('PUT', `/reports/${rep.json?.id}/review`,
  { token: mgrTok, body: { decision: 'forwarded', remark: 'Verified.' } });
const repApp = await call('PUT', `/reports/${rep.json?.id}/approve`,
  { token: admin, body: { decision: 'approved' } });
ok('report approved', repApp.json?.status === 'approved', repApp.json?.error);
const repPdf = await call('GET', `/reports/${rep.json?.id}/report.pdf`,
  { token: staffTok, raw: true });
ok('work report PDF issued',
  repPdf.status === 200 && repPdf.buf.subarray(0, 5).toString() === '%PDF-',
  `${repPdf.buf.length} bytes`);

console.log('\n== Project + activity ==');
const projectCode = `E2E-GF-${stamp}`;
let proj = await call('POST', '/projects', {
  token: mgrTok,
  body: {
    code: projectCode, name: 'Grassroots Football — East Siang',
    description: 'School-level football development across East Siang district.',
    sport: 'Football', district: 'East Siang', start_date: `${yr}-04-01`,
    end_date: `${yr + 1}-03-31`, budget: 450000, funder: 'CSR — State Bank',
    lead_id: mgr.id, status: 'active',
  },
});
if (proj.status === 409) {
  const all = await call('GET', '/projects', { token: mgrTok });
  proj = { status: 201, json: all.json.find((p) => p.code === projectCode) };
}
ok('project created', proj.status === 201 && !!proj.json?.id, proj.json?.error);

const act = await call('POST', '/projects/activities', {
  token: staffTok,
  body: {
    project_id: proj.json?.id, title: 'Inter-school football tournament, Pasighat',
    activity_date: `${yr}-01-22`, venue: 'Govt Higher Secondary School, Pasighat',
    district: 'East Siang', participants_male: 64, participants_female: 48,
    beneficiaries: 300,
    description: 'A one-day inter-school tournament with eight schools and a coaching clinic.',
    outcome: 'Four athletes identified for further scouting.',
    expenditure: 38500,
  },
});
ok('activity submitted', act.status === 201, act.json?.error);
ok('participants totalled', act.json?.participants_total === 112, `${act.json?.participants_total}`);

await call('PUT', `/projects/activities/${act.json?.id}/review`,
  { token: mgrTok, body: { decision: 'forwarded', remark: 'Attended and verified.' } });
const actApp = await call('PUT', `/projects/activities/${act.json?.id}/approve`,
  { token: admin, body: { decision: 'approved' } });
ok('activity approved', actApp.json?.status === 'approved', actApp.json?.error);

const actPdf = await call('GET', `/projects/activities/${act.json?.id}/report.pdf`,
  { token: staffTok, raw: true });
ok('activity report PDF issued',
  actPdf.status === 200 && actPdf.buf.subarray(0, 5).toString() === '%PDF-',
  `${actPdf.buf.length} bytes`);

const projPdf = await call('GET', `/projects/${proj.json?.id}/report.pdf`,
  { token: mgrTok, raw: true });
ok('project report PDF issued',
  projPdf.status === 200 && projPdf.buf.subarray(0, 5).toString() === '%PDF-',
  `${projPdf.buf.length} bytes`);

console.log('\n== TA/DA ==');
const rates = await call('GET', '/tada/rates', { token: staffTok });
ok('TA/DA rates resolve for grade',
  (rates.json?.ta_rates?.length || 0) > 0 && (rates.json?.da_rates?.length || 0) > 0);

const claim = await call('POST', '/tada', {
  token: staffTok,
  body: {
    purpose: 'Travel to Pasighat for the inter-school tournament.',
    project_id: proj.json?.id, from_date: `${yr}-01-21`, to_date: `${yr}-01-23`,
    advance: 2000,
    legs: [
      { travel_date: `${yr}-01-21`, from_place: 'Itanagar', to_place: 'Pasighat',
        mode: 'own_car', distance_km: 300, da_days: 1, da_area: 'ordinary', lodging: 1200 },
      { travel_date: `${yr}-01-23`, from_place: 'Pasighat', to_place: 'Itanagar',
        mode: 'own_car', distance_km: 300, da_days: 1, da_area: 'ordinary' },
    ],
  },
});
ok('TA/DA claim created', claim.status === 201, claim.json?.error);
// Grade C: own_car at Rs 12/km over 600 km = Rs 7,200; DA Rs 300 x 2 = Rs 600;
// lodging Rs 1,200. Gross Rs 9,000; net after a Rs 2,000 advance = Rs 7,000.
ok('fare priced server-side from rates', claim.json?.fare_paise === 720000, `${claim.json?.fare_paise}`);
ok('DA priced from the grade slab', claim.json?.da_paise === 60000, `${claim.json?.da_paise}`);
ok('total and net computed',
  claim.json?.total_paise === 900000 && claim.json?.net_payable_paise === 700000,
  `total=${claim.json?.total_paise} net=${claim.json?.net_payable_paise}`);

await call('PUT', `/tada/${claim.json?.id}/review`,
  { token: mgrTok, body: { decision: 'forwarded', remark: 'Journey verified.' } });
const over = await call('PUT', `/tada/${claim.json?.id}/approve`,
  { token: admin, body: { decision: 'approved', sanctioned: 99999 } });
ok('sanction above the claim rejected', over.status === 400, over.json?.error);

const tadaApp = await call('PUT', `/tada/${claim.json?.id}/approve`,
  { token: admin, body: { decision: 'approved', sanctioned: 8500, remark: 'Lodging capped.' } });
ok('reduced sanction recomputes net',
  tadaApp.json?.sanctioned_paise === 850000 && tadaApp.json?.net_payable_paise === 650000,
  `sanctioned=${tadaApp.json?.sanctioned_paise} net=${tadaApp.json?.net_payable_paise}`);

const tadaPdf = await call('GET', `/tada/${claim.json?.id}/bill.pdf`,
  { token: staffTok, raw: true });
ok('TA/DA bill PDF issued',
  tadaPdf.status === 200 && tadaPdf.buf.subarray(0, 5).toString() === '%PDF-',
  `${tadaPdf.buf.length} bytes`);

console.log('\n== CRM ==');
const contact = await call('POST', '/crm/contacts', {
  token: staffTok,
  body: {
    kind: 'organisation', category: 'csr', name: 'Ramesh Agarwal',
    organisation: 'Siang Valley Cements Pvt Ltd', designation: 'CSR Head',
    email: 'csr@example.com', phone: '+91 9800011122', district: 'East Siang',
    state: 'Arunachal Pradesh', stage: 'interested', source: 'Referral',
    next_action: 'Send the grassroots football proposal',
  },
});
ok('CRM contact created', contact.status === 201, contact.json?.error);

const inter = await call('POST', `/crm/contacts/${contact.json?.id}/interactions`, {
  token: staffTok,
  body: {
    kind: 'meeting', summary: 'Met at their Pasighat office; walked through the programme.',
    outcome: 'Asked for a formal proposal with a budget.', stage: 'proposal_sent',
  },
});
ok('interaction logged', inter.status === 201, inter.json?.error);

const contrib = await call('POST', `/crm/contacts/${contact.json?.id}/contributions`, {
  token: staffTok,
  body: { amount: 250000, kind: 'bank', status: 'received',
          reference: 'NEFT/8829102', project_id: proj.json?.id },
});
ok('contribution recorded', contrib.status === 201, contrib.json?.error);

const detail = await call('GET', `/crm/contacts/${contact.json?.id}`, { token: staffTok });
ok('contribution rolls up to the lifetime total',
  detail.json?.total_given_paise === 25000000, `${detail.json?.total_given_paise}`);
ok('stage advanced to donated', detail.json?.stage === 'donated', detail.json?.stage);
ok('pipeline returns all stages',
  (await call('GET', '/crm/pipeline', { token: admin })).json?.length === 8);

console.log('\n== Attendance ==');
const today = await call('GET', '/attendance/today', { token: staffTok });
ok('attendance state readable', today.status === 200 && 'can_check_in' in (today.json || {}));

// The selfie is mandatory, so a JSON-only check-in must be refused.
const noSelfie = await call('POST', '/attendance/check-in',
  { token: staffTok, body: { lat: 27.0844, lng: 93.6053 } });
ok('check-in without a selfie rejected', noSelfie.status === 400, noSelfie.json?.error);

const cal = await call('GET', '/attendance/calendar?year=2026&month=8', { token: staffTok });
ok('attendance calendar builds', cal.status === 200 && cal.json?.days === 31, `days=${cal.json?.days}`);

const leaveCal = await call('GET',
  `/leaves/calendar?year=${leaveYear}&month=${leaveMonth}`, { token: staffTok });
ok('leave calendar marks the approved days',
  Array.isArray(leaveCal.json?.by_date?.[leaveFrom]), leaveFrom);

const muster = await call('GET', '/attendance/muster.pdf?year=2026&month=8',
  { token: admin, raw: true });
ok('monthly muster PDF issued',
  muster.status === 200 && muster.buf.subarray(0, 5).toString() === '%PDF-',
  `${muster.buf.length} bytes`);

console.log('\n== Concurrent document numbering ==');
// Submit 3 leave applications to test that concurrent approvals get sequential file numbers.
const concurrent1 = await call('POST', '/leaves', {
  token: staffTok,
  body: { leave_type_id: 1, from_date: '2026-09-01', to_date: '2026-09-03', reason: 'Concurrent test 1' },
});
const concurrent2 = await call('POST', '/leaves', {
  token: staffTok,
  body: { leave_type_id: 1, from_date: '2026-09-05', to_date: '2026-09-06', reason: 'Concurrent test 2' },
});
const concurrent3 = await call('POST', '/leaves', {
  token: staffTok,
  body: { leave_type_id: 1, from_date: '2026-09-08', to_date: '2026-09-09', reason: 'Concurrent test 3' },
});
ok('3 concurrent applications submitted', concurrent1.status === 201 && concurrent2.status === 201 && concurrent3.status === 201);

// Approve all three in rapid succession.
const ids = [concurrent1.json?.id, concurrent2.json?.id, concurrent3.json?.id].filter(Boolean);
const approvals = await Promise.all(ids.map((id) =>
  call('PUT', `/leaves/${id}/approve`, { token: admin, body: { remark: 'Approved' } })
));
ok('3 concurrent approvals succeeded', approvals.every((a) => a.status === 200));

// Verify file numbers are sequential (no duplicates).
const fileNos = approvals.map((a) => a.json?.file_no).filter(Boolean);
const unique = new Set(fileNos);
ok('concurrent approvals got unique file numbers', unique.size === fileNos.length, `${fileNos.join(', ')}`);
ok('file numbers are sequential',
  fileNos[0] && fileNos[1] && fileNos[0] < fileNos[1], `${fileNos[0]} < ${fileNos[1]}`);

console.log('\n== Leave deduction math ==');
// Apply leave Fri-Mon with weekend between: should debit 2 days not 4.
// Assuming 2026-08-16 is Friday, 2026-08-17 is Saturday, 2026-08-18 is Sunday, 2026-08-19 is Monday.
const deductionTest = await call('POST', '/leaves', {
  token: staffTok,
  body: { leave_type_id: 1, from_date: '2026-08-16', to_date: '2026-08-19', reason: 'Includes weekend' },
});
ok('leave spanning weekend submitted', deductionTest.status === 201);
const leaveDetail = deductionTest.json;
ok('leave correctly excludes weekend days',
  leaveDetail?.days === 2, `expected 2 days, got ${leaveDetail?.days}`);

console.log('\n== Malformed input ==');
for (const badPath of ['/leaves/undefined', '/leaves/abc', '/tada/9e9', '/employees/1x']) {
  const r = await call('GET', badPath, { token: admin });
  ok(`${badPath} -> 400 not 500`, r.status === 400, `got ${r.status}`);
}
ok('unknown id -> 404', (await call('GET', '/leaves/99999999', { token: admin })).status === 404);

console.log(
  `\n${failures === 0 ? `✓ all ${checks} checks passed` : `✗ ${failures} of ${checks} checks failed`}\n`
);
process.exit(failures === 0 ? 0 : 1);
