import test from 'node:test';
import assert from 'node:assert/strict';
import { formatFolio, normalizeBrandColor, parseMoneyToCents, paymentSummary, quoteTotal, quotaPeriod, usageSummary, validateQuoteForFinalization, type Payment, type QuoteLine } from '../src/domain';

const payment = (amountCents: number, voidedAt: string | null = null): Payment => ({ id: String(amountCents), quoteId: 'q', receiptNumber: amountCents, method: 'cash', amountCents, paidAt: '2026-08-03T00:00:00Z', notes: '', voidedAt, receiptFinalizedAt: null, quotaPeriod: null });
const line = (quantity: number, unitPriceCents: number, concept = 'Servicio'): QuoteLine => ({ id: concept, concept, quantity, unitPriceCents, position: 0 });

test('calcula el total con cantidades decimales y redondea a centavos', () => {
  assert.equal(quoteTotal([line(1.5, 1099), line(2, 500)]), 2649);
});

test('deriva pendiente, parcial y pagada e ignora anulaciones', () => {
  assert.deepEqual(paymentSummary(10_000, []), { paidCents: 0, balanceCents: 10_000, status: 'pending' });
  assert.deepEqual(paymentSummary(10_000, [payment(3_000)]), { paidCents: 3_000, balanceCents: 7_000, status: 'partial' });
  assert.deepEqual(paymentSummary(10_000, [payment(11_000), payment(1_000, '2026-08-04T00:00:00Z')]), { paidCents: 11_000, balanceCents: 0, status: 'paid' });
});

test('valida la información mínima antes de finalizar', () => {
  assert.equal(validateQuoteForFinalization({ clientName: '', lines: [line(1, 100)] }), 'Escribe el nombre del cliente.');
  assert.equal(validateQuoteForFinalization({ clientName: 'Ana', lines: [line(1, 100, '')] }), 'Todos los conceptos necesitan una descripción.');
  assert.equal(validateQuoteForFinalization({ clientName: 'Ana', lines: [line(1, 100)] }), null);
  assert.match(validateQuoteForFinalization({ clientName: 'Ana', lines: [line(1, 100)], validUntil: '20/08/2026' }) ?? '', /AAAA-MM-DD/);
  assert.match(validateQuoteForFinalization({ clientName: 'Ana', lines: [line(1, 100)], validUntil: '2026-02-31' }) ?? '', /no es válida/);
});

test('calcula periodo, cuota y folios deterministas', () => {
  assert.equal(quotaPeriod(new Date(2026, 0, 15)), '2026-01');
  assert.deepEqual(usageSummary(2, '2026-01'), { period: '2026-01', used: 2, limit: 3, remaining: 1 });
  assert.equal(formatFolio('COT', 42), 'COT-000042');
});

test('convierte importes de captura a centavos', () => {
  assert.equal(parseMoneyToCents('$ 1,250'), 125000);
  assert.equal(parseMoneyToCents('1250.50'), 125050);
  assert.equal(parseMoneyToCents('1.250'), 125);
  assert.equal(parseMoneyToCents('1.250,50'), 125050);
  assert.equal(parseMoneyToCents('1250,50'), 125050);
  assert.equal(parseMoneyToCents('invalido'), 0);
});

test('normaliza el color institucional antes de usarlo en documentos', () => {
  assert.equal(normalizeBrandColor('#215a8e'), '#215A8E');
  assert.equal(normalizeBrandColor('red; color: black'), '#0E5E4A');
});
