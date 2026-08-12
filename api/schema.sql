-- ============================================================================
-- NESF Core — HR & CRM for The NE Sports Foundation
-- Standalone Postgres schema. Safe to re-run (idempotent).
--
-- Design notes:
--  * Every document that leaves the system on foundation letterhead draws a
--    sequential number from document_log, so file numbers are unique and
--    auditable across ALL document types (leave, TA/DA, reports, activities).
--  * Approval-bearing tables share the same 2-stage shape: submitted -> reviewed
--    (by reporting manager) -> approved (by authority). Signatures of whoever
--    reviewed/approved are stamped onto the PDF, so we store the actor ids.
--  * Money is stored in paise (BIGINT) to avoid float drift. Distances in metres.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Staff / auth
-- ---------------------------------------------------------------------------

-- Roles, lowest to highest authority:
--   staff      — submits own attendance, leave, reports, TA/DA
--   manager    — the above + reviews/forwards submissions of their reportees
--   authority  — final approver; their signature appears on issued documents
--   admin      — full config access (employees, rates, holidays, settings)
CREATE TABLE IF NOT EXISTS employees (
  id              BIGSERIAL PRIMARY KEY,
  emp_code        TEXT UNIQUE NOT NULL,
  full_name       TEXT NOT NULL,
  email           TEXT UNIQUE NOT NULL,
  phone           TEXT,
  password_hash   TEXT,
  role            TEXT NOT NULL DEFAULT 'staff'
                    CHECK (role IN ('staff', 'manager', 'authority', 'admin')),
  designation     TEXT,
  department      TEXT,
  grade           TEXT,                        -- drives TA/DA entitlement
  date_of_joining DATE,
  date_of_exit    DATE,
  reporting_to_id BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  photo_url       TEXT,
  -- Scanned signature, stamped onto PDFs this person reviews/approves.
  signature_url   TEXT,
  -- Designation printed under the signature on issued documents.
  signature_title TEXT,
  -- Home/base office used as the attendance geofence centre for this person.
  base_lat        DOUBLE PRECISION,
  base_lng        DOUBLE PRECISION,
  base_label      TEXT,
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  must_change_pw  BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at   TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_employees_reporting ON employees (reporting_to_id);
CREATE INDEX IF NOT EXISTS idx_employees_active ON employees (is_active) WHERE is_active;

-- Refresh-token store, so a stolen access token expires quickly but staff on
-- phones are not forced to re-login daily.
CREATE TABLE IF NOT EXISTS sessions (
  id           BIGSERIAL PRIMARY KEY,
  employee_id  BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  token_hash   TEXT UNIQUE NOT NULL,
  device       TEXT,
  expires_at   TIMESTAMPTZ NOT NULL,
  revoked_at   TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sessions_employee ON sessions (employee_id);

-- ---------------------------------------------------------------------------
-- Document numbering — one shared sequence per year across all doc types
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS document_log (
  id         BIGSERIAL PRIMARY KEY,
  file_no    TEXT UNIQUE NOT NULL,
  year       INT NOT NULL,
  seq        INT NOT NULL,
  doc_type   TEXT NOT NULL,
  ref_table  TEXT,
  ref_id     BIGINT,
  issued_by  BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (year, seq)
);
CREATE INDEX IF NOT EXISTS idx_document_log_ref ON document_log (ref_table, ref_id);

-- ---------------------------------------------------------------------------
-- Attendance — selfie + geo-tagged check-in / check-out
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS attendance (
  id                BIGSERIAL PRIMARY KEY,
  employee_id       BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  work_date         DATE NOT NULL,
  work_mode         TEXT NOT NULL DEFAULT 'office'
                      CHECK (work_mode IN ('office', 'field', 'wfh')),

  check_in_at       TIMESTAMPTZ,
  check_in_lat      DOUBLE PRECISION,
  check_in_lng      DOUBLE PRECISION,
  check_in_accuracy DOUBLE PRECISION,          -- metres, from the device GPS
  check_in_place    TEXT,                      -- reverse-geocoded or typed
  check_in_selfie   TEXT,                      -- stored image URL/path
  -- Metres from this employee's base_lat/lng at check-in; NULL when base unset.
  check_in_distance DOUBLE PRECISION,
  -- TRUE when check_in_distance exceeded settings.geofence_radius_m.
  check_in_offsite  BOOLEAN NOT NULL DEFAULT FALSE,

  check_out_at      TIMESTAMPTZ,
  check_out_lat     DOUBLE PRECISION,
  check_out_lng     DOUBLE PRECISION,
  check_out_place   TEXT,
  check_out_selfie  TEXT,

  minutes_worked    INT,                       -- computed at check-out
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- One attendance row per person per day; check-out updates the same row.
  UNIQUE (employee_id, work_date)
);
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance (work_date DESC);
CREATE INDEX IF NOT EXISTS idx_attendance_emp_date ON attendance (employee_id, work_date DESC);

-- Manual regularisation when someone forgot to punch (audited, admin-only).
CREATE TABLE IF NOT EXISTS attendance_edits (
  id            BIGSERIAL PRIMARY KEY,
  attendance_id BIGINT NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
  edited_by     BIGINT NOT NULL REFERENCES employees(id) ON DELETE SET NULL,
  reason        TEXT NOT NULL,
  before_json   JSONB,
  after_json    JSONB,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS holidays (
  id         BIGSERIAL PRIMARY KEY,
  holiday_on DATE UNIQUE NOT NULL,
  name       TEXT NOT NULL,
  kind       TEXT NOT NULL DEFAULT 'public'
               CHECK (kind IN ('public', 'restricted', 'weekly_off')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Leave
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leave_types (
  id            BIGSERIAL PRIMARY KEY,
  code          TEXT UNIQUE NOT NULL,
  name          TEXT NOT NULL,
  annual_quota  NUMERIC(5,1) NOT NULL DEFAULT 0,
  is_paid       BOOLEAN NOT NULL DEFAULT TRUE,
  -- Whether unused days roll into next year's opening balance.
  carry_forward BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order    INT NOT NULL DEFAULT 0,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS leave_balances (
  id            BIGSERIAL PRIMARY KEY,
  employee_id   BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_type_id BIGINT NOT NULL REFERENCES leave_types(id) ON DELETE CASCADE,
  year          INT NOT NULL,
  opening       NUMERIC(5,1) NOT NULL DEFAULT 0,
  accrued       NUMERIC(5,1) NOT NULL DEFAULT 0,
  used          NUMERIC(5,1) NOT NULL DEFAULT 0,
  UNIQUE (employee_id, leave_type_id, year)
);

CREATE TABLE IF NOT EXISTS leaves (
  id              BIGSERIAL PRIMARY KEY,
  employee_id     BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  leave_type_id   BIGINT NOT NULL REFERENCES leave_types(id),
  from_date       DATE NOT NULL,
  to_date         DATE NOT NULL,
  -- Working days excluding holidays/weekly offs; halves allowed.
  days            NUMERIC(4,1) NOT NULL,
  is_half_day     BOOLEAN NOT NULL DEFAULT FALSE,
  reason          TEXT NOT NULL,
  address_on_leave TEXT,
  contact_on_leave TEXT,
  -- Person covering duties while away, for the approval letter.
  handover_to_id  BIGINT REFERENCES employees(id) ON DELETE SET NULL,

  status          TEXT NOT NULL DEFAULT 'submitted'
                    CHECK (status IN ('draft','submitted','reviewed','approved','rejected','cancelled')),
  reviewed_by     BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  review_decision TEXT CHECK (review_decision IN ('forwarded','rejected')),
  review_remark   TEXT,
  reviewed_at     TIMESTAMPTZ,
  approved_by     BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  approve_remark  TEXT,
  approved_at     TIMESTAMPTZ,
  -- Minted once on approval and reused for every later download.
  file_no         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (to_date >= from_date)
);
CREATE INDEX IF NOT EXISTS idx_leaves_employee ON leaves (employee_id, from_date DESC);
CREATE INDEX IF NOT EXISTS idx_leaves_status ON leaves (status);
CREATE INDEX IF NOT EXISTS idx_leaves_range ON leaves (from_date, to_date);

-- ---------------------------------------------------------------------------
-- Projects & activities (programme delivery)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS projects (
  id           BIGSERIAL PRIMARY KEY,
  code         TEXT UNIQUE NOT NULL,
  name         TEXT NOT NULL,
  description  TEXT,
  sport        TEXT,
  district     TEXT,
  state        TEXT DEFAULT 'Arunachal Pradesh',
  start_date   DATE,
  end_date     DATE,
  budget_paise BIGINT NOT NULL DEFAULT 0,
  funder       TEXT,
  lead_id      BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  status       TEXT NOT NULL DEFAULT 'active'
                 CHECK (status IN ('planned','active','completed','on_hold','dropped')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS activities (
  id                BIGSERIAL PRIMARY KEY,
  project_id        BIGINT REFERENCES projects(id) ON DELETE SET NULL,
  employee_id       BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  title             TEXT NOT NULL,
  activity_date     DATE NOT NULL,
  end_date          DATE,
  venue             TEXT,
  district          TEXT,
  -- Headcounts for the impact numbers that appear in reports.
  participants_male   INT NOT NULL DEFAULT 0,
  participants_female INT NOT NULL DEFAULT 0,
  participants_other  INT NOT NULL DEFAULT 0,
  beneficiaries     INT NOT NULL DEFAULT 0,
  description       TEXT,
  outcome           TEXT,
  challenges        TEXT,
  expenditure_paise BIGINT NOT NULL DEFAULT 0,

  status            TEXT NOT NULL DEFAULT 'submitted'
                      CHECK (status IN ('draft','submitted','reviewed','approved','rejected')),
  reviewed_by       BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  review_decision   TEXT CHECK (review_decision IN ('forwarded','rejected')),
  review_remark     TEXT,
  reviewed_at       TIMESTAMPTZ,
  approved_by       BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  approve_remark    TEXT,
  approved_at       TIMESTAMPTZ,
  file_no           TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_activities_project ON activities (project_id, activity_date DESC);
CREATE INDEX IF NOT EXISTS idx_activities_employee ON activities (employee_id, activity_date DESC);
CREATE INDEX IF NOT EXISTS idx_activities_status ON activities (status);

-- Photo evidence attached to an activity, embedded in the activity report PDF.
CREATE TABLE IF NOT EXISTS activity_photos (
  id          BIGSERIAL PRIMARY KEY,
  activity_id BIGINT NOT NULL REFERENCES activities(id) ON DELETE CASCADE,
  url         TEXT NOT NULL,
  caption     TEXT,
  sort_order  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Periodic work reports (daily / weekly / monthly staff reporting)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS work_reports (
  id              BIGSERIAL PRIMARY KEY,
  employee_id     BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  period          TEXT NOT NULL DEFAULT 'monthly'
                    CHECK (period IN ('daily','weekly','monthly','quarterly')),
  period_start    DATE NOT NULL,
  period_end      DATE NOT NULL,
  project_id      BIGINT REFERENCES projects(id) ON DELETE SET NULL,
  title           TEXT NOT NULL,
  summary         TEXT NOT NULL,
  achievements    TEXT,
  challenges      TEXT,
  next_plan       TEXT,

  status          TEXT NOT NULL DEFAULT 'submitted'
                    CHECK (status IN ('draft','submitted','reviewed','approved','rejected')),
  reviewed_by     BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  review_decision TEXT CHECK (review_decision IN ('forwarded','rejected')),
  review_remark   TEXT,
  reviewed_at     TIMESTAMPTZ,
  approved_by     BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  approve_remark  TEXT,
  approved_at     TIMESTAMPTZ,
  file_no         TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (period_end >= period_start)
);
CREATE INDEX IF NOT EXISTS idx_work_reports_employee ON work_reports (employee_id, period_start DESC);
CREATE INDEX IF NOT EXISTS idx_work_reports_status ON work_reports (status);

-- ---------------------------------------------------------------------------
-- TA / DA claims
-- ---------------------------------------------------------------------------

-- Per-km reimbursement by mode of travel, and DA slab by employee grade.
-- Rates change over time, so each row is validity-dated and claims resolve the
-- rate effective on the date of travel.
CREATE TABLE IF NOT EXISTS ta_rates (
  id             BIGSERIAL PRIMARY KEY,
  mode           TEXT NOT NULL,               -- bus / train / air / taxi / two_wheeler / own_car
  grade          TEXT,                        -- NULL = applies to all grades
  paise_per_km   BIGINT NOT NULL DEFAULT 0,
  -- Some modes (air, train) are reimbursed on actual fare, not per km.
  actual_fare    BOOLEAN NOT NULL DEFAULT FALSE,
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS da_rates (
  id                BIGSERIAL PRIMARY KEY,
  grade             TEXT NOT NULL,
  -- Daily allowance differs by where the duty was performed.
  area              TEXT NOT NULL DEFAULT 'ordinary'
                      CHECK (area IN ('ordinary','state_capital','metro')),
  da_paise_per_day  BIGINT NOT NULL DEFAULT 0,
  lodging_cap_paise BIGINT NOT NULL DEFAULT 0,
  effective_from    DATE NOT NULL DEFAULT CURRENT_DATE,
  is_active         BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (grade, area, effective_from)
);

CREATE TABLE IF NOT EXISTS ta_da_claims (
  id                BIGSERIAL PRIMARY KEY,
  claim_no          TEXT UNIQUE,               -- human reference, minted on submit
  employee_id       BIGINT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  project_id        BIGINT REFERENCES projects(id) ON DELETE SET NULL,
  activity_id       BIGINT REFERENCES activities(id) ON DELETE SET NULL,
  purpose           TEXT NOT NULL,
  from_date         DATE NOT NULL,
  to_date           DATE NOT NULL,
  -- Advance already drawn, deducted from the net payable.
  advance_paise     BIGINT NOT NULL DEFAULT 0,
  -- Denormalised totals, recomputed from ta_da_legs on every write so the
  -- listing and PDF never have to re-aggregate.
  fare_paise        BIGINT NOT NULL DEFAULT 0,
  da_paise          BIGINT NOT NULL DEFAULT 0,
  lodging_paise     BIGINT NOT NULL DEFAULT 0,
  other_paise       BIGINT NOT NULL DEFAULT 0,
  total_paise       BIGINT NOT NULL DEFAULT 0,
  net_payable_paise BIGINT NOT NULL DEFAULT 0,

  status            TEXT NOT NULL DEFAULT 'submitted'
                      CHECK (status IN ('draft','submitted','reviewed','approved','rejected','paid')),
  reviewed_by       BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  review_decision   TEXT CHECK (review_decision IN ('forwarded','rejected')),
  review_remark     TEXT,
  reviewed_at       TIMESTAMPTZ,
  approved_by       BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  approve_remark    TEXT,
  -- Authority may sanction less than claimed; PDF shows both figures.
  sanctioned_paise  BIGINT,
  approved_at       TIMESTAMPTZ,
  paid_at           TIMESTAMPTZ,
  payment_ref       TEXT,
  file_no           TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (to_date >= from_date)
);
CREATE INDEX IF NOT EXISTS idx_tada_employee ON ta_da_claims (employee_id, from_date DESC);
CREATE INDEX IF NOT EXISTS idx_tada_status ON ta_da_claims (status);

-- One row per journey leg / day of the claim.
CREATE TABLE IF NOT EXISTS ta_da_legs (
  id             BIGSERIAL PRIMARY KEY,
  claim_id       BIGINT NOT NULL REFERENCES ta_da_claims(id) ON DELETE CASCADE,
  travel_date    DATE NOT NULL,
  from_place     TEXT NOT NULL,
  to_place       TEXT NOT NULL,
  mode           TEXT NOT NULL,
  distance_km    NUMERIC(8,1) NOT NULL DEFAULT 0,
  -- Rate actually applied, snapshotted so later rate changes don't rewrite
  -- historical claims.
  rate_paise_per_km BIGINT NOT NULL DEFAULT 0,
  fare_paise     BIGINT NOT NULL DEFAULT 0,
  da_days        NUMERIC(4,1) NOT NULL DEFAULT 0,
  da_rate_paise  BIGINT NOT NULL DEFAULT 0,
  da_paise       BIGINT NOT NULL DEFAULT 0,
  lodging_paise  BIGINT NOT NULL DEFAULT 0,
  other_paise    BIGINT NOT NULL DEFAULT 0,
  other_note     TEXT,
  receipt_url    TEXT,
  sort_order     INT NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_tada_legs_claim ON ta_da_legs (claim_id, sort_order);

-- ---------------------------------------------------------------------------
-- CRM — donors, sponsors, partners, institutions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS crm_contacts (
  id             BIGSERIAL PRIMARY KEY,
  kind           TEXT NOT NULL DEFAULT 'person'
                   CHECK (kind IN ('person','organisation')),
  category       TEXT NOT NULL DEFAULT 'donor'
                   CHECK (category IN ('donor','sponsor','csr','partner','government',
                                       'school','club','athlete_family','media','vendor','other')),
  name           TEXT NOT NULL,
  organisation   TEXT,
  designation    TEXT,
  email          TEXT,
  phone          TEXT,
  whatsapp       TEXT,
  address        TEXT,
  district       TEXT,
  state          TEXT,
  pincode        TEXT,
  website        TEXT,
  -- Sales-style pipeline stage for fundraising follow-up.
  stage          TEXT NOT NULL DEFAULT 'new'
                   CHECK (stage IN ('new','contacted','interested','proposal_sent',
                                    'committed','donated','declined','dormant')),
  source         TEXT,
  tags           TEXT[],
  notes          TEXT,
  -- Staff member responsible for this relationship.
  owner_id       BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  -- Denormalised rollups maintained by the interactions/deals endpoints.
  total_given_paise BIGINT NOT NULL DEFAULT 0,
  last_contacted_at TIMESTAMPTZ,
  next_action      TEXT,
  next_action_on   DATE,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_by     BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_crm_owner ON crm_contacts (owner_id);
CREATE INDEX IF NOT EXISTS idx_crm_stage ON crm_contacts (stage);
CREATE INDEX IF NOT EXISTS idx_crm_next_action ON crm_contacts (next_action_on)
  WHERE next_action_on IS NOT NULL;

CREATE TABLE IF NOT EXISTS crm_interactions (
  id            BIGSERIAL PRIMARY KEY,
  contact_id    BIGINT NOT NULL REFERENCES crm_contacts(id) ON DELETE CASCADE,
  employee_id   BIGINT NOT NULL REFERENCES employees(id) ON DELETE SET NULL,
  kind          TEXT NOT NULL DEFAULT 'call'
                  CHECK (kind IN ('call','meeting','email','whatsapp','visit','event','other')),
  happened_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  summary       TEXT NOT NULL,
  outcome       TEXT,
  next_action     TEXT,
  next_action_on  DATE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_crm_int_contact ON crm_interactions (contact_id, happened_at DESC);

-- Pledges and received contributions against a contact.
CREATE TABLE IF NOT EXISTS crm_contributions (
  id            BIGSERIAL PRIMARY KEY,
  contact_id    BIGINT NOT NULL REFERENCES crm_contacts(id) ON DELETE CASCADE,
  project_id    BIGINT REFERENCES projects(id) ON DELETE SET NULL,
  amount_paise  BIGINT NOT NULL DEFAULT 0,
  kind          TEXT NOT NULL DEFAULT 'cash'
                  CHECK (kind IN ('cash','bank','upi','cheque','in_kind')),
  status        TEXT NOT NULL DEFAULT 'pledged'
                  CHECK (status IN ('pledged','received','cancelled')),
  received_on   DATE,
  reference     TEXT,
  remark        TEXT,
  recorded_by   BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_crm_contrib_contact ON crm_contributions (contact_id);

-- ---------------------------------------------------------------------------
-- Org settings (single row) & audit trail
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS settings (
  id                  INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  org_name            TEXT NOT NULL DEFAULT 'The NE Sports Foundation',
  tagline             TEXT NOT NULL DEFAULT 'A Non-Profit Company',
  registration        TEXT NOT NULL DEFAULT 'Registered under section 8 of the Companies Act, 2013',
  websites            TEXT NOT NULL DEFAULT 'www.nesportsfoundation.in & www.nesports.in',
  email               TEXT NOT NULL DEFAULT 'nesportsf@gmail.com',
  mobile              TEXT NOT NULL DEFAULT '+91 8414948978',
  cin                 TEXT NOT NULL DEFAULT 'U88900AR2024NPL014171',
  gstin               TEXT NOT NULL DEFAULT '12AAJCN8454F1ZF',
  darpan_id           TEXT NOT NULL DEFAULT 'AR/2024/0446247',
  address             TEXT,
  file_no_prefix      TEXT NOT NULL DEFAULT 'NESF/ADMIN',
  -- Radius within which a check-in counts as on-site.
  geofence_radius_m   INT NOT NULL DEFAULT 300,
  office_lat          DOUBLE PRECISION,
  office_lng          DOUBLE PRECISION,
  work_start          TIME NOT NULL DEFAULT '09:30',
  work_end            TIME NOT NULL DEFAULT '17:30',
  -- ISO weekday numbers treated as weekly offs (1=Mon .. 7=Sun).
  weekly_offs         INT[] NOT NULL DEFAULT '{7}',
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS audit_log (
  id          BIGSERIAL PRIMARY KEY,
  employee_id BIGINT REFERENCES employees(id) ON DELETE SET NULL,
  action      TEXT NOT NULL,
  entity      TEXT,
  entity_id   BIGINT,
  detail      JSONB,
  ip          TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log (entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log (created_at DESC);
