import type { APIRoute } from "astro";
import { SESSION_COOKIE } from "../../../lib/auth";

export const prerender = false;

const clear: APIRoute = async ({ request, cookies }) => {
  cookies.delete(SESSION_COOKIE, { path: "/" });
  const origin = new URL(request.url).origin;
  return new Response(null, { status: 302, headers: { Location: `${origin}/` } });
};

export const GET = clear;
export const POST = clear;
