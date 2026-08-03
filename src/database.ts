import type { SQLiteDatabase } from 'expo-sqlite';

export type Client = { id: string; name: string; phone: string; neighborhood: string; address: string; notes: string; createdAt: string };
export type Appointment = { id: string; clientId: string; clientName: string; startsAt: string; service: string; durationMinutes: number; status: 'scheduled' | 'in_progress' | 'completed' | 'cancelled'; orderId: string | null };
export type OrderLine = { id: string; concept: string; quantity: number; unitPriceCents: number };
export type Attachment = { id: string; kind: 'before' | 'after'; localUri: string; remotePath: string | null };
export type Payment = { id: string; method: 'cash' | 'transfer'; amountCents: number; paidAt: string; voidedAt: string | null };
export type PaymentStatus = 'pending' | 'partial' | 'paid';
export type WorkOrder = { id: string; clientId: string; clientName: string; appointmentId: string | null; status: 'open' | 'closed'; paymentMethod: 'cash' | 'transfer' | 'pending'; followupAt: string | null; notes: string; totalCents: number; lines: OrderLine[]; attachments: Attachment[]; payments: Payment[] };
export type QueueRecord = { id: string; tableName: string; entityId: string; operation: 'upsert' | 'delete'; payload: string; attempts: number };
export type AccessState = { trialStartedAt: string; trialEndsAt: string; trialDaysRemaining: number; entitlement: 'trial' | 'active' | 'expired' };
export type OrderSummary = { id: string; clientName: string; totalCents: number; paidCents: number; balanceCents: number; paymentStatus: PaymentStatus; closedAt: string };

const now = () => new Date().toISOString();
export const newId = () => `${Date.now()}-${Math.random().toString(16).slice(2)}`;

export async function migrateDatabase(db: SQLiteDatabase) {
  // The first prototype used incompatible demo-only tables. Upgrade those
  // installations once; no production data existed in that schema.
  const oldColumns = await db.getAllAsync<{ name: string }>('PRAGMA table_info(appointments)');
  if (oldColumns.some(column => column.name === 'client_name')) {
    await db.execAsync('PRAGMA foreign_keys=OFF; DROP TABLE IF EXISTS sync_queue; DROP TABLE IF EXISTS attachments; DROP TABLE IF EXISTS orders; DROP TABLE IF EXISTS appointments; PRAGMA foreign_keys=ON;');
  }
  await db.execAsync(`
    PRAGMA journal_mode = WAL;
    PRAGMA foreign_keys = ON;
    CREATE TABLE IF NOT EXISTS clients (
      id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '',
      neighborhood TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT
    );
    CREATE TABLE IF NOT EXISTS appointments (
      id TEXT PRIMARY KEY NOT NULL, client_id TEXT NOT NULL, starts_at TEXT NOT NULL,
      service TEXT NOT NULL, duration_minutes INTEGER NOT NULL DEFAULT 60,
      status TEXT NOT NULL CHECK(status IN ('scheduled','in_progress','completed','cancelled')),
      order_id TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
      FOREIGN KEY(client_id) REFERENCES clients(id)
    );
    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY NOT NULL, client_id TEXT NOT NULL, appointment_id TEXT,
      status TEXT NOT NULL CHECK(status IN ('open','closed')), notes TEXT NOT NULL DEFAULT '',
      total_cents INTEGER NOT NULL DEFAULT 0 CHECK(total_cents >= 0),
      payment_method TEXT NOT NULL DEFAULT 'pending', followup_at TEXT,
      closed_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
      FOREIGN KEY(client_id) REFERENCES clients(id)
    );
    CREATE TABLE IF NOT EXISTS order_lines (
      id TEXT PRIMARY KEY NOT NULL, order_id TEXT NOT NULL, concept TEXT NOT NULL,
      quantity REAL NOT NULL CHECK(quantity > 0), unit_price_cents INTEGER NOT NULL CHECK(unit_price_cents >= 0),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT,
      FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS payments (
      id TEXT PRIMARY KEY NOT NULL, order_id TEXT NOT NULL, method TEXT NOT NULL,
      amount_cents INTEGER NOT NULL CHECK(amount_cents > 0), paid_at TEXT NOT NULL, created_at TEXT NOT NULL,
      voided_at TEXT,
      FOREIGN KEY(order_id) REFERENCES orders(id)
    );
    CREATE TABLE IF NOT EXISTS attachments (
      id TEXT PRIMARY KEY NOT NULL, order_id TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('before','after')),
      local_uri TEXT NOT NULL, remote_path TEXT, created_at TEXT NOT NULL, deleted_at TEXT,
      FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS followups (
      id TEXT PRIMARY KEY NOT NULL, client_id TEXT NOT NULL, order_id TEXT NOT NULL,
      due_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', created_at TEXT NOT NULL,
      FOREIGN KEY(client_id) REFERENCES clients(id), FOREIGN KEY(order_id) REFERENCES orders(id)
    );
    CREATE TABLE IF NOT EXISTS sync_queue (
      id TEXT PRIMARY KEY NOT NULL, table_name TEXT NOT NULL, entity_id TEXT NOT NULL,
      operation TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT, created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS app_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
    CREATE INDEX IF NOT EXISTS idx_appointments_starts ON appointments(starts_at);
    CREATE INDEX IF NOT EXISTS idx_orders_client ON orders(client_id);
    CREATE INDEX IF NOT EXISTS idx_queue_created ON sync_queue(created_at);
  `);
  await db.runAsync("INSERT OR IGNORE INTO app_metadata (key,value) VALUES ('trial_started_at',?)", now());
  const paymentColumns = await db.getAllAsync<{ name: string }>('PRAGMA table_info(payments)');
  if (paymentColumns.length > 0 && !paymentColumns.some(column => column.name === 'voided_at')) await db.execAsync('ALTER TABLE payments ADD COLUMN voided_at TEXT;');
}

