import { renderLegalPage } from './_lib/legal.js';

export const onRequest = ({ request }) =>
  request.method === 'GET' || request.method === 'HEAD'
    ? renderLegalPage('privacy')
    : new Response(null, { status: 405, headers: { allow: 'GET, HEAD' } });
