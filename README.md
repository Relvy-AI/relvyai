<p align="center">
  <img src="relvy-logo.png" alt="Relvy AI" width="280">
</p>

<p align="center"><strong>AI-powered on-call and incident response</strong></p>

Relvy AI executes your plain-language runbooks for on-call and incident response. Connect your observability stack, write runbooks in markdown, and let the AI handle the investigation when alerts fire — querying logs, metrics, traces, dashboards, and code to find root causes in minutes. Every investigation is captured in a notebook with rich data visualizations for humans to review and build trust with the AI.

> **Trial version** - This is a self-contained trial deployment. For full production deployment (SaaS or self-hosted), contact us at **support@relvy.ai**.

---

## Key Capabilities

- **AI Runbook Execution** — Write runbooks in plain English. Relvy's AI autonomously follows each step, querying your observability tools, correlating signals, and surfacing root causes.
- **Deep Observability Integration** — Connects natively to Datadog, New Relic, Grafana, Elastic, PagerDuty, and more. Queries logs, metrics, traces, and dashboards in real time during investigations.
- **Human-in-the-Loop** — Every investigation is fully transparent and auditable. The AI recommends actions but requires human approval before touching production.
- **Alert-to-Resolution Automation** *(available in full version)* — Triggers automatically from your alerting pipeline (PagerDuty, Slack, etc.), investigates the incident end-to-end, and delivers a structured root cause analysis.
- **Rapid Deployment with Forward Deployed Engineers** *(available in full version)* — Relvy's team tunes the AI on your infrastructure, runbooks, and data so you get accurate results from day one — no months-long onboarding.

---

## Prerequisites

- Docker Engine 20.10+ and Docker Compose v2
- At least 4 GB RAM available for containers

---

## Quick Start

### Step 1 - Clone the repo

```bash
git clone https://github.com/Relvy-AI/relvyai.git
cd relvyai
```

### Step 2 - Start the stack

```bash
./relvy.sh start
```

That's it. All services start with sensible defaults — no configuration needed. The script will pull images, wait for all services to be healthy, and open the app in your browser.

