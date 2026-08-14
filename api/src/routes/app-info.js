import { Router } from 'express';

const router = Router();

// Get latest app version and download URL
router.get('/latest-version', (req, res) => {
  // Update this version number when you build a new APK
  const latestVersion = '1.0.1';

  res.json({
    version: latestVersion,
    apk_url: `https://nesf-core.vercel.app/NESF-Core-v${latestVersion}.apk`,
    force: false, // Set to true to force all users to update
  });
});

export default router;
