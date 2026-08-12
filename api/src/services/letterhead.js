import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import pool from '../db.js';
import { readUpload } from './storage.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const LOGO_PATH = path.join(__dirname, '..', 'assets', 'ne-sports-foundation-logo.png');

export const BRAND = {
  green: '#1a4731',
  ink: '#111111',
  body: '#333333',
  muted: '#777777',
  faint: '#999999',
  rule: '#1a4731',
};

// Org identity is editable from the settings table so the registrar details can
// be corrected without a redeploy; these are the fallbacks and match the block
// already printed on existing NESF documents.
const ORG_FALLBACK = {
  org_name: 'The NE Sports Foundation',
  tagline: 'A Non-Profit Company',
  registration: 'Registered under section 8 of the Companies Act, 2013',
  websites: 'www.nesportsfoundation.in & www.nesports.in',
  email: 'nesportsf@gmail.com',
  mobile: '+91 8414948978',
  cin: 'U88900AR2024NPL014171',
  gstin: '12AAJCN8454F1ZF',
  darpan_id: 'AR/2024/0446247',
  address: null,
  file_no_prefix: 'NESF/ADMIN',
};

let orgCache = null;
let orgCachedAt = 0;

export async function getOrg() {
  // Settings change rarely; a short cache keeps PDF generation off the DB.
  if (orgCache && Date.now() - orgCachedAt < 60_000) return orgCache;
  try {
    const { rows } = await pool.query(
      `SELECT org_name, tagline, registration, websites, email, mobile,
              cin, gstin, darpan_id, address, file_no_prefix
         FROM settings WHERE id = 1`
    );
    orgCache = { ...ORG_FALLBACK, ...(rows[0] || {}) };
  } catch {
    orgCache = ORG_FALLBACK;
  }
  orgCachedAt = Date.now();
  return orgCache;
}

/**
 * Mints the next sequential file number for a document issued on letterhead.
 * Format: <prefix>/<year>/<seq>, seq restarting each calendar year.
 *
 * The INSERT ... SELECT MAX(seq)+1 is racy under concurrent approvals, so the
 * unique (year, seq) constraint is the real guard: on collision we retry.
 */
export async function nextFileNo(docType, refTable = null, refId = null, issuedBy = null) {
  const { file_no_prefix: prefix } = await getOrg();
  const year = new Date().getFullYear();

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const { rows } = await pool.query(
        `INSERT INTO document_log (file_no, year, seq, doc_type, ref_table, ref_id, issued_by)
         SELECT $1 || '/' || $2::text || '/' || LPAD((COALESCE(MAX(seq), 0) + 1)::text, 3, '0'),
                $2::int, COALESCE(MAX(seq), 0) + 1, $3, $4, $5, $6
           FROM document_log WHERE year = $2::int
         RETURNING file_no`,
        [prefix, year, docType, refTable, refId, issuedBy]
      );
      return rows[0].file_no;
    } catch (err) {
      // 23505 = unique_violation: another approval took this seq, try again.
      if (err.code !== '23505' || attempt === 4) throw err;
    }
  }
}

export function formatDate(value) {
  if (!value) return '—';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'long', year: 'numeric' });
}

export function formatDateTime(value) {
  if (!value) return '—';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return String(value);
  return d.toLocaleString('en-IN', {
    day: '2-digit', month: 'short', year: 'numeric',
    hour: '2-digit', minute: '2-digit', hour12: true,
    timeZone: 'Asia/Kolkata',
  });
}

// Paise -> "₹ 1,23,456.00" in Indian digit grouping.
export function formatMoney(paise) {
  const rupees = (Number(paise || 0) / 100).toFixed(2);
  const [whole, frac] = rupees.split('.');
  const last3 = whole.slice(-3);
  const rest = whole.slice(0, -3);
  const grouped = rest ? rest.replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3 : last3;
  return `Rs. ${grouped}.${frac}`;
}

/**
 * Draws the NESF letterhead at the top of the current page: logo, org block,
 * a green rule, then the file number and date row.
 * Call once per page immediately after the page is created.
 */
