import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireRole, requireAdmin } from '../middleware/auth.js';
import { uploadImage, uploadSignature, saveUpload, validateSignatureDimensions } from '../services/storage.js';
import { ah, parse, httpError, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

const LIST_SELECT = `
  SELECT e.id, e.emp_code, e.full_name, e.email, e.phone, e.role, e.designation,
         e.department, e.grade, e.date_of_joining, e.reporting_to_id, e.photo_url,
         e.signature_title, e.base_label, e.is_active, e.last_login_at,
         (e.signature_url IS NOT NULL) AS has_signature,
         m.full_name AS reporting_to_name
    FROM employees e
    LEFT JOIN employees m ON m.id = e.reporting_to_id
`;

/**
 * Staff directory. Everyone may browse it — staff need it to pick a handover
 * person and to know who their reporting officer is.
 */
router.get('/', ah(async (req, res) => {
  const params = [];
  let where = req.query.include_inactive === 'true' ? 'TRUE' : 'e.is_active';
  if (req.query.q) {
    params.push(`%${req.query.q}%`);
    const i = params.length;
    where += ` AND (e.full_name ILIKE $${i} OR e.emp_code ILIKE $${i} OR e.designation ILIKE $${i})`;
  }
  if (req.query.department) {
    params.push(req.query.department);
    where += ` AND e.department = $${params.length}`;
  }
  const { rows } = await pool.query(`${LIST_SELECT} WHERE ${where} ORDER BY e.full_name`, params);
  res.json(rows);
}));

/** Reporting tree, for the org chart screen. */
router.get('/org-chart', ah(async (req, res) => {
  const { rows } = await pool.query(
    `${LIST_SELECT} WHERE e.is_active ORDER BY e.reporting_to_id NULLS FIRST, e.full_name`
  );
  // Assemble parent -> children in one pass; roots are those with no manager.
  const byId = new Map(rows.map((r) => [String(r.id), { ...r, reports: [] }]));
  const roots = [];
  for (const node of byId.values()) {
    const parent = node.reporting_to_id ? byId.get(String(node.reporting_to_id)) : null;
    if (parent) parent.reports.push(node);
    else roots.push(node);
  }
  res.json(roots);
}));

router.get('/:id', ah(async (req, res) => {
  const { rows } = await pool.query(`${LIST_SELECT} WHERE e.id = $1`, [req.params.id]);
  if (!rows[0]) throw httpError(404, 'Employee not found');
  res.json(rows[0]);
}));

const employeeSchema = z.object({
  emp_code: z.string().trim().min(1, 'Employee code is required').max(30),
  full_name: z.string().trim().min(2, 'Full name is required'),
  email: z.string().trim().email('Enter a valid email address'),
  phone: z.string().trim().max(20).optional(),
  role: z.enum(['staff', 'manager', 'authority', 'admin']).default('staff'),
  designation: z.string().trim().max(150).optional(),
  department: z.string().trim().max(150).optional(),
  grade: z.string().trim().max(50).optional(),
  date_of_joining: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  reporting_to_id: z.coerce.number().int().positive().optional(),
  signature_title: z.string().trim().max(150).optional(),
  base_lat: z.coerce.number().min(-90).max(90).optional(),
  base_lng: z.coerce.number().min(-180).max(180).optional(),
  base_label: z.string().trim().max(200).optional(),
  is_active: z.coerce.boolean().default(true),
  // Only set on create, or when an admin resets a password.
  password: z.string().min(8, 'Password must be at least 8 characters').optional(),
});

router.post('/', requireAdmin, ah(async (req, res) => {
  const b = parse(employeeSchema, req.body);
  if (!b.password) throw httpError(400, 'An initial password is required for a new employee');

  const { rows } = await pool.query(
    `INSERT INTO employees (emp_code, full_name, email, phone, password_hash, role, designation,
        department, grade, date_of_joining, reporting_to_id, signature_title,
        base_lat, base_lng, base_label, is_active, must_change_pw)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,TRUE)
     RETURNING id`,
    [b.emp_code, b.full_name, b.email, b.phone ?? null, await bcrypt.hash(b.password, 10),
     b.role, b.designation ?? null, b.department ?? null, b.grade ?? null,
     b.date_of_joining ?? null, b.reporting_to_id ?? null, b.signature_title ?? null,
     b.base_lat ?? null, b.base_lng ?? null, b.base_label ?? null, b.is_active]
  ).catch((err) => {
    if (err.code === '23505') {
      throw httpError(409, 'An employee with that code or email already exists');
    }
    throw err;
  });

  const { rows: full } = await pool.query(`${LIST_SELECT} WHERE e.id = $1`, [rows[0].id]);
  res.status(201).json(full[0]);
}));

router.put('/:id', requireAdmin, ah(async (req, res) => {
  const b = parse(employeeSchema, req.body);

  // Guard against a reporting cycle, which would make the org chart recurse.
  if (b.reporting_to_id && String(b.reporting_to_id) === String(req.params.id)) {
    throw httpError(400, 'An employee cannot report to themselves');
  }

  const { rows } = await pool.query(
    `UPDATE employees SET emp_code=$1, full_name=$2, email=$3, phone=$4, role=$5,
        designation=$6, department=$7, grade=$8, date_of_joining=$9, reporting_to_id=$10,
        signature_title=$11, base_lat=$12, base_lng=$13, base_label=$14, is_active=$15,
        password_hash = COALESCE($16, password_hash),
        must_change_pw = CASE WHEN $16 IS NOT NULL THEN TRUE ELSE must_change_pw END,
        updated_at = NOW()
      WHERE id = $17 RETURNING id`,
    [b.emp_code, b.full_name, b.email, b.phone ?? null, b.role, b.designation ?? null,
     b.department ?? null, b.grade ?? null, b.date_of_joining ?? null,
     b.reporting_to_id ?? null, b.signature_title ?? null, b.base_lat ?? null,
     b.base_lng ?? null, b.base_label ?? null, b.is_active,
     b.password ? await bcrypt.hash(b.password, 10) : null, req.params.id]
  );
  if (!rows[0]) throw httpError(404, 'Employee not found');

  // A password reset invalidates that person's other devices.
  if (b.password) {
    await pool.query(
      'UPDATE sessions SET revoked_at = NOW() WHERE employee_id = $1 AND revoked_at IS NULL',
      [req.params.id]
    );
  }

  const { rows: full } = await pool.query(`${LIST_SELECT} WHERE e.id = $1`, [rows[0].id]);
  res.json(full[0]);
}));

/** Profile photo — own, or anyone's if admin. */
router.post('/:id/photo', uploadImage.single('photo'), ah(async (req, res) => {
  if (String(req.params.id) !== String(req.user.id) && req.user.role !== 'admin') {
    throw httpError(403, 'You can only change your own photo');
  }
  if (!req.file) throw httpError(400, 'No photo was uploaded');
  const url = await saveUpload(req.file, 'photos');
  await pool.query('UPDATE employees SET photo_url = $1, updated_at = NOW() WHERE id = $2',
    [url, req.params.id]);
  res.json({ photo_url: url });
}));

/**
 * Scanned signature upload. This image is what gets stamped onto every document
 * this person approves, so only the person themselves or an admin may set it.
 */
router.post('/:id/signature', uploadSignature.single('signature'), ah(async (req, res) => {
  if (String(req.params.id) !== String(req.user.id) && req.user.role !== 'admin') {
    throw httpError(403, 'You can only upload your own signature');
  }
  if (!req.file) throw httpError(400, 'No signature image was uploaded');

  // Validate image dimensions (signatures should be ~150x50 px, allow 50-200 x 20-100).
  const dimensionError = await validateSignatureDimensions(req.file.buffer);
  if (dimensionError) throw httpError(400, dimensionError);

  // A transparent PNG reproduces best on letterhead; warn rather than reject.
  const url = await saveUpload(req.file, 'signatures');
  await pool.query('UPDATE employees SET signature_url = $1, updated_at = NOW() WHERE id = $2',
    [url, req.params.id]);
  res.json({
    signature_url: url,
    note: req.file.mimetype === 'image/png' ? null
      : 'For the cleanest result on letterhead, upload a PNG with a transparent background.',
  });
}));

/** Base location for the attendance geofence — set from the device's GPS. */
router.put('/:id/base-location', ah(async (req, res) => {
  if (String(req.params.id) !== String(req.user.id) && req.user.role !== 'admin') {
    throw httpError(403, 'You can only set your own base location');
  }
  const schema = z.object({
    base_lat: z.coerce.number().min(-90).max(90),
    base_lng: z.coerce.number().min(-180).max(180),
    base_label: z.string().trim().max(200).optional(),
  });
  const b = parse(schema, req.body);
  await pool.query(
    'UPDATE employees SET base_lat=$1, base_lng=$2, base_label=$3, updated_at=NOW() WHERE id=$4',
    [b.base_lat, b.base_lng, b.base_label ?? null, req.params.id]
  );
  res.json({ ok: true });
}));

export default router;
