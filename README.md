# NESF Core

HR and CRM for **The NE Sports Foundation** — a native Flutter app for staff,
backed by its own Node/Postgres API. Every approved submission is issued as a PDF
on foundation letterhead, carrying a sequential file number and the signature of
the approving authority.

```
nesf-core/
├── api/    Node 24 + Express + Postgres + pdfkit  (the API and PDF engine)
└── app/    Flutter 3.44                            (Android, iOS and Web)
```

## What staff can do

| Module | Flow | Document issued |
|---|---|---|
| **Attendance** | Selfie + GPS check-in / check-out, geofenced against the person's base | Monthly attendance register (landscape) |
| **Leave** | Apply → reporting officer recommends → authority approves | Leave approval letter |
| **Work reports** | Daily / weekly / monthly / quarterly → review → approve | Work report |
| **TA/DA** | Multi-leg claim, priced server-side from rate tables → review → sanction | Travelling & Daily Allowance bill |
| **Activities** | Project activity with participation counts and photos → review → approve | Activity report (photos included) |
| **Projects** | Impact and budget rollups from approved activities | Consolidated project report |
| **CRM** | Donors, sponsors, CSR, schools and partners; interactions, pipeline, contributions | — |
| **Calendar** | Own attendance + everyone's approved leave + declared holidays | — |

## Roles

Approvals are a deliberate two-stage chain, and nobody can act on their own
submission.

| Role | Can do |
|---|---|
| `staff` | Submit own attendance, leave, reports, TA/DA, activities; own CRM contacts |
| `manager` | The above, plus **recommend** submissions from their direct reportees |
| `authority` | **Final approval** — their signature is stamped on the issued PDF |
| `admin` | Everything, plus staff records, rates, holidays and org settings |

## Getting started

### Quick start (One command)

**Linux/macOS:**
```bash
./scripts/setup-dev.sh
```

**Windows (PowerShell):**
```bash
.\scripts\setup-dev.bat
```

This installs dependencies, starts a local Postgres database, migrates the schema, and seeds initial data.

---

### Manual setup

#### 1. Database

Start a local Postgres database (requires Docker):

```bash
docker-compose up -d
```

Or use your own Postgres 15+ instance and set `DATABASE_URL` in `api/.env`:

```bash
DATABASE_URL=postgres://user:password@localhost:5432/nesf_core_dev
```

#### 2. API

```bash
cd api
npm install
npm run migrate           # applies schema.sql (idempotent, also used for upgrades)
npm run seed              # leave types, TA/DA rates, holidays, founding admin
npm start                 # http://localhost:4000
```

Check it is healthy:

```bash
curl http://localhost:4000/health
```

### 2. Import existing staff (optional, one time)

Pulls the staff directory out of the older `thenesports-api` database so the
office does not re-type everyone. Matches on **email**, so it is safe to re-run.

```bash
cd api
LEGACY_DATABASE_URL=postgres://user:pass@host:5432/thenesports npm run import:employees
```

Imported accounts get a temporary password (printed at the end of the run) and
must change it at first sign-in. Afterwards, in the app:

1. Give whoever signs documents the **`authority`** role (Settings → Staff).
2. Have them upload their signature (Profile → Signature) — until then, issued
   PDFs print a blank signature line.

