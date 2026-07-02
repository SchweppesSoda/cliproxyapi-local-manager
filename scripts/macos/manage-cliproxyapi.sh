#!/bin/bash

set -u

REPO="router-for-me/CLIProxyAPI"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
STATE_FILE="$PROJECT_ROOT/.cliproxyapi-manager-state.macos.json"
DEFAULT_INSTALL_DIR="$HOME/Apps/CLIProxyAPI"

info() {
  printf '[INFO] %s\n' "$1"
}

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

show_help() {
  cat <<'EOF'
CLIProxyAPI Local Manager for macOS

Usage:
  ./manage-cliproxyapi.sh
  ./manage-cliproxyapi.sh --status

Actions:
  --status        Show local status
  --install       Install or update CLIProxyAPI
  --config        Generate local-only config.yaml
  --start         Start CLIProxyAPI
  --health        Check /health
  --webui         Open Management Center
  --oauth         Run Codex OAuth login
  --device-login  Run Codex device-code login
  --models        Query /v1/models
  --workbuddy     Print WorkBuddy configuration summary
EOF
}

confirm_yes() {
  prompt=$1
  default_yes=$2
  if [ "$default_yes" = "yes" ]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi
  printf '%s %s ' "$prompt" "$suffix" >&2
  IFS= read -r answer
  if [ -z "$answer" ]; then
    [ "$default_yes" = "yes" ]
    return
  fi
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_state_value() {
  key=$1
  if [ ! -f "$STATE_FILE" ]; then
    return 1
  fi
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$STATE_FILE" | head -n 1
}

save_state() {
  install_dir=$1
  release_tag=$2
  if [ -z "$release_tag" ]; then
    existing_release_tag=$(read_state_value "lastReleaseTag" || true)
    if [ -n "$existing_release_tag" ]; then
      release_tag=$existing_release_tag
    fi
  fi
  updated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  escaped_install_dir=$(json_escape "$install_dir")
  escaped_release_tag=$(json_escape "$release_tag")
  cat > "$STATE_FILE" <<EOF
{
  "installDir": "$escaped_install_dir",
  "lastReleaseTag": "$escaped_release_tag",
  "updatedAt": "$updated_at"
}
EOF
}

expand_install_path() {
  path=$1
  case "$path" in
    "~") path="$HOME" ;;
    "~/"*) path="$HOME/${path#~/}" ;;
  esac
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s\n' "$(pwd)/$path" ;;
  esac
}

select_install_dir() {
  previous=$(read_state_value "installDir" || true)
  if [ -n "$previous" ]; then
    printf '\nPrevious install dir:\n  %s\n' "$previous" >&2
    printf 'Default install dir:\n  %s\n' "$DEFAULT_INSTALL_DIR" >&2
    printf "Install dir (Enter for previous, type 'default' for default, or enter a custom path): " >&2
    IFS= read -r input_path
    if [ -z "$input_path" ]; then
      expand_install_path "$previous"
      return
    fi
    if [ "$input_path" = "default" ]; then
      expand_install_path "$DEFAULT_INSTALL_DIR"
      return
    fi
    expand_install_path "$input_path"
    return
  fi

  printf '\nDefault install dir:\n  %s\n' "$DEFAULT_INSTALL_DIR" >&2
  printf 'Install dir (press Enter for default): ' >&2
  IFS= read -r input_path
  if [ -z "$input_path" ]; then
    input_path=$DEFAULT_INSTALL_DIR
  fi
  expand_install_path "$input_path"
}

paths_for() {
  install_dir=$1
  case "$2" in
    exe) printf '%s/cli-proxy-api\n' "$install_dir" ;;
    config) printf '%s/config.yaml\n' "$install_dir" ;;
    auth) printf '%s/auth\n' "$install_dir" ;;
    backups) printf '%s/backups\n' "$install_dir" ;;
    downloads) printf '%s/downloads\n' "$install_dir" ;;
    start_sh) printf '%s/start-cliproxyapi.sh\n' "$install_dir" ;;
    start_command) printf '%s/start-cliproxyapi.command\n' "$install_dir" ;;
  esac
}

