const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { handler } = require('../index.js');

function request(path) {
  return new Promise((resolve, reject) => {
    const srv = http.createServer(handler);
    srv.listen(0, () => {
      const { port } = srv.address();
      http.get(`http://127.0.0.1:${port}${path}`, (res) => {
        let body = '';
        res.on('data', (chunk) => { body += chunk; });
        res.on('end', () => {
          srv.close();
          resolve({ status: res.statusCode, headers: res.headers, body });
        });
      }).on('error', reject);
    });
  });
}

test('GET /healthz returns ok', async () => {
  const res = await request('/healthz');
  assert.equal(res.status, 200);
  assert.equal(JSON.parse(res.body).status, 'ok');
});

test('GET / returns the landing page', async () => {
  const res = await request('/');
  assert.equal(res.status, 200);
  assert.match(res.headers['content-type'], /text\/html/);
  assert.match(res.body, /Hello from Forge Stack/);
});

test('unknown routes return 404', async () => {
  const res = await request('/nope');
  assert.equal(res.status, 404);
});