export async function drawHeader(doc, fileNo, date = new Date(), org = null) {
  const ORG = org || (await getOrg());
  const left = doc.page.margins.left;
  const right = doc.page.width - doc.page.margins.right;
  const top = doc.page.margins.top;
  const textLeft = left + 82;
  const textWidth = right - textLeft;

  if (fs.existsSync(LOGO_PATH)) {
    doc.image(LOGO_PATH, left, top, { width: 70 });
  }

  doc.fontSize(15).fillColor(BRAND.green).font('Helvetica-Bold')
    .text(ORG.org_name, textLeft, top, { width: textWidth });
  doc.fontSize(9).fillColor('#555555').font('Helvetica')
    .text(ORG.tagline, textLeft, doc.y, { width: textWidth })
    .text(ORG.registration, textLeft, doc.y, { width: textWidth });
  doc.fontSize(8).fillColor(BRAND.muted)
    .text(`Website: ${ORG.websites}`, textLeft, doc.y, { width: textWidth })
    .text(`Email: ${ORG.email}  |  Mob: ${ORG.mobile}`, textLeft, doc.y, { width: textWidth })
    .text(`CIN: ${ORG.cin}  |  GSTIN: ${ORG.gstin}  |  Darpan ID: ${ORG.darpan_id}`,
      textLeft, doc.y, { width: textWidth });

  // Keep the rule below the logo even when the org block is shorter than it.
  const logoBottom = top + 70;
  doc.y = Math.max(doc.y, logoBottom) + 8;

  doc.moveTo(left, doc.y).lineTo(right, doc.y)
    .strokeColor(BRAND.rule).lineWidth(1.5).stroke();
  doc.moveDown(0.7);

  const y = doc.y;
  const half = (right - left) / 2;
  doc.fontSize(10).fillColor(BRAND.body).font('Helvetica-Bold')
    .text(`File No: ${fileNo}`, left, y, { width: half });
  doc.font('Helvetica-Bold')
    .text(`Date: ${formatDate(date)}`, left + half, y, { width: half, align: 'right' });
  doc.y = Math.max(doc.y, y + 14);
  doc.moveDown(0.8);
}

/**
 * Draws text in the margin strip below the content area.
 *
 * pdfkit paginates automatically whenever text is written past the bottom
 * margin, which would silently push footers onto a fresh blank page. Zeroing the
 * bottom margin for the duration suppresses that, and `lineBreak: false` stops
 * pdfkit measuring the string against the remaining page height.
 */
function drawInBottomMargin(doc, fn) {
  const saved = doc.page.margins.bottom;
  doc.page.margins.bottom = 0;
  try {
    fn();
  } finally {
    doc.page.margins.bottom = saved;
  }
}

export async function drawFooter(doc, org = null) {
  const ORG = org || (await getOrg());
  const left = doc.page.margins.left;
  const right = doc.page.width - doc.page.margins.right;
  const y = doc.page.height - doc.page.margins.bottom + 12;

  doc.moveTo(left, y - 6).lineTo(right, y - 6)
    .strokeColor('#dddddd').lineWidth(0.5).stroke();

  drawInBottomMargin(doc, () => {
    doc.fontSize(7.5).fillColor(BRAND.faint).font('Helvetica')
      .text(
        `${ORG.org_name}  |  ${ORG.websites}  |  ${ORG.email}  |  Mob & WhatsApp: ${ORG.mobile}`,
        left, y, { width: right - left, align: 'center', lineBreak: false }
      );
  });
}

export function drawPageNumber(doc, current, total) {
  const left = doc.page.margins.left;
  const width = doc.page.width - left - doc.page.margins.right;
  const y = doc.page.height - doc.page.margins.bottom + 24;

  drawInBottomMargin(doc, () => {
    doc.fontSize(7.5).fillColor(BRAND.faint).font('Helvetica')
      .text(`Page ${current} of ${total}`, left, y,
        { width, align: 'right', lineBreak: false });
  });
}

export function drawTitle(doc, title, subtitle = null) {
  const left = doc.page.margins.left;
  const width = doc.page.width - left - doc.page.margins.right;
  doc.fontSize(15).fillColor(BRAND.green).font('Helvetica-Bold')
    .text(title.toUpperCase(), left, doc.y, { width, align: 'center', characterSpacing: 0.6 });
  if (subtitle) {
    doc.fontSize(9.5).fillColor(BRAND.muted).font('Helvetica')
      .text(subtitle, left, doc.y + 2, { width, align: 'center' });
  }
  doc.moveDown(1.1);
}

// Label/value row used across all the documents' detail blocks.
export function drawField(doc, label, value, opts = {}) {
  const left = doc.page.margins.left;
  const right = doc.page.width - doc.page.margins.right;
  const labelWidth = opts.labelWidth || 150;
  const y = doc.y;

  doc.fontSize(10).fillColor(BRAND.body).font('Helvetica')
    .text(`${label}`, left, y, { width: labelWidth });
  const labelBottom = doc.y;

  doc.fontSize(10).fillColor(BRAND.ink).font(opts.bold ? 'Helvetica-Bold' : 'Helvetica')
    .text(value == null || value === '' ? '—' : String(value),
      left + labelWidth + 8, y, { width: right - left - labelWidth - 8 });

  doc.y = Math.max(labelBottom, doc.y) + 3;
}