ensure_install_layout() {
  install_dir=$1
  mkdir -p "$install_dir" "$(paths_for "$install_dir" auth)" "$(paths_for "$install_dir" backups)" "$(paths_for "$install_dir" downloads)"
}

architecture_regex() {
  arch=$(uname -m)
  case "$arch" in
    arm64|aarch64) printf 'arm64|aarch64\n' ;;
    *) printf 'amd64|x86_64|x64\n' ;;
  esac
}

download_latest_release_json() {
  release_file=$1
  info "Fetching latest release metadata from $REPO"
  curl -fsSL -H "User-Agent: cliproxyapi-manager" "$API_URL" -o "$release_file"
}

release_tag_from_json() {
  release_file=$1
  sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$release_file" | head -n 1
}

select_macos_asset() {
  release_file=$1
  arch_re=$(architecture_regex)
  awk -v os_re='darwin|macos|mac' -v arch_re="$arch_re" '
    function trim_json_value(line, key) {
      sub("^[[:space:]]*\"" key "\"[[:space:]]*:[[:space:]]*\"", "", line)
      sub("\",[[:space:]]*$", "", line)
      return line
    }
    /"name"[[:space:]]*:/ {
      name = trim_json_value($0, "name")
      lname = tolower(name)
    }
    /"browser_download_url"[[:space:]]*:/ {
      url = trim_json_value($0, "browser_download_url")
      if (lname ~ os_re && lname ~ arch_re && (lname ~ /\.zip$/ || lname ~ /\.tar\.gz$/ || lname ~ /\.tgz$/ || lname ~ /cli.*proxy.*api$/ || lname ~ /cliproxyapi$/)) {
        print name "\t" url
        exit
      }
    }
  ' "$release_file"
}

find_binary_candidate() {
  root=$1
  find "$root" -type f | while IFS= read -r path; do
    base=$(basename "$path")
    lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      *cli*proxy*api*|*cliproxyapi*)
        printf '%s\n' "$path"
        break
        ;;
    esac
  done | head -n 1
}

write_start_scripts() {
  install_dir=$1
  start_sh=$(paths_for "$install_dir" start_sh)
  start_command=$(paths_for "$install_dir" start_command)

  cat > "$start_sh" <<EOF
#!/bin/bash
set -e
SCRIPT_DIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
cd "\$SCRIPT_DIR"
./cli-proxy-api -config ./config.yaml
EOF

  cat > "$start_command" <<'EOF'
#!/bin/sh
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$SCRIPT_DIR/start-cliproxyapi.sh"
printf '\nPress Enter to close this window...'
read _unused
EOF

  chmod +x "$start_sh" "$start_command"
  ok "Start scripts written:"
  printf '  %s\n' "$start_sh"
  printf '  %s\n' "$start_command"
}

install_or_update() {
  install_dir=$1
  ensure_install_layout "$install_dir"

  exe=$(paths_for "$install_dir" exe)
  backups=$(paths_for "$install_dir" backups)
  downloads=$(paths_for "$install_dir" downloads)
  timestamp=$(date +"%Y%m%d-%H%M%S")
  release_file="$downloads/release-$timestamp.json"
  extract_dir="$downloads/extract-$timestamp"

  download_latest_release_json "$release_file" || return 1
  release_tag=$(release_tag_from_json "$release_file")
  asset_line=$(select_macos_asset "$release_file")
  if [ -z "$asset_line" ]; then
    warn "No macOS release asset found. Check the latest release assets manually."
    return 1
  fi

  asset_name=$(printf '%s' "$asset_line" | awk -F '\t' '{print $1}')
  asset_url=$(printf '%s' "$asset_line" | awk -F '\t' '{print $2}')
  download_path="$downloads/$asset_name"

  info "Latest release: $release_tag"
  info "Downloading: $asset_url"
  curl -fL -H "User-Agent: cliproxyapi-manager" "$asset_url" -o "$download_path" || return 1

  mkdir -p "$extract_dir"
  case "$asset_name" in
    *.zip)
      unzip -oq "$download_path" -d "$extract_dir" || return 1
      new_binary=$(find_binary_candidate "$extract_dir")
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$download_path" -C "$extract_dir" || return 1
      new_binary=$(find_binary_candidate "$extract_dir")
      ;;
    *)
      new_binary="$download_path"
      ;;
  esac

  if [ -z "$new_binary" ] || [ ! -f "$new_binary" ]; then
    warn "Downloaded asset did not contain cli-proxy-api"
    return 1
  fi

  if [ -f "$exe" ]; then
    backup_path="$backups/cli-proxy-api-$timestamp"
    cp "$exe" "$backup_path" || return 1
    info "Existing binary backed up to $backup_path"
  fi

  cp "$new_binary" "$exe" || return 1
  chmod +x "$exe"
  ok "Installed $exe"
  write_start_scripts "$install_dir"
  save_state "$install_dir" "$release_tag"

  info "Checking executable help output"
  help_file="$downloads/help-$timestamp.txt"
  if "$exe" -h > "$help_file" 2>&1; then
    sed -n '1,20p' "$help_file"
  else
    sed -n '1,20p' "$help_file"
    warn "Installed executable failed help check"
    return 1
  fi
}

