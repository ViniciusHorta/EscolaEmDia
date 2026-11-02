const origins = new Set([
  'http://localhost:5173', 'http://127.0.0.1:5173',
  'http://localhost:8080', 'http://127.0.0.1:8080',
  'http://localhost:3001', 'http://127.0.0.1:3001'
]);

// Exact local origins allow the Flutter dev server to use the same JSON API.
export function localCors(req, res) {
  const origin = req.headers.origin;
  if ((origin && !origins.has(origin)) || (!origin && req.headers['sec-fetch-site'] === 'cross-site')) {
    res.writeHead(403, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'Origem não autorizada.' }));
    return false;
  }
  if (origin) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    res.setHeader('Access-Control-Max-Age', '600');
  }
  if (req.method === 'OPTIONS') {
    res.writeHead(204); res.end(); return false;
  }
  return true;
}
