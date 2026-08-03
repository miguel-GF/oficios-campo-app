import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };
Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!; const anon = Deno.env.get('SUPABASE_ANON_KEY')!; const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; const authorization = request.headers.get('Authorization') ?? '';
    const auth = createClient(url, anon, { global: { headers: { Authorization: authorization } } }); const { data: { user } } = await auth.auth.getUser(); if (!user) return new Response('Unauthorized', { status: 401, headers: cors });
    const admin = createClient(url, serviceRole); const { data: profile } = await admin.from('profiles').select('business_id').eq('id', user.id).single(); if (!profile) return new Response('Profile missing', { status: 409, headers: cors });
    const { data, error } = await admin.from('subscription_entitlements').select('status,trial_ends_at,current_period_ends_at').eq('business_id', profile.business_id).single(); if (error) throw error;
    let status = data.status; if (status === 'trial' && data.trial_ends_at && new Date(data.trial_ends_at) <= new Date()) status = 'expired';
    return Response.json({ status, trialEndsAt: data.trial_ends_at, currentPeriodEndsAt: data.current_period_ends_at }, { headers: cors });
  } catch (error) { return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500, headers: cors }); }
});
