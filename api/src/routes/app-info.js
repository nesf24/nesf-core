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
    const apkPath = path.join(process.cwd(), 'public/NESF-Core-v2.1-google-signin.apk');

    if (!fs.existsSync(apkPath)) {
      return res.status(404).json({ error: 'APK not found' });
    }

    res.setHeader('Content-Type', 'application/vnd.android.package-archive');
    res.setHeader('Content-Disposition', 'attachment; filename="NESF-Core-v2.1.apk"');
    res.setHeader('Content-Length', fs.statSync(apkPath).size);

    const stream = fs.createReadStream(apkPath);
    stream.pipe(res);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

export default router;