// Free-text block with a heading, for narrative sections (reason, outcome...).
export function drawParagraph(doc, heading, body) {
  const left = doc.page.margins.left;
  const width = doc.page.width - left - doc.page.margins.right;
  if (heading) {
    doc.fontSize(10.5).fillColor(BRAND.green).font('Helvetica-Bold')
      .text(heading, left, doc.y, { width });
    doc.moveDown(0.25);
  }
  doc.fontSize(10).fillColor(BRAND.ink).font('Helvetica')
    .text(body == null || body === '' ? '—' : String(body), left, doc.y, {
      width, align: 'justify', lineGap: 1.5,
    });
  doc.moveDown(0.8);
}

/**
 * Simple table renderer. `columns` is [{ label, width, align, key }] with widths
 * in points; rows are plain objects. Repeats the header on page breaks.
 */
export function drawTable(doc, columns, rows, opts = {}) {
  const left = doc.page.margins.left;
  const bottomLimit = doc.page.height - doc.page.margins.bottom - 40;
  const rowPad = 5;

  const header = () => {
    const y = doc.y;
    doc.rect(left, y, columns.reduce((s, c) => s + c.width, 0), 18)
      .fillColor('#eef3f0').fill();
    let x = left;
    doc.fontSize(8.5).fillColor(BRAND.green).font('Helvetica-Bold');
    for (const col of columns) {
      doc.text(col.label, x + rowPad, y + 5, {
        width: col.width - rowPad * 2, align: col.align || 'left',
      });
      x += col.width;
    }
    doc.y = y + 18;
  };

  header();

  for (const row of rows) {
    // Measure the tallest cell so multi-line cells don't overlap the next row.
    let cellHeight = 12;
    doc.fontSize(8.5).font('Helvetica');
    for (const col of columns) {
      const text = row[col.key] == null ? '' : String(row[col.key]);
      const h = doc.heightOfString(text, { width: col.width - rowPad * 2 });
      cellHeight = Math.max(cellHeight, h);
    }
    cellHeight += rowPad * 2 - 2;

    if (doc.y + cellHeight > bottomLimit) {
      doc.addPage();
      if (opts.onNewPage) opts.onNewPage(doc);
      header();
    }

    const y = doc.y;
    let x = left;
    doc.fontSize(8.5).fillColor(BRAND.ink).font('Helvetica');
    for (const col of columns) {
      const text = row[col.key] == null ? '' : String(row[col.key]);
      doc.text(text, x + rowPad, y + rowPad, {
        width: col.width - rowPad * 2, align: col.align || 'left',
      });
      x += col.width;
    }
    doc.y = y + cellHeight;
    doc.moveTo(left, doc.y).lineTo(x, doc.y)
      .strokeColor('#e2e8e5').lineWidth(0.5).stroke();
  }
  doc.moveDown(0.6);
}

/**
 * Loads an image into a Buffer pdfkit can embed.
 *
 * `src` is normally a storage key (`signatures/1786…png`), read straight from
 * disk or Cloud Storage — no HTTP round trip back to this same server, and no
 * requirement for the object to be publicly readable.
 *
 * An absolute http(s) URL is still accepted, for an externally hosted image or a
 * record written before uploads became private.
 *
 * Returns null on any failure, so a missing signature degrades to a blank
 * signature line rather than failing the whole document.
 */
