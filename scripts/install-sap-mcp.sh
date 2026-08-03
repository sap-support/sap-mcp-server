#!/usr/bin/env bash
# One-line installer for the sap-mcp-server binary and its Claude Code registration.
#
# Usage:
#   curl -fsSL https://github.com/sap-support/sap-mcp-server/releases/latest/download/install-sap-mcp.sh | bash
#
# What it does:
#   1. Checks the platform (Linux / WSL only)
#   2. Installs Claude Code (npm install -g @anthropic-ai/claude-code)
#   3. Downloads the sap-mcp-server binary into ~/sap-mcp-server/ and marks it executable
#   4. Places connections.json.example into ~/.config/sap-mcp-server/ (the real file is yours to write)
#   5. Upserts the mcpServers entry in ~/.claude.json
#
# Environment variables:
#   SAP_MCP_REPO        GitHub repository (default: sap-support/sap-mcp-server)
#   SAP_MCP_VERSION     Release tag to fetch (default: latest)
#   SAP_MCP_BINARY_URL  Direct download URL for the binary (skips GitHub Releases when set)
#   GH_TOKEN            Token for private repos / API rate limits (optional)
#
set -euo pipefail

REPO="${SAP_MCP_REPO:-sap-support/sap-mcp-server}"
RELEASE_TAG="${SAP_MCP_VERSION:-latest}"
BIN_URL="${SAP_MCP_BINARY_URL:-}"
ASSET="sap-mcp-server-linux"
INSTALL_DIR="$HOME/sap-mcp-server"
CONFIG_DIR="$HOME/.config/sap-mcp-server"
CLAUDE_CONFIG="$HOME/.claude.json"

echo "=== sap-mcp-server install ==="

# 1. Platform check
OS=$(uname -s)
if [ "$OS" != "Linux" ]; then
  echo "Only Linux is supported. OS=$OS" >&2
  exit 1
fi

# 2. Claude Code
if ! command -v claude >/dev/null 2>&1; then
  echo "[1/4] Installing Claude Code..."
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm is required (install Node.js 18+ and re-run)" >&2
    exit 1
  fi
  npm install -g @anthropic-ai/claude-code
else
  echo "[1/4] Claude Code is already installed"
fi

# 3. Download the binary (public releases allow anonymous download; falls back to gh CLI / GH_TOKEN)
echo "[2/4] Downloading the binary into $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
if [ -n "$BIN_URL" ]; then
  curl -fsSL "$BIN_URL" -o "$INSTALL_DIR/$ASSET"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  if [ "$RELEASE_TAG" = "latest" ]; then
    gh release download --repo "$REPO" --pattern "$ASSET" --dir "$INSTALL_DIR" --clobber
  else
    gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$ASSET" --dir "$INSTALL_DIR" --clobber
  fi
else
  AUTH_HEADER=()
  [ -n "${GH_TOKEN:-}" ] && AUTH_HEADER=(-H "Authorization: Bearer $GH_TOKEN")
  if [ "$RELEASE_TAG" = "latest" ]; then
    DL_URL="https://github.com/$REPO/releases/latest/download/$ASSET"
  else
    DL_URL="https://github.com/$REPO/releases/download/$RELEASE_TAG/$ASSET"
  fi
  curl -fsSL "${AUTH_HEADER[@]}" "$DL_URL" -o "$INSTALL_DIR/$ASSET"
fi
chmod +x "$INSTALL_DIR/$ASSET"
echo "       $(ls -lh "$INSTALL_DIR/$ASSET" | awk '{print $5}')  ($("$INSTALL_DIR/$ASSET" --version))"

# 4. connections.json template
echo "[3/4] Preparing $CONFIG_DIR..."
mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/connections.json" ]; then
  cat > "$CONFIG_DIR/connections.json.example" <<'EOF'
{
  "defaultConnection": "primary",
  "connections": {
    "primary": {
      "defaultDestination": "<SID>",
      "relayUrl":     "https://your-backend.example.com",
      "relayBasePath": "/api/tableread/mcp",
      "clientId":     "REPLACE_WITH_CLIENT_ID",
      "clientSecret": "REPLACE_WITH_CLIENT_SECRET",
      "tokenUrl":     "https://your-idp.example.com/oauth/token"
    }
  }
}
EOF
  echo "       Template written to $CONFIG_DIR/connections.json.example"
  echo "       ⚠ Create connections.json yourself with your backend URL and credentials"
else
  echo "       Keeping the existing connections.json"
fi

# 5. Upsert mcpServers.sap-mcp-server in ~/.claude.json
echo "[4/4] Updating $CLAUDE_CONFIG..."
mkdir -p "$(dirname "$CLAUDE_CONFIG")"
python3 - "$CLAUDE_CONFIG" "$INSTALL_DIR/sap-mcp-server-linux" <<'PY'
import json, os, sys
path, binary = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        with open(path) as f: data = json.load(f)
    except: data = {}
data.setdefault('mcpServers', {})
data['mcpServers']['sap-mcp-server'] = { 'command': binary, 'args': [] }
with open(path, 'w') as f: json.dump(data, f, indent=2, ensure_ascii=False)
print(f"       Registered mcpServers.sap-mcp-server in {path}")
PY

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps (manual):"
echo "  1. Edit $CONFIG_DIR/connections.json with your connection details"
echo "  2. chmod 600 $CONFIG_DIR/connections.json"
echo "  3. Start claude and run /mcp to confirm sap-mcp-server is connected"
