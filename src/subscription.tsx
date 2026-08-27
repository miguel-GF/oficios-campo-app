import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import * as SecureStore from 'expo-secure-store';
import { deepLinkToSubscriptions, ErrorCode, finishTransaction, useIAP, type ProductSubscription, type SubscriptionOffer } from 'expo-iap';
import { localPurchaseVerifier } from './purchase-verification';

const PRODUCT_ID = 'jale_pro';
const CACHE_KEY = 'jale.pro.entitlement.v1';

type SubscriptionContextValue = {
  isPro: boolean;
  loading: boolean;
  connected: boolean;
  offers: SubscriptionOffer[];
  buy: (basePlanId: 'monthly' | 'yearly') => Promise<void>;
  restore: () => Promise<boolean>;
  manage: () => Promise<void>;
};

const SubscriptionContext = createContext<SubscriptionContextValue | null>(null);

export function SubscriptionProvider({ children }: { children: React.ReactNode }) {
  const [isPro, setIsPro] = useState(false); const [loading, setLoading] = useState(true);
  const grant = useCallback(async (value: boolean) => { setIsPro(value); await SecureStore.setItemAsync(CACHE_KEY, value ? 'active' : 'free'); }, []);
  const iap = useIAP({
    onPurchaseSuccess: purchase => {
      if (purchase.productId !== PRODUCT_ID) return;
      void (async () => {
        const verification = await localPurchaseVerifier.verify(purchase, PRODUCT_ID);
        if (verification.status !== 'valid') return;
        await grant(true);
        await finishTransaction({ purchase, isConsumable: false });
      })().catch(error => console.warn('No se pudo finalizar la compra:', error));
    },
    onPurchaseError: error => { if (error.code !== ErrorCode.UserCancelled) console.warn('No se completó la compra:', error.message); },
    onError: error => console.warn('Google Play no está disponible:', error.message),
  });

  useEffect(() => {
    void SecureStore.getItemAsync(CACHE_KEY)
      .then(value => setIsPro(value === 'active'))
      .catch(() => setIsPro(false))
      .finally(() => setLoading(false));
  }, []);
  useEffect(() => {
    if (!iap.connected) return;
    void (async () => {
      try {
        await iap.fetchProducts({ skus: [PRODUCT_ID], type: 'subs' });
        const active = await iap.hasActiveSubscriptions([PRODUCT_ID]);
        await grant(active);
      } catch { /* Fail open: preserve the cached entitlement while offline. */ }
      finally { setLoading(false); }
    })();
  }, [iap.connected, iap.fetchProducts, iap.hasActiveSubscriptions, grant]);

  const product = iap.subscriptions.find(item => item.id === PRODUCT_ID) as ProductSubscription | undefined;
  const offers = product?.subscriptionOffers ?? [];
  const buy = useCallback(async (basePlanId: 'monthly' | 'yearly') => {
    const offer = offers.find(item => item.basePlanIdAndroid === basePlanId && item.offerTokenAndroid);
    if (!offer?.offerTokenAndroid) throw new Error('Este plan todavía no está disponible en Google Play.');
    await iap.requestPurchase({ request: { google: { skus: [PRODUCT_ID], subscriptionOffers: [{ sku: PRODUCT_ID, offerToken: offer.offerTokenAndroid }] } }, type: 'subs' });
  }, [iap.requestPurchase, offers]);
  const restore = useCallback(async () => {
    if (!iap.connected) throw new Error('Conéctate a internet para restaurar la compra.');
    const active = await iap.hasActiveSubscriptions([PRODUCT_ID]); await grant(active); return active;
  }, [iap.connected, iap.hasActiveSubscriptions, grant]);
  const manage = useCallback(() => deepLinkToSubscriptions({ packageNameAndroid: 'mx.jale.app', skuAndroid: PRODUCT_ID }), []);
  const value = useMemo(() => ({ isPro, loading, connected: iap.connected, offers, buy, restore, manage }), [isPro, loading, iap.connected, offers, buy, restore, manage]);
  return <SubscriptionContext.Provider value={value}>{children}</SubscriptionContext.Provider>;
}

export function useSubscription() {
  const value = useContext(SubscriptionContext); if (!value) throw new Error('useSubscription debe usarse dentro de SubscriptionProvider.'); return value;
}
