import { auth } from "../../lib/auth";

const challengePattern = /^[A-Za-z0-9_-]{43,128}$/;
const statePattern = /^[A-Za-z0-9_-]{32,256}$/;
const redirectUri = "jale://auth/callback";

export async function GET(request: Request) {
  const source = new URL(request.url);
  const challenge = source.searchParams.get("code_challenge") ?? "";
  const state = source.searchParams.get("state") ?? "";
  const suppliedRedirect = source.searchParams.get("redirect_uri") ?? "";
  if (
    source.searchParams.get("code_challenge_method") !== "S256" ||
    suppliedRedirect !== redirectUri ||
    !challengePattern.test(challenge) ||
    !statePattern.test(state)
  ) {
    return new Response("Solicitud inválida", { status: 400 });
  }

  const { data: session } = await auth.getSession();
  if (!session?.user) {
    const returnTo = source.pathname + source.search;
    const login = new URL("/auth/sign-in", source);
    login.searchParams.set("returnTo", returnTo);
    return Response.redirect(login, 302);
  }

  const backend = process.env.JALE_API_INTERNAL_URL;
  const bridgeSecret = process.env.AUTH_BRIDGE_SECRET;
  if (!backend || !bridgeSecret || bridgeSecret.length < 32) {
    return new Response("Portal no configurado", { status: 503 });
  }
  const exchange = await fetch(
    new URL("/internal/auth/codes", backend),
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-auth-bridge": bridgeSecret,
      },
      body: JSON.stringify({
        user_id: session.user.id,
        email: session.user.email ?? "",
        code_challenge: challenge,
        redirect_uri: redirectUri,
      }),
      cache: "no-store",
    },
  );
  if (!exchange.ok) return new Response("No pudimos volver a Jale", { status: 502 });
  const body = (await exchange.json()) as { code: string };
  const callback = new URL(redirectUri);
  callback.searchParams.set("code", body.code);
  callback.searchParams.set("state", state);
  return Response.redirect(callback, 302);
}
