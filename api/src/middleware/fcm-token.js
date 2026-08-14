import pool from '../db.js';

export async function storeFcmToken(employeeId, token, deviceType = null) {
  const { rows } = await pool.query(
    `INSERT INTO device_tokens (employee_id, fcm_token, device_type, created_at, updated_at)
     VALUES ($1, $2, $3, NOW(), NOW())
     ON CONFLICT (employee_id, fcm_token) DO UPDATE
     SET updated_at = NOW()
     RETURNING *`,
    [employeeId, token, deviceType]
  );
  return rows[0];
}

export async function getDeviceTokens(employeeId) {
  const { rows } = await pool.query(
    'SELECT fcm_token FROM device_tokens WHERE employee_id = $1 AND fcm_token IS NOT NULL',
    [employeeId]
  );
  return rows.map(r => r.fcm_token);
}

export async function getAllDeviceTokens() {
  const { rows } = await pool.query(
    'SELECT DISTINCT fcm_token FROM device_tokens WHERE fcm_token IS NOT NULL'
  );
  return rows.map(r => r.fcm_token);
}
