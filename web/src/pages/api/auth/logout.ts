import type { APIRoute } from "astro";
import { SESSION_COOKIE } from "../../../lib/auth";

export const prerender = false;

const clear: APIRoute = async ({ request, cookies }) => {
  cookies.delete(SESSION_COOKIE, { path: "/" });
  const origin = new URL(request.url).origin;
  return Response.redirect(`${origin}/`, 302);
};

export const GET = clear;
export const POST = clear;