generate_uuid_key() {
  prefix=$1
  if [ -r /dev/urandom ]; then
    token=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n' | cut -c 1-24)
  elif command -v uuidgen >/dev/null 2>&1; then
    token=$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]' | cut -c 1-24)
  else
    token=$(date +%s%N | shasum 2>/dev/null | awk '{print $1}' | cut -c 1-24)
  fi
  printf '%s%s\n' "$prefix" "$token"
}

generate_config() {
  install_dir=$1
  ensure_install_layout "$install_dir"

  config=$(paths_for "$install_dir" config)
  backups=$(paths_for "$install_dir" backups)
  timestamp=$(date +"%Y%m%d-%H%M%S")

  if [ -f "$config" ]; then
    if ! confirm_yes "config.yaml already exists. Back it up and overwrite?" "no"; then
      warn "Keeping existing config.yaml"
      write_start_scripts "$install_dir"
      return 0
    fi
    backup_config="$backups/config-$timestamp.yaml"
    cp "$config" "$backup_config" || return 1
    info "Existing config backed up to $backup_config"
  fi

  printf 'Local port (press Enter for 8317): '
  IFS= read -r port
  if [ -z "$port" ]; then
    port=8317
  fi
  case "$port" in
    *[!0-9]*)
      warn "Port must be a number"
      return 1
      ;;
  esac
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    warn "Port must be between 1 and 65535"
    return 1
  fi

  mgmt_key=$(generate_uuid_key "mgmt-local-")
  client_key=$(generate_uuid_key "wb-local-")

  cat > "$config" <<EOF
host: "127.0.0.1"
port: $port

auth-dir: "./auth"

api-keys:
  - "$client_key"

remote-management:
  allow-remote: false
  secret-key: "$mgmt_key"
  disable-control-panel: false

debug: false
logging-to-file: true
request-retry: 3
max-retry-credentials: 1

routing:
  strategy: "fill-first"
  session-affinity: true
EOF

  ok "Config written: $config"
  printf '\nManagement Key (for WebUI):\n%s\n' "$mgmt_key"
  printf '\nClient API Key (for WorkBuddy):\n%s\n\n' "$client_key"
  warn "Save these keys in a local password manager. Do not commit or share them."
  write_start_scripts "$install_dir"
  save_state "$install_dir" ""
}

yaml_scalar_value() {
  config=$1
  yaml_key=$2
  bom=$(printf '\357\273\277')
  key_prefix="$yaml_key:"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line#$bom}
    trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
    case "$trimmed" in
      "$key_prefix"*)
        value=${trimmed#*:}
        printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^"//; s/"$//'
        return 0
        ;;
    esac
  done < "$config"
}

