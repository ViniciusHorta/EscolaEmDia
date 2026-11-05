type CorsOptions = {
  methods: string;
  parentUnlock?: boolean;
  retryAfter?: boolean;
};

// Exact browser origins only: never allow wildcards, paths or opaque origins.
function readAllowedOrigins(): Set<string> | null {
  const value = Deno.env.get("ALLOWED_ORIGINS");
  if (!value?.trim()) return null;
  const origins = value.split(",").map((origin) => origin.trim());
  try {
    for (const origin of origins) {
      const url = new URL(origin);
      if (!['http:', 'https:'].includes(url.protocol) || url.origin !== origin) {
        return null;
      }
    }
  } catch {
    return null;
  }
  return new Set(origins);
}

export function createCors(req: Request, options: CorsOptions) {
  // Read on every request so all functions use the current project configuration.
  const origins = readAllowedOrigins();
  const origin = req.headers.get("origin");
  const configured = origins !== null;
  // Native clients may omit Origin; authentication is still required by each route.
  const allowed = configured && (origin === null || origins.has(origin));
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type"
      + (options.parentUnlock ? ", x-parent-unlock" : ""),
    "Access-Control-Allow-Methods": options.methods,
    "Access-Control-Expose-Headers": "X-Request-Id"
      + (options.retryAfter ? ", Retry-After" : ""),
    "Vary": "Origin",
  };
  if (allowed && origin !== null) headers["Access-Control-Allow-Origin"] = origin;
  return {
    configured,
    allowed,
    headers,
    preflightResponse: allowed && req.method === "OPTIONS"
      ? new Response(null, { status: 204, headers })
      : null,
  };
}
