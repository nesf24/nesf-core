# Deploying NESF Core

Target: **`app.nesportsfoundation.in`** serving both the staff web app and the
API from a single Cloud Run service, plus an Android build for staff phones.

Conventions below match the existing `thenesports-api` deployment: GCP project
`thenesports-api-prod`, region `asia-south1`, Cloud SQL instance
`thenesports-db`, Artifact Registry repo `cloud-run-source-deploy`.

> **Nothing here has been run against production.** The API, the PDF engine, the
> web bundle and the Android APK were all built and verified locally; the GCP and
> DNS steps are written from the existing project's working configuration and
> still need to be executed by someone with access.

---

## 1. Why one service

`AppConfig.apiBase` resolves to the page's own origin on web, so the browser
build calls `/api/...` same-origin — no CORS preflight, one certificate, one
deploy. The native Android/iOS builds are pointed at the same domain with
`--dart-define`.

```
app.nesportsfoundation.in
├── /            → Flutter web app (api/public)
├── /api/*       → JSON API
├── /uploads/*   → only when STORAGE_DRIVER=local (not used in production)
└── /health      → readiness probe
```

---

## 2. Database

The schema is standalone — do **not** point it at the `thenesports` database.

```bash
# Create the database on the existing Cloud SQL instance
gcloud sql databases create nesf_core --instance=thenesports-db

# Create its own user
gcloud sql users create nesf_core \
  --instance=thenesports-db \
  --password='<a strong password>'
```

Apply the schema and seed. Easiest via the Cloud SQL Auth Proxy from your
machine:

```bash
cloud-sql-proxy thenesports-api-prod:asia-south1:thenesports-db --port 5433 &

cd api
DATABASE_URL='postgres://nesf_core:<password>@localhost:5433/nesf_core' npm run migrate
DATABASE_URL='postgres://nesf_core:<password>@localhost:5433/nesf_core' \
  SEED_ADMIN_EMAIL='biki@nesportsfoundation.in' \
  SEED_ADMIN_PASSWORD='<a strong temporary password>' npm run seed
```

`npm run migrate` is idempotent — it is also how later schema changes roll out.

### Import the existing staff (one time)

```bash
cd api
DATABASE_URL='postgres://nesf_core:<password>@localhost:5433/nesf_core' \
LEGACY_DATABASE_URL='postgres://<thenesports user>:<password>@localhost:5433/thenesports' \
  npm run import:employees
```

Matches on email, so it is safe to re-run. It prints the temporary password
issued to imported accounts — hand that to staff, and they must change it at
first sign-in.

---

## 3. Secrets

Never put these in `cloudbuild.yaml` or the image.

```bash
# Generate a strong signing key
node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"

printf '%s' '<that value>'      | gcloud secrets create nesf-core-jwt-secret --data-file=-
printf '%s' '<db password>'     | gcloud secrets create nesf-core-db-password --data-file=-
```

Grant the Cloud Run service account access:

```bash
PROJECT_NUMBER=$(gcloud projects describe thenesports-api-prod --format='value(projectNumber)')
SA="$PROJECT_NUMBER-compute@developer.gserviceaccount.com"

for s in nesf-core-jwt-secret nesf-core-db-password; do
  gcloud secrets add-iam-policy-binding "$s" \
    --member="serviceAccount:$SA" --role=roles/secretmanager.secretAccessor
done
```

---

## 4. File storage

The Cloud Run filesystem is ephemeral, so attendance selfies, signatures,
receipts and activity photos **must** go to Cloud Storage in production.

```bash
gcloud storage buckets create gs://nesf-core-uploads \
  --location=asia-south1 --uniform-bucket-level-access

# Only the service account needs access. There is deliberately no allUsers
# binding: nothing in this bucket is publicly readable.
gcloud storage buckets add-iam-policy-binding gs://nesf-core-uploads \
  --member="serviceAccount:$SA" --role=roles/storage.objectAdmin
```

> **The bucket stays private.** Attendance selfies, signatures, receipts and
> activity photographs are staff personal data, so the database stores a storage
> *key* rather than a URL, and the only way to read one back is
> `GET /api/media/<key>`, which requires a session and applies per-category
> rules: a selfie is visible to the staff member and their reporting line, a
> receipt to the claimant and their approvers, and signatures / profile photos /
> activity photographs to any signed-in member of staff. The PDF engine reads
> objects through the GCS SDK with the service account, so rendering a letterhead
> document never needs a public URL.

---

## 5. Build and deploy

```bash
cd app && flutter pub get && cd ..

# Compile the web app into api/public (empty API_BASE = same-origin)
cd api && npm run build:web

# Build the image and deploy
gcloud builds submit --config=cloudbuild.yaml .
```

Then set the runtime configuration once:

