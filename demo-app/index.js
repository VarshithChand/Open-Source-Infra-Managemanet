const http = require('node:http');
const os = require('node:os');

const START_TIME = Date.now();

const STAGES = [
  { name: 'Forgejo', role: 'git push received' },
  { name: 'Woodpecker', role: 'test + build' },
  { name: 'SonarQube', role: 'quality gate' },
  { name: 'Harbor', role: 'registry + CVE scan' },
  { name: 'Portainer', role: 'deploy' },
];

const TECH = ['Node.js', 'Docker', 'Traefik', 'Forgejo', 'Woodpecker CI', 'SonarQube', 'Harbor', 'Portainer', 'Prometheus', 'Grafana', 'Loki'];

function pipelineSvg() {
  const boxW = 148, boxH = 56, gap = 46, y = 30;
  const n = STAGES.length;
  const totalW = n * boxW + (n - 1) * gap;
  const svgW = totalW + 20;
  const svgH = y + boxH + 20;

  let boxes = '';
  let arrows = '';
  STAGES.forEach((stage, i) => {
    const x = 10 + i * (boxW + gap);
    const isGate = stage.name === 'SonarQube' || stage.name === 'Harbor';
    boxes += `
      <rect x="${x}" y="${y}" width="${boxW}" height="${boxH}" rx="9"
        fill="#111a2c" stroke="${isGate ? '#E8A33D' : '#3a4a72'}" stroke-width="${isGate ? 2 : 1.4}"/>
      <text x="${x + boxW / 2}" y="${y + 24}" text-anchor="middle" fill="#E7ECF6"
        font-family="JetBrains Mono, monospace" font-size="13" font-weight="700">${stage.name}</text>
      <text x="${x + boxW / 2}" y="${y + 41}" text-anchor="middle" fill="#8D98B3"
        font-family="JetBrains Mono, monospace" font-size="9.5">${stage.role}</text>`;
    if (i < n - 1) {
      const x1 = x + boxW, x2 = x + boxW + gap;
      const midY = y + boxH / 2;
      arrows += `<line x1="${x1}" y1="${midY}" x2="${x2 - 8}" y2="${midY}" stroke="#4FD1AE" stroke-width="1.6" marker-end="url(#arrow)"/>`;
    }
  });

  return `<svg viewBox="0 0 ${svgW} ${svgH}" role="img" aria-label="Pipeline: Forgejo receives the push, Woodpecker tests and builds, SonarQube and Harbor gate on quality and vulnerabilities, Portainer deploys." style="width:100%;height:auto;display:block;">
    <defs>
      <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
        <path d="M0,0 L10,5 L0,10 z" fill="#4FD1AE"/>
      </marker>
    </defs>
    ${arrows}
    ${boxes}
  </svg>`;
}

