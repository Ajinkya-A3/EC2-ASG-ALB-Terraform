<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ha-web</title>
<style>
  :root {
    --bg-1: #0f172a;
    --bg-2: #1e3a8a;
    --card: rgba(255, 255, 255, 0.06);
    --border: rgba(255, 255, 255, 0.12);
    --accent: #38bdf8;
    --text: #e2e8f0;
    --muted: #94a3b8;
  }

  * { box-sizing: border-box; }

  html, body {
    height: 100%;
    margin: 0;
  }

  body {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    padding: 24px;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: radial-gradient(circle at 20% 20%, var(--bg-2), var(--bg-1) 60%);
    color: var(--text);
  }

  .card {
    width: 100%;
    max-width: 480px;
    padding: 40px 36px;
    border-radius: 20px;
    background: var(--card);
    border: 1px solid var(--border);
    backdrop-filter: blur(10px);
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);
  }

  .badge {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 6px 14px;
    border-radius: 999px;
    background: rgba(56, 189, 248, 0.12);
    border: 1px solid rgba(56, 189, 248, 0.3);
    color: var(--accent);
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.02em;
  }

  .badge::before {
    content: "";
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #34d399;
    box-shadow: 0 0 0 4px rgba(52, 211, 153, 0.18);
  }

  h1 {
    margin: 20px 0 6px;
    font-size: 26px;
    font-weight: 700;
    letter-spacing: -0.02em;
  }

  p.sub {
    margin: 0 0 28px;
    color: var(--muted);
    font-size: 14px;
  }

  .rows {
    display: grid;
    gap: 12px;
  }

  .row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 16px;
    border-radius: 12px;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid var(--border);
  }

  .row .label {
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
  }

  .row .value {
    font-family: "SFMono-Regular", ui-monospace, Menlo, Consolas, monospace;
    font-size: 14px;
    color: var(--text);
    font-weight: 600;
  }

  footer {
    margin-top: 28px;
    text-align: center;
    font-size: 12px;
    color: var(--muted);
  }
</style>
</head>
<body>
  <div class="card">
    <span class="badge">Healthy</span>
    <h1>Served from {{INSTANCE_ID}}</h1>
    <p class="sub">This response came from one target behind the load balancer.</p>

    <div class="rows">
      <div class="row">
        <span class="label">Instance ID</span>
        <span class="value">{{INSTANCE_ID}}</span>
      </div>
      <div class="row">
        <span class="label">Availability Zone</span>
        <span class="value">{{AZ}}</span>
      </div>
    </div>

    <footer>Refresh to see the ALB route to a different instance or AZ</footer>
  </div>
</body>
</html>