```bash
gcloud run services update nesf-core-api --region=asia-south1 \
  --set-env-vars="NODE_ENV=production,\
INSTANCE_UNIX_SOCKET=/cloudsql/thenesports-api-prod:asia-south1:thenesports-db,\
DB_USER=nesf_core,DB_NAME=nesf_core,\
STORAGE_DRIVER=gcs,GCS_BUCKET=nesf-core-uploads,\
CORS_ORIGINS=https://app.nesportsfoundation.in" \
  --set-secrets="JWT_SECRET=nesf-core-jwt-secret:latest,DB_PASSWORD=nesf-core-db-password:latest" \
  --min-instances=0 --max-instances=4 --memory=1Gi --cpu=1 --timeout=120
```

`--memory=1Gi` because PDF rendering holds the logo and any embedded photos in
memory. `--min-instances=0` keeps cost down; the first request after idle takes a
few seconds. Raise to 1 if staff complain about the morning check-in being slow.

---

## 6. DNS for app.nesportsfoundation.in

`nesportsfoundation.in` is on Cloudflare.

```bash
gcloud beta run domain-mappings create \
  --service=nesf-core-api \
  --domain=app.nesportsfoundation.in \
  --region=asia-south1
```

The command prints the DNS records to add. In Cloudflare, for the `app` record:

- Add exactly the record type Google returns (usually a `CNAME` to
  `ghs.googlehosted.com`).
- **Set the proxy status to "DNS only" (grey cloud), not proxied.** Orange-cloud
  proxying in front of a Cloud Run domain mapping breaks the certificate
  challenge, and the mapping stays stuck on "pending certificate".
- SSL/TLS mode must be **Full (strict)** if you later re-enable proxying.

Certificate issuance takes up to ~30 minutes. Check with:

```bash
gcloud beta run domain-mappings describe \
  --domain=app.nesportsfoundation.in --region=asia-south1

curl -sS https://app.nesportsfoundation.in/health
```

> `app.thenesports.com` previously pointed at a proxy that is now dead — this is
> a different hostname on a different domain and does not conflict with it.

---

## 7. Post-deploy checklist

The approval chain cannot issue a signed document until these are done.

1. Sign in as the seeded admin and **change the password immediately**.
2. Settings → Staff: give whoever signs documents the **`authority`** role.
3. That person: Profile → Signature → upload a photo of their signature.
   Until then every issued PDF prints a blank signature line.
4. Settings: set the office latitude/longitude and the geofence radius
   (default 300 m), so office and field check-ins can be told apart.
5. Settings → Holidays: confirm this year's list against the Arunachal Pradesh
   gazette. The seed loads the commonly observed dates only, and holidays affect
   how many days a leave application is debited.
6. Settings → TA/DA rates: confirm the per-km and DA figures against the
   foundation's actual policy. The seed ships placeholder rates.
7. Ask each staff member to set their attendance base (Profile → Attendance base)
   from their usual place of work.

Smoke test against production:

```bash
curl -sS https://app.nesportsfoundation.in/health
# {"ok":true,"service":"nesf-core-api","db":"up"}
```

---

## 8. Android build for staff phones

```bash
cd app

# Split per ABI — a universal APK is ~54 MB, the per-ABI ones roughly a third
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE=https://app.nesportsfoundation.in
```

Output: `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (the one
almost every current handset needs).

For the Play Store, build an app bundle instead:

```bash
flutter build appbundle --release \
  --dart-define=API_BASE=https://app.nesportsfoundation.in
```

### Signing

The release build above uses the debug signing key, which is fine for
side-loading but **not** acceptable for the Play Store, and APKs signed with it
cannot be upgraded by a later properly-signed build. Before distributing widely:

```bash
keytool -genkey -v -keystore nesf-core-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then create `app/android/key.properties` (keep it out of version control) and
wire it into `android/app/build.gradle.kts` as a release `signingConfig`.

### Build notes

- **JDK 21** is required; 17 fails on the current Android Gradle Plugin.
- `android/gradle.properties` sets `kotlin.incremental=false`. This project sits
  at `D:\new app\...` and the space in that path breaks the Kotlin incremental
  compiler ("Could not close incremental caches"). Remove the line if the
  project ever moves somewhere without a space.
- iOS needs a Mac with Xcode. The usage strings for camera, location and photo
  library are already in `ios/Runner/Info.plist`; without them iOS terminates the
  app on first camera or GPS access.

---

## 9. Rolling out a change

```bash
cd api
npm run build:web                        # if the Flutter app changed
gcloud builds submit --config=cloudbuild.yaml .
npm run migrate                          # via the proxy, if schema.sql changed
```

Schema changes are additive (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT
EXISTS`), so migrating before deploying the new image is safe and avoids a window
where the new code expects a column that does not exist yet.

## 10. Backups

```bash
gcloud sql instances patch thenesports-db \
  --backup-start-time=19:00 \
  --retained-backups-count=14
```

19:00 UTC is 00:30 IST — outside office hours. NESF Core holds the attendance and
approval record that salary and TA/DA payments are based on, so confirm backups
are actually being retained rather than assuming the instance default.
