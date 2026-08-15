import { Router } from 'express';
import fs from 'fs';
import path from 'path';

const router = Router();

// Get latest app version and download URL
router.get('/latest-version', (req, res) => {
  res.json({
    version: '2.1',
    apk_url: 'https://app.nesportsfoundation.in/api/app/download',
    force: false,
  });
});

// Serve APK download
router.get('/download', (req, res) => {
  try {
    // Try multiple possible paths where APK might be located
    const possiblePaths = [
      path.join(process.cwd(), 'public/nesf-core.apk'),
      path.join(process.cwd(), 'public/NESF-Core-v2.1.apk'),
      path.join(process.cwd(), '../public/nesf-core.apk'),
      path.join(process.cwd(), '../public/NESF-Core-v2.1.apk'),
      path.join(process.cwd(), 'NESF-Core-v2.1.apk'),
      path.join(process.cwd(), '../NESF-Core-v2.1.apk'),
      path.join(process.cwd(), 'public/NESF-Core-v2.1-google-signin.apk'),
    ];

    let apkPath;
    for (const p of possiblePaths) {
      if (fs.existsSync(p)) {
        apkPath = p;
        break;
      }
    }

    if (!apkPath) {
      console.error('APK not found in any of:', possiblePaths);
      console.error('CWD:', process.cwd());
      console.error('Files in CWD:', fs.readdirSync(process.cwd()).slice(0, 20));
      return res.status(404).json({ error: 'APK not found', cwd: process.cwd() });
    }

    const stats = fs.statSync(apkPath);
    res.setHeader('Content-Type', 'application/vnd.android.package-archive');
    res.setHeader('Content-Disposition', 'attachment; filename="NESF-Core-v2.1.apk"');
    res.setHeader('Content-Length', stats.size);

    const stream = fs.createReadStream(apkPath);
    stream.pipe(res);
  } catch (err) {
    console.error('APK download error:', err);
    res.status(500).json({ error: err.message });
  }
});

export default router;
