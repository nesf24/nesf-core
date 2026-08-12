/**
 * Wraps an async route handler so a rejected promise reaches Express's error
 * middleware instead of hanging the request.
 */
export const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Throws a typed HTTP error the error middleware turns into a JSON response. */
export function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

/** Parses a zod schema, converting failures into a 400 with field details. */
export function parse(schema, data) {
  const result = schema.safeParse(data);
  if (!result.success) {
    const err = httpError(400, 'Please check the details you entered');
    err.fields = result.error.issues.map((i) => ({
      field: i.path.join('.') || '(body)',
      message: i.message,
    }));
    throw err;
  }
  return result.data;
}

/** Rupees (as typed by staff) -> paise, rounded to avoid float drift. */
export const toPaise = (rupees) => Math.round(Number(rupees || 0) * 100);

/** Great-circle distance in metres — used to score attendance against a base. */
export function distanceMetres(lat1, lng1, lat2, lng2) {
  if ([lat1, lng1, lat2, lng2].some((v) => v == null || Number.isNaN(Number(v)))) return null;
  const R = 6_371_000;
  const toRad = (d) => (Number(d) * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)));
}

/** Today's date in IST as YYYY-MM-DD, regardless of the server's timezone. */
export function istToday() {
  return istDateString(new Date());
}

export function istDateString(date) {
  // en-CA renders as YYYY-MM-DD, which is exactly the DATE column format.
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata' }).format(date);
}

/** Inclusive list of YYYY-MM-DD strings between two dates. */
export function dateRange(from, to) {
  const out = [];
  const d = new Date(`${from}T00:00:00Z`);
  const end = new Date(`${to}T00:00:00Z`);
  while (d <= end) {
    out.push(d.toISOString().slice(0, 10));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}

/** ISO weekday, 1 = Monday .. 7 = Sunday, for a YYYY-MM-DD string. */
export function isoWeekday(dateStr) {
  const day = new Date(`${dateStr}T00:00:00Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

/**
 * Express param validator for `:id` route segments.
 *
 * Without this, a malformed id (`/leaves/undefined`, `/leaves/abc`) reaches
 * Postgres and fails the bigint cast, surfacing as an opaque 500. Rejecting it
 * up front returns an honest 400 instead.
 */
export function numericId(req, res, next, value) {
  if (!/^\d+$/.test(String(value))) {
    return res.status(400).json({ error: `"${value}" is not a valid id` });
  }
  next();
}

/** Sends a generated PDF as a download with a sensible filename. */
export function sendPdf(res, buffer, filename) {
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Length', buffer.length);
  res.setHeader('Content-Disposition',
    `attachment; filename="${filename.replace(/[^a-zA-Z0-9._-]/g, '_')}"`);
  res.send(buffer);
}
