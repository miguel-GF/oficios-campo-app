import type { SQLiteDatabase } from 'expo-sqlite';
import { randomUUID } from 'expo-crypto';
import {
  normalizeBrandColor,
  type BackupSnapshot,
  type BusinessProfile,
  type Client,
  type Payment,
  type PaymentMethod,
  type Quote,
  type QuoteLine,
  type QuoteStatus,
  type QuoteSummary,
  paymentSummary,
  quotaPeriod,
  quoteTotal,
  usageSummary,
  validateQuoteForFinalization,
} from './domain';

const SCHEMA_VERSION = 2;
const now = () => new Date().toISOString();
export const newId = () => randomUUID();

type QuoteRow = {
  id: string; quote_number: number; client_id: string | null; client_name: string; status: QuoteStatus;
  issued_at: string; valid_until: string | null; notes: string; total_cents: number;
  finalized_at: string | null; quota_period: string | null; created_at: string; updated_at: string;
};

export async function migrateDatabase(db: SQLiteDatabase) {
  await db.execAsync('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;');
  const version = await db.getFirstAsync<{ user_version: number }>('PRAGMA user_version');
  if ((version?.user_version ?? 0) === 0) {
    await db.execAsync(`
      PRAGMA foreign_keys=OFF;
      DROP TABLE IF EXISTS sync_queue; DROP TABLE IF EXISTS attachments; DROP TABLE IF EXISTS followups;
      DROP TABLE IF EXISTS payments; DROP TABLE IF EXISTS order_lines; DROP TABLE IF EXISTS orders;
      DROP TABLE IF EXISTS appointments; DROP TABLE IF EXISTS clients; DROP TABLE IF EXISTS app_metadata;
      DROP TABLE IF EXISTS quote_lines; DROP TABLE IF EXISTS quotes; DROP TABLE IF EXISTS business_profile;
      PRAGMA foreign_keys=ON;
      CREATE TABLE business_profile (
        id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, trade TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '', logo_uri TEXT, brand_color TEXT NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE clients (
        id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      );
      CREATE TABLE quotes (
        id TEXT PRIMARY KEY NOT NULL, quote_number INTEGER NOT NULL UNIQUE,
        client_id TEXT, client_name TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL CHECK(status IN ('draft','finalized','sent','accepted','rejected')),
        issued_at TEXT NOT NULL, valid_until TEXT, notes TEXT NOT NULL DEFAULT '',
        total_cents INTEGER NOT NULL DEFAULT 0 CHECK(total_cents >= 0),
        finalized_at TEXT, quota_period TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY(client_id) REFERENCES clients(id)
      );
      CREATE TABLE quote_lines (
        id TEXT PRIMARY KEY NOT NULL, quote_id TEXT NOT NULL, concept TEXT NOT NULL,
        quantity REAL NOT NULL CHECK(quantity >= 0), unit_price_cents INTEGER NOT NULL CHECK(unit_price_cents >= 0),
        position INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY(quote_id) REFERENCES quotes(id) ON DELETE CASCADE
      );
      CREATE TABLE payments (
        id TEXT PRIMARY KEY NOT NULL, quote_id TEXT NOT NULL, receipt_number INTEGER NOT NULL UNIQUE,
        method TEXT NOT NULL CHECK(method IN ('cash','transfer','other')),
        amount_cents INTEGER NOT NULL CHECK(amount_cents > 0), paid_at TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '', voided_at TEXT, receipt_finalized_at TEXT, quota_period TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY(quote_id) REFERENCES quotes(id)
      );
      CREATE TABLE app_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
      CREATE INDEX idx_clients_name ON clients(name);
      CREATE INDEX idx_quotes_updated ON quotes(updated_at DESC);
      CREATE INDEX idx_quotes_client ON quotes(client_id);
      CREATE INDEX idx_payments_quote ON payments(quote_id, paid_at);
      PRAGMA user_version=${SCHEMA_VERSION};
    `);
    await db.runAsync("INSERT INTO app_metadata (key,value) VALUES ('next_quote_number','1'),('next_receipt_number','1')");
    return;
  }
  if ((version?.user_version ?? 0) === 1) {
    await db.withTransactionAsync(() => db.execAsync(`
      CREATE TABLE quote_lines_v2 (
        id TEXT PRIMARY KEY NOT NULL, quote_id TEXT NOT NULL, concept TEXT NOT NULL,
        quantity REAL NOT NULL CHECK(quantity >= 0), unit_price_cents INTEGER NOT NULL CHECK(unit_price_cents >= 0),
        position INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        FOREIGN KEY(quote_id) REFERENCES quotes(id) ON DELETE CASCADE
      );
      INSERT INTO quote_lines_v2 SELECT * FROM quote_lines;
      DROP TABLE quote_lines;
      ALTER TABLE quote_lines_v2 RENAME TO quote_lines;
      PRAGMA user_version=${SCHEMA_VERSION};
    `));
  }
  if ((version?.user_version ?? 0) > SCHEMA_VERSION) throw new Error('Esta base de datos pertenece a una versión más reciente de Jale.');
}

