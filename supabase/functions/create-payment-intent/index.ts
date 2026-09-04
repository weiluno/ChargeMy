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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const stripeSecret = Deno.env.get("STRIPE_SECRET_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!stripeSecret || !supabaseUrl || !supabaseAnonKey) {
    return json({ error: "Payment service is not configured" }, 500);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) return json({ error: "Authentication required" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const amount = Math.round(Number(body.amount));
  if (!Number.isInteger(amount) || amount < 200 || amount > 100000000) {
    return json({ error: "Amount must be between 200 and 100000000 cents" }, 400);
  }
  const currency = String(body.currency ?? "myr").toLowerCase();
  if (!/^[a-z]{3}$/.test(currency)) return json({ error: "Invalid currency" }, 400);
  const voucherClaimId =
    typeof body.voucherClaimId === "string" && body.voucherClaimId.trim().length > 0
      ? body.voucherClaimId.trim()
      : null;
  const { data: quote, error: quoteError } = await supabase.rpc(
    "preview_voucher_payment",
    {
      p_session_id: String(body.sessionId ?? ""),
      p_subtotal_myr: amount / 100,
      p_voucher_claim_id: voucherClaimId,
    },
  );
  if (quoteError || !quote || typeof quote !== "object") {
    return json({ error: "The voucher could not be applied" }, 400);
  }
  const quoteData = quote as Record<string, unknown>;
  const finalAmountMyr = Number(quoteData.final_amount_myr);
  const discountMyr = Number(quoteData.discount_myr);
  if (!Number.isFinite(finalAmountMyr) || !Number.isFinite(discountMyr)) {
    return json({ error: "The payment amount could not be calculated" }, 400);
  }
  const finalAmount = Math.round(finalAmountMyr * 100);
  if (finalAmount < 200 || finalAmount > 100000000) {
    return json({ error: "The final payment must be at least RM 2.00" }, 400);
  }

  const params = new URLSearchParams();
  params.set("amount", String(finalAmount));
  params.set("currency", currency);
  params.set("automatic_payment_methods[enabled]", "true");
  params.set("metadata[user_id]", user.id);
  params.set("metadata[session_id]", String(body.sessionId ?? ""));
  params.set("metadata[station_id]", String(body.stationId ?? ""));
  params.set("metadata[original_amount_myr]", (amount / 100).toFixed(2));
  params.set("metadata[discount_myr]", discountMyr.toFixed(2));
  if (voucherClaimId) params.set("metadata[voucher_claim_id]", voucherClaimId);

  const stripeResponse = await fetch("https://api.stripe.com/v1/payment_intents", {
    method: "POST",
    headers: {
      Authorization: `Basic ${btoa(`${stripeSecret}:`)}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params,
  });
  const stripeBody = await stripeResponse.json();
  if (!stripeResponse.ok || typeof stripeBody.client_secret !== "string") {
    console.error("Stripe PaymentIntent error", stripeBody);
    return json({ error: "Unable to create payment" }, 502);
  }
  return json({
    clientSecret: stripeBody.client_secret,
    paymentIntentId: stripeBody.id,
    finalAmountMyr,
    discountMyr,
  });
});
