// Injeta as disciplinas da base de dados na página inicial e no llms.txt.
// Restantes rotas (páginas legais) passam sem alterações.
import { applyToIndex, applyToLlms, fetchSubjects } from './_lib/subjects.js';

const TARGETS = {
  '/': { type: 'text/html', apply: applyToIndex },
  '/index.html': { type: 'text/html', apply: applyToIndex },
  '/llms.txt': { type: 'text/plain', apply: applyToLlms },
};

export async function onRequest({ request, next }) {
  const target = TARGETS[new URL(request.url).pathname];
  const response = await next();
  if (!target || request.method !== 'GET' || response.status !== 200
    || !(response.headers.get('content-type') ?? '').startsWith(target.type)) return response;

  const subjects = await fetchSubjects();
  if (!subjects) return response; // sem dados: serve a versão estática

  const body = target.apply(await response.text(), subjects);
  const headers = new Headers(response.headers);
  headers.delete('content-length');
  headers.delete('etag');
  return new Response(body, { status: 200, headers });
}
