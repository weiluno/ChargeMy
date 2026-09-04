import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function fixed(value: number, digits: number): string {
  return value.toFixed(digits);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const brevoKey = Deno.env.get("BREVO_API_KEY");
  const fromEmail = Deno.env.get("RECEIPT_FROM_EMAIL");
  const fromName = Deno.env.get("RECEIPT_FROM_NAME") ?? "ChargeMY";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: request.headers.get("Authorization") ?? "" } } },
  );
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user?.email) return json({ error: "Authentication required" }, 401);

  console.log("Receipt request received", {
    userId: user.id,
    recipient: user.email,
    hasBrevoKey: Boolean(brevoKey),
    fromEmail: fromEmail ?? null,
  });

  if (!brevoKey || !fromEmail) {
    console.warn("Receipt email is not configured");
    return json({ sent: false, reason: "not_configured" });
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const amount = Number(body.amountMyr);
  const originalAmount = Number(body.originalAmountMyr ?? amount);
  const discount = Number(body.discountMyr ?? 0);
  const voucherCode = String(body.voucherCode ?? "").trim();
  const energy = Number(body.energyKwh);
  if (
    !Number.isFinite(amount) || amount < 0 ||
    !Number.isFinite(originalAmount) || originalAmount < amount ||
    !Number.isFinite(discount) || discount < 0 ||
    !Number.isFinite(energy) || energy < 0
  ) {
    return json({ error: "Invalid receipt details" }, 400);
  }

  const stationId = String(body.stationId ?? "Charging station");
  const endSoc = Number(body.endSoc ?? 0);
  const endingSoc = Math.max(0, Math.min(100, endSoc));
  const { data: station } = await supabase
    .from("stations")
    .select("name")
    .eq("id", stationId)
    .maybeSingle();
  const stationName = String(station?.name ?? stationId);
  const paidAt = new Date().toLocaleString("en-MY", { timeZone: "Asia/Kuala_Lumpur" });
  const html = `
    <div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#17352d">
      <div style="background:#087f5b;color:white;padding:24px;border-radius:16px 16px 0 0">
        <div style="font-size:24px;font-weight:700">ChargeMY</div>
        <div style="margin-top:6px;opacity:.9">Charging payment receipt</div>
      </div>
      <div style="padding:24px;border:1px solid #dce8e2;border-top:0;border-radius:0 0 16px 16px">
        <h2 style="margin-top:0">Payment successful</h2>
        <p>Thank you for using ChargeMY. Your charging session has been completed.</p>
        <table style="width:100%;border-collapse:collapse">
          <tr><td style="padding:8px 0;color:#64756f">Station</td><td style="padding:8px 0;text-align:right;font-weight:600">${stationName}</td></tr>
          <tr><td style="padding:8px 0;color:#64756f">Energy used</td><td style="padding:8px 0;text-align:right;font-weight:600">${fixed(energy, 2)} kWh</td></tr>
          <tr><td style="padding:8px 0;color:#64756f">Ending battery</td><td style="padding:8px 0;text-align:right;font-weight:600">${fixed(endingSoc, 0)}%</td></tr>
          <tr><td style="padding:8px 0;color:#64756f">Charging total</td><td style="padding:8px 0;text-align:right;font-weight:600">RM ${fixed(originalAmount, 2)}</td></tr>
          ${voucherCode && discount > 0 ? `<tr><td style="padding:8px 0;color:#64756f">Voucher used</td><td style="padding:8px 0;text-align:right;font-weight:600">${voucherCode}</td></tr>` : ""}
          ${discount > 0 ? `<tr><td style="padding:8px 0;color:#64756f">Voucher discount</td><td style="padding:8px 0;text-align:right;font-weight:600">- RM ${fixed(discount, 2)}</td></tr>` : ""}
          <tr><td style="padding:12px 0;border-top:1px solid #dce8e2;font-size:18px;font-weight:700">Amount paid</td><td style="padding:12px 0;border-top:1px solid #dce8e2;text-align:right;font-size:18px;font-weight:700">RM ${fixed(amount, 2)}</td></tr>
        </table>
        <p style="font-size:12px;color:#64756f">Paid: ${paidAt}</p>
      </div>
    </div>`;

  const response = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: { "api-key": brevoKey, "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      sender: { email: fromEmail, name: fromName },
      to: [{ email: user.email }],
      subject: "ChargeMY payment receipt",
      htmlContent: html,
    }),
  });
  if (!response.ok) {
    console.error("Brevo receipt error", response.status, await response.text());
    return json({ sent: false, reason: "provider_error" });
  }
  console.log("Receipt sent", { recipient: user.email });
  return json({ sent: true });
});
