import { createClient } from "npm:@supabase/supabase-js@2";

type PurchaseRequest = {
  event_id: string;
  transaction_id: string;
  product_id: string;
  signed_transaction_jws?: string;
  requested_starts_at?: string;
  requested_ends_at?: string;
};

type AppleTransactionClaims = {
  transactionId?: string;
  originalTransactionId?: string;
  bundleId?: string;
  productId?: string;
  appAccountToken?: string;
  environment?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  revocationReason?: string | number;
};

const productAllowlist = new Set([
  "communitycalendar.commercial.standard",
  "communitycalendar.boost.standard",
  "communitycalendar.boost.insights",
]);

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const config = readConfig();
    const authHeader = request.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "Authentication required" }, 401);
    }

    const body = await readPurchaseRequest(request);
    const shapeError = validateRequestShape(body);
    if (shapeError) {
      return jsonResponse({ error: shapeError }, 400);
    }

    const userClient = createClient(config.supabaseUrl, config.supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user?.id) {
      return jsonResponse({ error: "Authentication failed" }, 401);
    }

    const userID = userData.user.id;
    const appleSignedTransaction = await fetchAppleSignedTransaction(
      config,
      body.transaction_id,
    );
    const claims = decodeAppleTransactionClaims(appleSignedTransaction);

    const claimError = validateAppleClaims({
      request: body,
      claims,
      expectedBundleID: config.appleBundleID,
      expectedEnvironment: config.appleEnvironment,
      expectedUserID: userID,
    });
    if (claimError) {
      return jsonResponse({ status: "rejected", error: claimError }, 409);
    }

    if (body.signed_transaction_jws && body.signed_transaction_jws !== appleSignedTransaction) {
      return jsonResponse({
        status: "rejected",
        error: "Client signed transaction does not match Apple server transaction",
      }, 409);
    }

    const serviceClient = createClient(config.supabaseUrl, config.supabaseServiceRoleKey, {
      auth: { persistSession: false },
    });

    const { data, error } = await serviceClient.rpc("process_verified_apple_iap_transaction", {
      p_apple_transaction_id: claims.transactionId,
      p_apple_original_transaction_id: claims.originalTransactionId ?? null,
      p_product_id: claims.productId,
      p_app_account_token: claims.appAccountToken ?? null,
      p_purchaser_user_id: userID,
      p_event_id: body.event_id,
      p_environment: claims.environment,
      p_bundle_id: claims.bundleId ?? null,
      p_purchase_date: dateFromAppleMilliseconds(claims.purchaseDate)?.toISOString(),
      p_expiration_date: dateFromAppleMilliseconds(claims.expiresDate)?.toISOString() ?? null,
      p_revocation_date: dateFromAppleMilliseconds(claims.revocationDate)?.toISOString() ?? null,
      p_revocation_reason: claims.revocationReason?.toString() ?? null,
      p_signed_transaction_hash: await sha256Hex(appleSignedTransaction),
      p_requested_starts_at: body.requested_starts_at ?? null,
      p_requested_ends_at: body.requested_ends_at ?? null,
    });

    if (error) {
      return jsonResponse({ status: "rejected", error: "Purchase processing failed" }, 500);
    }

    const result = Array.isArray(data) ? data[0] : data;
    return jsonResponse({
      status: result?.status ?? "rejected",
      apple_iap_transaction_id: result?.apple_iap_transaction_id ?? null,
      event_payment_record_id: result?.event_payment_record_id ?? null,
      event_promotion_id: result?.event_promotion_id ?? null,
      starts_at: result?.starts_at ?? null,
      ends_at: result?.ends_at ?? null,
      message: result?.message ?? null,
    });
  } catch (error) {
    return jsonResponse({
      status: "rejected",
      error: error instanceof Error ? error.message : "Unexpected purchase verification failure",
    }, 500);
  }
});

function readConfig() {
  const supabaseUrl = requiredEnv("SUPABASE_URL");
  const supabaseAnonKey = requiredEnv("SUPABASE_ANON_KEY");
  const supabaseServiceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  const appleIssuerID = requiredEnv("APPLE_ISSUER_ID");
  const appleKeyID = requiredEnv("APPLE_KEY_ID");
  const applePrivateKey = requiredEnv("APPLE_PRIVATE_KEY");
  const appleBundleID = requiredEnv("APPLE_BUNDLE_ID");
  const appleEnvironment = requiredEnv("APPLE_ENVIRONMENT");

  if (appleEnvironment !== "Sandbox" && appleEnvironment !== "Production") {
    throw new Error("APPLE_ENVIRONMENT must be Sandbox or Production");
  }

  return {
    supabaseUrl,
    supabaseAnonKey,
    supabaseServiceRoleKey,
    appleIssuerID,
    appleKeyID,
    applePrivateKey,
    appleBundleID,
    appleEnvironment,
  };
}

async function readPurchaseRequest(request: Request): Promise<PurchaseRequest> {
  try {
    return await request.json();
  } catch {
    throw new Error("Invalid JSON request body");
  }
}

