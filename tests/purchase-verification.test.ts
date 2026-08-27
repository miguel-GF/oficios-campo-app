import test from 'node:test';
import assert from 'node:assert/strict';
import type { Purchase } from 'expo-iap';
import { localPurchaseVerifier } from '../src/purchase-verification';

const purchase = (state: 'purchased' | 'pending', suspended?: boolean) => ({
  id: 'transaction', productId: 'jale_pro', purchaseState: state, quantity: 1,
  isAutoRenewing: true, store: 'google', transactionDate: Date.now(),
  isSuspendedAndroid: suspended,
} as Purchase);

test('la validación local solo concede compras activas del producto', async () => {
  assert.equal((await localPurchaseVerifier.verify(purchase('purchased'), 'jale_pro')).status, 'valid');
  assert.equal((await localPurchaseVerifier.verify(purchase('pending'), 'jale_pro')).status, 'pending');
  assert.equal((await localPurchaseVerifier.verify(purchase('purchased', true), 'jale_pro')).status, 'invalid');
  assert.equal((await localPurchaseVerifier.verify(purchase('purchased'), 'otro')).status, 'invalid');
});
