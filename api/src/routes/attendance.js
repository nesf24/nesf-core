import { Router } from 'express';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireRole, requireAdmin } from '../middleware/auth.js';
import { uploadImage, saveUpload } from '../services/storage.js';
import { buildAttendanceMuster } from '../services/documents.js';
import { nextFileNo } from '../services/letterhead.js';
import {
  ah, parse, httpError, distanceMetres, istToday, istDateString,
  dateRange, isoWeekday, sendPdf, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

async function getSettings() {
  const { rows } = await pool.query(
    'SELECT geofence_radius_m, office_lat, office_lng, work_start, work_end, weekly_offs FROM settings WHERE id = 1'
  );
  return rows[0];
}

// Multipart fields arrive as strings; coerce and bound-check the geo values.
const geoSchema = z.object({
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
  accuracy: z.coerce.number().min(0).optional(),
  place: z.string().trim().max(300).optional(),
  work_mode: z.enum(['office', 'field', 'wfh']).optional(),
  notes: z.string().trim().max(1000).optional(),
});

/**
 * Check in for today. The selfie is required — it is the proof of presence that
 * pairs with the GPS fix. Re-checking in on the same day is rejected rather than
 * overwriting, so the first punch of the day is the one on record.
 */
router.post('/check-in', uploadImage.single('selfie'), ah(async (req, res) => {
  const body = parse(geoSchema, req.body);
  if (!req.file) throw httpError(400, 'A selfie photo is required to check in');

  const today = istToday();
  const { rows: existing } = await pool.query(
    'SELECT id, check_in_at FROM attendance WHERE employee_id = $1 AND work_date = $2',
    [req.user.id, today]
  );
  if (existing[0]?.check_in_at) {
    throw httpError(409, 'You have already checked in today');
  }

  const settings = await getSettings();
  // Prefer the employee's own base location, falling back to the office.
  const baseLat = req.user.base_lat ?? settings.office_lat;
  const baseLng = req.user.base_lng ?? settings.office_lng;
  const distance = distanceMetres(body.lat, body.lng, baseLat, baseLng);
  const offsite = distance != null && distance > settings.geofence_radius_m;

  const selfieUrl = await saveUpload(req.file, `attendance/${today.slice(0, 7)}`);

  // Someone away from base is doing field duty unless they said work-from-home.
  const workMode = body.work_mode || (offsite ? 'field' : 'office');

  const { rows } = await pool.query(
    `INSERT INTO attendance (
        employee_id, work_date, work_mode,
        check_in_at, check_in_lat, check_in_lng, check_in_accuracy,
        check_in_place, check_in_selfie, check_in_distance, check_in_offsite, notes)
     VALUES ($1, $2, $3, NOW(), $4, $5, $6, $7, $8, $9, $10, $11)
     ON CONFLICT (employee_id, work_date) DO UPDATE SET
        work_mode = EXCLUDED.work_mode,
        check_in_lat = EXCLUDED.check_in_lat,
        check_in_lng = EXCLUDED.check_in_lng,
        check_in_accuracy = EXCLUDED.check_in_accuracy,
        check_in_place = EXCLUDED.check_in_place,
        check_in_selfie = EXCLUDED.check_in_selfie,
        check_in_distance = EXCLUDED.check_in_distance,
        check_in_offsite = EXCLUDED.check_in_offsite,
        notes = EXCLUDED.notes,
        updated_at = NOW()
     WHERE attendance.check_in_at IS NULL
     RETURNING *`,
    [req.user.id, today, workMode, body.lat ?? null, body.lng ?? null,
     body.accuracy ?? null, body.place ?? null, selfieUrl, distance, offsite,
     body.notes ?? null]
  );

  res.status(201).json({
    ...rows[0],
    // Surfaced so the app can warn the user their punch was flagged off-site.
    offsite_warning: offsite
      ? `Checked in ${(distance / 1000).toFixed(1)} km from your base location — recorded as ${workMode} duty.`
      : null,
  });
}));

router.post('/check-out', uploadImage.single('selfie'), ah(async (req, res) => {
  const body = parse(geoSchema, req.body);
  const today = istToday();

  const { rows: existing } = await pool.query(
    'SELECT * FROM attendance WHERE employee_id = $1 AND work_date = $2',
    [req.user.id, today]
  );
  const row = existing[0];
  if (!row?.check_in_at) throw httpError(409, 'You have not checked in today');
  if (row.check_out_at) throw httpError(409, 'You have already checked out today');

  const selfieUrl = req.file ? await saveUpload(req.file, `attendance/${today.slice(0, 7)}`) : null;

  const { rows } = await pool.query(
    `UPDATE attendance SET
        check_out_at = NOW(), check_out_lat = $1, check_out_lng = $2,
        check_out_place = $3, check_out_selfie = COALESCE($4, check_out_selfie),
        notes = COALESCE($5, notes),
        minutes_worked = GREATEST(0, ROUND(EXTRACT(EPOCH FROM (NOW() - check_in_at)) / 60))::int,
        updated_at = NOW()
      WHERE id = $6
      RETURNING *`,
    [body.lat ?? null, body.lng ?? null, body.place ?? null, selfieUrl,
     body.notes ?? null, row.id]
  );
  res.json(rows[0]);
}));

/** Today's punch state — drives the check-in/out button in the app. */
router.get('/today', ah(async (req, res) => {
  const today = istToday();
  const { rows } = await pool.query(
    'SELECT * FROM attendance WHERE employee_id = $1 AND work_date = $2',
    [req.user.id, today]
  );
  const settings = await getSettings();
  res.json({
    date: today,
    attendance: rows[0] || null,
    can_check_in: !rows[0]?.check_in_at,
    can_check_out: !!rows[0]?.check_in_at && !rows[0]?.check_out_at,
    geofence_radius_m: settings.geofence_radius_m,
    base: {
      lat: req.user.base_lat ?? settings.office_lat,
      lng: req.user.base_lng ?? settings.office_lng,
      label: req.user.base_label || 'Foundation Office',
    },
  });
}));

/** Own attendance history, newest first. */
router.get('/me', ah(async (req, res) => {
  const from = req.query.from || istDateString(new Date(Date.now() - 30 * 86_400_000));
  const to = req.query.to || istToday();
  const { rows } = await pool.query(
    `SELECT * FROM attendance
      WHERE employee_id = $1 AND work_date BETWEEN $2 AND $3
      ORDER BY work_date DESC`,
    [req.user.id, from, to]
  );
  res.json(rows);
}));

/**
 * Builds the day-by-day state grid for a month, resolving each date to exactly
 * one of: present/field/wfh (from a punch), leave (from an approved leave),
 * holiday, weekly_off, absent, or future.
 */
async function buildMonthGrid({ year, month, employeeIds }) {
  const first = `${year}-${String(month).padStart(2, '0')}-01`;
  const daysInMonth = new Date(year, month, 0).getDate();
  const last = `${year}-${String(month).padStart(2, '0')}-${String(daysInMonth).padStart(2, '0')}`;
  const today = istToday();
  const settings = await getSettings();
  const weeklyOffs = new Set(settings.weekly_offs || [7]);

  const [{ rows: staff }, { rows: punches }, { rows: leaveRows }, { rows: holidayRows }] =
    await Promise.all([
      pool.query(
        `SELECT id, emp_code, full_name, designation, department
           FROM employees
          WHERE ($1::bigint[] IS NULL OR id = ANY($1::bigint[]))
            AND (is_active OR id = ANY(COALESCE($1::bigint[], '{}')))
          ORDER BY full_name`,
        [employeeIds && employeeIds.length ? employeeIds : null]
      ),
      pool.query(
        `SELECT employee_id, work_date, work_mode, check_in_at, check_out_at,
                minutes_worked, check_in_offsite
           FROM attendance
          WHERE work_date BETWEEN $1 AND $2
            AND ($3::bigint[] IS NULL OR employee_id = ANY($3::bigint[]))`,
        [first, last, employeeIds && employeeIds.length ? employeeIds : null]
      ),
      pool.query(
        `SELECT l.employee_id, l.from_date, l.to_date, lt.code AS leave_code, lt.name AS leave_name
           FROM leaves l JOIN leave_types lt ON lt.id = l.leave_type_id
          WHERE l.status = 'approved'
            AND l.from_date <= $2 AND l.to_date >= $1
            AND ($3::bigint[] IS NULL OR l.employee_id = ANY($3::bigint[]))`,
        [first, last, employeeIds && employeeIds.length ? employeeIds : null]
      ),
      pool.query('SELECT holiday_on, name FROM holidays WHERE holiday_on BETWEEN $1 AND $2', [first, last]),
    ]);

  const holidays = new Map(holidayRows.map((h) => [h.holiday_on, h.name]));
  const punchBy = new Map();
  for (const p of punches) punchBy.set(`${p.employee_id}|${p.work_date}`, p);

  const leaveBy = new Map();
  for (const l of leaveRows) {
    for (const d of dateRange(l.from_date, l.to_date)) {
      leaveBy.set(`${l.employee_id}|${d}`, l);
    }
  }

  const allDates = dateRange(first, last);

  const rows = staff.map((s) => {
    const marks = {};
    const summary = { present: 0, leave: 0, absent: 0, holiday: 0, off: 0, minutes: 0 };

    for (const date of allDates) {
      const day = Number(date.slice(8, 10));
      const punch = punchBy.get(`${s.id}|${date}`);

      if (punch?.check_in_at) {
        // A punch always wins: the person demonstrably worked that day.
        marks[day] = punch.work_mode === 'field' ? 'field'
          : punch.work_mode === 'wfh' ? 'wfh' : 'present';
        summary.present++;
        summary.minutes += punch.minutes_worked || 0;
        continue;
      }
      if (leaveBy.has(`${s.id}|${date}`)) {
        marks[day] = 'leave';
        summary.leave++;
        continue;
      }
      if (holidays.has(date)) {
        marks[day] = 'holiday';
        summary.holiday++;
        continue;
      }
      if (weeklyOffs.has(isoWeekday(date))) {
        marks[day] = 'weekly_off';
        summary.off++;
        continue;
      }
      if (date > today) {
        // Don't brand a future date as absent.
        marks[day] = 'future';
        continue;
      }
      marks[day] = 'absent';
      summary.absent++;
    }

    return { ...s, marks, summary };
  });

  return { rows, days: daysInMonth, first, last, holidays: holidayRows };
}

/** Month grid for the calendar screen. Staff see themselves; managers see their team. */
router.get('/calendar', ah(async (req, res) => {
  const now = new Date();
  const year = Number(req.query.year) || now.getFullYear();
  const month = Number(req.query.month) || now.getMonth() + 1;

  let employeeIds = [req.user.id];
  if (req.query.scope === 'team' && ['manager', 'authority', 'admin'].includes(req.user.role)) {
    // Authority/admin see everyone; a manager sees themselves plus reportees.
    if (req.user.role === 'manager') {
      const { rows } = await pool.query(
        'SELECT id FROM employees WHERE reporting_to_id = $1 OR id = $1',
        [req.user.id]
      );
      employeeIds = rows.map((r) => r.id);
    } else {
      employeeIds = null;
    }
  } else if (req.query.employee_id && ['manager', 'authority', 'admin'].includes(req.user.role)) {
    employeeIds = [Number(req.query.employee_id)];
  }

  const grid = await buildMonthGrid({ year, month, employeeIds });
  res.json({ year, month, ...grid });
}));

/** Monthly muster roll PDF on foundation letterhead. */
router.get('/muster.pdf', requireRole('manager'), ah(async (req, res) => {
  const now = new Date();
  const year = Number(req.query.year) || now.getFullYear();
  const month = Number(req.query.month) || now.getMonth() + 1;

  let employeeIds = null;
  let single = null;
  if (req.query.employee_id) {
    employeeIds = [Number(req.query.employee_id)];
    const { rows } = await pool.query(
      'SELECT full_name, emp_code, designation FROM employees WHERE id = $1', employeeIds
    );
    single = rows[0];
  } else if (req.user.role === 'manager') {
    const { rows } = await pool.query(
      'SELECT id FROM employees WHERE reporting_to_id = $1 OR id = $1', [req.user.id]
    );
    employeeIds = rows.map((r) => r.id);
  }

  const grid = await buildMonthGrid({ year, month, employeeIds });
  if (!grid.rows.length) throw httpError(404, 'No staff records found for that month');

  // The muster is a register rather than an approved submission, so it takes a
  // fresh file number each time it is certified and issued.
  const fileNo = await nextFileNo('attendance_muster', 'attendance', null, req.user.id);

  const { rows: auth } = await pool.query(
    `SELECT full_name, designation, signature_url, signature_title
       FROM employees
      WHERE role IN ('authority', 'admin') AND is_active AND signature_url IS NOT NULL
      ORDER BY CASE role WHEN 'authority' THEN 0 ELSE 1 END, id
      LIMIT 1`
  );

  const pdf = await buildAttendanceMuster({
    month, year, rows: grid.rows, days: grid.days,
    authority: auth[0] || null, fileNo, employee: single,
  });
  sendPdf(res, pdf, `NESF-Attendance-${year}-${String(month).padStart(2, '0')}.pdf`);
}));

/** Org-wide daily view for the office — who is in, who is out, who is on leave. */
router.get('/', requireRole('manager'), ah(async (req, res) => {
  const date = req.query.date || istToday();
  const { rows } = await pool.query(
    `SELECT a.*, e.full_name, e.emp_code, e.designation, e.department
       FROM attendance a JOIN employees e ON e.id = a.employee_id
      WHERE a.work_date = $1
        AND ($2::text IS NULL OR e.department = $2)
      ORDER BY a.check_in_at`,
    [date, req.query.department || null]
  );

  const { rows: absent } = await pool.query(
    `SELECT e.id, e.full_name, e.emp_code, e.designation,
            CASE WHEN l.id IS NOT NULL THEN 'leave' ELSE 'absent' END AS state,
            lt.name AS leave_name
       FROM employees e
       LEFT JOIN leaves l ON l.employee_id = e.id AND l.status = 'approved'
                         AND $1 BETWEEN l.from_date AND l.to_date
       LEFT JOIN leave_types lt ON lt.id = l.leave_type_id
      WHERE e.is_active
        AND NOT EXISTS (SELECT 1 FROM attendance a
                         WHERE a.employee_id = e.id AND a.work_date = $1
                           AND a.check_in_at IS NOT NULL)
      ORDER BY e.full_name`,
    [date]
  );

  res.json({
    date,
    present: rows,
    not_present: absent,
    summary: {
      present: rows.length,
      on_leave: absent.filter((a) => a.state === 'leave').length,
      absent: absent.filter((a) => a.state === 'absent').length,
      field_duty: rows.filter((r) => r.work_mode === 'field').length,
    },
  });
}));

const editSchema = z.object({
  employee_id: z.coerce.number().int().positive(),
  work_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD'),
  work_mode: z.enum(['office', 'field', 'wfh']).optional(),
  check_in_at: z.string().optional(),
  check_out_at: z.string().optional(),
  place: z.string().max(300).optional(),
  reason: z.string().trim().min(3, 'A reason for the correction is required'),
});

/**
 * Admin regularisation for a missed punch. Every edit is written to
 * attendance_edits with the before/after snapshot, since attendance underpins
 * salary and TA/DA claims.
 */
router.post('/regularise', requireAdmin, ah(async (req, res) => {
  const b = parse(editSchema, req.body);

  const { rows: before } = await pool.query(
    'SELECT * FROM attendance WHERE employee_id = $1 AND work_date = $2',
    [b.employee_id, b.work_date]
  );

  const { rows } = await pool.query(
    `INSERT INTO attendance (employee_id, work_date, work_mode, check_in_at, check_out_at, check_in_place, notes)
     VALUES ($1, $2, COALESCE($3, 'office'), $4, $5, $6, $7)
     ON CONFLICT (employee_id, work_date) DO UPDATE SET
        work_mode = COALESCE($3, attendance.work_mode),
        check_in_at = COALESCE($4, attendance.check_in_at),
        check_out_at = COALESCE($5, attendance.check_out_at),
        check_in_place = COALESCE($6, attendance.check_in_place),
        notes = $7,
        minutes_worked = CASE
          WHEN COALESCE($5, attendance.check_out_at) IS NOT NULL
           AND COALESCE($4, attendance.check_in_at) IS NOT NULL
          THEN GREATEST(0, ROUND(EXTRACT(EPOCH FROM (
                 COALESCE($5, attendance.check_out_at) - COALESCE($4, attendance.check_in_at))) / 60))::int
          ELSE attendance.minutes_worked END,
        updated_at = NOW()
     RETURNING *`,
    [b.employee_id, b.work_date, b.work_mode ?? null,
     b.check_in_at ?? null, b.check_out_at ?? null, b.place ?? null,
     `Regularised: ${b.reason}`]
  );

  await pool.query(
    `INSERT INTO attendance_edits (attendance_id, edited_by, reason, before_json, after_json)
     VALUES ($1, $2, $3, $4, $5)`,
    [rows[0].id, req.user.id, b.reason,
     before[0] ? JSON.stringify(before[0]) : null, JSON.stringify(rows[0])]
  );

  res.json(rows[0]);
}));

export default router;
