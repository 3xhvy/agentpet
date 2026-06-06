// AgentPet pet mirror: serves the OpenPets library from our own R2 so the app
// is independent of any upstream CDN (Petdex's CDN died; OpenPets is the new
// source). We mirror every pet's spritesheet into R2 once, generate a tiny
// pet.json per pet, and build the app manifest from a stored catalog snapshot.
//
//   GET /manifest               -> app manifest, asset URLs pointing at /a/...
//   GET /a/<key>                -> a mirrored asset from R2 (sprite / pet.json)
//   GET /mirror/run?key=&cursor=-> mirror one batch into R2 (admin, resumable)
//   GET /mirror/status          -> mirror progress
//
// After a full mirror, /manifest and /a/ read only from R2 (zero upstream calls).

const CATALOG_INDEX = "https://openpets.dev/pets/catalog.v3.json";
const OPENPETS = "https://openpets.dev";
// R2 bucket's public custom domain. Assets are served from here (CF-cached,
// egress-free, off the Worker request quota) instead of through this Worker.
const R2_PUBLIC = "https://pets.thenightwatcher.online";
const ASSET_MAXAGE = 60 * 60 * 24 * 365; // 1 year
const IMMUTABLE = `public, max-age=${60 * 60 * 24 * 365}, immutable`;
const MIRROR_BATCH = 25;        // pets per /mirror/run (each = 1 upstream fetch)
const MIRROR_CONCURRENCY = 6;
const CORS = { "access-control-allow-origin": "*" };

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET" && request.method !== "HEAD")
      return new Response("Method not allowed", { status: 405 });
    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/manifest" || path === "/api/manifest") return manifest(env);
    if (path === "/mirror/status") return mirrorStatus(env);
    if (path === "/mirror/run") {
      if (env.MIRROR_KEY && url.searchParams.get("key") !== env.MIRROR_KEY)
        return json({ error: "forbidden" }, 403);
      return json(await mirrorBatch(url, env));
    }
    if (path.startsWith("/a/")) return asset(decodeURIComponent(path.slice(3)), env, ctx);
    if (path === "/") return new Response("AgentPet pet mirror.", { status: 200 });
    return new Response("Not found", { status: 404 });
  },
};

// ---- manifest (built from the R2 catalog snapshot, app-compatible shape) ----
// Asset URLs point at the R2 public domain so the app never touches this Worker
// for assets. A static copy is also written to R2 (key "manifest.json") so even
// the manifest is served off the Worker quota.
function manifestPets(catPets) {
  return catPets.map((p) => ({
    slug: p.folder,
    displayName: p.displayName || p.folder,
    spritesheetUrl: `${R2_PUBLIC}/pets/${p.folder}/spritesheet.webp`,
    petJsonUrl: `${R2_PUBLIC}/pets/${p.folder}/pet.json`,
  }));
}

async function manifest(env) {
  const snap = await env.CACHE.get("_catalog.json");
  if (!snap) return json({ error: "not mirrored yet", pets: [] }, 200, CORS);
  let cat;
  try { cat = await snap.json(); } catch { return json({ pets: [] }, 200, CORS); }
  return json({ pets: manifestPets(cat.pets || []) }, 200, { "cache-control": "public, max-age=300", ...CORS });
}

// ---- asset serving (R2 only after mirror; sprite falls back to upstream) ----
async function asset(key, env, ctx) {
  if (!key || key.includes("..") || key.startsWith("_")) return new Response("Bad key", { status: 400 });

  const hit = await env.CACHE.get(key);
  if (hit) {
    const h = new Headers(CORS);
    hit.writeHttpMetadata(h);
    h.set("cache-control", `public, max-age=${ASSET_MAXAGE}, immutable`);
    h.set("x-cache", "HIT");
    return new Response(hit.body, { headers: h });
  }

  // pet.json is generated only during mirror; no upstream to fall back to.
  if (key.endsWith("/pet.json")) return new Response("Not mirrored", { status: 404 });

  // Sprite fallback: fetch from OpenPets once and cache (covers un-mirrored pets).
  let resp;
  try { resp = await fetch(`${OPENPETS}/${key}`); }
  catch { return new Response("upstream error", { status: 502 }); }
  if (!resp || !resp.ok) return new Response("not found", { status: resp ? resp.status : 502 });
  const ct = resp.headers.get("content-type") || "image/webp";
  const buf = await resp.arrayBuffer();
  ctx.waitUntil(env.CACHE.put(key, buf, { httpMetadata: { contentType: ct, cacheControl: IMMUTABLE } }));
  return new Response(buf, {
    headers: { "content-type": ct, "cache-control": `public, max-age=${ASSET_MAXAGE}, immutable`, "x-cache": "MISS", ...CORS },
  });
}

