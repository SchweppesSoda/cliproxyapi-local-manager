#!/bin/bash

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$REPO_ROOT/scripts/macos/manage-cliproxyapi.sh"
STATE_FILE="$REPO_ROOT/.cliproxyapi-manager-state.macos.json"
STATE_BACKUP="${TMPDIR:-/tmp}/cliproxyapi-manager-state.macos.$$.$RANDOM.json"
INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-webui-info-$$-$RANDOM"
BCRYPT_INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-webui-bcrypt-$$-$RANDOM"
MISSING_PLAIN_INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-webui-missing-plain-$$-$RANDOM"
HAD_STATE=0
PORT=29173
SECRET_KEY="mgmt-local-full-secret-29173"
BCRYPT_HASH='$2a$10$Fzf5MdYAPAKPE1BtOfaLHubwrAspqK0.oCcQ4ExtavLwM7JA9Xp6u'
PLAIN_WEBUI_KEY="mgmt-local-plain-secret-for-webui"

if [ -f "$STATE_FILE" ]; then
  HAD_STATE=1
  mv "$STATE_FILE" "$STATE_BACKUP"
fi

cleanup() {
  rm -rf "$INSTALL_DIR" "$BCRYPT_INSTALL_DIR" "$MISSING_PLAIN_INSTALL_DIR"
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

mkdir -p "$BCRYPT_INSTALL_DIR"
cat > "$BCRYPT_INSTALL_DIR/config.yaml" <<EOF
host: "127.0.0.1"
port: 29174

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: '$BCRYPT_HASH'
EOF
printf '%s\n' "$PLAIN_WEBUI_KEY" > "$BCRYPT_INSTALL_DIR/webui-management-key.txt"

bcrypt_output_file="$BCRYPT_INSTALL_DIR/webui-info-output.txt"
set +e
"$MANAGER" --webui-info --install-dir "$BCRYPT_INSTALL_DIR" > "$bcrypt_output_file" 2>&1
bcrypt_status=$?
set -e

bcrypt_output=$(cat "$bcrypt_output_file")
if [ "$bcrypt_status" -ne 0 ]; then
  printf 'webui-info should exit successfully for bcrypt config with local plaintext key. Exit code: %s\nOutput:\n%s\n' "$bcrypt_status" "$bcrypt_output" >&2
  exit 1
fi
case "$bcrypt_output" in
  *"$PLAIN_WEBUI_KEY"*) ;;
  *)
    printf 'webui-info should print the saved plaintext WebUI key, not the bcrypt hash. Output:\n%s\n' "$bcrypt_output" >&2
    exit 1
    ;;
esac
case "$bcrypt_output" in
  *"$BCRYPT_HASH"*)
    printf 'webui-info must not print bcrypt hash as the WebUI management key. Output:\n%s\n' "$bcrypt_output" >&2
    exit 1
    ;;
esac

mkdir -p "$MISSING_PLAIN_INSTALL_DIR"
cat > "$MISSING_PLAIN_INSTALL_DIR/config.yaml" <<EOF
host: "127.0.0.1"
port: 29175

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: '$BCRYPT_HASH'
EOF

missing_plain_output_file="$MISSING_PLAIN_INSTALL_DIR/webui-info-output.txt"
set +e
"$MANAGER" --webui-info --install-dir "$MISSING_PLAIN_INSTALL_DIR" > "$missing_plain_output_file" 2>&1
missing_plain_status=$?
set -e

missing_plain_output=$(cat "$missing_plain_output_file")
if [ "$missing_plain_status" -ne 0 ]; then
  printf 'webui-info should exit successfully for bcrypt config without local plaintext key. Exit code: %s\nOutput:\n%s\n' "$missing_plain_status" "$missing_plain_output" >&2
  exit 1
fi
for required in "webui-management-key.txt" "不存在" "无法反推出明文" "重新生成配置"; do
  case "$missing_plain_output" in
    *"$required"*) ;;
    *)
      printf 'webui-info should clearly explain missing plaintext key files. Missing: %s\nOutput:\n%s\n' "$required" "$missing_plain_output" >&2
      exit 1
      ;;
  esac
done
case "$missing_plain_output" in
  *"$BCRYPT_HASH"*)
    printf 'webui-info must not print bcrypt hash when plaintext key file is missing. Output:\n%s\n' "$missing_plain_output" >&2
    exit 1
    ;;
esac

printf 'MACOS_WEBUI_INFO_OK\n'