function validateRequestShape(body: PurchaseRequest): string | null {
  if (!uuidPattern.test(body.event_id ?? "")) {
    return "event_id must be a UUID";
  }
  if (!body.transaction_id || body.transaction_id.trim().length === 0) {
    return "transaction_id is required";
  }
  if (!productAllowlist.has(body.product_id)) {
    return "product_id is not supported";
  }
  if (body.requested_starts_at && Number.isNaN(Date.parse(body.requested_starts_at))) {
    return "requested_starts_at must be an ISO date";
  }
  if (body.requested_ends_at && Number.isNaN(Date.parse(body.requested_ends_at))) {
    return "requested_ends_at must be an ISO date";
  }
  return null;
}

function validateAppleClaims(input: {
  request: PurchaseRequest;
  claims: AppleTransactionClaims;
  expectedBundleID: string;
  expectedEnvironment: string;
  expectedUserID: string;
}): string | null {
  if (input.claims.transactionId !== input.request.transaction_id) {
    return "Apple transaction id mismatch";
  }
  if (input.claims.productId !== input.request.product_id) {
    return "Apple product id mismatch";
  }
  if (input.claims.bundleId !== input.expectedBundleID) {
    return "Apple bundle id mismatch";
  }
  if (input.claims.environment !== input.expectedEnvironment) {
    return "Apple environment mismatch";
  }
  if (input.claims.appAccountToken && input.claims.appAccountToken !== input.expectedUserID) {
    return "Apple app account token mismatch";
  }
  if (input.claims.revocationDate) {
    return "Apple transaction is revoked or refunded";
  }
  if (!input.claims.purchaseDate) {
    return "Apple purchase date missing";
  }
  return null;
}

async function fetchAppleSignedTransaction(
  config: ReturnType<typeof readConfig>,
  transactionID: string,
): Promise<string> {
  const token = await createAppStoreServerJWT(config);
  const host = config.appleEnvironment === "Production"
    ? "https://api.storekit.itunes.apple.com"
    : "https://api.storekit-sandbox.itunes.apple.com";
  const response = await fetch(`${host}/inApps/v1/transactions/${encodeURIComponent(transactionID)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!response.ok) {
    throw new Error("Apple transaction verification failed");
  }

  const payload = await response.json();
  if (!payload.signedTransactionInfo || typeof payload.signedTransactionInfo !== "string") {
    throw new Error("Apple transaction response missing signed transaction info");
  }

  return payload.signedTransactionInfo;
}

async function createAppStoreServerJWT(config: ReturnType<typeof readConfig>): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = {
    alg: "ES256",
    kid: config.appleKeyID,
    typ: "JWT",
  };
  const payload = {
    iss: config.appleIssuerID,
    iat: now,
    exp: now + 600,
    aud: "appstoreconnect-v1",
    bid: config.appleBundleID,
  };
  const signingInput = `${base64URLJSON(header)}.${base64URLJSON(payload)}`;
  const privateKey = await importPrivateKey(config.applePrivateKey);
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(signingInput),
  ));

  return `${signingInput}.${base64URLBytes(normalizeEs256Signature(signature))}`;
}

async function importPrivateKey(pemValue: string): Promise<CryptoKey> {
  const pem = pemValue.replace(/\\n/g, "\n");
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function decodeAppleTransactionClaims(signedTransaction: string): AppleTransactionClaims {
  const parts = signedTransaction.split(".");
  if (parts.length !== 3) {
    throw new Error("Apple signed transaction is not a JWS");
  }
  return JSON.parse(new TextDecoder().decode(base64URLDecode(parts[1])));
}

function dateFromAppleMilliseconds(value: number | undefined): Date | null {
  if (!value) {
    return null;
  }
  return new Date(value);
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeEs256Signature(signature: Uint8Array): Uint8Array {
  if (signature.length === 64) {
    return signature;
  }
  if (signature[0] !== 0x30) {
    throw new Error("Unexpected ES256 signature format");
  }

  let offset = 2;
  if (signature[offset] !== 0x02) {
    throw new Error("Unexpected ES256 R component");
  }
  const rLength = signature[offset + 1];
  const r = signature.slice(offset + 2, offset + 2 + rLength);
  offset = offset + 2 + rLength;

  if (signature[offset] !== 0x02) {
    throw new Error("Unexpected ES256 S component");
  }
  const sLength = signature[offset + 1];
  const s = signature.slice(offset + 2, offset + 2 + sLength);

  const normalized = new Uint8Array(64);
  normalized.set(trimOrPadInteger(r), 0);
  normalized.set(trimOrPadInteger(s), 32);
  return normalized;
}

function trimOrPadInteger(value: Uint8Array): Uint8Array {
  const trimmed = value.length > 32 ? value.slice(value.length - 32) : value;
  const output = new Uint8Array(32);
  output.set(trimmed, 32 - trimmed.length);
  return output;
}

function base64URLJSON(value: unknown): string {
  return base64URLBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64URLBytes(value: Uint8Array): string {
  let binary = "";
  value.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64URLDecode(value: string): Uint8Array {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64.padEnd(base64.length + ((4 - base64.length % 4) % 4), "=");
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`${name} is not configured`);
  }
  return value;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
