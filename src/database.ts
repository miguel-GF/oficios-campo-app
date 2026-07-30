import type { SQLiteDatabase } from 'expo-sqlite';

export type LocalAppointment = { id: string; time: string; name: string; service: string };
export type QueueItem = { id: string; entityType: string; entityId: string; operation: string; createdAt: string };

export async function migrateDatabase(db: SQLiteDatabase) {
  await db.execAsync(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS appointments (
      id TEXT PRIMARY KEY NOT NULL,
      time TEXT NOT NULL,
      client_name TEXT NOT NULL,
      service TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY NOT NULL,
      client_name TEXT NOT NULL,
      total_cents INTEGER NOT NULL CHECK(total_cents >= 0),
      payment_method TEXT NOT NULL,
      followup TEXT,
      status TEXT NOT NULL CHECK(status IN ('open', 'closed')),
      updated_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS attachments (
      id TEXT PRIMARY KEY NOT NULL,
      order_id TEXT NOT NULL,
      kind TEXT NOT NULL CHECK(kind IN ('before', 'after')),
      local_uri TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sync_queue (
      id TEXT PRIMARY KEY NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    );
  `);
}

const id = () => `${Date.now()}-${Math.random().toString(16).slice(2)}`;

async function enqueue(db: SQLiteDatabase, entityType: string, entityId: string, operation: string, payload: unknown) {
  await db.runAsync(
    'INSERT INTO sync_queue (id, entity_type, entity_id, operation, payload, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    id(), entityType, entityId, operation, JSON.stringify(payload), new Date().toISOString(),
  );
}

export async function createAppointment(db: SQLiteDatabase, input: Omit<LocalAppointment, 'id'>) {
  const appointment = { ...input, id: id() };
  await db.withTransactionAsync(async () => {
    await db.runAsync('INSERT INTO appointments (id, time, client_name, service, created_at) VALUES (?, ?, ?, ?, ?)', appointment.id, appointment.time, appointment.name, appointment.service, new Date().toISOString());
    await enqueue(db, 'appointment', appointment.id, 'create', appointment);
  });
  return appointment;
}

export async function listAppointments(db: SQLiteDatabase): Promise<LocalAppointment[]> {
  const rows = await db.getAllAsync<{ id: string; time: string; client_name: string; service: string }>('SELECT id, time, client_name, service FROM appointments ORDER BY time');
  return rows.map(row => ({ id: row.id, time: row.time, name: row.client_name, service: row.service }));
}

export async function closeOrder(db: SQLiteDatabase, totalCents: number, paymentMethod: string, followup: string) {
  const orderId = 'demo-martha';
  const payload = { orderId, clientName: 'Martha López', totalCents, paymentMethod, followup, status: 'closed' };
  await db.withTransactionAsync(async () => {
    await db.runAsync(`INSERT INTO orders (id, client_name, total_cents, payment_method, followup, status, updated_at)
      VALUES (?, ?, ?, ?, ?, 'closed', ?)
      ON CONFLICT(id) DO UPDATE SET total_cents=excluded.total_cents, payment_method=excluded.payment_method, followup=excluded.followup, status='closed', updated_at=excluded.updated_at`,
      orderId, payload.clientName, totalCents, paymentMethod, followup, new Date().toISOString());
    await enqueue(db, 'order', orderId, 'upsert', payload);
  });
}

export async function isOrderClosed(db: SQLiteDatabase) {
  return Boolean(await db.getFirstAsync('SELECT id FROM orders WHERE id = ? AND status = ?', 'demo-martha', 'closed'));
}

export async function saveAttachment(db: SQLiteDatabase, kind: 'before' | 'after', localUri: string) {
  const attachmentId = id();
  const payload = { id: attachmentId, orderId: 'demo-martha', kind, localUri };
  await db.withTransactionAsync(async () => {
    await db.runAsync('INSERT INTO attachments (id, order_id, kind, local_uri, created_at) VALUES (?, ?, ?, ?, ?)', attachmentId, payload.orderId, kind, localUri, new Date().toISOString());
    await enqueue(db, 'attachment', attachmentId, 'upload', payload);
  });
  return payload;
}

export async function queueCount(db: SQLiteDatabase) {
  const row = await db.getFirstAsync<{ count: number }>('SELECT COUNT(*) AS count FROM sync_queue');
  return row?.count ?? 0;
}

export async function listQueue(db: SQLiteDatabase): Promise<QueueItem[]> {
  const rows = await db.getAllAsync<{ id: string; entity_type: string; entity_id: string; operation: string; created_at: string }>('SELECT id, entity_type, entity_id, operation, created_at FROM sync_queue ORDER BY created_at');
  return rows.map(row => ({ id: row.id, entityType: row.entity_type, entityId: row.entity_id, operation: row.operation, createdAt: row.created_at }));
}
