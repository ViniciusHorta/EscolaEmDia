import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { validateExercise } from './schema.mjs';
import { localCors } from './cors.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const data = path.join(root, 'data/exercises');
const dist = path.resolve(root, process.env.WEB_DIRECTORY || 'dist');
await mkdir(data, { recursive: true });
const send = (res, status, value) => {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(value));
};
const mime = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.ico': 'image/x-icon', '.json': 'application/json', '.wasm': 'application/wasm', '.woff2': 'font/woff2', '.ttf': 'font/ttf' };
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname.startsWith('/api/') && !localCors(req, res)) return;
    if (req.method === 'GET' && url.pathname === '/api/exercises') {
      const names = (await readdir(data)).filter(name => name.endsWith('.json')).sort();
      const exercises = await Promise.all(names.map(async name => validateExercise(JSON.parse(await readFile(path.join(data, name), 'utf8')))));
      return send(res, 200, exercises);
    }
    if (req.method === 'POST' && url.pathname === '/api/exercises') {
      if (!req.headers['content-type']?.startsWith('application/json')) return send(res, 415, { error: 'Envia application/json.' });
      let body = '', size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 262144) return send(res, 413, { error: 'O JSON excede o limite de 256 KB.' });
        body += chunk;
      }
      let exercise;
      try { exercise = validateExercise(JSON.parse(body)); }
      catch (error) { return send(res, 400, { error: error.message }); }
      try {
        // Exclusive creation prevents silently overwriting an existing exercise.
        await writeFile(path.join(data, `${exercise.id}.json`), JSON.stringify(exercise, null, 2) + '\n', { flag: 'wx' });
      } catch (error) {
        if (error.code === 'EEXIST') return send(res, 409, { error: 'Este id já existe. Escolhe outro id para guardar um novo exercício.' });
        throw error;
      }
      return send(res, 201, exercise);
    }
    if (url.pathname.startsWith('/api/')) return send(res, 404, { error: 'Endereço não encontrado.' });
    if (req.method !== 'GET') return send(res, 405, { error: 'Método não permitido.' });
    const relative = decodeURIComponent(url.pathname).replace(/^\/+/, '');
    const target = path.resolve(dist, relative || 'index.html');
    if (!target.startsWith(dist + path.sep)) return send(res, 403, { error: 'Caminho inválido.' });
    try {
      const file = await readFile(target);
      res.writeHead(200, { 'Content-Type': mime[path.extname(target)] || 'application/octet-stream' });
      res.end(file);
    } catch (error) {
      if (error.code !== 'ENOENT' && error.code !== 'EISDIR') throw error;
      return send(res, 404, { error: 'Página indisponível. Para desenvolvimento, executa npm run dev e abre http://localhost:5173. Para produção, executa npm run build antes de npm start.' });
    }
  } catch (error) {
    console.error(error);
    if (!res.headersSent) send(res, 500, { error: 'Não foi possível aceder aos ficheiros. Verifica o terminal do servidor.' });
    else res.end();
  }
});
server.listen(3001, '127.0.0.1', () => console.log('Servidor local: http://localhost:3001'));
server.on('error', error => { console.error(error.message); process.exitCode = 1; });
