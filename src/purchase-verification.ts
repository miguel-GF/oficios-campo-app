import type { Purchase } from 'expo-iap';

export type PurchaseVerificationStatus = 'valid' | 'pending' | 'invalid' | 'unavailable';

export type PurchaseVerification = {
  status: PurchaseVerificationStatus;
  reason?: string;
};

/**
 * Boundary for the first serverless release. A future backend can implement
 * this interface with Google Play token verification without changing screens
 * or the entitlement cache.
 */
export interface PurchaseVerifier {
  verify(purchase: Purchase, productId: string): Promise<PurchaseVerification>;
}

export const localPurchaseVerifier: PurchaseVerifier = {
  async verify(purchase, productId) {
    if (purchase.productId !== productId) return { status: 'invalid', reason: 'PRODUCT_MISMATCH' };
    if (purchase.purchaseState === 'pending') return { status: 'pending' };
    if (purchase.purchaseState !== 'purchased') return { status: 'unavailable', reason: 'STORE_STATE_UNKNOWN' };
    if ('isSuspendedAndroid' in purchase && purchase.isSuspendedAndroid === true) return { status: 'invalid', reason: 'SUBSCRIPTION_SUSPENDED' };
    return { status: 'valid' };
  },
};
