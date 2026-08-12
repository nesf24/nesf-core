import { Router } from 'express';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { uploadImage, saveUpload } from '../services/storage.js';
import { buildActivityReport, buildProjectReport } from '../services/documents.js';
import {
  review, approve, canReview, canApprove, canView, loadSignatories, ensureFileNo,
} from '../services/workflow.js';
import { nextFileNo } from '../services/letterhead.js';
import { ah, parse, httpError, toPaise, sendPdf, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------
const projectSchema = z.object({
  code: z.string().trim().min(2, 'Project code is required').max(40),
  name: z.string().trim().min(3, 'Project name is required'),
  description: z.string().trim().max(5000).optional(),
  sport: z.string().trim().max(100).optional(),
  district: z.string().trim().max(100).optional(),
  state: z.string().trim().max(100).optional(),
  start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  budget: z.coerce.number().min(0).default(0),
  funder: z.string().trim().max(200).optional(),
  lead_id: z.coerce.number().int().positive().optional(),
  status: z.enum(['planned', 'active', 'completed', 'on_hold', 'dropped']).default('active'),
});

// Impact rollups come from approved activities only, so unverified numbers never
// reach a project report.
const PROJECT_SELECT = `
  SELECT p.*, l.full_name AS lead_name, l.designation AS lead_designation,
         (SELECT COUNT(*) FROM activities a WHERE a.project_id = p.id AND a.status = 'approved') AS activity_count,
         (SELECT COALESCE(SUM(a.participants_male + a.participants_female + a.participants_other), 0)
            FROM activities a WHERE a.project_id = p.id AND a.status = 'approved') AS participants,
         (SELECT COALESCE(SUM(a.beneficiaries), 0)
            FROM activities a WHERE a.project_id = p.id AND a.status = 'approved') AS beneficiaries,
         (SELECT COALESCE(SUM(a.expenditure_paise), 0)
            FROM activities a WHERE a.project_id = p.id AND a.status = 'approved') AS expenditure_paise
    FROM projects p
    LEFT JOIN employees l ON l.id = p.lead_id
`;

router.get('/', ah(async (req, res) => {
  const params = [];
  let where = 'TRUE';
  if (req.query.status) {
    params.push(req.query.status);
    where += ` AND p.status = $${params.length}`;
  }
  if (req.query.mine === 'true') {
    params.push(req.user.id);
    where += ` AND p.lead_id = $${params.length}`;
  }
  const { rows } = await pool.query(
    `${PROJECT_SELECT} WHERE ${where} ORDER BY p.status, p.start_date DESC NULLS LAST`, params
  );
  res.json(rows);
}));

router.get('/:id', ah(async (req, res) => {
  const { rows } = await pool.query(`${PROJECT_SELECT} WHERE p.id = $1`, [req.params.id]);
  if (!rows[0]) throw httpError(404, 'Project not found');
  res.json(rows[0]);
}));

// Only managers and above define projects; staff report activities against them.
router.post('/', requireRole('manager'), ah(async (req, res) => {
  const b = parse(projectSchema, req.body);
  const { rows } = await pool.query(
    `INSERT INTO projects (code, name, description, sport, district, state,
                           start_date, end_date, budget_paise, funder, lead_id, status)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
     RETURNING id`,
    [b.code, b.name, b.description ?? null, b.sport ?? null, b.district ?? null,
     b.state ?? null, b.start_date ?? null, b.end_date ?? null, toPaise(b.budget),
     b.funder ?? null, b.lead_id ?? null, b.status]
  ).catch((err) => {
    // 23505 = the unique project code already exists.
    if (err.code === '23505') throw httpError(409, `Project code "${b.code}" is already in use`);
    throw err;
  });
  const { rows: full } = await pool.query(`${PROJECT_SELECT} WHERE p.id = $1`, [rows[0].id]);
  res.status(201).json(full[0]);
}));

router.put('/:id', requireRole('manager'), ah(async (req, res) => {
  const b = parse(projectSchema, req.body);
  const { rows } = await pool.query(
    `UPDATE projects SET code=$1, name=$2, description=$3, sport=$4, district=$5, state=$6,
            start_date=$7, end_date=$8, budget_paise=$9, funder=$10, lead_id=$11, status=$12,
            updated_at = NOW()
      WHERE id = $13 RETURNING id`,
    [b.code, b.name, b.description ?? null, b.sport ?? null, b.district ?? null,
     b.state ?? null, b.start_date ?? null, b.end_date ?? null, toPaise(b.budget),
     b.funder ?? null, b.lead_id ?? null, b.status, req.params.id]
  );
  if (!rows[0]) throw httpError(404, 'Project not found');
  const { rows: full } = await pool.query(`${PROJECT_SELECT} WHERE p.id = $1`, [rows[0].id]);
  res.json(full[0]);
}));

/** Consolidated project report on letterhead, prepared by the lead. */
router.get('/:id/report.pdf', requireRole('manager'), ah(async (req, res) => {
  const { rows } = await pool.query(`${PROJECT_SELECT} WHERE p.id = $1`, [req.params.id]);
  const project = rows[0];
  if (!project) throw httpError(404, 'Project not found');

  const { rows: activities } = await pool.query(
    `SELECT * FROM activities WHERE project_id = $1 AND status = 'approved'
      ORDER BY activity_date`,
    [project.id]
  );

  const { rows: lead } = await pool.query(
    `SELECT full_name, designation, signature_url, signature_title FROM employees WHERE id = $1`,
    [project.lead_id || req.user.id]
  );
  const { rows: auth } = await pool.query(
    `SELECT full_name, designation, signature_url, signature_title FROM employees
      WHERE role IN ('authority','admin') AND is_active AND signature_url IS NOT NULL
      ORDER BY CASE role WHEN 'authority' THEN 0 ELSE 1 END, id LIMIT 1`
  );

  const fileNo = await nextFileNo('project_report', 'projects', project.id, req.user.id);
  const pdf = await buildProjectReport({
    project,
    activities,
    totals: {
      activity_count: Number(project.activity_count),
      participants: Number(project.participants),
      beneficiaries: Number(project.beneficiaries),
      expenditure_paise: Number(project.expenditure_paise),
    },
    lead: lead[0] || null,
    authority: auth[0] || null,
    fileNo,
  });
  sendPdf(res, pdf, `NESF-Project-${project.code}.pdf`);
}));

// ---------------------------------------------------------------------------
// Activities (the project/activity report staff submit)
// ---------------------------------------------------------------------------
const ACTIVITY_SELECT = `
  SELECT a.*, e.full_name, e.emp_code, e.designation, e.department, e.reporting_to_id,
         p.name AS project_name, p.code AS project_code, p.funder,
         r.full_name AS reviewed_by_name,
         ap.full_name AS approved_by_name,
         (a.participants_male + a.participants_female + a.participants_other) AS participants_total
    FROM activities a
    JOIN employees e ON e.id = a.employee_id
    LEFT JOIN projects p ON p.id = a.project_id
    LEFT JOIN employees r ON r.id = a.reviewed_by
    LEFT JOIN employees ap ON ap.id = a.approved_by
`;

const activitySchema = z.object({
  project_id: z.coerce.number().int().positive().optional(),
  title: z.string().trim().min(3, 'Please give the activity a title'),
  activity_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Activity date must be YYYY-MM-DD'),
  end_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  venue: z.string().trim().max(300).optional(),
  district: z.string().trim().max(100).optional(),
  participants_male: z.coerce.number().int().min(0).default(0),
  participants_female: z.coerce.number().int().min(0).default(0),
  participants_other: z.coerce.number().int().min(0).default(0),
  beneficiaries: z.coerce.number().int().min(0).default(0),
  description: z.string().trim().min(20, 'Please describe the activity in at least 20 characters'),
  outcome: z.string().trim().max(5000).optional(),
  challenges: z.string().trim().max(5000).optional(),
  expenditure: z.coerce.number().min(0).default(0),
  status: z.enum(['draft', 'submitted']).default('submitted'),
});

router.post('/activities', ah(async (req, res) => {
  const b = parse(activitySchema, req.body);
  const { rows } = await pool.query(
    `INSERT INTO activities (project_id, employee_id, title, activity_date, end_date, venue, district,
        participants_male, participants_female, participants_other, beneficiaries,
        description, outcome, challenges, expenditure_paise, status)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)
     RETURNING id`,
    [b.project_id ?? null, req.user.id, b.title, b.activity_date, b.end_date ?? null,
     b.venue ?? null, b.district ?? null, b.participants_male, b.participants_female,
     b.participants_other, b.beneficiaries, b.description, b.outcome ?? null,
     b.challenges ?? null, toPaise(b.expenditure), b.status]
  );
  const { rows: full } = await pool.query(`${ACTIVITY_SELECT} WHERE a.id = $1`, [rows[0].id]);
  res.status(201).json(full[0]);
}));

router.get('/activities/list', ah(async (req, res) => {
  const scope = req.query.scope || 'mine';
  const params = [req.user.id];
  let where;

  if (scope === 'mine') {
    where = 'a.employee_id = $1';
  } else if (scope === 'inbox') {
    if (req.user.role === 'staff') return res.json([]);
    where = req.user.role === 'manager'
      ? `a.status = 'submitted' AND e.reporting_to_id = $1 AND a.employee_id <> $1`
      : `a.status IN ('submitted','reviewed') AND a.employee_id <> $1`;
  } else if (scope === 'all') {
    // Approved activities are the org's public record; everyone may read them.
    where = req.user.role === 'staff' ? `(a.employee_id = $1 OR a.status = 'approved')` : 'TRUE';
  } else {
    throw httpError(400, 'scope must be mine, inbox or all');
  }

  if (req.query.project_id) {
    params.push(req.query.project_id);
    where += ` AND a.project_id = $${params.length}`;
  }
  if (req.query.status) {
    params.push(req.query.status);
    where += ` AND a.status = $${params.length}`;
  }

  const { rows } = await pool.query(
    `${ACTIVITY_SELECT} WHERE ${where} ORDER BY a.activity_date DESC LIMIT 200`, params
  );
  res.json(rows);
}));

async function loadActivity(id) {
  const { rows } = await pool.query(`${ACTIVITY_SELECT} WHERE a.id = $1`, [id]);
  if (!rows[0]) throw httpError(404, 'Activity not found');
  const { rows: photos } = await pool.query(
    'SELECT id, url, caption, sort_order FROM activity_photos WHERE activity_id = $1 ORDER BY sort_order',
    [id]
  );
  return { activity: rows[0], photos };
}

router.get('/activities/:id', ah(async (req, res) => {
  const { activity, photos } = await loadActivity(req.params.id);
  if (activity.status !== 'approved' && !canView(req.user, activity)) {
    throw httpError(403, 'You cannot view this activity');
  }
  res.json({ ...activity, photos });
}));

/** Photo evidence, embedded in the activity report PDF. */
router.post('/activities/:id/photos', uploadImage.single('photo'), ah(async (req, res) => {
  if (!req.file) throw httpError(400, 'No photo was uploaded');
  const { activity } = await loadActivity(req.params.id);
  if (activity.employee_id !== req.user.id && req.user.role === 'staff') {
    throw httpError(403, 'You can only add photos to your own activity reports');
  }
  if (!['draft', 'submitted'].includes(activity.status)) {
    throw httpError(409, 'Photos cannot be added once the report has been reviewed');
  }

  const url = await saveUpload(req.file, `activities/${activity.id}`);
  const { rows } = await pool.query(
    `INSERT INTO activity_photos (activity_id, url, caption, sort_order)
     VALUES ($1, $2, $3, COALESCE((SELECT MAX(sort_order) + 1 FROM activity_photos WHERE activity_id = $1), 0))
     RETURNING *`,
    [activity.id, url, req.body?.caption || null]
  );
  res.status(201).json(rows[0]);
}));

const decisionSchema = z.object({
  decision: z.string(),
  remark: z.string().trim().max(2000).optional(),
});

router.put('/activities/:id/review', requireRole('manager'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { activity } = await loadActivity(req.params.id);
  if (!canReview(req.user, activity)) {
    throw httpError(403, 'You are not the reporting officer for this activity');
  }
  await review('activities', activity.id, req.user, b);
  const { activity: after, photos } = await loadActivity(activity.id);
  res.json({ ...after, photos });
}));

router.put('/activities/:id/approve', requireRole('authority'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { activity } = await loadActivity(req.params.id);
  if (!canApprove(req.user, activity)) throw httpError(403, 'You cannot approve this activity');
  await approve('activities', activity.id, req.user, b);
  const { activity: after, photos } = await loadActivity(activity.id);
  res.json({ ...after, photos });
}));

router.get('/activities/:id/report.pdf', ah(async (req, res) => {
  const { activity, photos } = await loadActivity(req.params.id);
  if (!canView(req.user, activity)) throw httpError(403, 'You cannot download this document');
  if (activity.status !== 'approved') {
    throw httpError(409, 'The signed activity report is available only after approval');
  }

  const fileNo = await ensureFileNo('activities', activity, req.user);
  const { reviewer, approver } = await loadSignatories(activity);
  const pdf = await buildActivityReport({
    activity: { ...activity, file_no: fileNo },
    employee: activity,
    project: activity.project_name
      ? { name: activity.project_name, code: activity.project_code, funder: activity.funder }
      : null,
    photos,
    reviewer,
    approver,
    fileNo,
  });
  sendPdf(res, pdf, `NESF-Activity-${activity.id}-${activity.activity_date}.pdf`);
}));

export default router;
