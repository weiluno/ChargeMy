
import { createClient } from 'npm:@supabase/supabase-js@2';

Deno.serve(async (request) => {
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  if (request.headers.get('authorization') !== `Bearer ${Deno.env.get('PUSH_WEBHOOK_SECRET')}`) return new Response('Unauthorized', { status: 401 });
  const event = await request.json();
  const record = event.record ?? event;
  const userId = record.user_id as string | undefined;
  if (!userId) return Response.json({ error: 'Missing user_id.' }, { status: 400 });
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data: devices } = await admin.from('user_devices').select('push_token, provider').eq('user_id', userId).eq('provider', 'onesignal');
  if (!devices?.length) return Response.json({ delivered: 0 });
  const result = await fetch('https://api.onesignal.com/notifications?c=push', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Key ${Deno.env.get('ONESIGNAL_REST_API_KEY')}` },
    body: JSON.stringify({ app_id: Deno.env.get('ONESIGNAL_APP_ID'), include_subscription_ids: devices.map((device) => device.push_token), headings: { en: record.title }, contents: { en: record.body }, data: record.data ?? {} }),
  });
  return Response.json({ delivered: devices.length, providerStatus: result.status });
});
