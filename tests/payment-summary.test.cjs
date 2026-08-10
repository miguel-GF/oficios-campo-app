const test = require('node:test');
const assert = require('node:assert/strict');
const { paymentSummary } = require('../.test-build/database.js');

const payment = (amountCents, voidedAt = null) => ({ id: String(amountCents), method: 'cash', amountCents, paidAt: '2026-08-03T00:00:00Z', voidedAt });

test('derives pending when no effective payment exists', () => {
  assert.deepEqual(paymentSummary({ totalCents: 10000, payments: [] }), { paidCents: 0, balanceCents: 10000, status: 'pending' });
});

test('derives partial from multiple effective payments', () => {
  assert.deepEqual(paymentSummary({ totalCents: 10000, payments: [payment(2000), payment(3000)] }), { paidCents: 5000, balanceCents: 5000, status: 'partial' });
});

test('derives paid and never returns a negative balance', () => {
  assert.deepEqual(paymentSummary({ totalCents: 10000, payments: [payment(11000)] }), { paidCents: 11000, balanceCents: 0, status: 'paid' });
});

test('ignores voided payments', () => {
  assert.deepEqual(paymentSummary({ totalCents: 10000, payments: [payment(10000, '2026-08-04T00:00:00Z')] }), { paidCents: 0, balanceCents: 10000, status: 'pending' });
});
