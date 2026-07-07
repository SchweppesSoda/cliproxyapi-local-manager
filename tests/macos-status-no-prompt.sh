#!/bin/bash

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$REPO_ROOT/scripts/macos/manage-cliproxyapi.sh"
LEGACY_STATE_FILE="$REPO_ROOT/.cliproxyapi-manager-state.macos.json"
LEGACY_STATE_BACKUP="${TMPDIR:-/tmp}/cliproxyapi-manager-state.macos.$$.$RANDOM.json"
INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-status-install-$$-$RANDOM"
EXPLICIT_INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-explicit-install-$$-$RANDOM"
INSTALL_STATE_FILE="$INSTALL_DIR/.cliproxyapi-manager-state.macos.json"
EXPLICIT_INSTALL_STATE_FILE="$EXPLICIT_INSTALL_DIR/.cliproxyapi-manager-state.macos.json"
HAD_LEGACY_STATE=0

if [ -f "$LEGACY_STATE_FILE" ]; then
  HAD_LEGACY_STATE=1
  mv "$LEGACY_STATE_FILE" "$LEGACY_STATE_BACKUP"
fi

cleanup() {
  rm -rf "$INSTALL_DIR" "$EXPLICIT_INSTALL_DIR"
  rm -f "$LEGACY_STATE_FILE"
  if [ "$HAD_LEGACY_STATE" -eq 1 ] && [ -f "$LEGACY_STATE_BACKUP" ]; then
    mv "$LEGACY_STATE_BACKUP" "$LEGACY_STATE_FILE"
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

run_manager() {
  output_file=$1
  shift
  timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd=timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd=gtimeout
  fi

  set +e
  if [ -n "$timeout_cmd" ]; then
    "$timeout_cmd" 5 "$MANAGER" "$@" </dev/null 2>&1 | head -c 20000 > "$output_file"
  else
    (
      "$MANAGER" "$@" </dev/null 2>&1 &
      manager_pid=$!
      (
        sleep 5
        if kill -0 "$manager_pid" 2>/dev/null; then
          kill "$manager_pid" 2>/dev/null
          sleep 1
          kill -9 "$manager_pid" 2>/dev/null
        fi
      ) &
      watchdog_pid=$!
      wait "$manager_pid"
      manager_status=$?
      kill "$watchdog_pid" 2>/dev/null
      wait "$watchdog_pid" 2>/dev/null
      if [ "$manager_status" -gt 128 ]; then
        exit 124
      fi
      exit "$manager_status"
    ) | head -c 20000 > "$output_file"
  fi
  statuses=("${PIPESTATUS[@]}")
  set -e
  return "${statuses[0]}"
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
cat > "$LEGACY_STATE_FILE" <<EOF
{
  "installDir": "$(printf '%s' "$INSTALL_DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "lastReleaseTag": "test",
  "updatedAt": "2026-07-02T00:00:00Z"
}
EOF

output_file="$INSTALL_DIR/status-output.txt"
if ! run_manager "$output_file" --status; then
  printf 'status command failed or timed out. Output:\n%s\n' "$(cat "$output_file")" >&2
  exit 1
fi
output=$(cat "$output_file")
assert_no_install_prompt "$output"

case "$output" in
  *"$INSTALL_DIR"*) ;;
  *)
    printf 'status should use saved install dir. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

if [ ! -f "$INSTALL_STATE_FILE" ]; then
  printf 'status should migrate legacy repo state into install dir state: %s\n' "$INSTALL_STATE_FILE" >&2
  exit 1
fi

case "$output" in
  *"mgmt-local-test"*)
    printf 'status must not print full WebUI management key. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

mkdir -p "$EXPLICIT_INSTALL_DIR"
explicit_output_file="$EXPLICIT_INSTALL_DIR/status-output.txt"
if ! run_manager "$explicit_output_file" --status --install-dir "$EXPLICIT_INSTALL_DIR"; then
  printf 'explicit install-dir status command failed or timed out. Output:\n%s\n' "$(cat "$explicit_output_file")" >&2
  exit 1
fi
explicit_output=$(cat "$explicit_output_file")
assert_no_install_prompt "$explicit_output"

case "$explicit_output" in
  *"$EXPLICIT_INSTALL_DIR"*) ;;
  *)
    printf 'status should use explicit install dir. Output:\n%s\n' "$explicit_output" >&2
    exit 1
    ;;
esac

if [ -f "$LEGACY_STATE_FILE" ]; then
  printf 'explicit --install-dir should not write manager state to repo root: %s\n' "$LEGACY_STATE_FILE" >&2
  exit 1
fi
if [ ! -f "$EXPLICIT_INSTALL_STATE_FILE" ]; then
  printf 'explicit --install-dir should save state inside install dir: %s\n' "$EXPLICIT_INSTALL_STATE_FILE" >&2
  exit 1
fi

saved_install_dir=$(sed -n 's/.*"installDir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$EXPLICIT_INSTALL_STATE_FILE" | head -n 1)
if [ "$saved_install_dir" != "$EXPLICIT_INSTALL_DIR" ]; then
  printf 'explicit --install-dir should save state.\nExpected: %s\nActual: %s\nState:\n' "$EXPLICIT_INSTALL_DIR" "$saved_install_dir" >&2
  cat "$EXPLICIT_INSTALL_STATE_FILE" >&2
  exit 1
fi

invalid_output_file="$INSTALL_DIR/invalid-install-dir-output.txt"
if run_manager "$invalid_output_file" --install-dir --status; then
  printf '%s\nOutput:\n%s\n' "--install-dir followed by an option should fail." "$(cat "$invalid_output_file")" >&2
  exit 1
fi
invalid_output=$(cat "$invalid_output_file")
case "$invalid_output" in
  *"--install-dir 需要路径参数"*) ;;
  *)
    printf '%s\nOutput:\n%s\n' "--install-dir followed by an option should report missing path." "$invalid_output" >&2
    exit 1
    ;;
esac

printf 'MACOS_STATUS_NO_PROMPT_OK\n'
