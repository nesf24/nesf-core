import { Router } from 'express';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { buildLeaveLetter } from '../services/documents.js';
import {
  review, approve, canReview, canApprove, canView, loadSignatories, ensureFileNo,
} from '../services/workflow.js';
import { ah, parse, httpError, dateRange, isoWeekday, sendPdf, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

/**
 * Counts chargeable leave days between two dates, skipping declared holidays and
 * weekly offs — staff should not be debited for a Sunday inside a leave spell.
 */
async function chargeableDays(from, to, isHalfDay) {
  const [{ rows: settings }, { rows: holidays }] = await Promise.all([
    pool.query('SELECT weekly_offs FROM settings WHERE id = 1'),
    pool.query('SELECT holiday_on FROM holidays WHERE holiday_on BETWEEN $1 AND $2', [from, to]),
  ]);
  const offs = new Set(settings[0]?.weekly_offs || [7]);
  const holidaySet = new Set(holidays.map((h) => h.holiday_on));

  let days = 0;
  for (const d of dateRange(from, to)) {
    if (holidaySet.has(d)) continue;
    if (offs.has(isoWeekday(d))) continue;
    days++;
  }
  // A half day only makes sense on a single-day application.
  if (isHalfDay && days === 1) return 0.5;
  return days;
}

const LEAVE_SELECT = `
  SELECT l.*, lt.code AS leave_type_code, lt.name AS leave_type_name, lt.is_paid,
         e.full_name, e.emp_code, e.designation, e.department, e.reporting_to_id,
         h.full_name AS handover_name,
         r.full_name AS reviewed_by_name,
         a.full_name AS approved_by_name
    FROM leaves l
    JOIN leave_types lt ON lt.id = l.leave_type_id
    JOIN employees e ON e.id = l.employee_id
    LEFT JOIN employees h ON h.id = l.handover_to_id
    LEFT JOIN employees r ON r.id = l.reviewed_by
    LEFT JOIN employees a ON a.id = l.approved_by
`;

/** Current-year leave balance summary for dashboard. */
router.get('/balance', ah(async (req, res) => {
  const year = new Date().getFullYear();
  const { rows } = await pool.query(
    `SELECT lt.id, lt.code, lt.name, lt.annual_quota,
            COALESCE(b.opening, 0) + COALESCE(b.accrued, lt.annual_quota) AS entitled,
            COALESCE(b.used, 0) AS used,
            COALESCE(b.opening, 0) + COALESCE(b.accrued, lt.annual_quota) - COALESCE(b.used, 0) AS available
       FROM leave_types lt
       LEFT JOIN leave_balances b
              ON b.leave_type_id = lt.id AND b.employee_id = $1 AND b.year = $2
      WHERE lt.is_active AND COALESCE(lt.annual_quota, 0) > 0
      ORDER BY lt.sort_order, lt.name`,
    [req.user.id, year]
  );
  res.json(rows);
}));

/** Leave types plus the signed-in user's current-year balance for each. */
router.get('/types', ah(async (req, res) => {
  const year = Number(req.query.year) || new Date().getFullYear();
  const { rows } = await pool.query(
    `SELECT lt.id, lt.code, lt.name, lt.annual_quota, lt.is_paid, lt.carry_forward,
            COALESCE(b.opening, 0) AS opening,
            COALESCE(b.accrued, lt.annual_quota) AS entitled,
            COALESCE(b.used, 0) AS used,
            COALESCE(b.opening, 0) + COALESCE(b.accrued, lt.annual_quota) - COALESCE(b.used, 0) AS available,
            -- Days locked in applications not yet decided.
            COALESCE((SELECT SUM(l.days) FROM leaves l
                       WHERE l.employee_id = $1 AND l.leave_type_id = lt.id
                         AND l.status IN ('submitted', 'reviewed')
                         AND EXTRACT(YEAR FROM l.from_date) = $2), 0) AS pending
       FROM leave_types lt
       LEFT JOIN leave_balances b
              ON b.leave_type_id = lt.id AND b.employee_id = $1 AND b.year = $2
      WHERE lt.is_active
      ORDER BY lt.sort_order, lt.name`,
    [req.user.id, year]
  );
  res.json(rows);
}));

const applySchema = z.object({
  leave_type_id: z.coerce.number().int().positive(),
  from_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'From date must be YYYY-MM-DD'),
  to_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'To date must be YYYY-MM-DD'),
  is_half_day: z.coerce.boolean().optional(),
  reason: z.string().trim().min(5, 'Please give a reason of at least 5 characters'),
  address_on_leave: z.string().trim().max(500).optional(),
  contact_on_leave: z.string().trim().max(100).optional(),
  handover_to_id: z.coerce.number().int().positive().optional(),
});

