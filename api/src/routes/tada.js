import { Router } from 'express';
import { z } from 'zod';
import pool, { withTransaction } from '../db.js';
import { requireAuth, requireRole, requireAdmin } from '../middleware/auth.js';
import { uploadDoc, saveUpload } from '../services/storage.js';
import { buildTaDaClaim } from '../services/documents.js';
import {
  review, approve, canReview, canApprove, canView, loadSignatories, ensureFileNo,
} from '../services/workflow.js';
import { ah, parse, httpError, toPaise, sendPdf, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

const CLAIM_SELECT = `
  SELECT c.*, e.full_name, e.emp_code, e.designation, e.department, e.grade, e.reporting_to_id,
         p.name AS project_name, p.code AS project_code,
         r.full_name AS reviewed_by_name,
         a.full_name AS approved_by_name
    FROM ta_da_claims c
    JOIN employees e ON e.id = c.employee_id
    LEFT JOIN projects p ON p.id = c.project_id
    LEFT JOIN employees r ON r.id = c.reviewed_by
    LEFT JOIN employees a ON a.id = c.approved_by
`;

/** Current TA per-km and DA slabs, so the app can price a claim as it is typed. */
router.get('/rates', ah(async (req, res) => {
  const grade = req.query.grade || req.user.grade;
  const [{ rows: ta }, { rows: da }] = await Promise.all([
    pool.query(
      `SELECT DISTINCT ON (mode) mode, paise_per_km, actual_fare, grade
         FROM ta_rates
        WHERE is_active AND effective_from <= CURRENT_DATE
          AND (grade IS NULL OR grade = $1)
        ORDER BY mode, grade NULLS LAST, effective_from DESC`,
      [grade || null]
    ),
    pool.query(
      `SELECT DISTINCT ON (area) area, da_paise_per_day, lodging_cap_paise
         FROM da_rates
        WHERE is_active AND effective_from <= CURRENT_DATE AND grade = $1
        ORDER BY area, effective_from DESC`,
      [grade || 'default']
    ),
  ]);
  res.json({ grade, ta_rates: ta, da_rates: da });
}));

/**
 * Resolves the per-km rate for a mode on a given date, preferring a
 * grade-specific row over the general one. `actual_fare` modes (air, train, bus)
 * carry no per-km rate — the staff member enters the ticket amount instead.
 *
 * A missing rate must never silently price a leg at zero, so travel predating
 * the oldest rate row falls back to the earliest rate on record, and a mode with
 * no rate configured at all is rejected outright.
 */
async function resolveRate(mode, grade, travelDate) {
  const { rows } = await pool.query(
    `SELECT paise_per_km, actual_fare FROM ta_rates
      WHERE is_active AND mode = $1 AND effective_from <= $3
        AND (grade IS NULL OR grade = $2)
      ORDER BY grade NULLS LAST, effective_from DESC
      LIMIT 1`,
    [mode, grade || null, travelDate]
  );
  if (rows[0]) return rows[0];

  // Back-dated travel (common while the app is first rolled out).
  const { rows: earliest } = await pool.query(
    `SELECT paise_per_km, actual_fare FROM ta_rates
      WHERE is_active AND mode = $1 AND (grade IS NULL OR grade = $2)
      ORDER BY grade NULLS LAST, effective_from ASC
      LIMIT 1`,
    [mode, grade || null]
  );
  if (earliest[0]) return earliest[0];

  throw httpError(400,
    `No travel rate is configured for "${mode}". Ask the office to add it under Settings.`);
}

/**
 * Daily allowance per day for a grade and area. Falls back to the 'default'
 * grade when a specific grade has no slab, then to the earliest slab on record,
 * so a claim is never quietly allowed zero DA for days actually spent on duty.
 */
async function resolveDaRate(grade, area, travelDate) {
  const { rows } = await pool.query(
    `SELECT da_paise_per_day FROM da_rates
      WHERE is_active AND area = $2 AND effective_from <= $3
        AND grade = ANY($1::text[])
      ORDER BY array_position($1::text[], grade), effective_from DESC
      LIMIT 1`,
    [[grade || 'default', 'default'], area || 'ordinary', travelDate]
  );
  if (rows[0]) return Number(rows[0].da_paise_per_day);

  const { rows: earliest } = await pool.query(
    `SELECT da_paise_per_day FROM da_rates
      WHERE is_active AND area = $2 AND grade = ANY($1::text[])
      ORDER BY array_position($1::text[], grade), effective_from ASC
      LIMIT 1`,
    [[grade || 'default', 'default'], area || 'ordinary']
  );
  if (earliest[0]) return Number(earliest[0].da_paise_per_day);

  throw httpError(400,
    `No daily allowance slab is configured for a ${area || 'ordinary'} area. ` +
    'Ask the office to add it under Settings.');
}

const legSchema = z.object({
  travel_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Travel date must be YYYY-MM-DD'),
  from_place: z.string().trim().min(1, 'From place is required'),
  to_place: z.string().trim().min(1, 'To place is required'),
  mode: z.enum(['bus', 'train', 'air', 'taxi', 'two_wheeler', 'own_car', 'shared', 'other']),
  distance_km: z.coerce.number().min(0).max(10000).default(0),
  // Present for actual-fare modes (air/train tickets); in rupees as typed.
  fare: z.coerce.number().min(0).optional(),
  da_days: z.coerce.number().min(0).max(60).default(0),
  da_area: z.enum(['ordinary', 'state_capital', 'metro']).default('ordinary'),
  lodging: z.coerce.number().min(0).optional(),
  other: z.coerce.number().min(0).optional(),
  other_note: z.string().trim().max(300).optional(),
  receipt_url: z.string().trim().max(500).optional(),
});

const claimSchema = z.object({
  purpose: z.string().trim().min(5, 'Please describe the purpose of the journey'),
  project_id: z.coerce.number().int().positive().optional(),
  activity_id: z.coerce.number().int().positive().optional(),
  from_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'From date must be YYYY-MM-DD'),
  to_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'To date must be YYYY-MM-DD'),
  advance: z.coerce.number().min(0).default(0),
  status: z.enum(['draft', 'submitted']).default('submitted'),
  legs: z.array(legSchema).min(1, 'Add at least one journey leg'),
});

