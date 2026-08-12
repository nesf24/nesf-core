import { Router } from 'express';
import pool from '../db.js';
import { requireAuth } from '../middleware/auth.js';
import { ah, istToday } from '../utils.js';

const router = Router();
router.use(requireAuth);

/**
 * Home screen payload. Deliberately one round trip: the app opens on this and a
 * phone on a patchy connection should not need five calls to render.
 */
router.get('/', ah(async (req, res) => {
  const today = istToday();
  const year = Number(today.slice(0, 4));
  const isReviewer = ['manager', 'authority', 'admin'].includes(req.user.role);

  const [attendance, leaveBalance, myPending, inbox, dues, orgToday] = await Promise.all([
    pool.query('SELECT * FROM attendance WHERE employee_id = $1 AND work_date = $2',
      [req.user.id, today]),

    pool.query(
      `SELECT lt.code, lt.name,
              COALESCE(b.opening, 0) + COALESCE(b.accrued, lt.annual_quota) - COALESCE(b.used, 0) AS available,
              lt.annual_quota
         FROM leave_types lt
         LEFT JOIN leave_balances b ON b.leave_type_id = lt.id AND b.employee_id = $1 AND b.year = $2
        WHERE lt.is_active ORDER BY lt.sort_order`,
      [req.user.id, year]
    ),

    // What the signed-in user is waiting on.
    pool.query(
      `SELECT
         (SELECT COUNT(*) FROM leaves WHERE employee_id = $1 AND status IN ('submitted','reviewed')) AS leaves,
         (SELECT COUNT(*) FROM work_reports WHERE employee_id = $1 AND status IN ('submitted','reviewed')) AS reports,
         (SELECT COUNT(*) FROM ta_da_claims WHERE employee_id = $1 AND status IN ('submitted','reviewed')) AS tada,
         (SELECT COUNT(*) FROM activities WHERE employee_id = $1 AND status IN ('submitted','reviewed')) AS activities`,
      [req.user.id]
    ),

    // What the signed-in user must act on. Managers see their reportees'
    // submissions; authority sees everything still open.
    isReviewer
      ? pool.query(
          req.user.role === 'manager'
            ? `SELECT
                 (SELECT COUNT(*) FROM leaves l JOIN employees e ON e.id = l.employee_id
                   WHERE l.status = 'submitted' AND e.reporting_to_id = $1 AND l.employee_id <> $1) AS leaves,
                 (SELECT COUNT(*) FROM work_reports r JOIN employees e ON e.id = r.employee_id
                   WHERE r.status = 'submitted' AND e.reporting_to_id = $1 AND r.employee_id <> $1) AS reports,
                 (SELECT COUNT(*) FROM ta_da_claims c JOIN employees e ON e.id = c.employee_id
                   WHERE c.status = 'submitted' AND e.reporting_to_id = $1 AND c.employee_id <> $1) AS tada,
                 (SELECT COUNT(*) FROM activities a JOIN employees e ON e.id = a.employee_id
                   WHERE a.status = 'submitted' AND e.reporting_to_id = $1 AND a.employee_id <> $1) AS activities`
            : `SELECT
                 (SELECT COUNT(*) FROM leaves WHERE status IN ('submitted','reviewed') AND employee_id <> $1) AS leaves,
                 (SELECT COUNT(*) FROM work_reports WHERE status IN ('submitted','reviewed') AND employee_id <> $1) AS reports,
                 (SELECT COUNT(*) FROM ta_da_claims WHERE status IN ('submitted','reviewed') AND employee_id <> $1) AS tada,
                 (SELECT COUNT(*) FROM activities WHERE status IN ('submitted','reviewed') AND employee_id <> $1) AS activities`,
          [req.user.id]
        )
      : Promise.resolve({ rows: [{ leaves: 0, reports: 0, tada: 0, activities: 0 }] }),

    // CRM follow-ups falling due for this user.
    pool.query(
      `SELECT id, name, organisation, next_action, next_action_on, phone, stage
         FROM crm_contacts
        WHERE is_active AND next_action_on IS NOT NULL AND next_action_on <= $2
          AND ($3 OR owner_id = $1)
        ORDER BY next_action_on LIMIT 10`,
      [req.user.id, today, ['authority', 'admin'].includes(req.user.role)]
    ),

    // Who is in the office today, for the whole-org snapshot.
    pool.query(
      `SELECT
         (SELECT COUNT(*) FROM employees WHERE is_active) AS staff_total,
         (SELECT COUNT(*) FROM attendance WHERE work_date = $1 AND check_in_at IS NOT NULL) AS checked_in,
         (SELECT COUNT(*) FROM attendance WHERE work_date = $1 AND work_mode = 'field') AS field_duty,
         (SELECT COUNT(*) FROM leaves WHERE status = 'approved' AND $1 BETWEEN from_date AND to_date) AS on_leave`,
      [today]
    ),
  ]);

  const att = attendance.rows[0] || null;

  res.json({
    date: today,
    user: {
      id: req.user.id,
      full_name: req.user.full_name,
      designation: req.user.designation,
      role: req.user.role,
      photo_url: req.user.photo_url,
      has_signature: !!req.user.signature_url,
    },
    attendance: {
      record: att,
      can_check_in: !att?.check_in_at,
      can_check_out: !!att?.check_in_at && !att?.check_out_at,
    },
    leave_balance: leaveBalance.rows,
    my_pending: myPending.rows[0],
    inbox: inbox.rows[0],
    crm_due: dues.rows,
    org_today: orgToday.rows[0],
  });
}));

export default router;
