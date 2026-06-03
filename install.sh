#!/usr/bin/env bash
set -u

INSTALL_DIR="/usr/local/bin"
INSTALL_PATH="$INSTALL_DIR/vm-audit"
REPO_RAW_URL="${VM_AUDIT_RAW_URL:-https://raw.githubusercontent.com/souraizuni/vm-audit/main}"

say() {
  printf '%s\n' "$*"
}

need_root() {
  if [ "$(id -u 2>/dev/null)" != "0" ]; then
    say "Please run as root, for example: curl -fsSL $REPO_RAW_URL/install.sh | sudo bash"
    exit 1
  fi
}

install_from_local() {
  src="$(dirname "$0")/vm-audit.sh"
  [ -r "$src" ] || return 1
  cp "$src" "$INSTALL_PATH"
}

install_from_remote() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW_URL/vm-audit.sh" -o "$INSTALL_PATH"
  else
    say "curl is required to install vm-audit"
    exit 1
  fi
}

need_root

if [ -f "$INSTALL_PATH" ]; then
  say "Updating vm-audit..."
else
  say "Installing vm-audit..."
fi

mkdir -p "$INSTALL_DIR"

if ! install_from_local; then
  install_from_remote
fi

chmod 0755 "$INSTALL_PATH"
say "Installed: $INSTALL_PATH"
say "Run: sudo vm-audit"