/**
 * Prices every leg server-side and writes the claim with its legs in one
 * transaction. Rates are never taken from the client — only distances, actual
 * fares and receipts are, so a tampered request cannot inflate the entitlement.
 */
async function priceLegs(legs, grade) {
  const priced = [];
  const totals = { fare: 0, da: 0, lodging: 0, other: 0 };

  for (const [i, leg] of legs.entries()) {
    const rate = await resolveRate(leg.mode, grade, leg.travel_date);
    const ratePaise = Number(rate.paise_per_km) || 0;

    // Actual-fare modes use the typed ticket amount; per-km modes are computed.
    const farePaise = rate.actual_fare
      ? toPaise(leg.fare || 0)
      : Math.round(Number(leg.distance_km || 0) * ratePaise);

    const daRate = leg.da_days > 0 ? await resolveDaRate(grade, leg.da_area, leg.travel_date) : 0;
    const daPaise = Math.round(Number(leg.da_days || 0) * daRate);
    const lodgingPaise = toPaise(leg.lodging || 0);
    const otherPaise = toPaise(leg.other || 0);

    totals.fare += farePaise;
    totals.da += daPaise;
    totals.lodging += lodgingPaise;
    totals.other += otherPaise;

    priced.push({
      ...leg,
      sort_order: i,
      rate_paise_per_km: rate.actual_fare ? 0 : ratePaise,
      fare_paise: farePaise,
      da_rate_paise: daRate,
      da_paise: daPaise,
      lodging_paise: lodgingPaise,
      other_paise: otherPaise,
    });
  }
  return { priced, totals };
}

router.post('/', ah(async (req, res) => {
  const b = parse(claimSchema, req.body);
  if (b.to_date < b.from_date) throw httpError(400, 'The end date cannot be before the start date');

  const { priced, totals } = await priceLegs(b.legs, req.user.grade);
  const total = totals.fare + totals.da + totals.lodging + totals.other;
  const advance = toPaise(b.advance);
  const net = total - advance;

  const claim = await withTransaction(async (client) => {
    const { rows } = await client.query(
      `INSERT INTO ta_da_claims (
          employee_id, project_id, activity_id, purpose, from_date, to_date,
          advance_paise, fare_paise, da_paise, lodging_paise, other_paise,
          total_paise, net_payable_paise, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
       RETURNING id`,
      [req.user.id, b.project_id ?? null, b.activity_id ?? null, b.purpose,
       b.from_date, b.to_date, advance, totals.fare, totals.da, totals.lodging,
       totals.other, total, net, b.status]
    );
    const id = rows[0].id;

    // Human-readable claim number, distinct from the letterhead file number
    // which is only minted at approval.
    await client.query(
      `UPDATE ta_da_claims
          SET claim_no = 'TADA/' || TO_CHAR(NOW(), 'YYYY') || '/' || LPAD($1::text, 4, '0')
        WHERE id = $1`,
      [id]
    );

    for (const leg of priced) {
      await client.query(
        `INSERT INTO ta_da_legs (
            claim_id, travel_date, from_place, to_place, mode, distance_km,
            rate_paise_per_km, fare_paise, da_days, da_rate_paise, da_paise,
            lodging_paise, other_paise, other_note, receipt_url, sort_order)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)`,
        [id, leg.travel_date, leg.from_place, leg.to_place, leg.mode, leg.distance_km,
         leg.rate_paise_per_km, leg.fare_paise, leg.da_days, leg.da_rate_paise,
         leg.da_paise, leg.lodging_paise, leg.other_paise, leg.other_note ?? null,
         leg.receipt_url ?? null, leg.sort_order]
      );
    }
    return id;
  });

  const { rows } = await pool.query(`${CLAIM_SELECT} WHERE c.id = $1`, [claim]);
  res.status(201).json(rows[0]);
}));

