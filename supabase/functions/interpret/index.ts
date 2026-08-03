import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };
Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!; const anon = Deno.env.get('SUPABASE_ANON_KEY')!; const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; const authorization = request.headers.get('Authorization') ?? '';
    const auth = createClient(url, anon, { global: { headers: { Authorization: authorization } } }); const { data: { user } } = await auth.auth.getUser(); if (!user) return new Response('Unauthorized', { status: 401, headers: cors });
    const admin = createClient(url, serviceRole); const { data: profile } = await admin.from('profiles').select('business_id').eq('id', user.id).single(); if (!profile) return new Response('Profile missing', { status: 409, headers: cors });
    const body = await request.json(); if (!body.transcript?.trim() || body.transcript.length > 1000) return new Response('Invalid transcript', { status: 400, headers: cors });
    const { data: clients } = await admin.from('clients').select('id,name').eq('business_id', profile.business_id).is('deleted_at', null).limit(100);
    const completion = await fetch('https://api.openai.com/v1/chat/completions', { method: 'POST', headers: { Authorization: `Bearer ${Deno.env.get('OPENAI_API_KEY')}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ model: Deno.env.get('OPENAI_MODEL') ?? 'gpt-4.1-mini', temperature: 0, response_format: { type: 'json_object' }, messages: [{ role: 'system', content: `Interpreta comandos de agenda para México. Fecha actual ISO: ${new Date().toISOString()}. Clientes: ${JSON.stringify(clients ?? [])}. Responde JSON: {"intent":"create_appointment","clientId":"id exacto","startsAt":"ISO","service":"texto","preview":"resumen español"}; si es ambiguo usa {"intent":"unknown","preview":"pregunta concreta"}. Nunca inventes cliente.` }, { role: 'user', content: body.transcript }] }) });
    if (!completion.ok) throw new Error(`AI HTTP ${completion.status}`); const json = await completion.json(); const result = JSON.parse(json.choices?.[0]?.message?.content ?? '{}');
    if (result.intent === 'create_appointment' && !(clients ?? []).some(client => client.id === result.clientId)) return Response.json({ intent: 'unknown', preview: 'No encontré un cliente único. Créalo o especifica su nombre.' }, { headers: cors });
    return Response.json(result, { headers: cors });
  } catch (error) { return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500, headers: cors }); }
});
