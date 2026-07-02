#!/bin/bash

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$REPO_ROOT/scripts/macos/manage-cliproxyapi.sh"
STATE_FILE="$REPO_ROOT/.cliproxyapi-manager-state.macos.json"
STATE_BACKUP="${TMPDIR:-/tmp}/cliproxyapi-manager-state.macos.$$.$RANDOM.json"
INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-status-install-$$-$RANDOM"
EXPLICIT_INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-explicit-install-$$-$RANDOM"
HAD_STATE=0

if [ -f "$STATE_FILE" ]; then
  HAD_STATE=1
  mv "$STATE_FILE" "$STATE_BACKUP"
fi

cleanup() {
  rm -rf "$INSTALL_DIR" "$EXPLICIT_INSTALL_DIR"
  rm -f "$STATE_FILE"
  if [ "$HAD_STATE" -eq 1 ] && [ -f "$STATE_BACKUP" ]; then
    mv "$STATE_BACKUP" "$STATE_FILE"
  fi
}
trap cleanup EXIT

assert_no_install_prompt() {
  checked_output=$1
  case "$checked_output" in
    *"安装目录（"*|*"上次安装目录"*|*"请选择安装目录"*|*"default"*)
      printf 'status should not prompt for install directory. Output:\n%s\n' "$checked_output" >&2
      exit 1
      ;;
  esac
}

mkdir -p "$INSTALL_DIR"
cat > "$INSTALL_DIR/config.yaml" <<'EOF'
host: "127.0.0.1"
port: 8317

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test"
EOF
printf 'placeholder\n' > "$INSTALL_DIR/cli-proxy-api"
chmod +x "$INSTALL_DIR/cli-proxy-api"
cat > "$STATE_FILE" <<EOF
{
  "installDir": "$(printf '%s' "$INSTALL_DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "lastReleaseTag": "test",
  "updatedAt": "2026-07-02T00:00:00Z"
}
EOF

output=$("$MANAGER" --status </dev/null 2>&1)
assert_no_install_prompt "$output"

case "$output" in
  *"$INSTALL_DIR"*) ;;
  *)
    printf 'status should use saved install dir. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"mgmt-local-test"*)
    printf 'status must not print full WebUI management key. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

mkdir -p "$EXPLICIT_INSTALL_DIR"
explicit_output=$("$MANAGER" --status --install-dir "$EXPLICIT_INSTALL_DIR" </dev/null 2>&1)
assert_no_install_prompt "$explicit_output"

case "$explicit_output" in
  *"$EXPLICIT_INSTALL_DIR"*) ;;
  *)
    printf 'status should use explicit install dir. Output:\n%s\n' "$explicit_output" >&2
    exit 1
    ;;
esac

saved_install_dir=$(sed -n 's/.*"installDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$STATE_FILE" | head -n 1)
if [ "$saved_install_dir" != "$EXPLICIT_INSTALL_DIR" ]; then
  printf 'explicit --install-dir should save state.\nExpected: %s\nActual: %s\nState:\n' "$EXPLICIT_INSTALL_DIR" "$saved_install_dir" >&2
  cat "$STATE_FILE" >&2
  exit 1
fi

printf 'MACOS_STATUS_NO_PROMPT_OK\n'