export async function getBusinessProfile(db: SQLiteDatabase): Promise<BusinessProfile | null> {
  const row = await db.getFirstAsync<any>('SELECT * FROM business_profile LIMIT 1');
  return row ? { id: row.id, name: row.name, trade: row.trade, phone: row.phone, logoUri: row.logo_uri, brandColor: row.brand_color, createdAt: row.created_at, updatedAt: row.updated_at } : null;
}

export async function saveBusinessProfile(db: SQLiteDatabase, input: Pick<BusinessProfile, 'name' | 'trade' | 'phone' | 'logoUri' | 'brandColor'>) {
  if (!input.name.trim()) throw new Error('Escribe el nombre de tu negocio.');
  const current = await getBusinessProfile(db); const stamp = now();
  const profile: BusinessProfile = { id: current?.id ?? newId(), name: input.name.trim(), trade: input.trade.trim(), phone: input.phone.trim(), logoUri: input.logoUri, brandColor: normalizeBrandColor(input.brandColor), createdAt: current?.createdAt ?? stamp, updatedAt: stamp };
  await db.runAsync(`INSERT INTO business_profile (id,name,trade,phone,logo_uri,brand_color,created_at,updated_at)
    VALUES (?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,trade=excluded.trade,phone=excluded.phone,logo_uri=excluded.logo_uri,brand_color=excluded.brand_color,updated_at=excluded.updated_at`,
    profile.id, profile.name, profile.trade, profile.phone, profile.logoUri, profile.brandColor, profile.createdAt, profile.updatedAt);
  return profile;
}

export async function listClients(db: SQLiteDatabase, query = ''): Promise<Client[]> {
  const like = `%${query.trim()}%`;
  const rows = await db.getAllAsync<any>('SELECT * FROM clients WHERE name LIKE ? OR phone LIKE ? OR address LIKE ? ORDER BY updated_at DESC,name LIMIT 100', like, like, like);
  return rows.map(rowToClient);
}

const rowToClient = (row: any): Client => ({ id: row.id, name: row.name, phone: row.phone, address: row.address, notes: row.notes, createdAt: row.created_at, updatedAt: row.updated_at });

export async function saveClient(db: SQLiteDatabase, input: Partial<Client> & { name: string }) {
  if (!input.name.trim()) throw new Error('Escribe el nombre del cliente.');
  const stamp = now(); const id = input.id ?? newId();
  await db.runAsync(`INSERT INTO clients (id,name,phone,address,notes,created_at,updated_at) VALUES (?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET name=excluded.name,phone=excluded.phone,address=excluded.address,notes=excluded.notes,updated_at=excluded.updated_at`,
    id, input.name.trim(), input.phone?.trim() ?? '', input.address?.trim() ?? '', input.notes?.trim() ?? '', input.createdAt ?? stamp, stamp);
  return (await db.getFirstAsync<any>('SELECT * FROM clients WHERE id=?', id).then(row => rowToClient(row))) as Client;
}

