import { Router } from 'express';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { buildWorkReport } from '../services/documents.js';
import {
  review, approve, canReview, canApprove, canView, loadSignatories, ensureFileNo,
} from '../services/workflow.js';
import { ah, parse, httpError, sendPdf, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

const REPORT_SELECT = `
  SELECT wr.*, e.full_name, e.emp_code, e.designation, e.department, e.reporting_to_id,
         p.name AS project_name, p.code AS project_code,
         r.full_name AS reviewed_by_name,
         a.full_name AS approved_by_name
    FROM work_reports wr
    JOIN employees e ON e.id = wr.employee_id
    LEFT JOIN projects p ON p.id = wr.project_id
    LEFT JOIN employees r ON r.id = wr.reviewed_by
    LEFT JOIN employees a ON a.id = wr.approved_by
`;

const reportSchema = z.object({
  period: z.enum(['daily', 'weekly', 'monthly', 'quarterly']).default('monthly'),
  period_start: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Start date must be YYYY-MM-DD'),
  period_end: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'End date must be YYYY-MM-DD'),
  project_id: z.coerce.number().int().positive().optional(),
  title: z.string().trim().min(3, 'Please give the report a subject'),
  summary: z.string().trim().min(20, 'The summary should be at least 20 characters'),
  achievements: z.string().trim().max(5000).optional(),
  challenges: z.string().trim().max(5000).optional(),
  next_plan: z.string().trim().max(5000).optional(),
  status: z.enum(['draft', 'submitted']).default('submitted'),
});

router.post('/', ah(async (req, res) => {
  const b = parse(reportSchema, req.body);
  if (b.period_end < b.period_start) {
    throw httpError(400, 'The period end cannot be before the period start');
  }

  const { rows } = await pool.query(
    `INSERT INTO work_reports (employee_id, period, period_start, period_end, project_id,
                               title, summary, achievements, challenges, next_plan, status)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
     RETURNING id`,
    [req.user.id, b.period, b.period_start, b.period_end, b.project_id ?? null,
     b.title, b.summary, b.achievements ?? null, b.challenges ?? null,
     b.next_plan ?? null, b.status]
  );
  const { rows: full } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [rows[0].id]);
  res.status(201).json(full[0]);
}));

/** Edit while still a draft or awaiting review; locked once a decision starts. */
router.put('/:id', ah(async (req, res) => {
  const b = parse(reportSchema, req.body);
  const { rows } = await pool.query(
    `UPDATE work_reports SET
        period = $1, period_start = $2, period_end = $3, project_id = $4,
        title = $5, summary = $6, achievements = $7, challenges = $8,
        next_plan = $9, status = $10, updated_at = NOW()
      WHERE id = $11 AND employee_id = $12 AND status IN ('draft', 'submitted')
      RETURNING id`,
    [b.period, b.period_start, b.period_end, b.project_id ?? null, b.title, b.summary,
     b.achievements ?? null, b.challenges ?? null, b.next_plan ?? null, b.status,
     req.params.id, req.user.id]
  );
  if (!rows[0]) {
    throw httpError(409, 'This report can no longer be edited');
  }
  const { rows: full } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [rows[0].id]);
  res.json(full[0]);
}));

router.get('/', ah(async (req, res) => {
  const scope = req.query.scope || 'mine';
  const params = [req.user.id];
  let where;

  if (scope === 'mine') {
    where = 'wr.employee_id = $1';
  } else if (scope === 'inbox') {
    if (req.user.role === 'staff') return res.json([]);
    where = req.user.role === 'manager'
      ? `wr.status = 'submitted' AND e.reporting_to_id = $1 AND wr.employee_id <> $1`
      : `wr.status IN ('submitted', 'reviewed') AND wr.employee_id <> $1`;
  } else if (scope === 'team') {
    where = req.user.role === 'manager' ? '(e.reporting_to_id = $1 OR wr.employee_id = $1)'
      : req.user.role === 'staff' ? 'wr.employee_id = $1'
      : 'TRUE';
  } else {
    throw httpError(400, 'scope must be mine, inbox or team');
  }

  if (req.query.status) {
    params.push(req.query.status);
    where += ` AND wr.status = $${params.length}`;
  }
  if (req.query.project_id) {
    params.push(req.query.project_id);
    where += ` AND wr.project_id = $${params.length}`;
  }

  const { rows } = await pool.query(
    `${REPORT_SELECT} WHERE ${where} ORDER BY wr.period_start DESC, wr.created_at DESC LIMIT 200`,
    params
  );
  res.json(rows);
}));

router.get('/:id', ah(async (req, res) => {
  const { rows } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Report not found');
  if (!canView(req.user, row)) throw httpError(403, 'You cannot view this report');
  res.json(row);
}));

const decisionSchema = z.object({
  decision: z.string(),
  remark: z.string().trim().max(2000).optional(),
});

router.put('/:id/review', requireRole('manager'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { rows } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Report not found');
  if (!canReview(req.user, row)) {
    throw httpError(403, 'You are not the reporting officer for this report');
  }
  await review('work_reports', row.id, req.user, b);
  const { rows: after } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [row.id]);
  res.json(after[0]);
}));

router.put('/:id/approve', requireRole('authority'), ah(async (req, res) => {
  const b = parse(decisionSchema, req.body);
  const { rows } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Report not found');
  if (!canApprove(req.user, row)) throw httpError(403, 'You cannot approve this report');
  await approve('work_reports', row.id, req.user, b);
  const { rows: after } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [row.id]);
  res.json(after[0]);
}));

router.get('/:id/report.pdf', ah(async (req, res) => {
  const { rows } = await pool.query(`${REPORT_SELECT} WHERE wr.id = $1`, [req.params.id]);
  const row = rows[0];
  if (!row) throw httpError(404, 'Report not found');
  if (!canView(req.user, row)) throw httpError(403, 'You cannot download this document');
  if (row.status !== 'approved') {
    throw httpError(409, 'The signed report is available only after approval');
  }

  const fileNo = await ensureFileNo('work_reports', row, req.user);
  const { reviewer, approver } = await loadSignatories(row);
  const pdf = await buildWorkReport({
    report: { ...row, file_no: fileNo }, employee: row, reviewer, approver, fileNo,
  });
  sendPdf(res, pdf, `NESF-Report-${row.emp_code}-${row.period_start}.pdf`);
}));

export default router;
