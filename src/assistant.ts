import type { Session } from './auth';

export type AssistantIntent = { intent: 'create_appointment'; clientId: string; startsAt: string; service: string; preview: string } | { intent: 'unknown'; preview: string };
export async function interpretCommand(session: Session, transcript: string): Promise<AssistantIntent> {
  const url = process.env.EXPO_PUBLIC_SUPABASE_URL; const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) throw new Error('El asistente requiere Supabase configurado.');
  const response = await fetch(`${url}/functions/v1/interpret`, { method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${session.accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ transcript }) });
  if (!response.ok) throw new Error((await response.text()).slice(0, 250)); return response.json();
}
