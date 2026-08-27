export const FREE_DOCUMENTS_PER_MONTH = 3;
export const DEFAULT_BRAND_COLOR = '#0E5E4A';

export function normalizeBrandColor(value: string | null | undefined) {
  return value && /^#[0-9A-Fa-f]{6}$/.test(value) ? value.toUpperCase() : DEFAULT_BRAND_COLOR;
}

export type QuoteStatus = 'draft' | 'finalized' | 'sent' | 'accepted' | 'rejected';
export type PaymentMethod = 'cash' | 'transfer' | 'other';
export type PaymentStatus = 'pending' | 'partial' | 'paid';

export type BusinessProfile = {
  id: string;
  name: string;
  trade: string;
  phone: string;
  logoUri: string | null;
  brandColor: string;
  createdAt: string;
  updatedAt: string;
};

export type Client = {
  id: string;
  name: string;
  phone: string;
  address: string;
  notes: string;
  createdAt: string;
  updatedAt: string;
};

export type QuoteLine = {
  id: string;
  concept: string;
  quantity: number;
  unitPriceCents: number;
  position: number;
};

export type Payment = {
  id: string;
  quoteId: string;
  receiptNumber: number;
  method: PaymentMethod;
  amountCents: number;
  paidAt: string;
  notes: string;
  voidedAt: string | null;
  receiptFinalizedAt: string | null;
  quotaPeriod: string | null;
};

export type Quote = {
  id: string;
  quoteNumber: number;
  clientId: string | null;
  clientName: string;
  status: QuoteStatus;
  issuedAt: string;
  validUntil: string | null;
  notes: string;
  totalCents: number;
  finalizedAt: string | null;
  quotaPeriod: string | null;
  createdAt: string;
  updatedAt: string;
  lines: QuoteLine[];
  payments: Payment[];
};

export type QuoteSummary = Pick<Quote, 'id' | 'quoteNumber' | 'clientName' | 'status' | 'issuedAt' | 'totalCents' | 'updatedAt'> & {
  paidCents: number;
  balanceCents: number;
  paymentStatus: PaymentStatus;
};

export type UsageSummary = {
  period: string;
  used: number;
  limit: number;
  remaining: number;
};

export type BackupSnapshot = {
  schemaVersion: 1;
  exportedAt: string;
  businessProfile: BusinessProfile | null;
  clients: Client[];
  quotes: Quote[];
  metadata: Record<string, string>;
  logoBase64?: string;
};

export function quoteTotal(lines: QuoteLine[]) {
  return lines.reduce((sum, line) => sum + Math.round(line.quantity * line.unitPriceCents), 0);
}

export function paymentSummary(totalCents: number, payments: Payment[]) {
  const paidCents = payments.filter(payment => !payment.voidedAt).reduce((sum, payment) => sum + payment.amountCents, 0);
  const balanceCents = Math.max(0, totalCents - paidCents);
  const status: PaymentStatus = paidCents <= 0 ? 'pending' : balanceCents > 0 ? 'partial' : 'paid';
  return { paidCents, balanceCents, status };
}

export function quotaPeriod(date = new Date()) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
}

export function usageSummary(used: number, period = quotaPeriod()): UsageSummary {
  return { period, used, limit: FREE_DOCUMENTS_PER_MONTH, remaining: Math.max(0, FREE_DOCUMENTS_PER_MONTH - used) };
}

export function validateQuoteForFinalization(quote: Pick<Quote, 'clientName' | 'lines'> & { validUntil?: string | null }) {
  if (!quote.clientName.trim()) return 'Escribe el nombre del cliente.';
  if (quote.lines.length === 0) return 'Agrega al menos un concepto.';
  if (quote.lines.some(line => !line.concept.trim())) return 'Todos los conceptos necesitan una descripción.';
  if (quote.lines.some(line => !Number.isFinite(line.quantity) || line.quantity <= 0)) return 'Las cantidades deben ser mayores a cero.';
  if (quote.lines.some(line => !Number.isInteger(line.unitPriceCents) || line.unitPriceCents < 0)) return 'Los precios deben ser importes válidos.';
  if (quote.validUntil && !/^\d{4}-\d{2}-\d{2}$/.test(quote.validUntil)) return 'La vigencia debe tener el formato AAAA-MM-DD.';
  if (quote.validUntil) {
    const [year, month, day] = quote.validUntil.split('-').map(Number);
    const parsed = new Date(Date.UTC(year ?? 0, (month ?? 0) - 1, day ?? 0));
    if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() + 1 !== month || parsed.getUTCDate() !== day) return 'La fecha de vigencia no es válida.';
  }
  return null;
}

export function formatFolio(prefix: 'COT' | 'REC', number: number) {
  return `${prefix}-${String(number).padStart(6, '0')}`;
}

export function money(cents: number) {
  return new Intl.NumberFormat('es-MX', { style: 'currency', currency: 'MXN' }).format(cents / 100);
}

export function parseMoneyToCents(value: string) {
  const cleaned = value.trim().replace(/\s|\$/g, '').replace(/[^\d,.-]/g, '');
  const comma = cleaned.lastIndexOf(',');
  const dot = cleaned.lastIndexOf('.');
  let normalized = cleaned;
  if (comma >= 0 && dot >= 0) {
    const decimalMark = comma > dot ? ',' : '.';
    normalized = cleaned.replace(decimalMark === ',' ? /\./g : /,/g, '').replace(decimalMark, '.');
  } else if (comma >= 0) {
    normalized = /^-?\d{1,3}(,\d{3})+$/.test(cleaned) ? cleaned.replace(/,/g, '') : cleaned.replace(',', '.');
  } else if ((cleaned.match(/\./g)?.length ?? 0) > 1 && /^-?\d{1,3}(\.\d{3})+$/.test(cleaned)) {
    normalized = cleaned.replace(/\./g, '');
  }
  if (!normalized) return 0;
  const amount = Number(normalized);
  return Number.isFinite(amount) ? Math.max(0, Math.round(amount * 100)) : 0;
}

export function newLinePlaceholder(position: number): QuoteLine {
  const random = Math.random().toString(16).slice(2);
  return { id: `line-${Date.now()}-${random}`, concept: '', quantity: 1, unitPriceCents: 0, position };
}