async function enqueue(db: SQLiteDatabase, tableName: string, entityId: string, operation: 'upsert' | 'delete', payload: unknown) {
  await db.runAsync('INSERT INTO sync_queue (id,table_name,entity_id,operation,payload,created_at) VALUES (?,?,?,?,?,?)', newId(), tableName, entityId, operation, JSON.stringify(payload), now());
}

export async function listClients(db: SQLiteDatabase, query = ''): Promise<Client[]> {
  const like = `%${query.trim()}%`;
  const rows = await db.getAllAsync<any>('SELECT * FROM clients WHERE deleted_at IS NULL AND (name LIKE ? OR phone LIKE ? OR neighborhood LIKE ?) ORDER BY name', like, like, like);
  return rows.map(r => ({ id: r.id, name: r.name, phone: r.phone, neighborhood: r.neighborhood, address: r.address, notes: r.notes, createdAt: r.created_at }));
}

export async function createClient(db: SQLiteDatabase, input: Omit<Client, 'id' | 'createdAt'>) {
  const client = { ...input, id: newId(), createdAt: now() };
  await db.withTransactionAsync(async () => {
    await db.runAsync('INSERT INTO clients (id,name,phone,neighborhood,address,notes,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)', client.id, client.name, client.phone, client.neighborhood, client.address, client.notes, client.createdAt, client.createdAt);
    await enqueue(db, 'clients', client.id, 'upsert', client);
  });
  return client;
}

export async function listAppointments(db: SQLiteDatabase): Promise<Appointment[]> {
  const rows = await db.getAllAsync<any>(`SELECT a.*, c.name client_name FROM appointments a JOIN clients c ON c.id=a.client_id WHERE a.deleted_at IS NULL AND a.status!='cancelled' ORDER BY a.starts_at`);
  return rows.map(r => ({ id: r.id, clientId: r.client_id, clientName: r.client_name, startsAt: r.starts_at, service: r.service, durationMinutes: r.duration_minutes, status: r.status, orderId: r.order_id }));
}

export async function createAppointment(db: SQLiteDatabase, input: { clientId: string; startsAt: string; service: string; durationMinutes?: number }) {
  const appointment = { id: newId(), ...input, durationMinutes: input.durationMinutes ?? 60, status: 'scheduled' as const, createdAt: now() };
  await db.withTransactionAsync(async () => {
    await db.runAsync('INSERT INTO appointments (id,client_id,starts_at,service,duration_minutes,status,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)', appointment.id, appointment.clientId, appointment.startsAt, appointment.service, appointment.durationMinutes, appointment.status, appointment.createdAt, appointment.createdAt);
    await enqueue(db, 'appointments', appointment.id, 'upsert', appointment);
  });
  return appointment.id;
}

