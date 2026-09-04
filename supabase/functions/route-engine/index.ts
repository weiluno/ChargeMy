
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
};

type Point = { latitude: number; longitude: number };

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const auth = request.headers.get('authorization');
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY') ?? Deno.env.get('SUPABASE_PUBLISHABLE_KEY');
  if (!auth || !publicKey) return json({ error: 'Unauthenticated.' }, 401);
  const user = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, {
    headers: { authorization: auth, apikey: publicKey },
  });
  if (!user.ok) return json({ error: 'Unauthenticated.' }, 401);
  const key = Deno.env.get('GOOGLE_MAPS_SERVER_KEY');
  if (!key) return json({ error: 'Google routing is not configured.' }, 503);
  try {
    const body = await request.json();
    const origin = point(body.origin);
    const destination = point(body.destination);
    const routeResponse = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask': 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,routes.travelAdvisory',
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: origin.latitude, longitude: origin.longitude } } },
        destination: { location: { latLng: { latitude: destination.latitude, longitude: destination.longitude } } },
        travelMode: 'DRIVE', routingPreference: 'TRAFFIC_AWARE', polylineQuality: 'HIGH_QUALITY',
      }),
    });
    if (!routeResponse.ok) return json({ error: 'Google Routes request failed.' }, 502);
    const route = (await routeResponse.json()).routes?.[0];
    if (!route?.polyline?.encodedPolyline) return json({ error: 'No driving route found.' }, 404);
    const encoded = route.polyline.encodedPolyline as string;
    const points = decodePolyline(encoded);
    const elevationGainM = body.includeElevation === true
      ? await elevationGain(encoded, key)
      : null;
    return json({
      provider: 'google', points,
      distanceMeters: route.distanceMeters ?? 0,
      durationSeconds: Number.parseInt(String(route.duration ?? '0s')) || 0,
      elevationGainM,
      traffic: route.travelAdvisory?.trafficRestriction ?? null,
    });
  } catch (_) {
    return json({ error: 'Invalid route request.' }, 400);
  }
});

function point(value: unknown): Point {
  const item = value as Record<string, unknown>;
  const latitude = Number(item?.latitude); const longitude = Number(item?.longitude);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) throw new Error('Bad coordinate');
  return { latitude, longitude };
}

async function elevationGain(encoded: string, key: string): Promise<number | null> {
  const response = await fetch(`https://maps.googleapis.com/maps/api/elevation/json?path=enc:${encodeURIComponent(encoded)}&samples=64&key=${encodeURIComponent(key)}`);
  if (!response.ok) return null;
  const values = (await response.json()).results as Array<{ elevation?: number }> | undefined;
  if (!values || values.length < 2) return null;
  let gain = 0;
  for (let index = 1; index < values.length; index++) gain += Math.max(0, (values[index].elevation ?? 0) - (values[index - 1].elevation ?? 0));
  return Math.round(gain);
}

function decodePolyline(encoded: string): number[][] {
  const points: number[][] = []; let index = 0; let lat = 0; let lng = 0;
  while (index < encoded.length) {
    let result = 0; let shift = 0; let byte: number;
    do { byte = encoded.charCodeAt(index++) - 63; result |= (byte & 0x1f) << shift; shift += 5; } while (byte >= 0x20);
    lat += (result & 1) ? ~(result >> 1) : (result >> 1);
    result = 0; shift = 0;
    do { byte = encoded.charCodeAt(index++) - 63; result |= (byte & 0x1f) << shift; shift += 5; } while (byte >= 0x20);
    lng += (result & 1) ? ~(result >> 1) : (result >> 1);
    points.push([lat / 1e5, lng / 1e5]);
  }
  return points;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
}
