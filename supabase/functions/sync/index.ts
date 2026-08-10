import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const allowed = new Set(['clients', 'appointments', 'orders', 'payments', 'attachments', 'followups']);
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };
const snake = (key: string) => key.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);
const normalize = (payload: Record<string, unknown>, businessId: string) => Object.fromEntries(Object.entries({ ...payload, business_id: businessId }).filter(([key]) => !['lines', 'attachments', 'payments', 'clientName', 'localUri'].includes(key)).map(([key, value]) => [snake(key), value]));

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const authorization = request.headers.get('Authorization') ?? '';
    const url = Deno.env.get('SUPABASE_URL')!; const anon = Deno.env.get('SUPABASE_ANON_KEY')!; const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const authClient = createClient(url, anon, { global: { headers: { Authorization: authorization } } });
    const { data: { user } } = await authClient.auth.getUser();
    if (!user) return new Response('Unauthorized', { status: 401, headers: cors });
    const admin = createClient(url, serviceRole); const body = await request.json();
    if (!allowed.has(body.table) || !body.idempotencyKey || !body.entityId) return new Response('Invalid sync operation', { status: 400, headers: cors });
    const { data: profile } = await admin.from('profiles').select('business_id').eq('id', user.id).single();
    if (!profile?.business_id) return new Response('Profile has no business', { status: 409, headers: cors });
    const { data: receipt } = await admin.from('sync_receipts').select('id').eq('id', body.idempotencyKey).maybeSingle();
    if (receipt) return Response.json({ duplicate: true }, { headers: cors });
    if (body.operation === 'delete') {
      const { error } = await admin.from(body.table).update({ deleted_at: new Date().toISOString() }).eq('id', body.entityId).eq('business_id', profile.business_id);
      if (error) throw error;
    } else {
      const record = normalize(body.payload, profile.business_id);
      const { error } = await admin.from(body.table).upsert(record, { onConflict: 'id' });
      if (error) throw error;
      if (body.table === 'orders' && Array.isArray(body.payload.lines)) {
        const lines = body.payload.lines.map((line: Record<string, unknown>) => normalize({ ...line, orderId: body.entityId }, profile.business_id));
        const { error: cleanupError } = await admin.from('order_lines').delete().eq('order_id', body.entityId).eq('business_id', profile.business_id); if (cleanupError) throw cleanupError;
        const { error: lineError } = lines.length ? await admin.from('order_lines').insert(lines) : { error: null };
        if (lineError) throw lineError;
      }
    }
    const { error: receiptError } = await admin.from('sync_receipts').insert({ id: body.idempotencyKey, user_id: user.id });
    if (receiptError) throw receiptError;
    return Response.json({ ok: true }, { headers: cors });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500, headers: cors });
  }
});