export async function startVisit(db: SQLiteDatabase, appointment: Appointment) {
  if (appointment.orderId) return appointment.orderId;
  const orderId = newId(); const stamp = now();
  await db.withTransactionAsync(async () => {
    await db.runAsync("INSERT INTO orders (id,client_id,appointment_id,status,created_at,updated_at) VALUES (?,?,?,'open',?,?)", orderId, appointment.clientId, appointment.id, stamp, stamp);
    await db.runAsync("UPDATE appointments SET status='in_progress',order_id=?,updated_at=? WHERE id=?", orderId, stamp, appointment.id);
    await enqueue(db, 'orders', orderId, 'upsert', { id: orderId, clientId: appointment.clientId, appointmentId: appointment.id, status: 'open' });
    await enqueue(db, 'appointments', appointment.id, 'upsert', { ...appointment, orderId, status: 'in_progress' });
  });
  return orderId;
}

export async function getOrder(db: SQLiteDatabase, orderId: string): Promise<WorkOrder | null> {
  const r = await db.getFirstAsync<any>('SELECT o.*,c.name client_name FROM orders o JOIN clients c ON c.id=o.client_id WHERE o.id=?', orderId);
  if (!r) return null;
  const lines = await db.getAllAsync<any>('SELECT * FROM order_lines WHERE order_id=? AND deleted_at IS NULL ORDER BY created_at', orderId);
  const attachments = await db.getAllAsync<any>('SELECT id,kind,local_uri,remote_path FROM attachments WHERE order_id=? AND deleted_at IS NULL ORDER BY created_at', orderId);
  const payments = await db.getAllAsync<any>('SELECT id,method,amount_cents,paid_at,voided_at FROM payments WHERE order_id=? ORDER BY paid_at', orderId);
  return { id: r.id, clientId: r.client_id, clientName: r.client_name, appointmentId: r.appointment_id, status: r.status, notes: r.notes, totalCents: r.total_cents, paymentMethod: r.payment_method, followupAt: r.followup_at, lines: lines.map(x => ({ id: x.id, concept: x.concept, quantity: x.quantity, unitPriceCents: x.unit_price_cents })), attachments: attachments.map(x => ({ id: x.id, kind: x.kind, localUri: x.local_uri, remotePath: x.remote_path })), payments: payments.map(x => ({ id: x.id, method: x.method, amountCents: x.amount_cents, paidAt: x.paid_at, voidedAt: x.voided_at })) };
}

export async function listClosedOrders(db: SQLiteDatabase): Promise<OrderSummary[]> {
  const rows = await db.getAllAsync<any>(`SELECT o.id,c.name client_name,o.total_cents,o.closed_at,COALESCE(SUM(CASE WHEN p.voided_at IS NULL THEN p.amount_cents ELSE 0 END),0) paid_cents FROM orders o JOIN clients c ON c.id=o.client_id LEFT JOIN payments p ON p.order_id=o.id WHERE o.status='closed' AND o.deleted_at IS NULL GROUP BY o.id ORDER BY o.closed_at DESC`);
  return rows.map(row => { const paidCents = row.paid_cents; const balanceCents = Math.max(0, row.total_cents - paidCents); return { id: row.id, clientName: row.client_name, totalCents: row.total_cents, paidCents, balanceCents, paymentStatus: paidCents <= 0 ? 'pending' : balanceCents > 0 ? 'partial' : 'paid', closedAt: row.closed_at }; });
}

export function paymentSummary(order: Pick<WorkOrder, 'totalCents' | 'payments'>) {
  const paidCents = order.payments.filter(payment => !payment.voidedAt).reduce((sum, payment) => sum + payment.amountCents, 0);
  const balanceCents = Math.max(0, order.totalCents - paidCents);
  const status: PaymentStatus = paidCents <= 0 ? 'pending' : balanceCents > 0 ? 'partial' : 'paid';
  return { paidCents, balanceCents, status };
}

export async function recordPayment(db: SQLiteDatabase, orderId: string, method: Payment['method'], amountCents: number, paidAt = now()) {
  if (!Number.isInteger(amountCents) || amountCents <= 0) throw new Error('El abono debe ser mayor a cero.');
  const payment: Payment & { orderId: string } = { id: newId(), orderId, method, amountCents, paidAt, voidedAt: null };
  await db.withTransactionAsync(async () => {
    await db.runAsync('INSERT INTO payments (id,order_id,method,amount_cents,paid_at,created_at) VALUES (?,?,?,?,?,?)', payment.id, orderId, method, amountCents, paidAt, now());
    await enqueue(db, 'payments', payment.id, 'upsert', payment);
  });
  return payment;
}