/** Apply for leave. Goes straight to `submitted` — the manager reviews next. */
router.post('/', ah(async (req, res) => {
  const b = parse(applySchema, req.body);
  if (b.to_date < b.from_date) throw httpError(400, 'The end date cannot be before the start date');

  const days = await chargeableDays(b.from_date, b.to_date, b.is_half_day);
  if (days <= 0) {
    throw httpError(400, 'That period contains no working days — please check the dates');
  }

  // Block double-booking against anything not already rejected/cancelled.
  const { rows: clash } = await pool.query(
    `SELECT id, from_date, to_date FROM leaves
      WHERE employee_id = $1 AND status IN ('submitted','reviewed','approved')
        AND from_date <= $3 AND to_date >= $2
      LIMIT 1`,
    [req.user.id, b.from_date, b.to_date]
  );
  if (clash[0]) {
    throw httpError(409,
      `You already have a leave application covering ${clash[0].from_date} to ${clash[0].to_date}`);
  }

  const { rows: types } = await pool.query(
    'SELECT name, annual_quota FROM leave_types WHERE id = $1 AND is_active',
    [b.leave_type_id]
  );
  if (!types[0]) throw httpError(400, 'That leave type is not available');

  const { rows } = await pool.query(
    `INSERT INTO leaves (employee_id, leave_type_id, from_date, to_date, days, is_half_day,
                         reason, address_on_leave, contact_on_leave, handover_to_id, status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'submitted')
     RETURNING id`,
    [req.user.id, b.leave_type_id, b.from_date, b.to_date, days, !!b.is_half_day,
     b.reason, b.address_on_leave ?? null, b.contact_on_leave ?? null, b.handover_to_id ?? null]
  );

  const { rows: full } = await pool.query(`${LEAVE_SELECT} WHERE l.id = $1`, [rows[0].id]);
  res.status(201).json(full[0]);
}));

/**
 * Listing. `scope=mine` (default) returns own applications; `scope=inbox`
 * returns what this user must act on next, which is the screen managers and the
 * authority actually work from.
 */
router.get('/', ah(async (req, res) => {
  const scope = req.query.scope || 'mine';
  const params = [];
  let where;

  if (scope === 'mine') {
    params.push(req.user.id);
    where = 'l.employee_id = $1';
  } else if (scope === 'inbox') {
    if (req.user.role === 'staff') return res.json([]);
    if (req.user.role === 'manager') {
      // A manager reviews their reportees' submitted applications.
      params.push(req.user.id);
      where = `l.status = 'submitted' AND e.reporting_to_id = $1 AND l.employee_id <> $1`;
    } else {
      // Authority/admin: anything submitted or reviewed, except their own.
      params.push(req.user.id);
      where = `l.status IN ('submitted', 'reviewed') AND l.employee_id <> $1`;
    }
  } else if (scope === 'team') {
    if (req.user.role === 'manager') {
      params.push(req.user.id);
      where = '(e.reporting_to_id = $1 OR l.employee_id = $1)';
    } else if (req.user.role === 'staff') {
      params.push(req.user.id);
      where = 'l.employee_id = $1';
    } else {
      where = 'TRUE';
    }
  } else {
    throw httpError(400, 'scope must be mine, inbox or team');
  }

  if (req.query.status) {
    params.push(req.query.status);
    where += ` AND l.status = $${params.length}`;
  }

  const { rows } = await pool.query(
    `${LEAVE_SELECT} WHERE ${where} ORDER BY l.created_at DESC LIMIT 200`, params
  );
  res.json(rows);
}));

/**
 * Approved leaves across the org for the calendar view, so staff can see who
 * else is away before choosing their own dates.
 */
