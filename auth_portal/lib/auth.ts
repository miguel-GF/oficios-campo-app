import { createNeonAuth } from "@neondatabase/auth/next/server";

const baseUrl = process.env.NEON_AUTH_BASE_URL;
const secret = process.env.NEON_AUTH_COOKIE_SECRET;

if (!baseUrl || !secret || secret.length < 32) {
  throw new Error("Neon Auth portal is not configured");
}

export const auth = createNeonAuth({
  baseUrl,
  cookies: { secret },
});
