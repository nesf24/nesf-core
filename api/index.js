import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import rateLimit from 'express-rate-limit';

import pool from './src/db.js';
import authRoutes from './src/routes/auth.js';
import employeeRoutes from './src/routes/employees.js';
import attendanceRoutes from './src/routes/attendance.js';
import attendanceConfigRoutes from './src/routes/attendance-config.js';
import appInfoRoutes from './src/routes/app-info.js';
import leaveRoutes from './src/routes/leaves.js';
import reportRoutes from './src/routes/reports.js';
import tadaRoutes from './src/routes/tada.js';
import projectRoutes from './src/routes/projects.js';
import crmRoutes from './src/routes/crm.js';
import dashboardRoutes from './src/routes/dashboard.js';
import settingsRoutes from './src/routes/settings.js';
import mediaRoutes from './src/routes/media.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
app.set('trust proxy', 1);

const origins = (process.env.CORS_ORIGINS || '')
  .split(',').map((s) => s.trim()).filter(Boolean);

app.use(cors({
  origin(origin, cb) {
    if (!origin || origins.includes(origin)) return cb(null, true);
    cb(new Error(`Origin ${origin} is not allowed`));
  },
  credentials: true,
}));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));
app.use('/api', rateLimit({ windowMs: 60_000, limit: 300, standardHeaders: true }));

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

// Serve static web files
const possibleWebRoots = [
  path.join(__dirname, '../public'),
  path.join(__dirname, 'public'),
  process.env.WEB_ROOT ? path.resolve(process.env.WEB_ROOT) : null,
].filter(Boolean);

let webRoot = null;
for (const p of possibleWebRoots) {
  if (fs.existsSync(path.join(p, 'index.html'))) {
    webRoot = p;
    console.log(`[nesf-core-api] serving web from ${p}`);
    break;
  }
}

if (webRoot) {
  // Serve index.html at root
  app.get('/', (req, res) => {
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.sendFile(path.join(webRoot, 'index.html'));
  });

  // Serve static files
  app.use(express.static(webRoot, {
    index: false,
    setHeaders(res, filePath) {
      const name = path.basename(filePath);
      if (name === 'index.html' || name === 'flutter_service_worker.js' || name === 'version.json') {
        res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      } else {
        res.setHeader('Cache-Control', 'public, max-age=604800');
      }
      if (filePath.endsWith('.apk')) {
        res.setHeader('Content-Type', 'application/vnd.android.package-archive');
        res.setHeader('Content-Disposition', `attachment; filename="${name}"`);
      }
    },
  }));

  // Client-side routing fallback
  app.get(/^(?!\/api\/|\/health$).*/, (req, res, next) => {
    if (!req.accepts('html')) return next();
    res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.sendFile(path.join(webRoot, 'index.html'));
  });
}

// 404 handler
app.use((req, res) => res.status(404).json({ error: `No such endpoint: ${req.method} ${req.path}` }));

// Error handler
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

export default app;