> **Relvy will be available at [http://localhost:5001](http://localhost:5001)** once all services are healthy (typically under a minute).

---

## Configuration (Optional)

All settings can be overridden by creating a `.env` file next to `docker-compose.yml`.

<details>
<summary><strong>Environment variable reference</strong></summary>

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_USER` | `relvy` | Database user |
| `POSTGRES_PASSWORD` | `relvy` | Database password |
| `POSTGRES_DB` | `relvydb` | Database name |
| `DEFAULT_USER_EMAIL` | `admin@relvy.local` | Admin email created on first boot |
| `DEFAULT_USER_PASSWORD` | `changeme` | Admin password |
| `DEFAULT_ORG_NAME` | `Default Organization` | Organization name |
| `SERVER_HOSTNAME` | `http://localhost` | Public URL where the instance is reachable |

</details>

<details>
<summary><strong>Services started</strong></summary>

| Service | Description |
|---|---|
| `db` | PostgreSQL 15 with pgvector |
| `redis` | Redis 7 (caching + Celery broker) |
| `proxy` | Squid forward + reverse proxy |
| `migrations` | Runs DB migrations (exits after completion) |
| `setup` | Creates default org and admin user (exits after completion) |
| `celery-worker` | Background task worker with Celery Beat |
| `web` | Web server serving the Relvy application |

</details>

---

## CLI Reference (`relvy.sh`)

The `relvy.sh` script is a convenience wrapper around Docker Compose that handles health checks, pre-flight validation, and browser launching.

| Command | Description |
|---|---|
| `./relvy.sh start` | Pull images, start all services, open browser |
| `./relvy.sh start --no-open` | Same as above, without opening the browser |
| `./relvy.sh stop` | Stop all services |
| `./relvy.sh restart` | Full restart (stop, pull, start) |
| `./relvy.sh restart <service>` | Restart a single service (`web`, `celery-worker`, or `proxy`) |
| `./relvy.sh status` | Show health of all services |
| `./relvy.sh logs [service] [opts]` | Tail logs for all or a specific service |
| `./relvy.sh reset` | Destroy all containers, volumes, and data, then start fresh |
| `./relvy.sh help` | Show available commands |

**Examples:**

```bash
./relvy.sh logs web --tail 50      # Last 50 lines from web
./relvy.sh logs celery-worker      # Follow celery logs
./relvy.sh restart web             # Restart only the web service
```

> You can still use `docker compose` commands directly if you prefer.

---

## Forward Proxy

The edge deployment routes all outbound traffic through a Squid forward proxy. The default config **allows all outbound traffic** — no changes needed to get started.

If your security policy requires restricting egress, follow the steps below.

<details>
<summary><strong>Restricting outbound traffic</strong></summary>

### 1. Switch to allowlist mode

Replace the access rules section in `squid.conf`:

```conf
# --- Access rules (allowlist mode) ---
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow CONNECT allowed_domains
http_access allow allowed_domains
http_access allow reverse_traffic
http_access deny all
```

### 2. Add domains for your integrations

Add `acl allowed_domains` lines **above** the access rules. Pick only what you use.

#### LLM Providers (required — pick one or more)

| Provider | ACL |
|---|---|
| OpenAI | `acl allowed_domains dstdomain .openai.com` |
| Anthropic | `acl allowed_domains dstdomain .anthropic.com` |
| Google Gemini | `acl allowed_domains dstdomain .googleapis.com` |
| Mistral | `acl allowed_domains dstdomain .mistral.ai` |
| Azure OpenAI | `acl allowed_domains dstdomain .openai.azure.com`<br>`acl allowed_domains dstdomain .blob.core.windows.net` |

#### Observability Platforms

| Platform | ACL | Notes |
|---|---|---|
| Datadog | `acl allowed_domains dstdomain .datadoghq.com`<br>`acl allowed_domains dstdomain .datadoghq.eu` | Region-dependent |
| New Relic | `acl allowed_domains dstdomain .newrelic.com` | |
| Elastic | `acl allowed_domains dstdomain .elastic.co` | Self-hosted: use your cluster hostname |
| Grafana Cloud | `acl allowed_domains dstdomain .grafana.com`<br>`acl allowed_domains dstdomain .grafana.net` | Self-hosted: use your hostname |
| PagerDuty | `acl allowed_domains dstdomain .pagerduty.com` | |
| Observe Inc | `acl allowed_domains dstdomain .observeinc.com` | |
| OpenObserve | `acl allowed_domains dstdomain .openobserve.ai` | Self-hosted: use your hostname |

#### Collaboration & Code

| Integration | ACL |
|---|---|
| Slack | `acl allowed_domains dstdomain .slack.com` |
| GitHub | `acl allowed_domains dstdomain .github.com`<br>`acl allowed_domains dstdomain .githubusercontent.com` |
| Jira / Atlassian | `acl allowed_domains dstdomain .atlassian.net`<br>`acl allowed_domains dstdomain .atlassian.com` |

### 3. Restart the proxy

```bash
./relvy.sh restart proxy
```

### Example: restricted squid.conf (OpenAI + Datadog + Slack)

```conf
# --- Port definitions ---
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 443
acl Safe_ports port 8080
acl CONNECT method CONNECT

# --- Domain allowlist ---
acl allowed_domains dstdomain .openai.com
acl allowed_domains dstdomain .datadoghq.com
acl allowed_domains dstdomain .slack.com
acl allowed_domains dstdomain .langfuse.com

# --- Reverse proxy settings (do not modify) ---
http_port 8080 accel defaultsite=web vhost
cache_peer web parent 8000 0 no-query originserver login=PASS name=webapp
request_header_access Authorization allow all
acl reverse_traffic localport 8080
cache_peer_access webapp allow reverse_traffic
never_direct allow reverse_traffic

# --- Access rules (allowlist mode) ---
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow CONNECT allowed_domains
http_access allow allowed_domains
http_access allow reverse_traffic
http_access deny all

# --- Forward proxy listener ---
http_port 3128

# --- Logging ---
access_log stdio:/dev/stdout
cache_log stdio:/dev/stderr
```

</details>

---

## Troubleshooting

<details>
<summary><strong>Services fail to start</strong></summary>

```bash
./relvy.sh status
./relvy.sh logs <service-name>
```

</details>

<details>
<summary><strong>Outbound requests failing (proxy errors)</strong></summary>

If integrations fail with connection errors, the domain is likely missing from `squid.conf`:

```bash
./relvy.sh logs proxy | grep DENIED
```

Add the missing domain and restart the proxy:

```bash
./relvy.sh restart proxy
```

</details>

<details>
<summary><strong>Cannot access the web UI</strong></summary>

- Verify the configured port is not in use by another process
- Check service health: `./relvy.sh status`
- Review proxy logs: `./relvy.sh logs proxy`

</details>

---

<p align="center">
  <a href="https://www.relvy.ai">Website</a> &middot;
  <a href="https://www.relvy.ai/docs/capabilities/overview">Docs</a> &middot;
  <a href="mailto:support@relvy.ai">support@relvy.ai</a>
</p>