async function nextNumber(db: SQLiteDatabase, key: 'next_quote_number' | 'next_receipt_number') {
  const row = await db.getFirstAsync<{ value: string }>('SELECT value FROM app_metadata WHERE key=?', key);
  const value = Math.max(1, Number(row?.value) || 1);
  await db.runAsync('INSERT INTO app_metadata (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', key, String(value + 1));
  return value;
}

export async function createQuote(db: SQLiteDatabase, client?: Pick<Client, 'id' | 'name'>) {
  const stamp = now(); const id = newId();
  await db.withTransactionAsync(async () => {
    const number = await nextNumber(db, 'next_quote_number');
    await db.runAsync(`INSERT INTO quotes (id,quote_number,client_id,client_name,status,issued_at,notes,total_cents,created_at,updated_at) VALUES (?,?,?,?,'draft',?,'',0,?,?)`, id, number, client?.id ?? null, client?.name ?? '', stamp, stamp, stamp);
    await db.runAsync('INSERT INTO quote_lines (id,quote_id,concept,quantity,unit_price_cents,position,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)', newId(), id, '', 1, 0, 0, stamp, stamp);
  });
  return id;
}

export async function getQuote(db: SQLiteDatabase, id: string): Promise<Quote | null> {
  const row = await db.getFirstAsync<QuoteRow>('SELECT * FROM quotes WHERE id=?', id);
  if (!row) return null;
  const [lines, payments] = await Promise.all([
    db.getAllAsync<any>('SELECT * FROM quote_lines WHERE quote_id=? ORDER BY position,id', id),
    db.getAllAsync<any>('SELECT * FROM payments WHERE quote_id=? ORDER BY paid_at,receipt_number', id),
  ]);
  return rowToQuote(row, lines, payments);
}

function rowToPayment(row: any): Payment { return { id: row.id, quoteId: row.quote_id, receiptNumber: row.receipt_number, method: row.method, amountCents: row.amount_cents, paidAt: row.paid_at, notes: row.notes, voidedAt: row.voided_at, receiptFinalizedAt: row.receipt_finalized_at, quotaPeriod: row.quota_period }; }
function rowToLine(row: any): QuoteLine { return { id: row.id, concept: row.concept, quantity: row.quantity, unitPriceCents: row.unit_price_cents, position: row.position }; }
function rowToQuote(row: QuoteRow, lines: any[], payments: any[]): Quote { return { id: row.id, quoteNumber: row.quote_number, clientId: row.client_id, clientName: row.client_name, status: row.status, issuedAt: row.issued_at, validUntil: row.valid_until, notes: row.notes, totalCents: row.total_cents, finalizedAt: row.finalized_at, quotaPeriod: row.quota_period, createdAt: row.created_at, updatedAt: row.updated_at, lines: lines.map(rowToLine), payments: payments.map(rowToPayment) }; }

export async function saveQuoteDraft(db: SQLiteDatabase, quote: Quote) {
  const stamp = now(); const total = quoteTotal(quote.lines);
  await db.withTransactionAsync(async () => {
    await db.runAsync('UPDATE quotes SET client_id=?,client_name=?,issued_at=?,valid_until=?,notes=?,total_cents=?,updated_at=? WHERE id=?', quote.clientId, quote.clientName.trim(), quote.issuedAt, quote.validUntil, quote.notes, total, stamp, quote.id);
    await db.runAsync('DELETE FROM quote_lines WHERE quote_id=?', quote.id);
    for (const [position, line] of quote.lines.entries()) await db.runAsync('INSERT INTO quote_lines (id,quote_id,concept,quantity,unit_price_cents,position,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)', line.id, quote.id, line.concept.trim(), line.quantity, line.unitPriceCents, position, stamp, stamp);
  });
}

