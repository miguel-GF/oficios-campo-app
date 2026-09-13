export default {
  async fetch(request, env) {
    const maxBodyBytes = 64 * 1024;
    const source = new URL(request.url);
    const allowedPaths = new Set([
      '/health',
      '/v1/auth/exchange',
      '/v1/auth/refresh',
      '/v1/auth/logout',
      '/v1/account',
      '/v1/quotes/interpret',
      '/v1/billing/plans',
      '/v1/billing/checkout',
      '/v1/billing/portal',
      '/v1/billing/stripe/webhook',
    ]);
    if (!allowedPaths.has(source.pathname)) {
      return new Response('Not found', { status: 404 });
    }
    if (!env.ORIGIN_URL || !env.ORIGIN_VERIFY_SECRET) {
      return new Response(JSON.stringify({ detail: 'PROXY_NOT_CONFIGURED' }), {
        status: 503,
        headers: {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      });
    }
    if (
      source.pathname === '/v1/quotes/interpret' &&
      (!env.AI_RATE_LIMITER || !env.AI_IP_RATE_LIMITER)
    ) {
      return new Response(JSON.stringify({ detail: 'RATE_LIMIT_NOT_CONFIGURED' }), {
        status: 503,
        headers: {
          'content-type': 'application/json',
          'cache-control': 'no-store',
        },
      });
    }
    if (source.pathname === '/v1/quotes/interpret') {
      const installation = request.headers.get('X-Installation-ID') || 'anonymous';
      const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
      const { success } = await env.AI_RATE_LIMITER.limit({
        key: `${installation}:${ip}`,
      });
      if (!success) {
        return new Response(JSON.stringify({ detail: 'RATE_LIMITED' }), {
          status: 429,
          headers: {
            'content-type': 'application/json',
            'cache-control': 'no-store',
          },
        });
      }
    }
    if (source.pathname === '/v1/quotes/interpret') {
      const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
      const { success } = await env.AI_IP_RATE_LIMITER.limit({ key: ip });
      if (!success) {
        return new Response(JSON.stringify({ detail: 'RATE_LIMITED' }), {
          status: 429,
          headers: {
            'content-type': 'application/json',
            'cache-control': 'no-store',
          },
        });
      }
    }
    let body;
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      // Do not rely only on Content-Length: chunked requests can omit it.
      body = await request.arrayBuffer();
      if (body.byteLength > maxBodyBytes) {
        return new Response(JSON.stringify({ detail: 'REQUEST_TOO_LARGE' }), {
          status: 413,
          headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
        });
      }
    }
    const target = new URL(source.pathname + source.search, env.ORIGIN_URL);
    const headers = new Headers(request.headers);
    headers.set('X-Origin-Verify', env.ORIGIN_VERIFY_SECRET);
    headers.delete('cookie');
    if (body !== undefined) headers.delete('content-length');
    const upstream = await fetch(target, {
      method: request.method,
      headers,
      body,
      redirect: 'manual',
    });
    const response = new Response(upstream.body, upstream);
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.delete('Set-Cookie');
    return response;
  },
};
