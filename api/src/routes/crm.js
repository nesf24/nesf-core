import { Router } from 'express';
import { z } from 'zod';
import pool from '../db.js';
import { requireAuth, requireRole } from '../middleware/auth.js';
import { ah, parse, httpError, toPaise, istToday, numericId } from '../utils.js';

const router = Router();
// Reject malformed :id segments before they reach a bigint cast.
router.param('id', numericId);
router.use(requireAuth);

// Staff see the contacts they own; managers and above see the whole book, since
// fundraising follow-up has to be coordinated across the office.
function ownershipClause(user, params) {
  if (['manager', 'authority', 'admin'].includes(user.role)) return 'TRUE';
  params.push(user.id);
  return `(c.owner_id = $${params.length} OR c.owner_id IS NULL)`;
}

const CONTACT_SELECT = `
  SELECT c.*, o.full_name AS owner_name,
         (SELECT COUNT(*) FROM crm_interactions i WHERE i.contact_id = c.id) AS interaction_count,
         (SELECT COALESCE(SUM(ct.amount_paise), 0) FROM crm_contributions ct
           WHERE ct.contact_id = c.id AND ct.status = 'received') AS received_paise,
         (SELECT COALESCE(SUM(ct.amount_paise), 0) FROM crm_contributions ct
           WHERE ct.contact_id = c.id AND ct.status = 'pledged') AS pledged_paise
    FROM crm_contacts c
    LEFT JOIN employees o ON o.id = c.owner_id
`;

