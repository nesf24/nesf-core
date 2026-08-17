import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import rateLimit from 'express-rate-limit';

import pool from './db.js';
import authRoutes from './routes/auth.js';
import employeeRoutes from './routes/employees.js';
import attendanceRoutes from './routes/attendance.js';
import attendanceConfigRoutes from './routes/attendance-config.js';
import appInfoRoutes from './routes/app-info.js';
import { startAttendanceScheduler } from './services/scheduler.js';
import leaveRoutes from './routes/leaves.js';
import reportRoutes from './routes/reports.js';
import tadaRoutes from './routes/tada.js';
import projectRoutes from './routes/projects.js';
import crmRoutes from './routes/crm.js';
import dashboardRoutes from './routes/dashboard.js';
import settingsRoutes from './routes/settings.js';
import mediaRoutes from './routes/media.js';

const app = express();
app.set('trust proxy', 1); // Cloud Run terminates TLS upstream.

const origins = (process.env.CORS_ORIGINS || '')
  .split(',').map((s) => s.trim()).filter(Boolean);

app.use(cors({
  origin(origin, cb) {
    // Native Flutter clients send no Origin header; only browsers are gated.
    if (!origin || origins.includes(origin)) return cb(null, true);
    cb(new Error(`Origin ${origin} is not allowed`));
  },
  credentials: true,
}));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

// Broad ceiling so a misbehaving client cannot exhaust the instance; the login
// endpoint has its own tighter limit.
app.use('/api', rateLimit({ windowMs: 60_000, limit: 300, standardHeaders: true }));

// Uploads are NOT served statically. Selfies, signatures, receipts and activity
// photographs are staff personal data, so they go through /api/media, which
// requires a session and applies per-category access rules.

app.get('/health', async (_req, res) => {
  try {
    const timeout = new Promise((_, reject) =>
      setTimeout(() => reject(new Error('database query timeout (5s)')), 5000)
    );
    await Promise.race([pool.query('SELECT 1'), timeout]);
    res.json({ ok: true, service: 'nesf-core-api', db: 'up' });
  } catch (err) {
    console.error('[health] database check failed:', err.message);
    res.status(503).json({ ok: false, db: 'down', error: err.message });
  }
});