config_value() {
  config=$1
  key=$2
  default_value=$3

  if [ ! -f "$config" ]; then
    printf '%s\n' "$default_value"
    return
  fi

  case "$key" in
    host)
      value=$(yaml_scalar_value "$config" "host")
      ;;
    port)
      value=$(yaml_scalar_value "$config" "port")
      ;;
    management_key)
      value=$(yaml_scalar_value "$config" "secret-key")
      ;;
    allow_remote)
      value=$(yaml_scalar_value "$config" "allow-remote" | tr '[:upper:]' '[:lower:]')
      ;;
    client_key)
      value=$(awk '
        /^[[:space:]]*api-keys:[[:space:]]*$/ { in_api=1; next }
        in_api && /^[[:space:]]*-[[:space:]]*/ {
          line=$0
          sub(/^[[:space:]]*-[[:space:]]*"?/, "", line)
          sub(/"?[[:space:]]*$/, "", line)
          print line
          exit
        }
        /^[^[:space:]]/ { in_api=0 }
      ' "$config" | head -n 1)
      ;;
  esac

  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$default_value"
  fi
}

assert_local_only_config() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  host=$(config_value "$config" host "127.0.0.1")
  allow_remote=$(config_value "$config" allow_remote "false")

  case "$host" in
    127.0.0.1|localhost|::1) ;;
    *)
      warn "Unsafe config host '$host'. This manager only supports local loopback hosts."
      return 1
      ;;
  esac

  if [ "$allow_remote" = "true" ]; then
    warn "Unsafe config: remote-management.allow-remote is true. Set it to false before continuing."
    return 1
  fi
}

show_status() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  host=$(config_value "$config" host "127.0.0.1")
  port=$(config_value "$config" port "8317")

  printf '\nProject root: %s\n' "$PROJECT_ROOT"
  printf 'State file:   %s\n' "$STATE_FILE"
  printf 'Install dir:  %s\n' "$install_dir"
  printf 'Binary:       %s [%s]\n' "$exe" "$(test -f "$exe" && printf true || printf false)"
  printf 'Config:       %s [%s]\n' "$config" "$(test -f "$config" && printf true || printf false)"
  printf 'Host:         %s\n' "$host"
  printf 'Port:         %s\n' "$port"
}

start_clip_proxy_api() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  start_command=$(paths_for "$install_dir" start_command)

  if [ ! -f "$exe" ]; then
    warn "Executable not found. Run install/update first."
    return 1
  fi
  if [ ! -f "$config" ]; then
    warn "config.yaml not found. Generate config first."
    return 1
  fi
  assert_local_only_config "$install_dir" || return 1

  write_start_scripts "$install_dir"
  info "Opening CLIProxyAPI in Terminal"
  open "$start_command"
}

health_check() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  host=$(config_value "$config" host "127.0.0.1")
  port=$(config_value "$config" port "8317")
  assert_local_only_config "$install_dir" || return 1
  url="http://$host:$port/health"
  info "GET $url"
  if curl -fsS "$url"; then
    printf '\n'
    ok "Health check succeeded"
  else
    warn "Health check failed"
    return 1
  fi
}

open_webui() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  port=$(config_value "$config" port "8317")
  assert_local_only_config "$install_dir" || return 1
  url="http://localhost:$port/management.html"
  info "Opening $url"
  open "$url"
}

codex_login() {
  install_dir=$1
  mode=$2
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)

  if [ ! -f "$exe" ]; then
    warn "Executable not found. Run install/update first."
    return 1
  fi
  if [ ! -f "$config" ]; then
    warn "config.yaml not found. Generate config first."
    return 1
  fi
  assert_local_only_config "$install_dir" || return 1

  (
    cd "$install_dir" || exit 1
    if [ "$mode" = "device" ]; then
      "$exe" -config "$config" -codex-device-login
    else
      "$exe" -config "$config" -codex-login
    fi
  )
}

query_models() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  host=$(config_value "$config" host "127.0.0.1")
  port=$(config_value "$config" port "8317")
  client_key=$(config_value "$config" client_key "")
  assert_local_only_config "$install_dir" || return 1

  if [ -z "$client_key" ]; then
    printf 'Client API Key (wb-local-...): '
    IFS= read -r client_key
  fi

  url="http://$host:$port/v1/models"
  info "GET $url"
  if command -v jq >/dev/null 2>&1; then
    curl -fsS -H "Authorization: Bearer $client_key" "$url" | jq .
  else
    curl -fsS -H "Authorization: Bearer $client_key" "$url"
    printf '\n'
  fi
}