export async function listQuotes(db: SQLiteDatabase, query = ''): Promise<QuoteSummary[]> {
  const like = `%${query.trim()}%`;
  const rows = await db.getAllAsync<any>(`SELECT q.*,COALESCE(SUM(CASE WHEN p.voided_at IS NULL THEN p.amount_cents ELSE 0 END),0) paid_cents
    FROM quotes q LEFT JOIN payments p ON p.quote_id=q.id WHERE q.client_name LIKE ? OR CAST(q.quote_number AS TEXT) LIKE ?
    GROUP BY q.id ORDER BY q.updated_at DESC LIMIT 150`, like, like);
  return rows.map(row => { const summary = paymentSummary(row.total_cents, [{ amountCents: row.paid_cents, voidedAt: null } as Payment]); return { id: row.id, quoteNumber: row.quote_number, clientName: row.client_name, status: row.status, issuedAt: row.issued_at, totalCents: row.total_cents, updatedAt: row.updated_at, paidCents: summary.paidCents, balanceCents: summary.balanceCents, paymentStatus: summary.status }; });
}

export async function getDocumentUsage(db: SQLiteDatabase, period = quotaPeriod()) {
  const quoteCount = await db.getFirstAsync<{ count: number }>('SELECT COUNT(*) count FROM quotes WHERE quota_period=?', period);
  const receiptCount = await db.getFirstAsync<{ count: number }>('SELECT COUNT(*) count FROM payments WHERE quota_period=?', period);
  return usageSummary((quoteCount?.count ?? 0) + (receiptCount?.count ?? 0), period);
}

export async function finalizeQuote(db: SQLiteDatabase, quote: Quote, isPro: boolean) {
  const validation = validateQuoteForFinalization(quote); if (validation) throw new Error(validation);
  await saveQuoteDraft(db, quote);
  if (quote.finalizedAt) return getQuote(db, quote.id);
  const period = quotaPeriod(); const usage = await getDocumentUsage(db, period);
  if (!isPro && usage.remaining <= 0) throw new Error('FREE_LIMIT_REACHED');
  const stamp = now();
  await db.runAsync("UPDATE quotes SET status='finalized',finalized_at=?,quota_period=?,updated_at=? WHERE id=?", stamp, period, stamp, quote.id);
  return getQuote(db, quote.id);
}

export async function setQuoteStatus(db: SQLiteDatabase, id: string, status: Exclude<QuoteStatus, 'draft'>) {
  await db.runAsync('UPDATE quotes SET status=?,updated_at=? WHERE id=?', status, now(), id);
  return getQuote(db, id);
}

export async function recordPayment(db: SQLiteDatabase, quote: Quote, method: PaymentMethod, amountCents: number, notes = '', paidAt = now()) {
  if (!Number.isInteger(amountCents) || amountCents <= 0) throw new Error('El abono debe ser mayor a cero.');
  const currentQuote = await getQuote(db, quote.id);
  if (!currentQuote) throw new Error('No se encontró la cotización.');
  if (currentQuote.status !== 'accepted') throw new Error('Solo se pueden registrar pagos de una cotización aceptada.');
  const summary = paymentSummary(currentQuote.totalCents, currentQuote.payments);
  if (amountCents > summary.balanceCents) throw new Error('El abono supera el saldo pendiente.');
  const id = newId(); const stamp = now();
  await db.withTransactionAsync(async () => {
    const receiptNumber = await nextNumber(db, 'next_receipt_number');
    await db.runAsync('INSERT INTO payments (id,quote_id,receipt_number,method,amount_cents,paid_at,notes,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)', id, quote.id, receiptNumber, method, amountCents, paidAt, notes.trim(), stamp, stamp);
  });
  return (await getQuote(db, quote.id))?.payments.find(payment => payment.id === id) ?? null;
}

export async function voidPayment(db: SQLiteDatabase, paymentId: string) {
  const stamp = now();
  await db.runAsync('UPDATE payments SET voided_at=?,updated_at=? WHERE id=? AND voided_at IS NULL', stamp, stamp, paymentId);
}