/** Receipt upload, returning a URL to attach to a leg. */
router.post('/receipt', uploadDoc.single('receipt'), ah(async (req, res) => {
  if (!req.file) throw httpError(400, 'No file was uploaded');
  const url = await saveUpload(req.file, 'receipts');
  res.status(201).json({ url });
}));

router.get('/', ah(async (req, res) => {
  const scope = req.query.scope || 'mine';
  const params = [req.user.id];
  let where;

  if (scope === 'mine') {
    where = 'c.employee_id = $1';
  } else if (scope === 'inbox') {
    if (req.user.role === 'staff') return res.json([]);
    where = req.user.role === 'manager'
      ? `c.status = 'submitted' AND e.reporting_to_id = $1 AND c.employee_id <> $1`
      : `c.status IN ('submitted', 'reviewed') AND c.employee_id <> $1`;
  } else if (scope === 'team') {
    where = req.user.role === 'manager' ? '(e.reporting_to_id = $1 OR c.employee_id = $1)'
      : req.user.role === 'staff' ? 'c.employee_id = $1'
      : 'TRUE';
  } else {
    throw httpError(400, 'scope must be mine, inbox or team');
  }

  if (req.query.status) {
    params.push(req.query.status);
    where += ` AND c.status = $${params.length}`;
  }

  const { rows } = await pool.query(
    `${CLAIM_SELECT} WHERE ${where} ORDER BY c.from_date DESC, c.created_at DESC LIMIT 200`,
    params
  );
  res.json(rows);
}));

async function loadClaim(id) {
  const { rows } = await pool.query(`${CLAIM_SELECT} WHERE c.id = $1`, [id]);
  if (!rows[0]) throw httpError(404, 'TA/DA claim not found');
  const { rows: legs } = await pool.query(
    'SELECT * FROM ta_da_legs WHERE claim_id = $1 ORDER BY sort_order, travel_date', [id]
  );
  return { claim: rows[0], legs };
}

router.get('/:id', ah(async (req, res) => {
  const { claim, legs } = await loadClaim(req.params.id);
  if (!canView(req.user, claim)) throw httpError(403, 'You cannot view this claim');
  res.json({ ...claim, legs });
}));

const decisionSchema = z.object({
  decision: z.string(),
  remark: z.string().trim().max(2000).optional(),
  // Authority may sanction a reduced amount, in rupees.
  sanctioned: z.coerce.number().min(0).optional(),
});

router.put('/:id/review', requireRole('manager'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { claim } = await loadClaim(req.params.id);
  if (!canReview(req.user, claim)) {
    throw httpError(403, 'You are not the reporting officer for this claim');
  }
  await review('ta_da_claims', claim.id, req.user, b);
  const { claim: after, legs } = await loadClaim(claim.id);
  res.json({ ...after, legs });
}));

router.put('/:id/approve', requireRole('authority'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { claim } = await loadClaim(req.params.id);
  if (!canApprove(req.user, claim)) throw httpError(403, 'You cannot approve this claim');

  // A reduced sanction changes what is actually payable, so recompute the net.
  const extra = {};
  if (b.decision === 'approved' && b.sanctioned != null) {
    const sanctioned = toPaise(b.sanctioned);
    if (sanctioned > claim.total_paise) {
      throw httpError(400, 'The sanctioned amount cannot exceed the amount claimed');
    }
    extra.sanctioned_paise = sanctioned;
    extra.net_payable_paise = sanctioned - claim.advance_paise;
  }

  await approve('ta_da_claims', claim.id, req.user, { ...b, extra });
  const { claim: after, legs } = await loadClaim(claim.id);
  res.json({ ...after, legs });
}));

/** Records disbursement once the finance side has paid out. */
router.put('/:id/paid', requireAdmin, ah(async (req, res) => {
  const ref = String(req.body?.payment_ref || '').trim();
  if (!ref) throw httpError(400, 'A payment reference is required');
  const { rows } = await pool.query(
    `UPDATE ta_da_claims SET status = 'paid', paid_at = NOW(), payment_ref = $1, updated_at = NOW()
      WHERE id = $2 AND status = 'approved' RETURNING id`,
    [ref, req.params.id]
  );
  if (!rows[0]) throw httpError(409, 'Only an approved claim can be marked paid');
  const { claim, legs } = await loadClaim(req.params.id);
  res.json({ ...claim, legs });
}));

router.get('/:id/bill.pdf', ah(async (req, res) => {
  const { claim, legs } = await loadClaim(req.params.id);
  if (!canView(req.user, claim)) throw httpError(403, 'You cannot download this document');
  if (!['approved', 'paid'].includes(claim.status)) {
    throw httpError(409, 'The sanction bill is available only after approval');
  }

  const fileNo = await ensureFileNo('ta_da_claims', claim, req.user);
  const { reviewer, approver } = await loadSignatories(claim);
  const pdf = await buildTaDaClaim({
    claim: { ...claim, file_no: fileNo },
    employee: claim,
    legs,
    project: claim.project_name ? { name: claim.project_name, code: claim.project_code } : null,
    reviewer,
    approver,
    fileNo,
  });
  sendPdf(res, pdf, `NESF-TADA-${claim.emp_code}-${claim.from_date}.pdf`);
}));

export default router;