export async function voidPayment(db: SQLiteDatabase, payment: Payment) {
  const voidedAt = now();
  await db.withTransactionAsync(async () => {
    await db.runAsync('UPDATE payments SET voided_at=? WHERE id=?', voidedAt, payment.id);
    await enqueue(db, 'payments', payment.id, 'upsert', { ...payment, voidedAt });
  });
}

export async function saveOrderDraft(db: SQLiteDatabase, order: WorkOrder) {
  const totalCents = order.lines.reduce((sum, l) => sum + Math.round(l.quantity * l.unitPriceCents), 0); const stamp = now();
  await db.withTransactionAsync(async () => {
    await db.runAsync('UPDATE orders SET notes=?,total_cents=?,payment_method=?,followup_at=?,updated_at=? WHERE id=?', order.notes, totalCents, order.paymentMethod, order.followupAt, stamp, order.id);
    await db.runAsync('DELETE FROM order_lines WHERE order_id=?', order.id);
    for (const line of order.lines) await db.runAsync('INSERT INTO order_lines (id,order_id,concept,quantity,unit_price_cents,created_at,updated_at) VALUES (?,?,?,?,?,?,?)', line.id, order.id, line.concept, line.quantity, line.unitPriceCents, stamp, stamp);
    await enqueue(db, 'orders', order.id, 'upsert', { ...order, totalCents });
  });
}

export async function closeOrder(db: SQLiteDatabase, order: WorkOrder) {
  await saveOrderDraft(db, order);
  const totalCents = order.lines.reduce((sum, l) => sum + Math.round(l.quantity * l.unitPriceCents), 0); const stamp = now();
  await db.withTransactionAsync(async () => {
    await db.runAsync("UPDATE orders SET status='closed',total_cents=?,closed_at=?,updated_at=? WHERE id=?", totalCents, stamp, stamp, order.id);
    if (order.appointmentId) await db.runAsync("UPDATE appointments SET status='completed',updated_at=? WHERE id=?", stamp, order.appointmentId);
    if (order.followupAt) {
      const followup = { id: newId(), clientId: order.clientId, orderId: order.id, dueAt: order.followupAt, status: 'pending' };
      await db.runAsync('INSERT INTO followups (id,client_id,order_id,due_at,status,created_at) VALUES (?,?,?,?,?,?)', followup.id, followup.clientId, followup.orderId, followup.dueAt, followup.status, stamp);
      await enqueue(db, 'followups', followup.id, 'upsert', followup);
    }
    await enqueue(db, 'orders', order.id, 'upsert', { ...order, status: 'closed', totalCents, closedAt: stamp });
  });
}

export async function saveAttachment(db: SQLiteDatabase, orderId: string, kind: 'before' | 'after', localUri: string) {
  const attachment = { id: newId(), orderId, kind, localUri, createdAt: now() };
  await db.withTransactionAsync(async () => {
    await db.runAsync('INSERT INTO attachments (id,order_id,kind,local_uri,created_at) VALUES (?,?,?,?,?)', attachment.id, orderId, kind, localUri, attachment.createdAt);
    await enqueue(db, 'attachments', attachment.id, 'upsert', attachment);
  });
  return attachment;
}

export async function setAttachmentRemotePath(db: SQLiteDatabase, attachmentId: string, remotePath: string) { await db.runAsync('UPDATE attachments SET remote_path=? WHERE id=?', remotePath, attachmentId); }

export async function getLastPullAt(db: SQLiteDatabase) { return (await db.getFirstAsync<{ value: string }>("SELECT value FROM app_metadata WHERE key='last_pull_at'"))?.value ?? '1970-01-01T00:00:00.000Z'; }

