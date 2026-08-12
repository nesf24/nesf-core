import { Router } from 'express';
import bcrypt from 'bcryptjs';
import crypto from 'crypto';
import { z } from 'zod';
import rateLimit from 'express-rate-limit';
import pool from '../db.js';
import { signAccessToken, requireAuth } from '../middleware/auth.js';
import { ah, parse, httpError } from '../utils.js';

const router = Router();

/**
 * Brute-force guards on sign-in.
 *
 * Deliberately keyed on the ACCOUNT first, not the IP. The whole foundation
 * office shares one NAT'd address, so a purely IP-based limit would let staff
 * lock each other out on a Monday morning while doing nothing extra against an
 * attacker targeting one account.
 */
const perAccountLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  keyGenerator: (req) => `acct:${String(req.body?.email || '').trim().toLowerCase()}`,
  // Don't spend the budget on a successful sign-in.
  skipSuccessfulRequests: true,
  message: {
    error: 'Too many failed sign-in attempts for this account. '
      + 'Please wait a few minutes, or ask the office to reset your password.',
  },
});

/**
 * A much looser per-IP ceiling, so a single host cannot cycle through many
 * accounts. Set high enough that an entire office behind one address never
 * reaches it in normal use.
 */
const perIpLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 150,
  standardHeaders: true,
  skipSuccessfulRequests: true,
  message: { error: 'Too many sign-in attempts from this network. Please try again shortly.' },
});

const loginLimiter = [perIpLimiter, perAccountLimiter];

const REFRESH_DAYS = Number(process.env.REFRESH_TOKEN_DAYS || 30);

async function issueRefreshToken(employeeId, device) {
  const token = crypto.randomBytes(48).toString('hex');
  const hash = crypto.createHash('sha256').update(token).digest('hex');
  const expires = new Date(Date.now() + REFRESH_DAYS * 86_400_000);
  await pool.query(
    `INSERT INTO sessions (employee_id, token_hash, device, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [employeeId, hash, device || null, expires]
  );
  return token;
}

function publicUser(u) {
  return {
    id: u.id,
    emp_code: u.emp_code,
    full_name: u.full_name,
    email: u.email,
    phone: u.phone,
    role: u.role,
    designation: u.designation,
    department: u.department,
    grade: u.grade,
    reporting_to_id: u.reporting_to_id,
    photo_url: u.photo_url,
    signature_url: u.signature_url,
    signature_title: u.signature_title,
    base_lat: u.base_lat,
    base_lng: u.base_lng,
    base_label: u.base_label,
    must_change_pw: u.must_change_pw,
  };
}

const loginSchema = z.object({
  email: z.string().trim().min(1, 'Email is required'),
  password: z.string().min(1, 'Password is required'),
  device: z.string().optional(),
});

router.post('/login', loginLimiter, ah(async (req, res) => {
  const { email, password, device } = parse(loginSchema, req.body);

  // Staff may sign in with either their email or their employee code.
  const { rows } = await pool.query(
    `SELECT * FROM employees
      WHERE lower(email) = lower($1) OR lower(emp_code) = lower($1)
      LIMIT 1`,
    [email]
  );
  const user = rows[0];

  // Same message for unknown account and wrong password, so the endpoint does
  // not confirm which emails exist.
  const invalid = httpError(401, 'Incorrect email or password');
  if (!user || !user.password_hash) throw invalid;
  if (!(await bcrypt.compare(password, user.password_hash))) throw invalid;
  if (!user.is_active) throw httpError(403, 'Your account has been deactivated. Please contact the office.');

  await pool.query('UPDATE employees SET last_login_at = NOW() WHERE id = $1', [user.id]);

  res.json({
    access_token: signAccessToken(user),
    refresh_token: await issueRefreshToken(user.id, device),
    user: publicUser(user),
  });
}));

router.post('/refresh', ah(async (req, res) => {
  const token = String(req.body?.refresh_token || '');
  if (!token) throw httpError(400, 'Refresh token is required');
  const hash = crypto.createHash('sha256').update(token).digest('hex');

  const { rows } = await pool.query(
    `SELECT s.id, e.*
       FROM sessions s JOIN employees e ON e.id = s.employee_id
      WHERE s.token_hash = $1 AND s.revoked_at IS NULL AND s.expires_at > NOW()`,
    [hash]
  );
  const user = rows[0];
  if (!user) throw httpError(401, 'Session expired, please sign in again');
  if (!user.is_active) throw httpError(403, 'Your account has been deactivated.');

  res.json({ access_token: signAccessToken(user), user: publicUser(user) });
}));

router.post('/logout', ah(async (req, res) => {
  const token = String(req.body?.refresh_token || '');
  if (token) {
    const hash = crypto.createHash('sha256').update(token).digest('hex');
    await pool.query(
      'UPDATE sessions SET revoked_at = NOW() WHERE token_hash = $1 AND revoked_at IS NULL',
      [hash]
    );
  }
  res.json({ ok: true });
}));

router.get('/me', requireAuth, ah(async (req, res) => {
  const { rows } = await pool.query(
    `SELECT e.*, m.full_name AS reporting_to_name, m.designation AS reporting_to_designation
       FROM employees e
       LEFT JOIN employees m ON m.id = e.reporting_to_id
      WHERE e.id = $1`,
    [req.user.id]
  );
  const u = rows[0];
  res.json({
    ...publicUser(u),
    reporting_to_name: u.reporting_to_name,
    reporting_to_designation: u.reporting_to_designation,
  });
}));

const pwSchema = z.object({
  current_password: z.string().min(1, 'Current password is required'),
  new_password: z.string().min(8, 'New password must be at least 8 characters'),
});

router.post('/change-password', requireAuth, ah(async (req, res) => {
  const { current_password, new_password } = parse(pwSchema, req.body);

  const { rows } = await pool.query('SELECT password_hash FROM employees WHERE id = $1', [req.user.id]);
  if (!(await bcrypt.compare(current_password, rows[0].password_hash || ''))) {
    throw httpError(400, 'Your current password is incorrect');
  }

  await pool.query(
    'UPDATE employees SET password_hash = $1, must_change_pw = FALSE, updated_at = NOW() WHERE id = $2',
    [await bcrypt.hash(new_password, 10), req.user.id]
  );
  // Force other devices to re-authenticate after a password change.
  await pool.query(
    'UPDATE sessions SET revoked_at = NOW() WHERE employee_id = $1 AND revoked_at IS NULL',
    [req.user.id]
  );
  res.json({ ok: true });
}));

export default router;
