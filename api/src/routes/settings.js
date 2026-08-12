import { Router } from 'express';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireAdmin } from '../middleware/auth.js';
import { ah, parse, httpError, toPaise, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

router.get('/', ah(async (req, res) => {
  const { rows } = await pool.query('SELECT * FROM settings WHERE id = 1');
  res.json(rows[0]);
}));

const settingsSchema = z.object({
  org_name: z.string().trim().min(2),
  tagline: z.string().trim().max(200),
  registration: z.string().trim().max(300),
  websites: z.string().trim().max(200),
  email: z.string().trim().max(150),
  mobile: z.string().trim().max(60),
  cin: z.string().trim().max(60),
  gstin: z.string().trim().max(60),
  darpan_id: z.string().trim().max(60),
  address: z.string().trim().max(500).optional(),
  file_no_prefix: z.string().trim().min(1).max(40),
  geofence_radius_m: z.coerce.number().int().min(50).max(20000),
  office_lat: z.coerce.number().min(-90).max(90).optional(),
  office_lng: z.coerce.number().min(-180).max(180).optional(),
  work_start: z.string().regex(/^\d{2}:\d{2}$/, 'Use HH:MM'),
  work_end: z.string().regex(/^\d{2}:\d{2}$/, 'Use HH:MM'),
  weekly_offs: z.array(z.coerce.number().int().min(1).max(7)).max(7),
});

router.put('/', requireAdmin, ah(async (req, res) => {
  const b = parse(settingsSchema, req.body);
  const { rows } = await pool.query(
    `UPDATE settings SET org_name=$1, tagline=$2, registration=$3, websites=$4, email=$5,
        mobile=$6, cin=$7, gstin=$8, darpan_id=$9, address=$10, file_no_prefix=$11,
        geofence_radius_m=$12, office_lat=$13, office_lng=$14, work_start=$15,
        work_end=$16, weekly_offs=$17, updated_at = NOW()
      WHERE id = 1 RETURNING *`,
    [b.org_name, b.tagline, b.registration, b.websites, b.email, b.mobile, b.cin,
     b.gstin, b.darpan_id, b.address ?? null, b.file_no_prefix, b.geofence_radius_m,
     b.office_lat ?? null, b.office_lng ?? null, b.work_start, b.work_end, b.weekly_offs]
  );
  res.json(rows[0]);
}));

// ---------------------------------------------------------------------------
// Holidays — feed both the calendar and the leave-day calculation
// ---------------------------------------------------------------------------
router.get('/holidays', ah(async (req, res) => {
  const year = Number(req.query.year) || new Date().getFullYear();
  const { rows } = await pool.query(
    `SELECT * FROM holidays WHERE EXTRACT(YEAR FROM holiday_on) = $1 ORDER BY holiday_on`,
    [year]
  );
  res.json(rows);
}));

router.post('/holidays', requireAdmin, ah(async (req, res) => {
  const schema = z.object({
    holiday_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date must be YYYY-MM-DD'),
    name: z.string().trim().min(2, 'Holiday name is required'),
    kind: z.enum(['public', 'restricted', 'weekly_off']).default('public'),
  });
  const b = parse(schema, req.body);
  const { rows } = await pool.query(
    `INSERT INTO holidays (holiday_on, name, kind) VALUES ($1, $2, $3)
     ON CONFLICT (holiday_on) DO UPDATE SET name = EXCLUDED.name, kind = EXCLUDED.kind
     RETURNING *`,
    [b.holiday_on, b.name, b.kind]
  );
  res.status(201).json(rows[0]);
}));

router.delete('/holidays/:id', requireAdmin, ah(async (req, res) => {
  const { rows } = await pool.query('DELETE FROM holidays WHERE id = $1 RETURNING id', [req.params.id]);
  if (!rows[0]) throw httpError(404, 'Holiday not found');
  res.json({ ok: true });
}));

// ---------------------------------------------------------------------------
// Leave types & TA/DA rates
// ---------------------------------------------------------------------------
router.put('/leave-types/:id', requireAdmin, ah(async (req, res) => {
  const schema = z.object({
    name: z.string().trim().min(2),
    annual_quota: z.coerce.number().min(0).max(365),
    is_paid: z.coerce.boolean(),
    carry_forward: z.coerce.boolean(),
    is_active: z.coerce.boolean(),
  });
  const b = parse(schema, req.body);
  const { rows } = await pool.query(
    `UPDATE leave_types SET name=$1, annual_quota=$2, is_paid=$3, carry_forward=$4, is_active=$5
      WHERE id = $6 RETURNING *`,
    [b.name, b.annual_quota, b.is_paid, b.carry_forward, b.is_active, req.params.id]
  );
  if (!rows[0]) throw httpError(404, 'Leave type not found');
  res.json(rows[0]);
}));

router.get('/ta-rates', ah(async (req, res) => {
  const [{ rows: ta }, { rows: da }] = await Promise.all([
    pool.query('SELECT * FROM ta_rates ORDER BY mode, grade NULLS FIRST, effective_from DESC'),
    pool.query('SELECT * FROM da_rates ORDER BY grade, area, effective_from DESC'),
  ]);
  res.json({ ta_rates: ta, da_rates: da });
}));

/**
 * Adds a new validity-dated rate rather than editing the old one, so claims
 * already approved keep the rate that was actually applied to them.
 */
router.post('/ta-rates', requireAdmin, ah(async (req, res) => {
  const schema = z.object({
    mode: z.string().trim().min(2).max(30),
    grade: z.string().trim().max(50).optional(),
    per_km: z.coerce.number().min(0),
    actual_fare: z.coerce.boolean().default(false),
    effective_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  });
  const b = parse(schema, req.body);
  const { rows } = await pool.query(
    `INSERT INTO ta_rates (mode, grade, paise_per_km, actual_fare, effective_from)
     VALUES ($1, $2, $3, $4, COALESCE($5::date, CURRENT_DATE)) RETURNING *`,
    [b.mode, b.grade ?? null, toPaise(b.per_km), b.actual_fare, b.effective_from ?? null]
  );
  res.status(201).json(rows[0]);
}));

router.post('/da-rates', requireAdmin, ah(async (req, res) => {
  const schema = z.object({
    grade: z.string().trim().min(1).max(50),
    area: z.enum(['ordinary', 'state_capital', 'metro']).default('ordinary'),
    per_day: z.coerce.number().min(0),
    lodging_cap: z.coerce.number().min(0).default(0),
    effective_from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  });
  const b = parse(schema, req.body);
  const { rows } = await pool.query(
    `INSERT INTO da_rates (grade, area, da_paise_per_day, lodging_cap_paise, effective_from)
     VALUES ($1, $2, $3, $4, COALESCE($5::date, CURRENT_DATE))
     ON CONFLICT (grade, area, effective_from)
     DO UPDATE SET da_paise_per_day = EXCLUDED.da_paise_per_day,
                   lodging_cap_paise = EXCLUDED.lodging_cap_paise
     RETURNING *`,
    [b.grade, b.area, toPaise(b.per_day), toPaise(b.lodging_cap), b.effective_from ?? null]
  );
  res.status(201).json(rows[0]);
}));

/** The document register — every numbered document issued, newest first. */
router.get('/documents', requireAdmin, ah(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT d.*, e.full_name AS issued_by_name
       FROM document_log d LEFT JOIN employees e ON e.id = d.issued_by
      ORDER BY d.year DESC, d.seq DESC LIMIT 500`
  );
  res.json(rows);
}));

export default router;