export async function applyRemoteSnapshot(db: SQLiteDatabase, snapshot: Record<string, any[]>, pulledAt: string) {
  await db.withTransactionAsync(async () => {
    for (const r of snapshot.clients ?? []) await db.runAsync(`INSERT INTO clients (id,name,phone,neighborhood,address,notes,created_at,updated_at,deleted_at) VALUES (?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,phone=excluded.phone,neighborhood=excluded.neighborhood,address=excluded.address,notes=excluded.notes,updated_at=excluded.updated_at,deleted_at=excluded.deleted_at`, r.id, r.name, r.phone ?? '', r.neighborhood ?? '', r.address ?? '', r.notes ?? '', r.created_at, r.updated_at, r.deleted_at ?? null);
    for (const r of snapshot.appointments ?? []) await db.runAsync(`INSERT INTO appointments (id,client_id,starts_at,service,duration_minutes,status,order_id,created_at,updated_at,deleted_at) VALUES (?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET client_id=excluded.client_id,starts_at=excluded.starts_at,service=excluded.service,duration_minutes=excluded.duration_minutes,status=excluded.status,order_id=excluded.order_id,updated_at=excluded.updated_at,deleted_at=excluded.deleted_at`, r.id, r.client_id, r.starts_at, r.service, r.duration_minutes, r.status, r.order_id, r.created_at, r.updated_at, r.deleted_at ?? null);
    for (const r of snapshot.orders ?? []) await db.runAsync(`INSERT INTO orders (id,client_id,appointment_id,status,notes,total_cents,payment_method,followup_at,closed_at,created_at,updated_at,deleted_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,notes=excluded.notes,total_cents=excluded.total_cents,payment_method=excluded.payment_method,followup_at=excluded.followup_at,closed_at=excluded.closed_at,updated_at=excluded.updated_at,deleted_at=excluded.deleted_at`, r.id, r.client_id, r.appointment_id, r.status, r.notes ?? '', r.total_cents, r.payment_method, r.followup_at, r.closed_at, r.created_at, r.updated_at, r.deleted_at ?? null);
    for (const r of snapshot.order_lines ?? []) await db.runAsync(`INSERT INTO order_lines (id,order_id,concept,quantity,unit_price_cents,created_at,updated_at,deleted_at) VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET concept=excluded.concept,quantity=excluded.quantity,unit_price_cents=excluded.unit_price_cents,updated_at=excluded.updated_at,deleted_at=excluded.deleted_at`, r.id, r.order_id, r.concept, r.quantity, r.unit_price_cents, r.created_at, r.updated_at, r.deleted_at ?? null);
    for (const r of snapshot.payments ?? []) await db.runAsync(`INSERT INTO payments (id,order_id,method,amount_cents,paid_at,created_at,voided_at) VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET method=excluded.method,amount_cents=excluded.amount_cents,paid_at=excluded.paid_at,voided_at=excluded.voided_at`, r.id, r.order_id, r.method, r.amount_cents, r.paid_at, r.created_at, r.voided_at);
    for (const r of snapshot.attachments ?? []) await db.runAsync(`INSERT INTO attachments (id,order_id,kind,local_uri,remote_path,created_at,deleted_at) VALUES (?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET remote_path=excluded.remote_path,deleted_at=excluded.deleted_at`, r.id, r.order_id, r.kind, '', r.remote_path, r.created_at, r.deleted_at ?? null);
    for (const r of snapshot.followups ?? []) await db.runAsync(`INSERT INTO followups (id,client_id,order_id,due_at,status,created_at) VALUES (?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET due_at=excluded.due_at,status=excluded.status`, r.id, r.client_id, r.order_id, r.due_at, r.status, r.created_at);
    await db.runAsync("INSERT INTO app_metadata (key,value) VALUES ('last_pull_at',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", pulledAt);
  });
}

export async function queueCount(db: SQLiteDatabase) { const row = await db.getFirstAsync<{ count: number }>('SELECT COUNT(*) count FROM sync_queue'); return row?.count ?? 0; }
export async function listQueue(db: SQLiteDatabase): Promise<QueueRecord[]> { const rows = await db.getAllAsync<any>('SELECT * FROM sync_queue ORDER BY created_at LIMIT 100'); return rows.map(r => ({ id: r.id, tableName: r.table_name, entityId: r.entity_id, operation: r.operation, payload: r.payload, attempts: r.attempts })); }
export async function markQueueDone(db: SQLiteDatabase, id: string) { await db.runAsync('DELETE FROM sync_queue WHERE id=?', id); }
export async function markQueueFailed(db: SQLiteDatabase, id: string, error: string) { await db.runAsync('UPDATE sync_queue SET attempts=attempts+1,last_error=? WHERE id=?', error.slice(0, 500), id); }

export async function getAccessState(db: SQLiteDatabase): Promise<AccessState> {
  const row = await db.getFirstAsync<{ value: string }>("SELECT value FROM app_metadata WHERE key='trial_started_at'");
  const trialStartedAt = row?.value ?? now(); const end = new Date(trialStartedAt); end.setDate(end.getDate() + 15);
  const trialDaysRemaining = Math.max(0, Math.ceil((end.getTime() - Date.now()) / 86400000));
  return { trialStartedAt, trialEndsAt: end.toISOString(), trialDaysRemaining, entitlement: trialDaysRemaining > 0 ? 'trial' : 'expired' };
}
