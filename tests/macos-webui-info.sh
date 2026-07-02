#!/bin/bash

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$REPO_ROOT/scripts/macos/manage-cliproxyapi.sh"
STATE_FILE="$REPO_ROOT/.cliproxyapi-manager-state.macos.json"
STATE_BACKUP="${TMPDIR:-/tmp}/cliproxyapi-manager-state.macos.$$.$RANDOM.json"
INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-webui-info-$$-$RANDOM"
HAD_STATE=0
PORT=29173
SECRET_KEY="mgmt-local-full-secret-29173"

if [ -f "$STATE_FILE" ]; then
  HAD_STATE=1
  mv "$STATE_FILE" "$STATE_BACKUP"
fi

cleanup() {
  rm -rf "$INSTALL_DIR"
  rm -f "$STATE_FILE"
  if [ "$HAD_STATE" -eq 1 ] && [ -f "$STATE_BACKUP" ]; then
    mv "$STATE_BACKUP" "$STATE_FILE"
  fi
}
trap cleanup EXIT

mkdir -p "$INSTALL_DIR"
cat > "$INSTALL_DIR/config.yaml" <<EOF
host: "127.0.0.1"
port: $PORT

unrelated-secret:
  secret-key: "not-the-webui-management-secret"

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "$SECRET_KEY"
EOF

output_file="$INSTALL_DIR/webui-info-output.txt"
set +e
"$MANAGER" --webui-info --install-dir "$INSTALL_DIR" > "$output_file" 2>&1
status=$?
set -e

output=$(cat "$output_file")
if [ "$status" -ne 0 ]; then
  printf 'webui-info should exit successfully. Exit code: %s\nOutput:\n%s\n' "$status" "$output" >&2
  exit 1
fi

case "$output" in
  *"http://localhost:$PORT/management.html"*) ;;
  *)
    printf 'webui-info should print management URL. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"WebUI 管理密钥"*) ;;
  *)
    printf 'webui-info should label the WebUI management key. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"remote-management.secret-key"*"$SECRET_KEY"*|*"$SECRET_KEY"*"remote-management.secret-key"*) ;;
  *)
    printf 'webui-info should print the full remote-management.secret-key. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"not-the-webui-management-secret"*)
    printf 'webui-info must only print remote-management.secret-key. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

printf 'MACOS_WEBUI_INFO_OK\n'