function renderPage() {
  const hostname = os.hostname();
  const nowIso = new Date().toISOString();

  const techChips = TECH.map((t) => `<span class="chip">${t}</span>`).join('');

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Forge Stack Demo App</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@500;700;800&family=IBM+Plex+Sans:wght@400;500;600&display=swap">
<style>
  :root{
    --bg:#0A101C; --surface:#111a2c; --surface-2:#0d1424; --border:#263252;
    --text:#E7ECF6; --text-dim:#8D98B3;
    --accent:#E8A33D; --accent-ink:#F6C97A; --accent-2:#4FD1AE;
  }
  *{ box-sizing:border-box; }
  body{
    margin:0; background:var(--bg); color:var(--text);
    font-family:'IBM Plex Sans', -apple-system, sans-serif;
    padding:32px 20px 60px;
  }
  main{ max-width:820px; margin:0 auto; }
  .eyebrow{
    font-family:'JetBrains Mono', monospace; font-size:11px; letter-spacing:.12em;
    color:var(--accent-2); text-transform:uppercase; display:flex; align-items:center; gap:8px;
    margin-bottom:20px;
  }
  .dot{
    width:8px; height:8px; border-radius:50%; background:var(--accent-2);
    box-shadow:0 0 0 3px color-mix(in srgb, var(--accent-2) 25%, transparent);
    animation:pulse 2s ease-in-out infinite;
  }
  @keyframes pulse{ 50%{ opacity:.4; } }
  @media (prefers-reduced-motion: reduce){ .dot{ animation:none; } }
  h1{
    font-family:'JetBrains Mono', monospace; font-weight:800; font-size:clamp(28px,5vw,40px);
    margin:0 0 14px; letter-spacing:-.01em; text-wrap:balance;
  }
  p.lede{ margin:0 0 32px; color:var(--text-dim); font-size:15.5px; line-height:1.65; max-width:62ch; }
  code{ font-family:'JetBrains Mono', monospace; font-size:.92em; color:var(--accent-ink); }

  section{ margin-bottom:28px; }
  .card{
    background:var(--surface); border:1px solid var(--border); border-radius:12px; padding:22px;
  }
  .card h2{
    font-family:'JetBrains Mono', monospace; font-size:11px; letter-spacing:.1em;
    color:var(--text-dim); text-transform:uppercase; margin:0 0 16px;
  }
  .pipeline-wrap{ overflow-x:auto; }
  .pipeline-caption{
    margin-top:12px; font-size:12.5px; color:var(--text-dim);
  }
  .pipeline-caption b{ color:var(--accent-ink); font-weight:600; }

  .stats{ display:grid; grid-template-columns:repeat(auto-fit, minmax(150px,1fr)); gap:14px; }
  .stat{ background:var(--surface-2); border:1px solid var(--border); border-radius:10px; padding:14px 16px; }
  .stat .label{
    font-family:'JetBrains Mono', monospace; font-size:10px; letter-spacing:.06em;
    color:var(--text-dim); text-transform:uppercase; margin-bottom:6px;
  }
  .stat .value{
    font-family:'JetBrains Mono', monospace; font-size:15px; font-weight:700;
    font-variant-numeric:tabular-nums; word-break:break-all;
  }
  .stat .value.accent{ color:var(--accent-2); }

  .chips{ display:flex; flex-wrap:wrap; gap:8px; }
  .chip{
    font-family:'JetBrains Mono', monospace; font-size:12px;
    padding:6px 12px; border:1px solid var(--border); border-radius:20px;
    background:var(--surface-2); color:var(--text);
  }

  ul.proves{ margin:0; padding-left:20px; color:var(--text-dim); font-size:14px; line-height:1.9; }
  ul.proves b{ color:var(--text); font-weight:600; }

  footer{
    margin-top:36px; padding-top:20px; border-top:1px solid var(--border);
    font-size:12px; color:var(--text-dim); font-family:'JetBrains Mono', monospace;
    display:flex; justify-content:space-between; flex-wrap:wrap; gap:8px;
  }
  footer a{ color:var(--accent-2); text-decoration:none; }
</style>
</head>
<body>
  <main>
    <div class="eyebrow"><span class="dot"></span>Live &mdash; served by Forge Stack</div>
    <h1>Hello from Forge Stack</h1>
    <p class="lede">This page exists because a <code>git push</code> flowed through a self-hosted CI/CD pipeline end to end: tested, quality-gated, built, scanned for vulnerabilities, and deployed &mdash; no manual step in between.</p>

    <section class="card">
      <h2>Pipeline</h2>
      <div class="pipeline-wrap">${pipelineSvg()}</div>
      <p class="pipeline-caption"><b>SonarQube</b> and <b>Harbor</b> (amber outline) are the two gates &mdash; a failing quality check or a critical CVE stops the pipeline before this container is ever built.</p>
    </section>

    <section class="card">
      <h2>Live status</h2>
      <div class="stats">
        <div class="stat"><div class="label">Status</div><div class="value accent">&#9679; running</div></div>
        <div class="stat"><div class="label">Hostname</div><div class="value">${hostname}</div></div>
        <div class="stat"><div class="label">Uptime</div><div class="value" id="uptime">&mdash;</div></div>
        <div class="stat"><div class="label">Server time</div><div class="value" id="clock">${nowIso}</div></div>
        <div class="stat"><div class="label">Node</div><div class="value">${process.version}</div></div>
        <div class="stat"><div class="label">Platform</div><div class="value">${os.platform()}/${os.arch()}</div></div>
      </div>
    </section>

    <section class="card">
      <h2>What this proves</h2>
      <ul class="proves">
        <li><b>Forgejo</b> received the push and triggered Woodpecker via webhook</li>
        <li><b>Woodpecker</b> ran the test suite and built this exact image</li>
        <li><b>SonarQube</b> passed its quality gate before the build was allowed to proceed</li>
        <li><b>Harbor</b> scanned the image for known CVEs before it was deployable</li>
        <li><b>Portainer</b> deployed it, and <b>Traefik</b> is routing this HTTPS request to it right now</li>
      </ul>
    </section>

    <section class="card">
      <h2>Stack</h2>
      <div class="chips">${techChips}</div>
    </section>

    <footer>
      <span>GET <a href="/healthz">/healthz</a> for a machine-readable health check</span>
      <span>Started ${new Date(START_TIME).toISOString()}</span>
    </footer>
  </main>

  <script>
    const startedAt = ${START_TIME};
    function pad(n){ return String(n).padStart(2, '0'); }
    function tick(){
      const now = Date.now();
      const secs = Math.floor((now - startedAt) / 1000);
      const h = Math.floor(secs / 3600);
      const m = Math.floor((secs % 3600) / 60);
      const s = secs % 60;
      document.getElementById('uptime').textContent = h + 'h ' + pad(m) + 'm ' + pad(s) + 's';
      document.getElementById('clock').textContent = new Date(now).toISOString();
    }
    tick();
    setInterval(tick, 1000);
  </script>
</body>
</html>`;
}

function handler(req, res) {
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok' }));
    return;
  }

  if (req.url === '/') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(renderPage());
    return;
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'not found' }));
}

const server = http.createServer(handler);

if (require.main === module) {
  const port = process.env.PORT || 3000;
  server.listen(port, () => {
    console.log(`listening on :${port}`);
  });
}

module.exports = { server, handler };
