import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };
Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!; const anon = Deno.env.get('SUPABASE_ANON_KEY')!; const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const authorization = request.headers.get('Authorization') ?? '';
    const auth = createClient(url, anon, { global: { headers: { Authorization: authorization } } });
    const { data: { user } } = await auth.auth.getUser(); if (!user) return new Response('Unauthorized', { status: 401, headers: cors });
    const admin = createClient(url, serviceRole); const { data: existing } = await admin.from('profiles').select('business_id').eq('id', user.id).maybeSingle();
    if (existing) return Response.json({ businessId: existing.business_id, existing: true }, { headers: cors });
    const body = await request.json(); if (!body.businessName?.trim()) return new Response('Business name required', { status: 400, headers: cors });
    const { data: business, error } = await admin.from('businesses').insert({ name: body.businessName.trim(), trade: body.trade?.trim() ?? '' }).select('id').single(); if (error) throw error;
    const trialEndsAt = new Date(); trialEndsAt.setDate(trialEndsAt.getDate() + 15);
    const { error: profileError } = await admin.from('profiles').insert({ id: user.id, business_id: business.id, name: user.email ?? '', role: 'owner' }); if (profileError) throw profileError;
    const { error: entitlementError } = await admin.from('subscription_entitlements').insert({ business_id: business.id, status: 'trial', trial_ends_at: trialEndsAt.toISOString() }); if (entitlementError) throw entitlementError;
    return Response.json({ businessId: business.id, trialEndsAt: trialEndsAt.toISOString() }, { headers: cors });
  } catch (error) { return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500, headers: cors }); }
});
