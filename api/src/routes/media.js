import { Router } from 'express';
import pool from '../db.js';
import { requireAuth } from '../middleware/auth.js';
import { isSafeKey, mimeForKey, streamUpload } from '../services/storage.js';
import { ah, httpError } from '../utils.js';

const router = Router();
router.use(requireAuth);

const RANK = { staff: 0, manager: 1, authority: 2, admin: 3 };

/**
 * True when `user` may see something belonging to `ownerId`: their own, their
 * reportees' if they are a manager, anyone's from authority upwards.
 */
async function canSeeOwner(user, ownerId) {
  if (ownerId == null) return RANK[user.role] >= RANK.authority;
  if (String(ownerId) === String(user.id)) return true;
  if (RANK[user.role] >= RANK.authority) return true;
  if (user.role !== 'manager') return false;

  const { rows } = await pool.query(
    'SELECT 1 FROM employees WHERE id = $1 AND reporting_to_id = $2',
    [ownerId, user.id]
  );
  return !!rows[0];
}

/**
 * Decides whether `user` may read `key`, from the folder it lives in.
 *
 * The categories differ genuinely in sensitivity:
 *  - attendance selfies are personal, and are restricted to the staff member and
 *    their reporting line;
 *  - receipts belong to a money claim, so the claimant and their approvers;
 *  - signatures, profile photos and activity photographs all already appear on
 *    documents circulated inside the foundation, so any signed-in member of staff
 *    may load them.
 *
 * Nothing is readable without a session — that is the point of this endpoint.
 */
async function authorise(user, key) {
  const folder = key.split('/')[0];

  switch (folder) {
    case 'attendance': {
      // Find whose punch this selfie belongs to.
      const { rows } = await pool.query(
        `SELECT employee_id FROM attendance
          WHERE check_in_selfie = $1 OR check_out_selfie = $1 LIMIT 1`,
        [key]
      );
      // An orphaned object (its row was deleted) is treated as sensitive.
      return canSeeOwner(user, rows[0]?.employee_id ?? null);
    }

    case 'receipts': {
      const { rows } = await pool.query(
        `SELECT c.employee_id FROM ta_da_legs l
           JOIN ta_da_claims c ON c.id = l.claim_id
          WHERE l.receipt_url = $1 LIMIT 1`,
        [key]
      );
      return canSeeOwner(user, rows[0]?.employee_id ?? null);
    }

    case 'signatures':
    case 'photos':
    case 'activities':
      return true;

    default:
      // Unknown prefix: refuse rather than guess.
      return false;
  }
}

/**
 * Serves an uploaded file to a signed-in staff member.
 *
 * Everything under /api/media is private. The URL is not a capability — knowing
 * it is not enough, the caller must hold a valid session and pass the check for
 * that category.
 */
router.get(/^\/(.+)$/, ah(async (req, res) => {
  const key = decodeURIComponent(req.params[0] || '');
  if (!isSafeKey(key)) throw httpError(400, 'Invalid media reference');

  if (!(await authorise(req.user, key))) {
    throw httpError(403, 'You do not have permission to view this file');
  }

  res.setHeader('Content-Type', mimeForKey(key));
  // Private so shared caches and proxies never retain staff photographs; the
  // long max-age is safe because keys are immutable once written.
  res.setHeader('Cache-Control', 'private, max-age=86400');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  // These are photographs and PDFs, never markup — do not let a browser treat
  // one as a document in this origin.
  res.setHeader('Content-Security-Policy', "default-src 'none'; sandbox");

  const served = await streamUpload(key, res);
  if (!served && !res.headersSent) throw httpError(404, 'File not found');
}));

export default router;
