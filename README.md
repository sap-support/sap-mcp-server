# sap-mcp-server

> Securely operate SAP ABAP and BTP services from MCP-compatible AI clients.

Connect to SAP **ABAP** and **BTP services** from general MCP-compatible AI clients such as
**Claude Code**, **Codex**, and **Gemini CLI**. Distributed as a single self-contained binary
(Node.js SEA) for Linux.

> This tool is **not standalone**: it requires a backend service deployed on **SAP BTP, Cloud Foundry**.
> Through strong, multi-layered security it accesses **on-premise / RISE** SAP environments.

> **This repository is the official binary distribution point.** Every binary published here is built
> from a tagged source revision by the release workflow in this repository, then signed and attested
> before it is attached to a release.

---

## 🔒 Security

Security is enforced in **multiple layers (defense in depth)**, so AI-driven access to SAP
stays controlled and auditable.

| Layer | Control |
|---|---|
| **Access scope** | Restrict access to **Full**, **Reference-only (read-only)** or **Development-only**. |
| **Landscape** | Per-landscape access control for **DEV / QAS / PRD**. |
| **Authentication** | Connects only over a secure, authenticated channel; SAP credentials are never held by the client. |
| **Secret handling** | Connection secrets are kept **local only** and are **never** committed or embedded in the binary. |

### Security pattern: role-based authorization

Three scopes — `mcp` (**Full**), `mcp_readonly` (**Reference-only**) and `mcp_developer` (**Development-only**) — are enforced in layers (the reference backend implements this; bring-your-own backends are encouraged to follow it):

1. **Scope gate (app level)** — every MCP route is mounted behind "require `mcp` *or* `mcp_readonly` *or* `mcp_developer`"; a token with none of these scopes is rejected (403) before any handler runs.
2. **Environment gate (per destination)** — each destination is tagged `DEV` / `QAS` / `PRD`. `mcp_developer` may reach only `DEV`/`QAS`; `mcp_readonly` may also reach `PRD` but for reads only. Untagged destinations are denied for restricted scopes (fail-closed). `mcp` reaches all.
3. **Method gate (REST relays)** — `mcp_readonly` may use any method on `DEV`/`QAS` and only `GET` on `PRD`. `mcp_developer` is limited to `GET` (external app relays allow any method on `DEV`/`QAS`).
4. **No function modules in production** — `mcp_readonly` is denied `sap_call_fm` against `PRD` **regardless of the `commit` flag**. Many function modules write without an explicit commit, so "read-only" cannot be delegated to a caller-supplied flag.
5. **Hard-deny** — PII tools (IAS / IPS), CLI execution and OS SSH execution (`os_call_windows_ssh` / `os_call_linux_ssh`) are `mcp`-only, regardless of environment.
6. **ABAP writes stay in development** — write / delete / transport / activate target `DEV`-tagged destinations only, for every scope. `QAS` and `PRD` are not modifiable under standard SAP practice; changes arrive by transport.

The per-tool matrix is generated from the tool catalog that ships inside the binary, so it always
matches the release. It is published as a page rather than duplicated here:

