#!/usr/bin/env bash
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT_DIR="${TMPDIR:-/tmp}/vm-audit-smoke-$$"

cleanup() {
  rm -rf "$OUT_DIR"
}
trap cleanup EXIT

bash -n "$ROOT_DIR/vm-audit.sh"
bash -n "$ROOT_DIR/install.sh"
bash -n "$ROOT_DIR/uninstall.sh"

bash "$ROOT_DIR/vm-audit.sh" --version >/dev/null
bash "$ROOT_DIR/vm-audit.sh" --output "$OUT_DIR" >/dev/null

[ -s "$OUT_DIR/report.md" ]
[ -s "$OUT_DIR/report.html" ]
[ -d "$OUT_DIR/raw" ]
grep -q "VM Audit Report" "$OUT_DIR/report.md"
grep -q "Migration Checklist" "$OUT_DIR/report.md"

printf '%s\n' "smoke test passed"
