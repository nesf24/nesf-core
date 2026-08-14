import { Router } from 'express';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireAdmin } from '../middleware/auth.js';
import { ah, parse, httpError } from '../utils.js';

const router = Router();

// Get all team configurations
router.get('/teams', requireAuth, ah(async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM attendance_config ORDER BY team_name'
  );
  res.json(rows);
}));

// Get team configuration by ID
router.get('/teams/:id', requireAuth, ah(async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM attendance_config WHERE id = $1',
    [req.params.id]
  );
  if (rows.length === 0) throw httpError(404, 'Team configuration not found');
  res.json(rows[0]);
}));

// Create team configuration (admin only)
const createTeamSchema = z.object({
  team_name: z.string().min(1, 'Team name required'),
  checkin_start_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/, 'Invalid time format'),
  checkin_reminder_interval_minutes: z.number().min(1),
  checkin_deadline_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/),
  checkout_start_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/),
  checkout_reminder_interval_minutes: z.number().min(1),
  checkout_autocheckin_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/),
  enabled: z.boolean().optional(),
});

router.post('/teams', requireAdmin, ah(async (req, res) => {
  const data = parse(createTeamSchema, req.body);

  const { rows } = await pool.query(
    `INSERT INTO attendance_config
      (team_name, checkin_start_time, checkin_reminder_interval_minutes,
       checkin_deadline_time, checkout_start_time, checkout_reminder_interval_minutes,
       checkout_autocheckin_time, enabled)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [
      data.team_name,
      data.checkin_start_time,
      data.checkin_reminder_interval_minutes,
      data.checkin_deadline_time,
      data.checkout_start_time,
      data.checkout_reminder_interval_minutes,
      data.checkout_autocheckin_time,
      data.enabled !== false,
    ]
  );

  res.status(201).json(rows[0]);
}));

// Update team configuration (admin only)
const updateTeamSchema = z.object({
  team_name: z.string().min(1).optional(),
  checkin_start_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/).optional(),
  checkin_reminder_interval_minutes: z.number().min(1).optional(),
  checkin_deadline_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/).optional(),
  checkout_start_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/).optional(),
  checkout_reminder_interval_minutes: z.number().min(1).optional(),
  checkout_autocheckin_time: z.string().regex(/^\d{2}:\d{2}:\d{2}$/).optional(),
  enabled: z.boolean().optional(),
});

router.put('/teams/:id', requireAdmin, ah(async (req, res) => {
  const data = parse(updateTeamSchema, req.body);

  const updates = [];
  const values = [];
  let paramCount = 1;

  Object.entries(data).forEach(([key, value]) => {
    if (value !== undefined) {
      updates.push(`${key} = $${paramCount++}`);
      values.push(value);
    }
  });

  if (updates.length === 0) {
    return res.json({ message: 'No updates provided' });
  }

  values.push(req.params.id);
  updates.push(`updated_at = NOW()`);

  const { rows } = await pool.query(
    `UPDATE attendance_config SET ${updates.join(', ')} WHERE id = $${paramCount} RETURNING *`,
    values
  );

  if (rows.length === 0) throw httpError(404, 'Team not found');
  res.json(rows[0]);
}));

// Assign staff to team
const assignTeamSchema = z.object({
  employee_id: z.number().min(1),
  team_id: z.number().min(1),
});

router.post('/team-members', requireAdmin, ah(async (req, res) => {
  const { employee_id, team_id } = parse(assignTeamSchema, req.body);

  const { rows } = await pool.query(
    `INSERT INTO team_members (employee_id, team_id, assigned_at)
     VALUES ($1, $2, NOW())
     ON CONFLICT (employee_id, team_id) DO NOTHING
     RETURNING *`,
    [employee_id, team_id]
  );

  res.status(201).json(rows[0] || { message: 'Already assigned' });
}));

// Get team members
router.get('/team-members/:team_id', requireAuth, ah(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT e.id, e.emp_code, e.full_name, e.email, e.phone, tm.assigned_at
     FROM team_members tm
     JOIN employees e ON e.id = tm.employee_id
     WHERE tm.team_id = $1
     ORDER BY e.full_name`,
    [req.params.team_id]
  );

  res.json(rows);
}));

export default router;
