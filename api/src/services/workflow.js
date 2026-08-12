import pool from '../db.js';
import { nextFileNo } from './letterhead.js';

/**
 * Every submission in NESF Core (leave, work report, activity, TA/DA) moves
 * through the same two-stage chain:
 *
 *   submitted --review(forward)--> reviewed --approve--> approved
 *              \--review(reject)--> rejected  \--reject--> rejected
 *
 * The tables share column names for the workflow fields, so these helpers are
 * generic over the table and keep the permission rules in one place.
 */

const TABLES = {
  leaves: { label: 'Leave application', docType: 'leave_approval' },
  work_reports: { label: 'Work report', docType: 'work_report' },
  activities: { label: 'Activity report', docType: 'activity_report' },
  ta_da_claims: { label: 'TA/DA claim', docType: 'ta_da_sanction' },
};

const RANK = { staff: 0, manager: 1, authority: 2, admin: 3 };

/**
 * True when `user` may review `row`. A reviewer must be the submitter's
 * reporting manager, or hold authority/admin rank. Nobody reviews their own
 * submission — that would defeat the two-stage control.
 */
export function canReview(user, row) {
  if (row.employee_id === user.id) return false;
  if (RANK[user.role] >= RANK.authority) return true;
  return user.role === 'manager' && row.reporting_to_id === user.id;
}

/** Final approval is reserved for authority/admin, and never on own submission. */
export function canApprove(user, row) {
  if (row.employee_id === user.id) return false;
  return RANK[user.role] >= RANK.authority;
}

/** A submitter may always read their own row; managers up the chain may too. */
export function canView(user, row) {
  if (row.employee_id === user.id) return true;
  if (RANK[user.role] >= RANK.authority) return true;
  return user.role === 'manager' && row.reporting_to_id === user.id;
}

/**
 * Records the review decision. `forwarded` moves the row to `reviewed` and makes
 * it visible in the authority's approval queue; `rejected` ends the chain.
 */
export async function review(table, id, user, { decision, remark }) {
  if (!TABLES[table]) throw new Error(`Unknown workflow table: ${table}`);
  if (!['forwarded', 'rejected'].includes(decision)) {
    const err = new Error('Decision must be either forwarded or rejected');
    err.status = 400;
    throw err;
  }

  const status = decision === 'forwarded' ? 'reviewed' : 'rejected';
  const { rows } = await pool.query(
    `UPDATE ${table}
        SET status = $1, reviewed_by = $2, review_decision = $3,
            review_remark = $4, reviewed_at = NOW(), updated_at = NOW()
      WHERE id = $5 AND status = 'submitted'
      RETURNING *`,
    [status, user.id, decision, remark || null, id]
  );
  if (!rows[0]) {
    const err = new Error(`${TABLES[table].label} is not awaiting review`);
    err.status = 409;
    throw err;
  }
  return rows[0];
}

/**
 * Records final approval and, on approval, mints the letterhead file number.
 *
 * The file number is allocated exactly once and stored, so re-downloading the
 * PDF never consumes a new number from the register.
 */
export async function approve(table, id, user, { decision, remark, extra = {} }) {
  if (!TABLES[table]) throw new Error(`Unknown workflow table: ${table}`);
  if (!['approved', 'rejected'].includes(decision)) {
    const err = new Error('Decision must be either approved or rejected');
    err.status = 400;
    throw err;
  }

  // Accept from either 'submitted' (approved directly) or 'reviewed'.
  const { rows } = await pool.query(
    `UPDATE ${table}
        SET status = $1, approved_by = $2, approve_remark = $3,
            approved_at = NOW(), updated_at = NOW()
      WHERE id = $4 AND status IN ('submitted', 'reviewed')
      RETURNING *`,
    [decision, user.id, remark || null, id]
  );
  let row = rows[0];
  if (!row) {
    const err = new Error(`${TABLES[table].label} is not awaiting approval`);
    err.status = 409;
    throw err;
  }

  if (decision === 'approved' && !row.file_no) {
    const fileNo = await nextFileNo(TABLES[table].docType, table, id, user.id);
    const { rows: updated } = await pool.query(
      `UPDATE ${table} SET file_no = $1 WHERE id = $2 RETURNING *`,
      [fileNo, id]
    );
    row = updated[0];
  }

  // Some tables carry approval-time extras (e.g. TA/DA sanctioned amount).
  const keys = Object.keys(extra);
  if (keys.length) {
    const sets = keys.map((k, i) => `${k} = $${i + 2}`).join(', ');
    const { rows: updated } = await pool.query(
      `UPDATE ${table} SET ${sets} WHERE id = $1 RETURNING *`,
      [id, ...keys.map((k) => extra[k])]
    );
    row = updated[0];
  }

  return row;
}

/**
 * Ensures a row that is already approved has a file number. Guards against rows
 * approved before numbering existed, or imported records.
 */
export async function ensureFileNo(table, row, user) {
  if (row.file_no) return row.file_no;
  const fileNo = await nextFileNo(TABLES[table].docType, table, row.id, user?.id || null);
  await pool.query(`UPDATE ${table} SET file_no = $1 WHERE id = $2`, [fileNo, row.id]);
  return fileNo;
}

/**
 * Loads the reviewer and approver as signatories, annotated with when they
 * acted so the PDF can print "Signed on <date>".
 */
export async function loadSignatories(row) {
  const ids = [row.reviewed_by, row.approved_by].filter(Boolean);
  if (!ids.length) return { reviewer: null, approver: null };

  const { rows } = await pool.query(
    `SELECT id, full_name, designation, signature_url, signature_title
       FROM employees WHERE id = ANY($1::bigint[])`,
    [ids]
  );
  const byId = new Map(rows.map((r) => [String(r.id), r]));
  const reviewer = row.reviewed_by ? byId.get(String(row.reviewed_by)) : null;
  const approver = row.approved_by ? byId.get(String(row.approved_by)) : null;

  return {
    reviewer: reviewer && row.review_decision === 'forwarded'
      ? { ...reviewer, acted_at: row.reviewed_at } : null,
    approver: approver ? { ...approver, acted_at: row.approved_at } : null,
  };
}

/**
 * SQL fragment restricting a listing to what `user` is allowed to see:
 * own rows always; reportees' rows for a manager; everything for authority+.
 * Returns { clause, params } to splice into a WHERE.
 */
export function visibilityFilter(user, alias = 't', startIndex = 1) {
  if (RANK[user.role] >= RANK.authority) return { clause: 'TRUE', params: [] };
  if (user.role === 'manager') {
    return {
      clause: `(${alias}.employee_id = $${startIndex} OR e.reporting_to_id = $${startIndex})`,
      params: [user.id],
    };
  }
  return { clause: `${alias}.employee_id = $${startIndex}`, params: [user.id] };
}