// ---- mirroring ----

// Fetches every catalog page and returns the flat pet list (folder + metadata).
async function buildCatalog() {
  const idx = await (await fetch(CATALOG_INDEX)).json();
  const pages = idx.pages || [];
  const pets = [];
  for (const pageUrl of pages) {
    const page = await (await fetch(pageUrl)).json();
    for (const p of page.pets || []) {
      const m = /\/pets\/([^/]+)\/spritesheet\./.exec(p.spritesheet || "");
      if (!m) continue;
      pets.push({
        folder: m[1],
        id: p.id,
        displayName: p.displayName || p.id,
        description: p.description || "",
        category: p.category || "",
        spritesheet: p.spritesheet,
      });
    }
  }
  return { generatedAt: idx.generatedAt, total: pets.length, pets };
}

async function mirrorBatch(url, env) {
  const cursor = parseInt(url.searchParams.get("cursor") || "0", 10) || 0;
  const batch = parseInt(url.searchParams.get("batch") || String(MIRROR_BATCH), 10) || MIRROR_BATCH;

  // On the first batch, snapshot the catalog into R2 so the manifest and pet.json
  // generation are independent of OpenPets afterwards.
  let cat;
  if (cursor === 0) {
    cat = await buildCatalog();
    await env.CACHE.put("_catalog.json", JSON.stringify(cat), { httpMetadata: { contentType: "application/json" } });
  } else {
    const snap = await env.CACHE.get("_catalog.json");
    if (!snap) return { ok: false, reason: "no catalog snapshot; run cursor=0 first" };
    cat = await snap.json();
  }

  const slice = cat.pets.slice(cursor, cursor + batch);
  let mirrored = 0, failed = 0, i = 0;
  async function run() {
    while (i < slice.length) {
      const p = slice[i++];
      const dir = `pets/${p.folder}`;
      try {
        // pet.json (generated) — matches the format the app reads.
        await env.CACHE.put(`${dir}/pet.json`, JSON.stringify({
          id: p.id, displayName: p.displayName, description: p.description,
          spritesheetPath: "spritesheet.webp", category: p.category,
        }), { httpMetadata: { contentType: "application/json", cacheControl: IMMUTABLE } });
        // spritesheet (streamed straight from OpenPets into R2).
        const r = await fetch(p.spritesheet);
        if (!r.ok) { failed++; continue; }
        await env.CACHE.put(`${dir}/spritesheet.webp`, r.body,
          { httpMetadata: { contentType: r.headers.get("content-type") || "image/webp", cacheControl: IMMUTABLE } });
        mirrored++;
      } catch { failed++; }
    }
  }
  await Promise.all(Array.from({ length: MIRROR_CONCURRENCY }, run));

  const next = cursor + batch;
  const done = next >= cat.pets.length;
  if (done) {
    // Publish the static manifest the app reads (served from the R2 domain).
    await env.CACHE.put("manifest.json", JSON.stringify({ pets: manifestPets(cat.pets) }),
      { httpMetadata: { contentType: "application/json", cacheControl: "public, max-age=300" } });
  }
  await env.CACHE.put("_mirror.json", JSON.stringify({
    cursor: Math.min(next, cat.pets.length), total: cat.pets.length, done, lastMirrored: mirrored, lastFailed: failed,
  }), { httpMetadata: { contentType: "application/json" } });
  return { ok: true, cursor: Math.min(next, cat.pets.length), total: cat.pets.length, done, mirrored, failed };
}

async function mirrorStatus(env) {
  const s = await env.CACHE.get("_mirror.json");
  const doc = s ? await s.json().catch(() => null) : null;
  return json({ progress: doc || { cursor: 0, total: 0, done: false } }, 200, CORS);
}

const json = (data, status = 200, extra = {}) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...extra },
  });
