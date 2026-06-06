import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";

export const prerender = false;

// Returns a random pet (slug, name, description + the same derived demo stats as
// the home page) so the "Shuffle" button can re-roll without a reload. The source
// origin stays server-side only.
function fnv(s: string): number { let x = 2166136261; for (let i = 0; i < s.length; i++) { x ^= s.charCodeAt(i); x = Math.imul(x, 16777619) >>> 0; } return x >>> 0; }
const stat = (slug: string, k: string, mod: number, base: number) => (fnv(slug + k) % mod) + base;

export const GET: APIRoute = async () => {
  const base = (env as any).PETS_ORIGIN || import.meta.env.PETS_ORIGIN || "";
  if (!base) return new Response(JSON.stringify({ error: "not configured" }), { status: 500 });
  try {
    const m: any = await (await fetch(`${base}/manifest.json`)).json();
    const pets = m.pets ?? [];
    if (!pets.length) return new Response(JSON.stringify({ error: "empty" }), { status: 404 });
    const p = pets[Math.floor(Math.random() * pets.length)];
    let desc = "";
    try { const j: any = await (await fetch(`${base}/pets/${p.slug}/pet.json`)).json(); desc = (j.description ?? "").toString(); } catch {}
    return new Response(JSON.stringify({
      slug: p.slug,
      name: p.displayName ?? p.slug,
      desc,
      likes: stat(p.slug, "l", 880, 24),
      downloads: stat(p.slug, "d", 7400, 130),
      usage: stat(p.slug, "u", 2400, 12),
    }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
  } catch {
    return new Response(JSON.stringify({ error: "upstream" }), { status: 502 });
  }
};
