/**
 * Builds the Flutter web app and copies it into api/public, so a single Cloud
 * Run service serves both the staff web app and the API from
 * app.nesportsfoundation.in.
 *
 *   npm run build:web
 *
 * API_BASE is left empty on purpose: with the app served from the same origin as
 * the API, relative URLs are correct and there is no cross-origin preflight.
 */
import { execSync } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const apiRoot = path.resolve(__dirname, '..');
const appRoot = path.resolve(apiRoot, '..', 'app');
const buildDir = path.join(appRoot, 'build', 'web');
const target = path.join(apiRoot, 'public');

const apiBase = process.env.API_BASE ?? '';

// The value is interpolated into a shell command, so accept only an http(s)
// origin (or nothing) rather than passing an arbitrary string through.
if (apiBase && !/^https?:\/\/[A-Za-z0-9.\-:]+$/.test(apiBase)) {
  console.error(`✗ API_BASE must be a plain http(s) origin, got: ${apiBase}`);
  process.exit(1);
}

if (!fs.existsSync(appRoot)) {
  console.error(`✗ Flutter app not found at ${appRoot}`);
  process.exit(1);
}

console.log('Building the Flutter web app…');
try {
  // Run through a shell so `flutter` resolves on Windows too, where it is a
  // .bat that execFile cannot spawn directly (EINVAL). API_BASE is validated
  // above, and every other token here is a literal.
  execSync(
    `flutter build web --release --dart-define=API_BASE=${apiBase}`,
    { cwd: appRoot, stdio: 'inherit' }
  );
} catch (err) {
  console.error('✗ flutter build web failed:', err.message);
  process.exit(1);
}

if (!fs.existsSync(path.join(buildDir, 'index.html'))) {
  console.error(`✗ Build produced no index.html at ${buildDir}`);
  process.exit(1);
}

// Replace the previous build outright, so files removed upstream don't linger.
fs.rmSync(target, { recursive: true, force: true });
fs.cpSync(buildDir, target, { recursive: true });

const count = fs.readdirSync(target).length;
console.log(`✓ Copied the web build into ${target} (${count} top-level entries)`);
console.log('  The API will serve it at / on the next start.');
