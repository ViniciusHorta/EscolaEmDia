import test from 'node:test';
import assert from 'node:assert/strict';
import { localCors } from './cors.mjs';

function request(origin, method = 'GET', site) {
  const response = { headers: {}, setHeader(key, value) { this.headers[key] = value; },
    writeHead(status) { this.status = status; }, end(body) { this.body = body; } };
  const proceed = localCors({ method, headers: { origin, 'sec-fetch-site': site } }, response);
  return { proceed, response };
}
test('Flutter local pode ler e criar exercícios, incluindo preflight', () => {
  for (const method of ['GET', 'POST']) {
    const { proceed, response } = request('http://localhost:8080', method, 'cross-site');
    assert.equal(proceed, true);
    assert.equal(response.headers['Access-Control-Allow-Origin'], 'http://localhost:8080');
  }
  const preflight = request('http://127.0.0.1:8080', 'OPTIONS');
  assert.equal(preflight.proceed, false);
  assert.equal(preflight.response.status, 204);
});
test('origens externas continuam bloqueadas e clientes nativos podem usar a API', () => {
  assert.equal(request('https://example.com', 'POST').response.status, 403);
  assert.equal(request(undefined, 'POST', 'cross-site').response.status, 403);
  assert.equal(request(undefined, 'POST').proceed, true);
  assert.equal(request('http://localhost:5173', 'POST').proceed, true);
});
