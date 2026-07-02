#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/scripts/macos/manage-cliproxyapi.sh"
printf '\nPress Enter to close this window...'
read _unused