app.use('/api/auth', authRoutes);
app.use('/api/employees', employeeRoutes);
app.use('/api/attendance', attendanceRoutes);
app.use('/api/attendance-config', attendanceConfigRoutes);
app.use('/api/app', appInfoRoutes);
app.use('/api/leaves', leaveRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/tada', tadaRoutes);
app.use('/api/projects', projectRoutes);
app.use('/api/crm', crmRoutes);
app.use('/api/dashboard', dashboardRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/media', mediaRoutes);

// ---------------------------------------------------------------------------
// Flutter web build
//
// app.nesportsfoundation.in serves the staff web app and the API from the same
// origin, so the native app and the browser build share one base URL and there
// is no cross-origin preflight. `npm run build:web` copies the Flutter build
// into ./public; when it is absent (a pure API deployment, or local API-only
// development) these handlers simply do not mount.
// ---------------------------------------------------------------------------
// Resolve webRoot - try multiple paths to handle different deployment environments
let webRoot = null;

try {
  // Try hardcoded paths first (most specific to least specific)
  // __dirname is always /app/src in Cloud Run, /absolute/path/to/api/src locally
  const possiblePaths = [
    // Cloud Run: __dirname=/app/src, need /app/public
    path.resolve(path.join(__dirname, '../public')),
    // Local development: __dirname=.../api/src, might be launched from root
    path.resolve(path.join(__dirname, '../../public')),
    // Local development: launched from api/ directory
    path.resolve(path.join(__dirname, '../public')),
    // Fallback: relative to cwd
    path.resolve(path.join(process.cwd(), 'public')),
    path.resolve(path.join(process.cwd(), 'api', 'public')),
  ];

  for (const p of possiblePaths) {
    try {
      const indexPath = path.join(p, 'index.html');
      const exists = fs.existsSync(indexPath);
      console.log(`[nesf-core-api] Checking ${p}... ${exists ? '✓ FOUND' : '✗ not found'}`);
      if (exists) {
        webRoot = path.resolve(p);
        console.log(`[nesf-core-api] ✅ Found web build at: ${webRoot}`);
        break;
      }
    } catch (_e) {
      console.log(`[nesf-core-api] Error checking path ${p}: ${_e.message}`);
    }
  }

  if (!webRoot) {
    console.log(`[nesf-core-api] ❌ Web build not found at any path. Running API-only mode.`);
    console.log(`[nesf-core-api] Current working directory: ${process.cwd()}`);
    console.log(`[nesf-core-api] __dirname: ${__dirname}`);
  }
} catch (_e) {
  console.error(`[nesf-core-api] Error resolving webRoot: ${_e.message}`);
}

if (webRoot && fs.existsSync(path.join(webRoot, 'index.html'))) {
  // Explicitly serve index.html at root
  app.get('/', (req, res) => {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    try {
      res.sendFile(path.join(webRoot, 'index.html'));
    } catch (err) {
      console.error('[root handler error]', err.message);
      res.status(500).json({ error: 'Failed to serve index.html: ' + err.message });
    }
  });

  app.use(express.static(webRoot, {
    index: false,
    // Flutter fingerprints its assets, but index.html and the service worker
    // must never be cached or staff keep loading an old build after a deploy.
    setHeaders(res, filePath) {
      const name = path.basename(filePath);
      if (name === 'index.html' || name === 'flutter_service_worker.js' || name === 'version.json') {
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      } else {
        res.setHeader('Cache-Control', 'public, max-age=604800');
      }
      // APK files must have the correct MIME type for browser downloads
      if (filePath.endsWith('.apk')) {
        res.setHeader('Content-Type', 'application/vnd.android.package-archive');
        res.setHeader('Content-Disposition', `attachment; filename="${name}"`);
      }
    },
  }));

  // Client-side routing: any non-API GET falls back to the app shell so a deep
  // link such as /leaves/apply loads instead of 404ing.
  app.get(/^(?!\/api\/|\/health$).*/, (req, res, next) => {
    if (!req.accepts('html')) return next();
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.sendFile(path.join(webRoot, 'index.html'));
  });

  console.log(`[nesf-core-api] serving the web app from ${webRoot}`);
} else {
  console.log(`[nesf-core-api] Web build not found, registering fallback root handler`);
  // Serve a simple HTML page at root if web build not found
  app.get('/', (req, res) => {
    res.setHeader('Content-Type', 'text/html');
    res.send(`
      <!DOCTYPE html>
      <html>
      <head>
        <title>NESF Core API</title>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
      </head>
      <body>
        <h1>NESF Core API</h1>
        <p>API is running. For the web UI, use a mobile device with the NESF Core app.</p>
        <p><a href="/health">Health Check</a></p>
      </body>
      </html>
    `);
  });
}

// Explicit catch for root path as final fallback
app.all('/', (req, res, next) => {
  console.log('[root catch-all] webRoot:', webRoot);
  if (webRoot) {
    const indexPath = path.join(webRoot, 'index.html');
    const hasIndex = fs.existsSync(indexPath);
    console.log('[root catch-all] indexPath:', indexPath, '- exists:', hasIndex);
    if (hasIndex && req.accepts('html')) {
      console.log('[root catch-all] Serving index.html');
      return res.sendFile(indexPath);
    }
  } else {
    console.log('[root catch-all] webRoot is null, serving fallback');
    return res.status(200).send(`<!DOCTYPE html>
<html>
<head><title>NESF Core API</title></head>
<body>
<h1>NESF Core API</h1>
<p>Web build location: ${process.cwd()}</p>
<p>Web build not found. API is running on /api/*</p>
<p><a href="/health">Health Check</a></p>
</body>
</html>`);
  }
  console.log('[root catch-all] Calling next()');
  next();
});

// Final fallback: return 404 for everything else
app.use((req, res) => {
  res.status(404).json({ error: `No such endpoint: ${req.method} ${req.path}` });
});

// Central error handler. Client-safe messages for known statuses; opaque for the
// rest, with the detail kept in the server log.
app.use((err, req, res, _next) => {
  const status = err.status || (err.code === 'LIMIT_FILE_SIZE' ? 413 : 500);

  if (status >= 500) {
    console.error(`[error] ${req.method} ${req.path}:`, err);
  }

  res.status(status).json({
    error: status >= 500 ? 'Something went wrong. Please try again.' : err.message,
    ...(err.fields ? { fields: err.fields } : {}),
  });
});

const port = Number(process.env.PORT) || 4000;
app.listen(port, () => {
  console.log(`[nesf-core-api] listening on :${port}`);

  // Start the attendance reminder scheduler
  startAttendanceScheduler();
});
