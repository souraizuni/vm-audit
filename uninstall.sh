#!/usr/bin/env bash
set -u

TARGET="/usr/local/bin/vm-audit"

if [ "$(id -u 2>/dev/null)" != "0" ]; then
  printf '%s\n' "Please run as root: sudo uninstall.sh"
  exit 1
fi

if [ -f "$TARGET" ]; then
  rm -f "$TARGET"
  printf '%s\n' "Removed $TARGET"
else
  printf '%s\n' "$TARGET not found"
fi
