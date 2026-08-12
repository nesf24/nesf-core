import jwt from 'jsonwebtoken';
import pool from '../db.js';

const SECRET = process.env.JWT_SECRET || 'dev-only-insecure-secret';

export function signAccessToken(employee) {
  return jwt.sign(
    { sub: employee.id, role: employee.role, code: employee.emp_code },
    SECRET,
    { expiresIn: process.env.ACCESS_TOKEN_TTL || '2h' }
  );
}

// Loads the employee fresh on every request rather than trusting the token
// payload, so deactivating or demoting someone takes effect immediately
// instead of waiting for their access token to expire.
export async function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Authentication required' });

  let payload;
  try {
    payload = jwt.verify(token, SECRET);
  } catch {
    return res.status(401).json({ error: 'Session expired, please sign in again' });
  }

  try {
    const { rows } = await pool.query(
      `SELECT id, emp_code, full_name, email, role, designation, department, grade,
              reporting_to_id, photo_url, signature_url, signature_title,
              base_lat, base_lng, base_label, is_active, must_change_pw
         FROM employees WHERE id = $1`,
      [payload.sub]
    );
    const user = rows[0];
    if (!user) return res.status(401).json({ error: 'Account no longer exists' });
    if (!user.is_active) return res.status(403).json({ error: 'Account is deactivated' });
    req.user = user;
    next();
  } catch (err) {
    next(err);
  }
}

const RANK = { staff: 0, manager: 1, authority: 2, admin: 3 };

// Gate by minimum role. `admin` implicitly satisfies every lower requirement.
export function requireRole(...allowed) {
  const floor = Math.min(...allowed.map((r) => RANK[r] ?? 99));
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Authentication required' });
    if ((RANK[req.user.role] ?? -1) < floor) {
      return res.status(403).json({ error: 'You do not have permission to do this' });
    }
    next();
  };
}

// A reviewer is the submitter's reporting manager; managers and above may also
// review anything beneath them, and admins may review anything at all.
export const requireReviewer = requireRole('manager');
// Only an authority (or admin) gives final approval — their signature is what
// appears on the issued document.
export const requireApprover = requireRole('authority');
export const requireAdmin = requireRole('admin');
