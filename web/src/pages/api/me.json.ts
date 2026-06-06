import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { verifySession, SESSION_COOKIE } from "../../lib/auth";

export const prerender = false;

const v = (n: string): string => {
  try { const e = (env as any)?.[n]; if (e) return String(e); } catch {}
  return (import.meta as any).env?.[n] ?? "";
};

// Current signed-in user (or null). The nav fetches this client-side so it works
// on the statically prerendered pages too.
export const GET: APIRoute = async ({ cookies }) => {
  const token = cookies.get(SESSION_COOKIE)?.value || "";
  const user = token ? await verifySession(token, v("SESSION_SECRET")) : null;
  const safe = user ? { id: user.id, login: user.login, name: user.name, avatar: user.avatar } : null;
  return new Response(JSON.stringify({ user: safe }), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};