show_workbuddy_info() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  port=$(config_value "$config" port "8317")
  client_key=$(config_value "$config" client_key "")
  assert_local_only_config "$install_dir" || return 1

  printf '\nWorkBuddy Base URL:\n'
  printf 'http://127.0.0.1:%s/v1\n' "$port"
  printf '\nWorkBuddy Chat Completions URL:\n'
  printf 'http://127.0.0.1:%s/v1/chat/completions\n' "$port"
  printf '\nWorkBuddy API Key:\n'
  if [ -n "$client_key" ]; then
    printf '%s\n' "$client_key"
  else
    printf '<read from config.yaml api-keys>\n'
  fi
  printf '\nWebUI:\n'
  printf 'http://localhost:%s/management.html\n' "$port"
  printf '\nUse /v1/models output as the Model value.\n'
}

run_action() {
  action=$1
  install_dir=$2
  case "$action" in
    status) show_status "$install_dir" ;;
    install) install_or_update "$install_dir" ;;
    config) generate_config "$install_dir" ;;
    start) start_clip_proxy_api "$install_dir" ;;
    health) health_check "$install_dir" ;;
    webui) open_webui "$install_dir" ;;
    oauth) codex_login "$install_dir" browser ;;
    device-login) codex_login "$install_dir" device ;;
    models) query_models "$install_dir" ;;
    workbuddy) show_workbuddy_info "$install_dir" ;;
    *) warn "Unknown action: $action"; return 1 ;;
  esac
}

show_menu() {
  install_dir=$1
  while :; do
    printf '\nCLIProxyAPI Local Manager\n'
    printf 'Install dir: %s\n\n' "$install_dir"
    printf '1. Status\n'
    printf '2. Install or update CLIProxyAPI\n'
    printf '3. Generate local config.yaml\n'
    printf '4. Start CLIProxyAPI\n'
    printf '5. Health check\n'
    printf '6. Open WebUI\n'
    printf '7. Codex OAuth login\n'
    printf '8. Codex device-code login\n'
    printf '9. Query /v1/models\n'
    printf '10. Print WorkBuddy settings\n'
    printf '11. Change install dir\n'
    printf '0. Exit\n'
    printf 'Select: '
    IFS= read -r choice

    case "$choice" in
      1) show_status "$install_dir" ;;
      2) install_or_update "$install_dir" ;;
      3) generate_config "$install_dir" ;;
      4) start_clip_proxy_api "$install_dir" ;;
      5) health_check "$install_dir" ;;
      6) open_webui "$install_dir" ;;
      7) codex_login "$install_dir" browser ;;
      8) codex_login "$install_dir" device ;;
      9) query_models "$install_dir" ;;
      10) show_workbuddy_info "$install_dir" ;;
      11) install_dir=$(select_install_dir); save_state "$install_dir" "" ;;
      0) return 0 ;;
      *) warn "Unknown choice: $choice" ;;
    esac
  done
}

ACTION="menu"
case "${1:-}" in
  -h|--help) show_help; exit 0 ;;
  --status) ACTION="status" ;;
  --install) ACTION="install" ;;
  --config) ACTION="config" ;;
  --start) ACTION="start" ;;
  --health) ACTION="health" ;;
  --webui) ACTION="webui" ;;
  --oauth) ACTION="oauth" ;;
  --device-login) ACTION="device-login" ;;
  --models) ACTION="models" ;;
  --workbuddy) ACTION="workbuddy" ;;
  "") ACTION="menu" ;;
  *) warn "Unknown option: $1"; show_help; exit 1 ;;
esac

INSTALL_DIR=$(select_install_dir)
if [ "$ACTION" = "menu" ]; then
  show_menu "$INSTALL_DIR"
else
  run_action "$ACTION" "$INSTALL_DIR"
fi