- **[Tool reference](https://sap-support.github.io/sap-mcp-server/)** — switch between **PRD** and **QAS / DEV** to see what each scope may do, with the authentication and call path behind every tool
- **[ツール一覧（日本語）](https://sap-support.github.io/sap-mcp-server/ja/)**

Operational controls (defense in depth): (1) MCP key issuance, (2) scope `mcp` / `mcp_readonly` / `mcp_developer`, (3) key revoke, (4) audit log of every call, (5) per-destination environment tag.

## Capabilities

**41 tools.** Per-tool descriptions, official API references and per-scope permissions are carried in
the tool catalog embedded in the binary, which your MCP client shows once the server is connected.

The same catalog is published as the [Tool reference](https://sap-support.github.io/sap-mcp-server/)
page linked above.

- **Connection**
  - List destinations, switch the active destination, show the current one
- **SAP ABAP**
  - **Run any remote-enabled Function Module / BAPI without cumbersome web service configuration.**
  - Function Modules (RFC / BAPI)
  - Table read (RFC_READ_TABLE-equivalent)
  - ADT SQL / Open SQL / DDIC preview
  - **Add-on development** — read / write / activate / delete reports and function modules (SE37) via ADT
  - **Transport management** — create / release transport requests (CTS)
  - **S/4HANA APIs** — OData V2 / V4, REST and SOAP services published on the system
    (the transport for [SAP Business Accelerator Hub](https://api.sap.com/) APIs)
- **SAP BTP services**
  - Cloud Identity Services (IAS) Admin / SCIM
  - Identity Provisioning (IPS) Jobs / JobLogs
  - Cloud Foundry API v3
  - Build Work Zone (Content API)
  - Cloud Transport Management (cTMS) v2
  - Forms Service by Adobe
  - Cloud Information Service (CIS Central)
  - Integration Suite (CPI) Audit / Monitoring
  - Alert Notification Service (ANS)
  - Build Process Automation (SBPA)
  - Datasphere (public REST / OData API)
  - Analytics Cloud (SAC REST API)
  - Cloud ALM (REST API)
- **SAP applications**
  - Integrated Business Planning (IBP) OData API
- **CLI execution** (`mcp` scope only)
  - `btp` CLI / `cf` CLI / `datasphere` CLI
- **External app relays**
  - JIRA REST API v3
  - SmartDB REST API v3
- **On-premise OS / monitoring** (SSH via Connectivity SOCKS5 + Cloud Connector / Zabbix 7.0 API)
  - Arbitrary OS command execution on Windows / Linux hosts over SSH (`mcp` scope only)
  - Allow-listed JP1/AJS3 - Manager commands over SSH
  - Zabbix 7.0 JSON-RPC API (monitoring configuration, problems, maintenance windows)

## Install

Download the Linux binary from GitHub Releases.

```bash
curl -fsSL https://github.com/sap-support/sap-mcp-server/releases/latest/download/install-sap-mcp.sh | bash
```

### Verifying a download

Every binary ships with a `*.sha256` checksum and a GitHub build provenance attestation. The binary
is additionally signed with [sigstore](https://www.sigstore.dev/) — keyless, so there is no
long-lived private key to protect; the signing identity is the release workflow itself.

```bash
sha256sum -c sap-mcp-server-linux.sha256

# sigstore signature (requires cosign)
cosign verify-blob sap-mcp-server-linux \
  --bundle sap-mcp-server-linux.cosign.bundle \
  --certificate-identity-regexp '^https://github.com/sap-support/sap-mcp-server/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

# build provenance (requires GitHub CLI 2.49 or later)
gh attestation verify sap-mcp-server-linux --repo sap-support/sap-mcp-server
```

## Configuration

The binary reads a `connections.json` describing one or more backend connections. It is read by the
**binary itself** (independent of the AI client), in this lookup order:

`$SAP_MCP_CONFIG` → `~/.config/sap-mcp-server/connections.json` → next to the executable.

### connections.json format

```json
{
  "defaultConnection": "primary",
  "connections": {
    "primary": {
      "defaultDestination": "AC1",
      "relayUrl": "https://your-backend.example.com",
      "relayBasePath": "/api/tableread/mcp",
      "clientId": "sb-xxxxxxxx",
      "clientSecret": "xxxxxxxx",
      "tokenUrl": "https://<subdomain>.authentication.<region>.hana.ondemand.com/oauth/token"
    }
  }
}
```

| Field | Required | Description |
|---|---|---|
| `defaultConnection` | optional | Connection used when a tool call omits `connection`. Defaults to the first entry. |
| `defaultDestination` | optional | SAP destination (SID / Destination name) used when a tool call omits `destination`. |
| `relayUrl` | **required** | Base URL of the **backend** (the backend host itself, **not** the approuter). No trailing slash. |
| `relayBasePath` | **required*** | Path where the backend mounts the MCP relay. **It must match your backend.** The provided reference backend mounts it at **`/api/tableread/mcp`**. |
| `clientId` / `clientSecret` | **required** | OAuth2 `client_credentials` of the XSUAA service key that protects the backend. |
| `tokenUrl` | **required** | XSUAA token endpoint (ends with `/oauth/token`). |

> ⚠ **Most common failure — "cannot connect / tools return 404".**
> If `relayBasePath` is omitted it defaults to `/api/mcp`, which does **not** match the reference
> backend (mounted at `/api/tableread/mcp`), so every relay call 404s. Always set `relayBasePath`
> to your backend's actual MCP mount path.

### Getting the values (recommended)

Ask your backend administrator to issue you an MCP key. In the reference backend's **MCP admin** app,
open your approved request and click **"Get credentials"**. The dialog shows every field and provides:

- **Copy all** — copies the complete `connections.json` to the clipboard, and
- **Download connections.json** — saves a ready-to-use file.

`relayUrl`, `relayBasePath`, `clientId`, `clientSecret`, and `tokenUrl` are already filled in; you only
set **`defaultDestination`** (and optionally the connection name) in the dialog before copying/downloading.

> Credentials are shown **once**. If you miss them, ask the admin to **rotate** the key.

### Create / update the file

```bash
mkdir -p ~/.config/sap-mcp-server
# New install — move the downloaded file into place:
mv ~/Downloads/connections.json ~/.config/sap-mcp-server/connections.json
chmod 600 ~/.config/sap-mcp-server/connections.json
```

To add another landscape, add a second entry under `connections` (e.g. `"dev"`, `"prd"`), then either
set `defaultConnection` or pass the `connection` argument per tool call. Keep secrets **local only** —
never commit `connections.json`.

## Client Configuration

Register the binary in your AI client, then **restart the client** (or reconnect its MCP servers) so it
reloads. The MCP server name is arbitrary; `sap-mcp-server` is used below.

### Claude Code (CLI)

`install-sap-mcp.sh` auto-registers the server in `~/.claude.json`. To register manually:

```bash
claude mcp add sap-mcp-server -- /path/to/sap-mcp-server-linux
```

…or edit `~/.claude.json` directly:

```json
{ "mcpServers": { "sap-mcp-server": { "command": "/path/to/sap-mcp-server-linux", "args": [] } } }
```

Verify with **`/mcp`** inside Claude Code — it should list `sap-mcp-server` as connected. After you
**update the binary or `connections.json`**, run `/mcp` → reconnect (or restart Claude Code) to pick up
the change.

### Claude Desktop

- **Linux:** `~/.config/Claude/claude_desktop_config.json`

```json
{ "mcpServers": { "sap-mcp-server": { "command": "/path/to/sap-mcp-server-linux", "args": [] } } }
```

Restart Claude Desktop after editing.

### Gemini CLI (`~/.gemini/settings.json`)

```json
{ "mcpServers": { "sap-mcp-server": { "command": "/path/to/sap-mcp-server-linux", "args": [] } } }
```

Restart the Gemini CLI session after editing. (The binary still reads `connections.json` from the lookup
order above — the client config only points at the binary.)

## Backend

Actual SAP communication and the security controls above are performed by a **backend** that this
server connects to over a secure channel. A **compatible backend is required** (Bring Your Own Backend).

- The REST contract a backend must satisfy is documented separately and is available on request.
- A reference backend is **not** included. A production-ready backend
  (setup, connection configuration, and operation) is **provided separately under a consulting engagement**.
  Contact: contact@hugoconsulting.com

## Security Policy

Please report vulnerabilities via [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE).
"SAP" and SAP product names are trademarks of SAP SE. This project is not affiliated with,
endorsed by, or sponsored by SAP SE. See [NOTICE](NOTICE).
