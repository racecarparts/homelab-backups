#!/bin/sh
# =============================================================================
# setup.sh — One-time host setup for homelab-backups
#
# Run this on each host before deploying the Backrest Portainer stack.
# Installs git (if needed), rclone, and configures the Google Drive remote
# using a service account key.
#
# Compatible with Alpine (apk) and Debian/Ubuntu (apt-get).
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

set -eu

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
error()   { printf "${RED}[✗]${NC} %s\n" "$*" >&2; exit 1; }
section() { printf "\n${YELLOW}── %s ──${NC}\n" "$*"; }

# ── Re-exec with sudo if not root ─────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "This script requires root. Re-running with sudo..."
  exec sudo sh "$0" "$@"
fi

# ── Detect OS package manager ─────────────────────────────────────────────────
if command -v apt-get >/dev/null 2>&1; then
  DISTRO="debian"
elif command -v apk >/dev/null 2>&1; then
  DISTRO="alpine"
else
  DISTRO="unknown"
fi

pkg_install() {
  case "$DISTRO" in
    debian)
      apt-get update -qq
      apt-get install -y "$1"
      ;;
    alpine)
      apk update -q
      apk add --no-cache "$1"
      ;;
    *)
      error "$1 is not installed and no supported package manager found. Install it manually and re-run."
      ;;
  esac
}

# ── Install rclone ────────────────────────────────────────────────────────────
# Alpine's BusyBox unzip doesn't support rclone's install script — use apk instead.
install_rclone() {
  case "$DISTRO" in
    alpine)
      apk update -q
      apk add --no-cache rclone
      ;;
    *)
      curl -fsSL https://rclone.org/install.sh | sh
      ;;
  esac
}

# ── Ensure dependencies are installed ─────────────────────────────────────────
section "Checking dependencies"

command -v git >/dev/null 2>&1     || pkg_install git
info "git: $(git --version)"

command -v python3 >/dev/null 2>&1 || pkg_install python3
info "python3: $(python3 --version)"

command -v curl >/dev/null 2>&1    || pkg_install curl
info "curl ready"

# ── Get service account key — from file arg or interactive paste ──────────────
SA_KEY_SRC="${1:-}"
SA_KEY_CONTENT=""

if [ -n "$SA_KEY_SRC" ]; then
  if [ ! -f "$SA_KEY_SRC" ]; then
    error "Service account key not found: $SA_KEY_SRC"
  fi
  SA_KEY_CONTENT=$(cat "$SA_KEY_SRC")
else
  printf "\n"
  warn "No key file provided."
  printf "\n"
  printf "  Paste your Google Cloud service account JSON key below.\n"
  printf "  (Copy the entire contents of the .json key file)\n"
  printf "  When done, press Enter then Ctrl+D on a new line.\n"
  printf "\n"
  SA_KEY_CONTENT=$(cat)
  printf "\n"
fi

# Validate it looks like a service account JSON
if ! printf '%s' "$SA_KEY_CONTENT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('type')=='service_account'" 2>/dev/null; then
  error "That doesn't look like a valid service account JSON key. Check the contents and try again."
fi
info "Service account key validated"

# ── Install rclone ────────────────────────────────────────────────────────────
section "Installing rclone"
if command -v rclone >/dev/null 2>&1; then
  info "rclone already installed: $(rclone --version | head -1)"
else
  install_rclone
  info "rclone installed: $(rclone --version | head -1)"
fi

# ── Create rclone config directory ────────────────────────────────────────────
section "Configuring rclone"
RCLONE_DIR="/root/.config/rclone"
mkdir -p "$RCLONE_DIR"
info "Config directory ready: $RCLONE_DIR"

# ── Write service account key ─────────────────────────────────────────────────
SA_KEY_DEST="$RCLONE_DIR/sa-key.json"
printf '%s\n' "$SA_KEY_CONTENT" > "$SA_KEY_DEST"
chmod 600 "$SA_KEY_DEST"
info "Service account key written to: $SA_KEY_DEST"

# ── Write rclone.conf ─────────────────────────────────────────────────────────
RCLONE_CONF="$RCLONE_DIR/rclone.conf"
if [ -f "$RCLONE_CONF" ]; then
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
if rclone lsd gdrive: >/dev/null 2>&1; then
  info "Google Drive connection successful"
  printf "\n  Contents of gdrive:/\n"
  rclone lsd gdrive: | sed 's/^/    /'
else
  warn "Could not connect to Google Drive."
  warn "Check that the service account has been granted access to your Drive folder."
  warn "See README.md for details."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
section "Done"
printf "\n"
printf "  Host is ready for Backrest deployment.\n"
printf "\n"
printf "  Next steps:\n"
printf "    1. In Portainer, go to Stacks -> Add stack\n"
printf "    2. Choose 'Repository' as the build method\n"
printf "    3. Set repository URL to your homelab-backups GitHub repo\n"
printf "    4. Set compose path to: docker-compose.yml\n"
printf "    5. Deploy the stack\n"
printf "\n"
printf "  Backrest UI will be available at: http://%s:9898\n" "$(hostname -I 2>/dev/null | awk '{print $1}' || hostname)"
printf "\n"