export async function fetchImage(src) {
  if (!src) return null;
  try {
    if (/^https?:\/\//i.test(src)) {
      const res = await fetch(src);
      if (!res.ok) return null;
      return Buffer.from(await res.arrayBuffer());
    }
    // Tolerate a legacy "/uploads/<key>" prefix from earlier records.
    const key = src.replace(/^\/?uploads\//, '');
    return await readUpload(key);
  } catch {
    return null;
  }
}

/**
 * Draws the signature block that authorises the document.
 *
 * `signatories` is an array of { name, title, signature_url, at, caption } —
 * typically the reviewing manager on the left and the approving authority on
 * the right. The signature image is stamped above the name; if it is missing a
 * ruled line is drawn instead so the document can still be wet-signed.
 */
export async function drawSignatures(doc, signatories) {
  const left = doc.page.margins.left;
  const right = doc.page.width - doc.page.margins.right;
  const usable = right - left;
  const blocks = signatories.filter(Boolean);
  if (!blocks.length) return;

  const blockWidth = Math.min(210, usable / blocks.length);
  const SIG_H = 42;
  const NEEDED = SIG_H + 60;

  // Keep the whole signature block together; never split it across pages.
  // The -20 reserve leaves room for the single-line issued note underneath.
  if (doc.y + NEEDED > doc.page.height - doc.page.margins.bottom - 20) {
    doc.addPage();
  }
  doc.moveDown(1.2);

  const images = await Promise.all(blocks.map((b) => fetchImage(b.signature_url)));
  const baseY = doc.y;
  let maxBottom = baseY;

  blocks.forEach((block, i) => {
    // First block flush left, last flush right, others spread between.
    const x = blocks.length === 1
      ? left
      : left + i * ((usable - blockWidth) / (blocks.length - 1));

    if (images[i]) {
      try {
        doc.image(images[i], x, baseY, { fit: [blockWidth - 20, SIG_H], align: 'left' });
      } catch {
        // Unsupported/corrupt image: fall through to the ruled line.
      }
    }

    const lineY = baseY + SIG_H + 4;
    doc.moveTo(x, lineY).lineTo(x + blockWidth - 20, lineY)
      .strokeColor('#666666').lineWidth(0.8).stroke();

    let y = lineY + 4;
    doc.fontSize(9.5).fillColor(BRAND.ink).font('Helvetica-Bold')
      .text(block.name || '', x, y, { width: blockWidth - 10 });
    y = doc.y;
    if (block.title) {
      doc.fontSize(8.5).fillColor(BRAND.body).font('Helvetica')
        .text(block.title, x, y, { width: blockWidth - 10 });
      y = doc.y;
    }
    if (block.caption) {
      doc.fontSize(7.5).fillColor(BRAND.muted).font('Helvetica')
        .text(block.caption, x, y, { width: blockWidth - 10 });
      y = doc.y;
    }
    if (block.at) {
      doc.fontSize(7.5).fillColor(BRAND.faint).font('Helvetica')
        .text(`Signed on ${formatDate(block.at)}`, x, y, { width: blockWidth - 10 });
      y = doc.y;
    }
    maxBottom = Math.max(maxBottom, y);
  });

  doc.y = maxBottom + 6;
}

// Printed at the very end of an approved document so a paper copy can be
// traced back to the record that produced it.
export function drawIssuedNote(doc, fileNo) {
  const left = doc.page.margins.left;
  const width = doc.page.width - left - doc.page.margins.right;
  // Kept to a single compact line: on a long document (a multi-leg TA/DA bill)
  // a taller note would not fit under the signatures and would spill a whole
  // near-empty page.
  const text = `Generated electronically by NESF Core  ·  Ref ${fileNo}  ·  `
    + `${formatDateTime(new Date())} IST  ·  Valid without a physical seal.`;

  doc.fontSize(7).font('Helvetica-Oblique');
  const needed = doc.heightOfString(text, { width, align: 'center' });
  const contentBottom = doc.page.height - doc.page.margins.bottom;

  // Never let the note split across pages — a traceability footer broken in half
  // reads as a printing fault on an official document.
  if (doc.y + 8 + needed > contentBottom) doc.addPage();
  else doc.moveDown(0.8);

  doc.fillColor(BRAND.faint)
    .text(text, left, doc.y, { width, align: 'center' });
}

// Page geometry for the two layouts we issue documents in.
export const PORTRAIT = {
  layout: 'portrait',
  margins: { top: 45, bottom: 55, left: 50, right: 50 },
};
export const LANDSCAPE = {
  layout: 'landscape',
  margins: { top: 40, bottom: 50, left: 35, right: 35 },
};

/**
 * Wraps the pdfkit lifecycle: creates an A4 document, hands it to `build`, and
 * resolves with the finished Buffer. `build` receives (doc, org) and may await.
 *
 * Pass LANDSCAPE as `page` for wide documents (the attendance muster). The
 * layout must be set here rather than via addPage, otherwise pdfkit's implicit
 * first page is emitted as a blank sheet of the wrong orientation.
 */
export async function renderPdf(build, page = PORTRAIT) {
  const org = await getOrg();
  const PDFDocument = (await import('pdfkit')).default;

  const doc = new PDFDocument({
    size: 'A4',
    layout: page.layout,
    // Bottom margin leaves room for the footer strip.
    margins: page.margins,
    bufferPages: true,
    info: { Author: org.org_name, Creator: 'NESF Core' },
  });

  const chunks = [];
  doc.on('data', (c) => chunks.push(c));

  const done = new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });

  await build(doc, org);

  // Footer goes on every page, so it must be drawn after all content exists.
  const range = doc.bufferedPageRange();
  for (let i = range.start; i < range.start + range.count; i++) {
    doc.switchToPage(i);
    await drawFooter(doc, org);
    if (range.count > 1) drawPageNumber(doc, i - range.start + 1, range.count);
  }

  doc.end();
  return done;
}
