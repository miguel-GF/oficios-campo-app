import * as SecureStore from 'expo-secure-store';
import * as FileSystem from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';

export type Session = { accessToken: string; refreshToken: string; expiresAt: number; email: string };
const SESSION_KEY = 'jale.supabase.session.v1';
const config = () => ({ url: process.env.EXPO_PUBLIC_SUPABASE_URL, anonKey: process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY });
export const isCloudConfigured = () => Boolean(config().url && config().anonKey);

async function request(path: string, init: RequestInit) {
  const { url, anonKey } = config();
  if (!url || !anonKey) throw new Error('Supabase no está configurado.');
  const response = await fetch(`${url}${path}`, { ...init, headers: { apikey: anonKey, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  if (!response.ok) { const body = await response.json().catch(() => ({})); throw new Error(body.msg ?? body.message ?? body.error_description ?? `Error ${response.status}`); }
  return response.json();
}

export async function requestEmailOtp(email: string) {
  await request('/auth/v1/otp', { method: 'POST', body: JSON.stringify({ email: email.trim().toLowerCase(), create_user: true }) });
}

export async function verifyEmailOtp(email: string, token: string): Promise<Session> {
  const body = await request('/auth/v1/verify', { method: 'POST', body: JSON.stringify({ email: email.trim().toLowerCase(), token: token.trim(), type: 'email' }) });
  const session = { accessToken: body.access_token, refreshToken: body.refresh_token, expiresAt: Date.now() + Number(body.expires_in ?? 3600) * 1000, email: body.user?.email ?? email };
  await SecureStore.setItemAsync(SESSION_KEY, JSON.stringify(session)); return session;
}

export async function loadSession(): Promise<Session | null> {
  const raw = await SecureStore.getItemAsync(SESSION_KEY); if (!raw) return null;
  const session = JSON.parse(raw) as Session;
  if (session.expiresAt > Date.now() + 60_000) return session;
  try {
    const body = await request('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: JSON.stringify({ refresh_token: session.refreshToken }) });
    const renewed = { accessToken: body.access_token, refreshToken: body.refresh_token, expiresAt: Date.now() + Number(body.expires_in ?? 3600) * 1000, email: body.user?.email ?? session.email };
    await SecureStore.setItemAsync(SESSION_KEY, JSON.stringify(renewed)); return renewed;
  } catch { await SecureStore.deleteItemAsync(SESSION_KEY); return null; }
}

export async function bootstrapBusiness(session: Session, businessName: string, trade: string) {
  const { url, anonKey } = config();
  const response = await fetch(`${url}/functions/v1/bootstrap`, { method: 'POST', headers: { apikey: anonKey!, Authorization: `Bearer ${session.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ businessName: businessName.trim(), trade: trade.trim() }) });
  if (!response.ok) throw new Error((await response.text()).slice(0, 250));
}

export async function signOut() { await SecureStore.deleteItemAsync(SESSION_KEY); }

export async function deleteCloudAccount(session: Session) {
  const { url, anonKey } = config(); const response = await fetch(`${url}/functions/v1/account`, { method: 'DELETE', headers: { apikey: anonKey!, Authorization: `Bearer ${session.accessToken}` } });
  if (!response.ok) throw new Error((await response.text()).slice(0, 250)); await signOut();
}

export async function exportCloudAccount(session: Session) {
  const { url, anonKey } = config(); const response = await fetch(`${url}/functions/v1/account`, { headers: { apikey: anonKey!, Authorization: `Bearer ${session.accessToken}` } });
  if (!response.ok) throw new Error((await response.text()).slice(0, 250)); if (!FileSystem.documentDirectory) throw new Error('No hay almacenamiento disponible.');
  const uri = `${FileSystem.documentDirectory}jale-export-${Date.now()}.json`; await FileSystem.writeAsStringAsync(uri, await response.text());
  await Sharing.shareAsync(uri, { mimeType: 'application/json', dialogTitle: 'Exportar mis datos' });
}

export async function loadCloudEntitlement(session: Session) {
  const { url, anonKey } = config(); const response = await fetch(`${url}/functions/v1/entitlement`, { headers: { apikey: anonKey!, Authorization: `Bearer ${session.accessToken}` } });
  if (!response.ok) throw new Error(`No se pudo consultar la suscripción: ${response.status}`); return response.json() as Promise<{ status: 'trial' | 'active' | 'grace' | 'expired' | 'cancelled'; trialEndsAt: string | null; currentPeriodEndsAt: string | null }>;
}
