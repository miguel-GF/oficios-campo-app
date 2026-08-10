import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };
Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!; const anon = Deno.env.get('SUPABASE_ANON_KEY')!; const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; const authorization = request.headers.get('Authorization') ?? '';
    const auth = createClient(url, anon, { global: { headers: { Authorization: authorization } } }); const { data: { user } } = await auth.auth.getUser(); if (!user) return new Response('Unauthorized', { status: 401, headers: cors });
    const admin = createClient(url, serviceRole); const { data: profile } = await admin.from('profiles').select('business_id,role').eq('id', user.id).single(); if (!profile) return new Response('Profile missing', { status: 409, headers: cors });
    if (request.method === 'GET') { const result: Record<string, unknown> = { profile }; for (const table of ['clients','appointments','orders','order_lines','payments','attachments','followups']) { const { data } = await admin.from(table).select('*').eq('business_id', profile.business_id); result[table] = data ?? []; } return Response.json(result, { headers: { ...cors, 'Content-Disposition': 'attachment; filename="jale-export.json"' } }); }
    if (request.method !== 'DELETE' || profile.role !== 'owner') return new Response('Forbidden', { status: 403, headers: cors });
    const { data: evidence } = await admin.from('attachments').select('remote_path').eq('business_id', profile.business_id).not('remote_path', 'is', null); const paths = (evidence ?? []).map(item => item.remote_path).filter(Boolean); if (paths.length) await admin.storage.from('evidence').remove(paths);
    for (const table of ['followups','attachments','payments','order_lines','orders','appointments','clients','subscription_entitlements','sync_receipts']) { const column = table === 'sync_receipts' ? 'user_id' : 'business_id'; await admin.from(table).delete().eq(column, table === 'sync_receipts' ? user.id : profile.business_id); }
    await admin.from('profiles').delete().eq('business_id', profile.business_id); await admin.from('businesses').delete().eq('id', profile.business_id); await admin.auth.admin.deleteUser(user.id);
    return Response.json({ deleted: true }, { headers: cors });
  } catch (error) { return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500, headers: cors }); }
});
