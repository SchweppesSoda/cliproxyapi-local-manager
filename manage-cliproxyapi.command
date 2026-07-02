#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/scripts/macos/manage-cliproxyapi.sh"
printf '\n按回车关闭此窗口...'
read _unused
