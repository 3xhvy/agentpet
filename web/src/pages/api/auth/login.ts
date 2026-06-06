import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";

export const prerender = false;

const v = (n: string): string => {
  try { const e = (env as any)?.[n]; if (e) return String(e); } catch {}
  return (import.meta as any).env?.[n] ?? "";
};

function randomState(): string {
  const a = new Uint8Array(16);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, "0")).join("");
}

// Kick off GitHub OAuth: stash a CSRF state + return-to, then redirect to GitHub.
export const GET: APIRoute = async ({ request, cookies }) => {
  const clientId = v("GITHUB_CLIENT_ID");
  if (!clientId) return new Response("GitHub login is not configured yet.", { status: 500 });

  const origin = new URL(request.url).origin;
  const secure = origin.startsWith("https");
  const state = randomState();
  const returnTo = new URL(request.url).searchParams.get("returnTo") || "/";

  cookies.set("ap_oauth_state", state, { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 600 });
  cookies.set("ap_oauth_return", returnTo.startsWith("/") ? returnTo : "/", { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: 600 });

  const u = new URL("https://github.com/login/oauth/authorize");
  u.searchParams.set("client_id", clientId);
  u.searchParams.set("redirect_uri", `${origin}/api/auth/callback`);
  u.searchParams.set("scope", "read:user");
  u.searchParams.set("state", state);
  return new Response(null, { status: 302, headers: { Location: u.toString() } });
};