const contactSchema = z.object({
  kind: z.enum(['person', 'organisation']).default('person'),
  category: z.enum(['donor', 'sponsor', 'csr', 'partner', 'government', 'school',
                    'club', 'athlete_family', 'media', 'vendor', 'other']).default('donor'),
  name: z.string().trim().min(2, 'Name is required'),
  organisation: z.string().trim().max(200).optional(),
  designation: z.string().trim().max(150).optional(),
  email: z.string().trim().email('Enter a valid email').optional().or(z.literal('')),
  phone: z.string().trim().max(30).optional(),
  whatsapp: z.string().trim().max(30).optional(),
  address: z.string().trim().max(500).optional(),
  district: z.string().trim().max(100).optional(),
  state: z.string().trim().max(100).optional(),
  pincode: z.string().trim().max(10).optional(),
  website: z.string().trim().max(300).optional(),
  stage: z.enum(['new', 'contacted', 'interested', 'proposal_sent', 'committed',
                 'donated', 'declined', 'dormant']).default('new'),
  source: z.string().trim().max(150).optional(),
  tags: z.array(z.string().trim().max(40)).max(20).optional(),
  notes: z.string().trim().max(5000).optional(),
  owner_id: z.coerce.number().int().positive().optional(),
  next_action: z.string().trim().max(300).optional(),
  next_action_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

router.get('/contacts', ah(async (req, res) => {
  const params = [];
  let where = ownershipClause(req.user, params);

  if (req.query.stage) {
    params.push(req.query.stage);
    where += ` AND c.stage = $${params.length}`;
  }
  if (req.query.category) {
    params.push(req.query.category);
    where += ` AND c.category = $${params.length}`;
  }
  if (req.query.q) {
    params.push(`%${req.query.q}%`);
    const i = params.length;
    where += ` AND (c.name ILIKE $${i} OR c.organisation ILIKE $${i}
                    OR c.email ILIKE $${i} OR c.phone ILIKE $${i})`;
  }
  // Follow-ups that are due — the working list for fundraising staff.
  if (req.query.due === 'true') {
    params.push(istToday());
    where += ` AND c.next_action_on IS NOT NULL AND c.next_action_on <= $${params.length}`;
  }
  if (req.query.active !== 'false') where += ' AND c.is_active';

  const { rows } = await pool.query(
    `${CONTACT_SELECT} WHERE ${where}
      ORDER BY c.next_action_on ASC NULLS LAST, c.updated_at DESC
      LIMIT 300`,
    params
  );
  res.json(rows);
}));

/** Pipeline counts and value by stage, for the CRM dashboard. */
router.get('/pipeline', ah(async (req, res) => {
  const params = [];
  const where = ownershipClause(req.user, params);
  const { rows } = await pool.query(
    `SELECT c.stage, COUNT(*) AS contacts,
            COALESCE(SUM((SELECT COALESCE(SUM(ct.amount_paise), 0) FROM crm_contributions ct
                           WHERE ct.contact_id = c.id AND ct.status = 'received')), 0) AS received_paise,
            COALESCE(SUM((SELECT COALESCE(SUM(ct.amount_paise), 0) FROM crm_contributions ct
                           WHERE ct.contact_id = c.id AND ct.status = 'pledged')), 0) AS pledged_paise
       FROM crm_contacts c
      WHERE ${where} AND c.is_active
      GROUP BY c.stage`,
    params
  );

  const STAGES = ['new', 'contacted', 'interested', 'proposal_sent', 'committed',
                  'donated', 'declined', 'dormant'];
  const byStage = new Map(rows.map((r) => [r.stage, r]));
  res.json(STAGES.map((stage) => ({
    stage,
    contacts: Number(byStage.get(stage)?.contacts || 0),
    received_paise: Number(byStage.get(stage)?.received_paise || 0),
    pledged_paise: Number(byStage.get(stage)?.pledged_paise || 0),
  })));
}));

router.post('/contacts', ah(async (req, res) => {
  const b = parse(contactSchema, req.body);
  const { rows } = await pool.query(
    `INSERT INTO crm_contacts (kind, category, name, organisation, designation, email, phone,
        whatsapp, address, district, state, pincode, website, stage, source, tags, notes,
        owner_id, next_action, next_action_on, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)
     RETURNING id`,
    [b.kind, b.category, b.name, b.organisation ?? null, b.designation ?? null,
     b.email || null, b.phone ?? null, b.whatsapp ?? null, b.address ?? null,
     b.district ?? null, b.state ?? null, b.pincode ?? null, b.website ?? null,
     b.stage, b.source ?? null, b.tags ?? null, b.notes ?? null,
     // Default ownership to whoever created the record.
     b.owner_id ?? req.user.id, b.next_action ?? null, b.next_action_on ?? null, req.user.id]
  );
  const { rows: full } = await pool.query(`${CONTACT_SELECT} WHERE c.id = $1`, [rows[0].id]);
  res.status(201).json(full[0]);
}));

async function assertContactAccess(user, id) {
  const { rows } = await pool.query('SELECT owner_id FROM crm_contacts WHERE id = $1', [id]);
  if (!rows[0]) throw httpError(404, 'Contact not found');
  const isOwner = String(rows[0].owner_id) === String(user.id);
  if (!isOwner && !['manager', 'authority', 'admin'].includes(user.role)) {
    throw httpError(403, 'This contact is assigned to another staff member');
  }
}

router.get('/contacts/:id', ah(async (req, res) => {
  await assertContactAccess(req.user, req.params.id);
  const { rows } = await pool.query(`${CONTACT_SELECT} WHERE c.id = $1`, [req.params.id]);

  const [{ rows: interactions }, { rows: contributions }] = await Promise.all([
    pool.query(
      `SELECT i.*, e.full_name AS by_name FROM crm_interactions i
         LEFT JOIN employees e ON e.id = i.employee_id
        WHERE i.contact_id = $1 ORDER BY i.happened_at DESC`,
      [req.params.id]
    ),
    pool.query(
      `SELECT ct.*, p.name AS project_name FROM crm_contributions ct
         LEFT JOIN projects p ON p.id = ct.project_id
        WHERE ct.contact_id = $1 ORDER BY ct.created_at DESC`,
      [req.params.id]
    ),
  ]);

  res.json({ ...rows[0], interactions, contributions });
}));

router.put('/contacts/:id', ah(async (req, res) => {
  await assertContactAccess(req.user, req.params.id);
  const b = parse(contactSchema, req.body);
  const { rows } = await pool.query(
    `UPDATE crm_contacts SET kind=$1, category=$2, name=$3, organisation=$4, designation=$5,
        email=$6, phone=$7, whatsapp=$8, address=$9, district=$10, state=$11, pincode=$12,
        website=$13, stage=$14, source=$15, tags=$16, notes=$17, owner_id=$18,
        next_action=$19, next_action_on=$20, updated_at = NOW()
      WHERE id = $21 RETURNING id`,
    [b.kind, b.category, b.name, b.organisation ?? null, b.designation ?? null,
     b.email || null, b.phone ?? null, b.whatsapp ?? null, b.address ?? null,
     b.district ?? null, b.state ?? null, b.pincode ?? null, b.website ?? null,
     b.stage, b.source ?? null, b.tags ?? null, b.notes ?? null,
     b.owner_id ?? null, b.next_action ?? null, b.next_action_on ?? null, req.params.id]
  );
  const { rows: full } = await pool.query(`${CONTACT_SELECT} WHERE c.id = $1`, [rows[0].id]);
  res.json(full[0]);
}));

const interactionSchema = z.object({
  kind: z.enum(['call', 'meeting', 'email', 'whatsapp', 'visit', 'event', 'other']).default('call'),
  happened_at: z.string().optional(),
  summary: z.string().trim().min(3, 'Please summarise the conversation'),
  outcome: z.string().trim().max(2000).optional(),
  next_action: z.string().trim().max(300).optional(),
  next_action_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  // Optionally advance the pipeline in the same call.
  stage: z.enum(['new', 'contacted', 'interested', 'proposal_sent', 'committed',
                 'donated', 'declined', 'dormant']).optional(),
});

/**
 * Logs an interaction and rolls the summary onto the contact, so the listing can
 * show who is overdue for follow-up without a join.
 */
router.post('/contacts/:id/interactions', ah(async (req, res) => {
  await assertContactAccess(req.user, req.params.id);
  const b = parse(interactionSchema, req.body);

  const { rows } = await pool.query(
    `INSERT INTO crm_interactions (contact_id, employee_id, kind, happened_at, summary,
                                   outcome, next_action, next_action_on)
     VALUES ($1,$2,$3,COALESCE($4::timestamptz, NOW()),$5,$6,$7,$8)
     RETURNING *`,
    [req.params.id, req.user.id, b.kind, b.happened_at ?? null, b.summary,
     b.outcome ?? null, b.next_action ?? null, b.next_action_on ?? null]
  );

  await pool.query(
    `UPDATE crm_contacts
        SET last_contacted_at = GREATEST(COALESCE(last_contacted_at, $2), $2),
            next_action = COALESCE($3, next_action),
            next_action_on = COALESCE($4, next_action_on),
            stage = COALESCE($5, stage),
            updated_at = NOW()
      WHERE id = $1`,
    [req.params.id, rows[0].happened_at, b.next_action ?? null,
     b.next_action_on ?? null, b.stage ?? null]
  );

  res.status(201).json(rows[0]);
}));

const contributionSchema = z.object({
  amount: z.coerce.number().min(0),
  kind: z.enum(['cash', 'bank', 'upi', 'cheque', 'in_kind']).default('bank'),
  status: z.enum(['pledged', 'received', 'cancelled']).default('pledged'),
  project_id: z.coerce.number().int().positive().optional(),
  received_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  reference: z.string().trim().max(200).optional(),
  remark: z.string().trim().max(1000).optional(),
});

router.post('/contacts/:id/contributions', ah(async (req, res) => {
  await assertContactAccess(req.user, req.params.id);
  const b = parse(contributionSchema, req.body);

  const { rows } = await pool.query(
    `INSERT INTO crm_contributions (contact_id, project_id, amount_paise, kind, status,
                                     received_on, reference, remark, recorded_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
    [req.params.id, b.project_id ?? null, toPaise(b.amount), b.kind, b.status,
     b.received_on ?? null, b.reference ?? null, b.remark ?? null, req.user.id]
  );

  // Received money moves the contact to 'donated' and updates the lifetime total.
  if (b.status === 'received') {
    await pool.query(
      `UPDATE crm_contacts
          SET total_given_paise = (SELECT COALESCE(SUM(amount_paise), 0) FROM crm_contributions
                                    WHERE contact_id = $1 AND status = 'received'),
              stage = CASE WHEN stage IN ('declined','dormant') THEN stage ELSE 'donated' END,
              updated_at = NOW()
        WHERE id = $1`,
      [req.params.id]
    );
  }

  res.status(201).json(rows[0]);
}));

/** Soft delete — the relationship history is kept for the record. */
router.delete('/contacts/:id', requireRole('manager'), ah(async (req, res) => {
  const { rows } = await pool.query(
    'UPDATE crm_contacts SET is_active = FALSE, updated_at = NOW() WHERE id = $1 RETURNING id',
    [req.params.id]
  );
  if (!rows[0]) throw httpError(404, 'Contact not found');
  res.json({ ok: true });
}));

export default router;