export async function deleteAllLocalData(db: SQLiteDatabase) {
  await db.withTransactionAsync(async () => {
    await db.runAsync('DELETE FROM payments');
    await db.runAsync('DELETE FROM quote_lines');
    await db.runAsync('DELETE FROM quotes');
    await db.runAsync('DELETE FROM clients');
    await db.runAsync('DELETE FROM business_profile');
    await db.runAsync("UPDATE app_metadata SET value=CASE key WHEN 'next_quote_number' THEN '1' WHEN 'next_receipt_number' THEN '1' ELSE value END WHERE key IN ('next_quote_number','next_receipt_number')");
  });
}

export async function finalizeReceipt(db: SQLiteDatabase, paymentId: string, isPro: boolean) {
  const payment = await db.getFirstAsync<any>('SELECT p.*,q.status AS quote_status FROM payments p JOIN quotes q ON q.id=p.quote_id WHERE p.id=?', paymentId);
  if (!payment) throw new Error('No se encontró el pago.');
  if (payment.quote_status !== 'accepted') throw new Error('Solo se pueden emitir recibos de una cotización aceptada.');
  if (payment.voided_at) throw new Error('No se puede generar un recibo para un pago anulado.');
  if (payment.receipt_finalized_at) return rowToPayment(payment);
  const period = quotaPeriod(); const usage = await getDocumentUsage(db, period);
  if (!isPro && usage.remaining <= 0) throw new Error('FREE_LIMIT_REACHED');
  const stamp = now(); await db.runAsync('UPDATE payments SET receipt_finalized_at=?,quota_period=?,updated_at=? WHERE id=?', stamp, period, stamp, paymentId);
  return rowToPayment({ ...payment, receipt_finalized_at: stamp, quota_period: period });
}

export async function exportSnapshot(db: SQLiteDatabase): Promise<BackupSnapshot> {
  const [businessProfile, clients, quoteRows, metadataRows] = await Promise.all([
    getBusinessProfile(db), listClients(db), db.getAllAsync<QuoteRow>('SELECT * FROM quotes ORDER BY quote_number'), db.getAllAsync<{ key: string; value: string }>('SELECT * FROM app_metadata'),
  ]);
  const quotes: Quote[] = [];
  for (const row of quoteRows) { const quote = await getQuote(db, row.id); if (quote) quotes.push(quote); }
  return { schemaVersion: 1, exportedAt: now(), businessProfile, clients, quotes, metadata: Object.fromEntries(metadataRows.map(row => [row.key, row.value])) };
}

