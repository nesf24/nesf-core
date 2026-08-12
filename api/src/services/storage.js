import fs from 'fs/promises';
import fsSync from 'fs';
import path from 'path';
import crypto from 'crypto';
import multer from 'multer';

const DRIVER = process.env.STORAGE_DRIVER || 'local';
const UPLOAD_DIR = process.env.UPLOAD_DIR || 'uploads';

const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);
const DOC_TYPES = new Set([...IMAGE_TYPES, 'application/pdf']);

const MIME_BY_EXT = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
};

// Files are buffered in memory then handed to the driver, so switching between
// local disk and GCS needs no change at the call sites.
function uploader(allowed, maxMb) {
  return multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: maxMb * 1024 * 1024 },
    fileFilter: (_req, file, cb) => {
      if (!allowed.has(file.mimetype)) {
        return cb(new Error(`Unsupported file type: ${file.mimetype}`));
      }
      cb(null, true);
    },
  });
}

// Phone cameras produce large JPEGs; 8 MB covers a full-resolution selfie.
export const uploadImage = uploader(IMAGE_TYPES, 8);
export const uploadDoc = uploader(DOC_TYPES, 12);
// Signatures should be small, crisp images: max 500 KB.
export const uploadSignature = uploader(IMAGE_TYPES, 0.5);

let bucket = null;
async function getBucket() {
  if (bucket) return bucket;
  const { Storage } = await import('@google-cloud/storage');
  bucket = new Storage().bucket(process.env.GCS_BUCKET);
  return bucket;
}

/**
 * Rejects anything that could escape the storage root. Keys are always of the
 * form `<folder>/<generated-name>`, so this is deliberately strict.
 */
export function isSafeKey(key) {
  return typeof key === 'string'
    && key.length > 0
    && key.length < 300
    && /^[A-Za-z0-9][A-Za-z0-9/_.-]*$/.test(key)
    && !key.includes('..')
    && !key.startsWith('/');
}

/**
 * Validates signature image dimensions and returns error if out of bounds.
 * Signatures should be roughly 150-200 px wide by 50-100 px tall (landscape format).
 * Min: 50x20 (unusably small), Max: 200x100 (oversized will clutter letterhead).
 */
export async function validateSignatureDimensions(buffer) {
  // Simple JPEG/PNG header parsing to extract dimensions without external deps.
  // JPEG: FF D8 ... (SOF marker at position varies, complex)
  // PNG: starts with PNG header, width/height at bytes 16-23 (big-endian)

  if (buffer.length < 24) {
    return 'Signature image is too small to be valid';
  }

  // PNG magic bytes: 89 50 4E 47 (0x89, P, N, G)
  if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4E && buffer[3] === 0x47) {
    const width = buffer.readUInt32BE(16);
    const height = buffer.readUInt32BE(20);
    if (width < 50 || width > 200 || height < 20 || height > 100) {
      return `Signature dimensions (${width}x${height}) out of range. `
           + `Signatures should be 50-200 px wide and 20-100 px tall.`;
    }
    return null;
  }

  // JPEG: look for SOF0 marker (0xFF 0xC0) which contains width/height
  for (let i = 2; i < Math.min(buffer.length - 8, 500); i++) {
    if (buffer[i] === 0xFF && buffer[i + 1] === 0xC0) {
      // SOF0: height at i+5-6 (big-endian), width at i+7-8
      const height = buffer.readUInt16BE(i + 5);
      const width = buffer.readUInt16BE(i + 7);
      if (width < 50 || width > 200 || height < 20 || height > 100) {
        return `Signature dimensions (${width}x${height}) out of range. `
             + `Signatures should be 50-200 px wide and 20-100 px tall.`;
      }
      return null;
    }
  }

  // If we can't parse dimensions, don't block (WebP or other format).
  return null;
}

export function mimeForKey(key) {
  return MIME_BY_EXT[path.extname(key).toLowerCase()] || 'application/octet-stream';
}

/**
 * Persists an uploaded file and returns its **storage key** — not a URL.
 *
 * Nothing uploaded here is publicly reachable: selfies, signatures, receipts and
 * activity photos are all staff personal data. The key is what gets stored in the
 * database, and the only way to read it back is the authenticated
 * `/api/media/<key>` endpoint (or `readUpload` server-side, for PDF embedding).
 */
export async function saveUpload(file, folder) {
  const ext = path.extname(file.originalname || '').toLowerCase()
    || ({ 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp', 'application/pdf': '.pdf' }[file.mimetype] || '');
  const name = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
  const key = `${folder}/${name}`;

  if (DRIVER === 'gcs') {
    const b = await getBucket();
    await b.file(key).save(file.buffer, {
      contentType: file.mimetype,
      // Private: the bucket needs no allUsers binding.
      metadata: { cacheControl: 'private, max-age=31536000' },
    });
    return key;
  }

  const dir = path.resolve(UPLOAD_DIR, folder);
  await fs.mkdir(dir, { recursive: true });
  await fs.writeFile(path.join(dir, name), file.buffer);
  return key;
}

/** Absolute path of a local key, or null when it escapes the upload root. */
function localPath(key) {
  const root = path.resolve(UPLOAD_DIR);
  const abs = path.resolve(root, key);
  return abs.startsWith(root + path.sep) ? abs : null;
}

/**
 * Reads a stored object into a Buffer. Used by the PDF engine to embed
 * signatures and activity photos, so rendering never makes an HTTP round trip
 * back to itself. Returns null when the object is missing.
 */
export async function readUpload(key) {
  if (!isSafeKey(key)) return null;

  if (DRIVER === 'gcs') {
    try {
      const b = await getBucket();
      const [buf] = await b.file(key).download();
      return buf;
    } catch {
      return null;
    }
  }

  const abs = localPath(key);
  if (!abs || !fsSync.existsSync(abs)) return null;
  return fs.readFile(abs);
}

/**
 * Streams a stored object to an Express response. Streaming rather than
 * buffering keeps memory flat when several staff open photo-heavy reports at
 * once. Returns false when the object does not exist.
 */
export async function streamUpload(key, res) {
  if (!isSafeKey(key)) return false;

  if (DRIVER === 'gcs') {
    const b = await getBucket();
    const file = b.file(key);
    const [exists] = await file.exists();
    if (!exists) return false;
    await new Promise((resolve, reject) => {
      file.createReadStream()
        .on('error', reject)
        .on('end', resolve)
        .pipe(res);
    });
    return true;
  }

  const abs = localPath(key);
  if (!abs || !fsSync.existsSync(abs)) return false;
  await new Promise((resolve, reject) => {
    fsSync.createReadStream(abs)
      .on('error', reject)
      .on('end', resolve)
      .pipe(res);
  });
  return true;
}