#### 3. App

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE=http://localhost:4000
```

`API_BASE` defaults to `https://app.nesportsfoundation.in` in release builds. In
debug it defaults to `http://10.0.2.2:4000` on device/emulator (the Android
emulator's route to the host) and `http://localhost:4000` on web — so pass the
define explicitly whenever you are not on an emulator.

#### 4. Import existing staff (optional, one time)

Pulls the staff directory out of the older `thenesports-api` database so the
office does not re-type everyone. Matches on **email**, so it is safe to re-run.

```bash
cd api
LEGACY_DATABASE_URL=postgres://user:pass@host:5432/thenesports npm run import:employees
```

Imported accounts get a temporary password (printed at the end of the run) and
must change it at first sign-in. Afterwards:

1. Give whoever signs documents the **`authority`** role (Settings → Staff).
2. Have them upload their signature (Profile → Signature) — until then, issued
   PDFs print a blank signature line.

## Tests

### API Tests

**End-to-end tests** (approval chain, PDF issue, access control, server-side pricing):
```bash
cd api && npm start          # in one terminal
cd api && npm run test:e2e   # 60+ checks
```

**Media privacy tests** (uploads stay private, access rules enforced):
```bash
cd api && npm run test:media # 21 checks
```

### Flutter App Tests

**Widget tests** (formatting and layout):
```bash
cd app && flutter test test/widget_test.dart
```

**API contract tests** (Dart client against live API, catches breaking changes):
```bash
cd app && flutter test test/api_contract_test.dart --dart-define=API_BASE=http://localhost:4000
```
```

## How documents are numbered

Every issued document draws the next number from a single shared register
(`document_log`), formatted `NESF/ADMIN/<year>/<seq>` with the sequence
restarting each January. The prefix is editable in Settings.

The number is minted **once**, at the moment of approval, and stored on the
record — so re-downloading a PDF never consumes a new number. The full register
is visible to admins at `GET /api/settings/documents`.

## Notable design decisions

- **Money is stored in paise** (`BIGINT`), never floats, and formatted to Indian
  digit grouping at the edges.
- **TA/DA is priced entirely server-side.** The client sends distances, ticket
  amounts and receipts; rates come from `ta_rates` / `da_rates`, and the rate
  actually applied is snapshotted onto each leg so later rate changes never
  rewrite historical claims. A mode with no rate configured is rejected rather
  than silently priced at zero.
- **Attendance never silently loses a punch.** The selfie is mandatory; a missing
  GPS fix is confirmed with the user rather than filed quietly; the distance from
  base and the fix accuracy are both stored, so a poor fix is visible on the
  record. Off-base check-ins are recorded as field duty, not rejected.
- **Leave days exclude holidays and weekly offs**, so nobody is debited for a
  Sunday inside a leave spell.
- **Approvals are audited by construction** — the reviewer and approver ids are
  stored on the row, and it is their stored signatures that the PDF stamps.
- **Uploaded files are private.** Attendance selfies, scanned signatures,
  expense receipts and activity photographs are staff personal data, so the
  database stores a storage *key*, never a public URL, and nothing is served
  statically. Reads go through `GET /api/media/<key>`, which requires a session
  and applies rules per category: a selfie is visible to the staff member and
  their reporting line, a receipt to the claimant and their approvers, and
  signatures / profile photos / activity photographs to any signed-in staff
  member. The PDF engine reads objects straight from disk or Cloud Storage, so
  rendering never needs a public URL and the bucket takes no `allUsers` binding.
- **Sign-in throttling is keyed on the account, not the IP.** The whole office
  shares one NAT'd address, so an IP-only limit would let staff lock each other
  out at the morning check-in while doing nothing extra against an attacker
  working on one account. Ten failed attempts per account per 15 minutes, plus a
  loose per-IP ceiling to blunt account cycling. Successful sign-ins don't count
  against either.

## Dependency note

`api/package.json` pins `uuid` forward via `overrides`.
`@google-cloud/storage` pulls `uuid@9` transitively through `gaxios` and
`teeny-request`, which carries [GHSA-w5hq-g745-h8pq](https://github.com/advisories/GHSA-w5hq-g745-h8pq).
Only `v3`/`v5`/`v6` with a caller-supplied buffer are affected and the SDK uses
`v4`, so it was not exploitable here — but pinning to `uuid@11` keeps
`npm audit` clean and the SDK was verified to still work against it. Drop the
override once `@google-cloud/storage` updates its own dependency.

## Pre-Deployment Checklist

Before deploying to production, verify:

### Code & Testing
- [ ] All P0 bugs fixed and committed
- [ ] E2E test suite passes (`npm run test:e2e` → 60+ checks)
- [ ] Media privacy tests pass (`npm run test:media` → 21 checks)
- [ ] No console warnings/errors on Flutter web build
- [ ] Android APK builds and installs on test device

### Configuration
- [ ] Admin password changed from `ChangeMe@123`
- [ ] Authority signature uploaded (Profile → Signature)
- [ ] Office geofence configured (Settings: latitude, longitude, radius)
- [ ] TA/DA rates set (not placeholders)
- [ ] Holiday calendar for Arunachal Pradesh 2026 confirmed

### Infrastructure
- [ ] Cloud SQL database created and seeded
- [ ] Cloud Storage bucket created
- [ ] Secrets stored in Secret Manager
- [ ] Cloud Run service deployed
- [ ] Domain mapping configured
- [ ] SSL certificate issued and verified

### Staff Readiness
- [ ] All employees have set their attendance base location
- [ ] Manager and authority roles assigned
- [ ] Test workflow: attendance → leave → TA/DA → document PDF

See **[DEPLOYMENT.md](DEPLOYMENT.md)** for detailed Cloud Run + Cloud SQL, DNS, and Android build instructions.