export async function importSnapshot(db: SQLiteDatabase, snapshot: BackupSnapshot) {
  if (snapshot.schemaVersion !== 1 || !Array.isArray(snapshot.clients) || !Array.isArray(snapshot.quotes)) throw new Error('El respaldo no es compatible.');
  await db.withTransactionAsync(async () => {
    if (snapshot.businessProfile) {
      const currentProfile = await getBusinessProfile(db);
      if (!currentProfile || currentProfile.updatedAt <= snapshot.businessProfile.updatedAt) await saveBusinessProfile(db, snapshot.businessProfile);
    }
    for (const client of snapshot.clients) {
      const currentClient = await db.getFirstAsync<{ updated_at: string }>('SELECT updated_at FROM clients WHERE id=?', client.id);
      if (!currentClient || currentClient.updated_at <= client.updatedAt) await saveClient(db, client);
    }
    for (const quote of snapshot.quotes) {
      const currentQuote = await db.getFirstAsync<{ updated_at: string; quote_number: number }>('SELECT updated_at,quote_number FROM quotes WHERE id=?', quote.id);
      if (currentQuote && currentQuote.updated_at > quote.updatedAt) continue;
      const quoteNumberOwner = await db.getFirstAsync<{ id: string }>('SELECT id FROM quotes WHERE quote_number=?', quote.quoteNumber);
      const importedQuoteNumber = quoteNumberOwner && quoteNumberOwner.id !== quote.id ? await nextNumber(db, 'next_quote_number') : quote.quoteNumber;
      await db.runAsync(`INSERT INTO quotes (id,quote_number,client_id,client_name,status,issued_at,valid_until,notes,total_cents,finalized_at,quota_period,created_at,updated_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET client_id=excluded.client_id,client_name=excluded.client_name,status=excluded.status,issued_at=excluded.issued_at,valid_until=excluded.valid_until,notes=excluded.notes,total_cents=excluded.total_cents,finalized_at=excluded.finalized_at,quota_period=excluded.quota_period,updated_at=excluded.updated_at
        WHERE excluded.updated_at >= quotes.updated_at`, quote.id, importedQuoteNumber, quote.clientId, quote.clientName, quote.status, quote.issuedAt, quote.validUntil, quote.notes, quote.totalCents, quote.finalizedAt, quote.quotaPeriod, quote.createdAt, quote.updatedAt);
      await db.runAsync('DELETE FROM quote_lines WHERE quote_id=?', quote.id);
      for (const line of quote.lines) await db.runAsync('INSERT INTO quote_lines (id,quote_id,concept,quantity,unit_price_cents,position,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)', line.id, quote.id, line.concept, line.quantity, line.unitPriceCents, line.position, quote.createdAt, quote.updatedAt);
      const importedPaymentIds = new Set(quote.payments.map(payment => payment.id));
      const existingPayments = await db.getAllAsync<{ id: string }>('SELECT id FROM payments WHERE quote_id=?', quote.id);
      for (const existingPayment of existingPayments) {
        if (!importedPaymentIds.has(existingPayment.id)) await db.runAsync('DELETE FROM payments WHERE id=?', existingPayment.id);
      }
      for (const payment of quote.payments) {
        const currentPayment = await db.getFirstAsync<{ receipt_number: number }>('SELECT receipt_number FROM payments WHERE id=?', payment.id);
        const receiptNumberOwner = await db.getFirstAsync<{ id: string }>('SELECT id FROM payments WHERE receipt_number=?', payment.receiptNumber);
        const importedReceiptNumber = currentPayment?.receipt_number ?? (receiptNumberOwner && receiptNumberOwner.id !== payment.id ? await nextNumber(db, 'next_receipt_number') : payment.receiptNumber);
        await db.runAsync(`INSERT INTO payments (id,quote_id,receipt_number,method,amount_cents,paid_at,notes,voided_at,receipt_finalized_at,quota_period,created_at,updated_at)
          VALUES (?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET method=excluded.method,amount_cents=excluded.amount_cents,paid_at=excluded.paid_at,notes=excluded.notes,voided_at=excluded.voided_at,receipt_finalized_at=excluded.receipt_finalized_at,quota_period=excluded.quota_period,updated_at=excluded.updated_at`, payment.id, quote.id, importedReceiptNumber, payment.method, payment.amountCents, payment.paidAt, payment.notes, payment.voidedAt, payment.receiptFinalizedAt, payment.quotaPeriod, quote.createdAt, quote.updatedAt);
      }
    }
    for (const [key, value] of Object.entries(snapshot.metadata)) await db.runAsync('INSERT INTO app_metadata (key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=CASE WHEN CAST(excluded.value AS INTEGER)>CAST(value AS INTEGER) THEN excluded.value ELSE value END', key, value);
    const maxQuote = await db.getFirstAsync<{ next_value: number }>('SELECT COALESCE(MAX(quote_number),0)+1 next_value FROM quotes');
    const maxReceipt = await db.getFirstAsync<{ next_value: number }>('SELECT COALESCE(MAX(receipt_number),0)+1 next_value FROM payments');
    await db.runAsync("UPDATE app_metadata SET value=MAX(CAST(value AS INTEGER),?) WHERE key='next_quote_number'", maxQuote?.next_value ?? 1);
    await db.runAsync("UPDATE app_metadata SET value=MAX(CAST(value AS INTEGER),?) WHERE key='next_receipt_number'", maxReceipt?.next_value ?? 1);
  });
}
