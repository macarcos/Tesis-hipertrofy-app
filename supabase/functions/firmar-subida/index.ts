// ============================================================
// Edge Function: firmar-subida
// Genera una URL FIRMADA (presigned) para que la app suba el video
// DIRECTO a Cloudflare R2, sin exponer el secret. La app hace un PUT
// a esa URL y el video va directo a R2 (rápido). El secret vive aquí.
//
// R2 es compatible con S3, así que usamos AWS Signature V4.
// ============================================================

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── Helpers de firma AWS V4 (HMAC-SHA256) ──────────────────────────────────
async function hmac(key: ArrayBuffer | Uint8Array, msg: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(msg));
}

async function sha256Hex(msg: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(msg));
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function toHex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    // Credenciales R2 — viven en los secrets de Supabase, NO en la app
    const ACCESS_KEY = Deno.env.get("R2_ACCESS_KEY_ID");
    const SECRET_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY");
    const ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID");
    const BUCKET = Deno.env.get("R2_BUCKET") ?? "uniaccess-fotos";
    const PUBLIC_URL = Deno.env.get("R2_PUBLIC_URL") ?? "";

    if (!ACCESS_KEY || !SECRET_KEY || !ACCOUNT_ID) {
      return new Response(JSON.stringify({ error: "Faltan credenciales R2 en secrets" }),
        { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
    }

    // Leer qué tipo de archivo se va a subir (video o pdf)
    let tipo = "video";
    try {
      const body = await req.json();
      if (body && typeof body.tipo === "string") tipo = body.tipo;
    } catch (_) {
      // sin body → por defecto video (compatibilidad con lo que ya existía)
    }

    // Nombre y carpeta según el tipo
    const ts = Date.now();
    const rand = Math.random().toString(36).substring(2, 10);
    const objectName = tipo === "pdf"
        ? `documentos/reporte_${ts}_${rand}.pdf`
        : `videos/sesion_${ts}_${rand}.mp4`;

    // Endpoint S3 de R2
    const host = `${ACCOUNT_ID}.r2.cloudflarestorage.com`;
    const region = "auto";
    const service = "s3";

    // Fechas para la firma
    const now = new Date();
    const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, ""); // YYYYMMDDTHHMMSSZ
    const dateStamp = amzDate.substring(0, 8);                       // YYYYMMDD

    // Parámetros de la URL firmada (válida 10 minutos)
    const expires = 600;
    const credential = `${ACCESS_KEY}/${dateStamp}/${region}/${service}/aws4_request`;

    const canonicalUri = `/${BUCKET}/${objectName}`;
    const params: Record<string, string> = {
      "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
      "X-Amz-Credential": credential,
      "X-Amz-Date": amzDate,
      "X-Amz-Expires": String(expires),
      "X-Amz-SignedHeaders": "host",
    };
    const canonicalQuery = Object.keys(params)
      .sort()
      .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k])}`)
      .join("&");

    const canonicalHeaders = `host:${host}\n`;
    const payloadHash = "UNSIGNED-PAYLOAD";
    const canonicalRequest = [
      "PUT", canonicalUri, canonicalQuery, canonicalHeaders, "host", payloadHash,
    ].join("\n");

    const scope = `${dateStamp}/${region}/${service}/aws4_request`;
    const stringToSign = [
      "AWS4-HMAC-SHA256", amzDate, scope, await sha256Hex(canonicalRequest),
    ].join("\n");

    // Derivar la clave de firma
    const kDate = await hmac(new TextEncoder().encode("AWS4" + SECRET_KEY), dateStamp);
    const kRegion = await hmac(kDate, region);
    const kService = await hmac(kRegion, service);
    const kSigning = await hmac(kService, "aws4_request");
    const signature = toHex(await hmac(kSigning, stringToSign));

    // URL firmada final
    const uploadUrl =
      `https://${host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;

    // URL pública para ver el video después de subido
    const publicUrl = PUBLIC_URL ? `${PUBLIC_URL}/${objectName}` : "";

    return new Response(
      JSON.stringify({ uploadUrl, publicUrl, objectName }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } });
  }
});