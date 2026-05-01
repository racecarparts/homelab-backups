#!/bin/bash
# =============================================================================
# setup.sh — One-time host setup for homelab-backups
#
# Run this on each host before deploying the Backrest Portainer stack.
# Installs git (if needed), rclone, and configures the Google Drive remote
# using a service account key.
#
# Usage:
#   Clone this repo on the host and run the script. You can either:
#
#   Option A — paste the key interactively (no scp needed):
#        git clone https://github.com/YOUR_USERNAME/homelab-backups.git
#        cd homelab-backups
#        ./setup.sh
#     (the script will prompt you to paste the JSON key)
#
#   Option B — provide the key as a file:
#        ./setup.sh ~/sa-key.json
#
#   The script will re-run itself with sudo if not already root.
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${YELLOW}── $* ──${NC}"; }

# ── Re-exec with sudo if not root ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "This script requires root. Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

# ── Detect OS package manager ─────────────────────────────────────────────────
if command -v apt-get &>/dev/null; then
  PKG_INSTALL="apt-get install -y"
  PKG_UPDATE="apt-get update -qq"
elif command -v apk &>/dev/null; then
  PKG_INSTALL="apk add --no-cache"
  PKG_UPDATE="apk update -q"
else
  PKG_INSTALL=""
  PKG_UPDATE=""
fi

# ── Ensure git is installed ───────────────────────────────────────────────────
section "Checking dependencies"
if command -v git &>/dev/null; then
  info "git already installed: $(git --version)"
else
  if [[ -z "$PKG_INSTALL" ]]; then
    error "git is not installed and no supported package manager found. Install git manually and re-run."
  fi
  warn "git not found — installing..."
  $PKG_UPDATE
  $PKG_INSTALL git
  info "git installed: $(git --version)"
fi

# ── Ensure python3 is installed (used for JSON validation) ───────────────────
if ! command -v python3 &>/dev/null; then
  if [[ -z "$PKG_INSTALL" ]]; then
    error "python3 is not installed and no supported package manager found. Install python3 manually and re-run."
  fi
  warn "python3 not found — installing..."
  $PKG_UPDATE
  $PKG_INSTALL python3
  info "python3 installed"
fi

# ── Get service account key — from file arg or interactive paste ──────────────
SA_KEY_SRC="${1:-}"
SA_KEY_CONTENT=""

if [[ -n "$SA_KEY_SRC" ]]; then
  # File path provided as argument
  if [[ ! -f "$SA_KEY_SRC" ]]; then
    error "Service account key not found: $SA_KEY_SRC"
  fi
  SA_KEY_CONTENT=$(cat "$SA_KEY_SRC")
else
  # No file provided — prompt for paste
  echo ""
  warn "No key file provided."
  echo ""
  echo "  Paste your Google Cloud service account JSON key below."
  echo "  (Copy the entire contents of the .json key file)"
  echo "  When done, press Enter then Ctrl+D on a new line."
  echo ""
  SA_KEY_CONTENT=$(cat)
  echo ""
fi

# Validate it looks like a service account JSON
if ! echo "$SA_KEY_CONTENT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('type')=='service_account'" 2>/dev/null; then
  error "That doesn't look like a valid service account JSON key. Check the contents and try again."
fi
info "Service account key validated"

# ── Install rclone ────────────────────────────────────────────────────────────
section "Installing rclone"
if command -v rclone &>/dev/null; then
  info "rclone already installed: $(rclone --version | head -1)"
else
  curl -fsSL https://rclone.org/install.sh | bash
  info "rclone installed: $(rclone --version | head -1)"
fi

# ── Create rclone config directory ────────────────────────────────────────────
section "Configuring rclone"
RCLONE_DIR="/root/.config/rclone"
mkdir -p "$RCLONE_DIR"
info "Config directory ready: $RCLONE_DIR"

# ── Write service account key ─────────────────────────────────────────────────
SA_KEY_DEST="$RCLONE_DIR/sa-key.json"
echo "$SA_KEY_CONTENT" > "$SA_KEY_DEST"
chmod 600 "$SA_KEY_DEST"
info "Service account key written to: $SA_KEY_DEST"

# ── Write rclone.conf ─────────────────────────────────────────────────────────
RCLONE_CONF="$RCLONE_DIR/rclone.conf"
if [[ -f "$RCLONE_CONF" ]]; then
  warn "rclone.conf already exists — skipping (delete it manually to regenerate)"
else
  cat > "$RCLONE_CONF" <<EOF
[gdrive]
type = drive
scope = drive
service_account_file = $SA_KEY_DEST
EOF
  chmod 600 "$RCLONE_CONF"
  info "rclone.conf written: $RCLONE_CONF"
fi

# ── Verify rclone can reach Google Drive ──────────────────────────────────────
section "Verifying Google Drive connection"
if rclone lsd gdrive: &>/dev/null; then
  info "Google Drive connection successful"
  echo ""
  echo "  Contents of gdrive:/"
  rclone lsd gdrive: | sed 's/^/    /'
else
  warn "Could not connect to Google Drive."
  warn "Check that the service account has been granted access to your Drive folder."
  warn "See README.md for details."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
section "Done"
echo ""
echo "  Host is ready for Backrest deployment."
echo ""
echo "  Next steps:"
echo "    1. In Portainer, go to Stacks → Add stack"
echo "    2. Choose 'Repository' as the build method"
echo "    3. Set repository URL to your homelab-backups GitHub repo"
echo "    4. Set compose path to: docker-compose.yml"
echo "    5. Deploy the stack"
echo ""
echo "  Backrest UI will be available at: http://$(hostname -I | awk '{print $1}'):9898"
echo ""