router.get('/calendar', ah(async (req, res) => {
  const now = new Date();
  const year = Number(req.query.year) || now.getFullYear();
  const month = Number(req.query.month) || now.getMonth() + 1;
  const first = `${year}-${String(month).padStart(2, '0')}-01`;
  const last = `${year}-${String(month).padStart(2, '0')}-${String(new Date(year, month, 0).getDate()).padStart(2, '0')}`;

  const [{ rows: leaves }, { rows: holidays }] = await Promise.all([
    pool.query(
      `SELECT l.id, l.employee_id, l.from_date, l.to_date, l.days, l.status,
              lt.code AS leave_type_code, lt.name AS leave_type_name,
              e.full_name, e.emp_code, e.designation, e.photo_url
         FROM leaves l
         JOIN leave_types lt ON lt.id = l.leave_type_id
         JOIN employees e ON e.id = l.employee_id
        WHERE l.status IN ('approved', 'reviewed', 'submitted')
          AND l.from_date <= $2 AND l.to_date >= $1
        ORDER BY l.from_date`,
      [first, last]
    ),
    pool.query('SELECT holiday_on, name, kind FROM holidays WHERE holiday_on BETWEEN $1 AND $2', [first, last]),
  ]);

  // Expand each spell into per-day entries the calendar can index directly.
  const byDate = {};
  for (const l of leaves) {
    for (const d of dateRange(
      l.from_date < first ? first : l.from_date,
      l.to_date > last ? last : l.to_date
    )) {
      (byDate[d] ||= []).push({
        leave_id: l.id, employee_id: l.employee_id, full_name: l.full_name,
        emp_code: l.emp_code, designation: l.designation, photo_url: l.photo_url,
        leave_type_code: l.leave_type_code, leave_type_name: l.leave_type_name,
        status: l.status,
      });
    }
  }

  res.json({ year, month, by_date: byDate, leaves, holidays });
}));

router.get('/:id', ah(async (req, res) => {
  const { rows } = await pool.query(`${LEAVE_SELECT} WHERE l.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Leave application not found');
  if (!canView(req.user, row)) throw httpError(403, 'You cannot view this application');
  res.json(row);
}));

const decisionSchema = z.object({
  decision: z.string(),
  remark: z.string().trim().max(2000).optional(),
});

router.put('/:id/review', requireRole('manager'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { rows } = await pool.query(`${LEAVE_SELECT} WHERE l.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Leave application not found');
  if (!canReview(req.user, row)) {
    throw httpError(403, 'You are not the reporting officer for this application');
  }

  await review('leaves', row.id, req.user, b);
  const { rows: after } = await pool.query(`${LEAVE_SELECT} WHERE l.id = $1`, [row.id]);
  res.json(after[0]);
}));

router.put('/:id/approve', requireRole('authority'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { rows } = await pool.query(`${LEAVE_SELECT} WHERE l.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Leave application not found');
  if (!canApprove(req.user, row)) throw httpError(403, 'You cannot approve this application');

  const updated = await approve('leaves', row.id, req.user, b);

  // Debit the balance only once the leave is actually sanctioned.
  if (updated.status === 'approved') {
    await pool.query(
      `INSERT INTO leave_balances (employee_id, leave_type_id, year, accrued, used)
       VALUES ($1, $2, $3,
               (SELECT annual_quota FROM leave_types WHERE id = $2), $4)
       ON CONFLICT (employee_id, leave_type_id, year)
       DO UPDATE SET used = leave_balances.used + $4`,
      [row.employee_id, row.leave_type_id, Number(String(row.from_date).slice(0, 4)), row.days]
    );
  }

  const { rows: after } = await pool.query(`${LEAVE_SELECT} WHERE l.id = $1`, [row.id]);
  res.json(after[0]);
}));

/** Applicant withdraws their own application before it is decided. */
router.put('/:id/cancel', ah(async (req, res) => {
  const { rows } = await pool.query(
    `UPDATE leaves SET status = 'cancelled', updated_at = NOW()
      WHERE id = $1 AND employee_id = $2 AND status IN ('draft', 'submitted', 'reviewed')
      RETURNING id`,
    [req.params.id, req.user.id]
  );
  if (!rows[0]) {
    throw httpError(409, 'Only your own applications that are not yet decided can be cancelled');
  }
  res.json({ ok: true });
}));

/** The approved leave letter, on foundation letterhead with signatures. */
router.get('/:id/letter.pdf', ah(async (req, res) => {
  const { rows } = await pool.query(`${LEAVE_SELECT} WHERE l.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Leave application not found');
  if (!canView(req.user, row)) throw httpError(403, 'You cannot download this document');
  if (row.status !== 'approved') {
    throw httpError(409, 'The letter is available only after the leave is approved');
  }

  const fileNo = await ensureFileNo('leaves', row, req.user);
  const { reviewer, approver } = await loadSignatories(row);

  const pdf = await buildLeaveLetter({
    leave: { ...row, file_no: fileNo },
    employee: row,
    reviewer,
    approver,
    handover: row.handover_name ? { full_name: row.handover_name } : null,
    fileNo,
  });
  sendPdf(res, pdf, `NESF-Leave-${row.emp_code}-${row.from_date}.pdf`);
}));

export default router;
