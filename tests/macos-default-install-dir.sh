#!/bin/bash

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$REPO_ROOT/manage-cliproxyapi.sh"
STATE_FILE="$REPO_ROOT/.cliproxyapi-manager-state.macos.json"
STATE_BACKUP="${TMPDIR:-/tmp}/cliproxyapi-manager-state.macos.$$.$RANDOM.json"
HAD_STATE=0

if [ -f "$STATE_FILE" ]; then
  HAD_STATE=1
  mv "$STATE_FILE" "$STATE_BACKUP"
fi

cleanup() {
  if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
  fi
  if [ "$HAD_STATE" -eq 1 ] && [ -f "$STATE_BACKUP" ]; then
    mv "$STATE_BACKUP" "$STATE_FILE"
  fi
}
trap cleanup EXIT

expected="$HOME/Library/Application Support/CLIProxyAPI"
output=$(printf '\n' | "$MANAGER" --status 2>&1)

case "$output" in
  *"Install dir:  $expected"*) ;;
  *)
    printf 'Expected default install dir: %s\nActual output:\n%s\n' "$expected" "$output" >&2
    exit 1
    ;;
esac

printf 'MACOS_DEFAULT_INSTALL_DIR_OK\n'

