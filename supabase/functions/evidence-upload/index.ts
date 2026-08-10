import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type' };
Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const url = Deno.env.get('SUPABASE_URL')!; const anon = Deno.env.get('SUPABASE_ANON_KEY')!; const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const authorization = request.headers.get('Authorization') ?? ''; const auth = createClient(url, anon, { global: { headers: { Authorization: authorization } } });
    const { data: { user } } = await auth.auth.getUser(); if (!user) return new Response('Unauthorized', { status: 401, headers: cors });
    const body = await request.json(); if (!body.orderId || !body.attachmentId) return new Response('Invalid attachment', { status: 400, headers: cors });
    const admin = createClient(url, serviceRole); const { data: profile } = await admin.from('profiles').select('business_id').eq('id', user.id).single(); if (!profile) return new Response('Profile missing', { status: 409, headers: cors });
    const extension = body.contentType === 'image/png' ? 'png' : 'jpg'; const path = `${profile.business_id}/${body.orderId}/${body.attachmentId}.${extension}`;
    const { data, error } = await admin.storage.from('evidence').createSignedUploadUrl(path, { upsert: true }); if (error) throw error;
    return Response.json({ path, signedUrl: data.signedUrl, token: data.token }, { headers: cors });
  } catch (error) { return Response.json({ error: error instanceof Error ? error.message : String(error) }, { status: 500, headers: cors }); }
});
