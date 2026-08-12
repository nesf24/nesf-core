import pg from 'pg';
import 'dotenv/config';

// Money is stored in paise as BIGINT. node-postgres hands BIGINT back as a
// string by default to avoid precision loss; our amounts are far below
// Number.MAX_SAFE_INTEGER, so parse them to numbers for convenient JSON output.
pg.types.setTypeParser(pg.types.builtins.INT8, (v) => (v === null ? null : Number(v)));
// NUMERIC (leave days) likewise — always small decimals such as 1.5.
pg.types.setTypeParser(pg.types.builtins.NUMERIC, (v) => (v === null ? null : Number(v)));
// DATE columns are calendar dates with no timezone meaning. Left to the driver
// they become JS Dates that shift a day when serialised from IST, so keep the
// raw YYYY-MM-DD string.
pg.types.setTypeParser(pg.types.builtins.DATE, (v) => v);

const { Pool } = pg;

// Cloud Run reaches Cloud SQL over a unix socket; everything else uses TCP.
const socketPath = process.env.INSTANCE_UNIX_SOCKET;

const pool = new Pool(
  socketPath
    ? {
        host: socketPath,
        user: process.env.DB_USER,
        password: process.env.DB_PASSWORD,
        database: process.env.DB_NAME,
        max: 10,
      }
    : {
        connectionString: process.env.DATABASE_URL,
        ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
        max: 10,
      }
);

pool.on('error', (err) => {
  console.error('[db] idle client error:', err.message);
});

// Runs fn inside a transaction, rolling back on any throw. Used wherever a
// write touches more than one table (e.g. a TA/DA claim and its legs).
export async function withTransaction(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

export default pool;
