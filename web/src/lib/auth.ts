// Stateless signed-cookie sessions (HMAC-SHA256). No DB needed for auth itself.
// The cookie holds the GitHub profile we need plus an expiry; the signature
// prevents tampering. Secret comes from SESSION_SECRET.

const enc = new TextEncoder();
const dec = new TextDecoder();

export interface SessionUser {
  id: number;
  login: string;
  name: string;
  avatar: string;
  exp?: number;
}

export const SESSION_COOKIE = "ap_session";

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unb64url(str: string): Uint8Array {
  let s = str.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function signSession(payload: SessionUser, secret: string): Promise<string> {
  const body = b64url(enc.encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(secret), enc.encode(body)));
  return `${body}.${b64url(sig)}`;
}

export async function verifySession(token: string, secret: string): Promise<SessionUser | null> {
  if (!secret || !token) return null;
  const [body, sig] = token.split(".");
  if (!body || !sig) return null;
  let ok = false;
  try {
    ok = await crypto.subtle.verify("HMAC", await hmacKey(secret), unb64url(sig), enc.encode(body));
  } catch {
    return null;
  }
  if (!ok) return null;
  try {
    const obj = JSON.parse(dec.decode(unb64url(body))) as SessionUser;
    if (obj.exp && Date.now() > obj.exp) return null;
    return obj;
  } catch {
    return null;
  }
}
