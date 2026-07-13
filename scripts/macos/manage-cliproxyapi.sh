#!/bin/bash

set -u

REPO="router-for-me/CLIProxyAPI"
API_URL="https://api.github.com/repos/$REPO/releases/latest"
MODEL_CATALOG_URLS=(
  "https://raw.githubusercontent.com/router-for-me/models/refs/heads/main/models.json"
  "https://models.router-for.me/models.json"
)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
LEGACY_STATE_FILE="$PROJECT_ROOT/.cliproxyapi-manager-state.macos.json"
STATE_FILE=""
DEFAULT_INSTALL_DIR="$HOME/Library/Application Support/CLIProxyAPI"
MENU_RIGHT_COLUMN=46
PANEL_VALUE_COLUMN=24

info() {
  printf '[INFO] %s\n' "$1"
}

ok() {
  printf '[OK] %s\n' "$1"
}

warn() {
  printf '[WARN] %s\n' "$1"
}

MENU_WIDTH=64

menu_divider() {
  printf '%*s\n' "$MENU_WIDTH" '' | tr ' ' '='
}

panel_divider() {
  printf '%*s\n' "$MENU_WIDTH" '' | tr ' ' '-'
}

print_title() {
  printf '\n'
  menu_divider
  printf '%s\n' "$1"
  menu_divider
}

print_menu_section() {
  panel_divider
  printf '%s\n' "$1"
}

print_menu_item() {
  printf '  %s %s\n' "$1" "$2"
}

print_menu_pair() {
  printf '  %s %s' "$1" "$2"
  if [ -n "${3:-}" ]; then
    if [ -t 1 ]; then
      printf '\033[%sG' "$MENU_RIGHT_COLUMN"
    else
      printf '    '
    fi
    printf '%s %s' "$3" "$4"
  fi
  printf '\n'
}

print_panel_section() {
  panel_divider
  printf '%s\n' "$1"
}

print_panel_value_column() {
  if [ -t 1 ]; then
    printf '\033[%sG' "$PANEL_VALUE_COLUMN"
  else
    printf '    '
  fi
}

print_panel_row() {
  label=$1
  shift
  printf '  %s' "$label"
  print_panel_value_column
  printf ': %s\n' "$*"
}

show_help() {
  cat <<'EOF'
CLIProxyAPI 本地管理器（macOS）

Usage:
  ./manage-cliproxyapi.sh
  ./manage-cliproxyapi.sh --status

Actions:
  --status        显示本地状态
  --install       安装或更新 CLIProxyAPI
  --config        生成仅本机访问的 config.yaml
  --start         后台启动 CLIProxyAPI（写入 logs）
  --stop          停止由本管理器启动的 CLIProxyAPI
  --health        API 可用性检查（GET /v1/models）
  --webui         打开管理中心
  --webui-info    输出 WebUI URL 和完整管理密钥
  --oauth         执行 Codex 浏览器 OAuth 登录
  --device-login  执行 Codex 设备码登录
  --models        查询 /v1/models
  --workbuddy     输出 WorkBuddy 配置摘要
  --client-config 输出客户端模型配置 JSON（当前支持 workbuddy）
  --workbuddy-json 兼容别名；已弃用
  --schedule-status  查看定时自动更新状态
  --schedule-enable  开启或修改每日定时自动更新
  --schedule-disable 关闭定时自动更新
  --cleanup       清理更新下载缓存，并按类型仅保留最近 3 个备份

Options:
  --format workbuddy                    客户端配置格式
  --vendor "My Local Provider"          自定义客户端显示 Vendor
  --model-ids "model-a,model-b"       只输出指定模型 ID
  --image-model-ids "model-b"         将指定模型标记为 supportsImages=true；使用 * 表示全部
  --include-token-limits              输出 maxInputTokens/maxOutputTokens；默认不输出
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

backup_file_name() {
  base_name=$1
  extension=$2
  release_tag=$3
  timestamp=$4

  if [ -z "$release_tag" ]; then
    release_tag="unknown-version"
  fi
  safe_release_tag=$(printf '%s' "$release_tag" | sed -E 's#[/\\:*?"<>|[:space:]]+#-#g; s#^-+##; s#-+$##')
  if [ -z "$safe_release_tag" ]; then
    safe_release_tag="unknown-version"
  fi
  case "$extension" in
    ""|.*) ;;
    *) extension=".$extension" ;;
  esac

  printf '%s-%s-%s%s\n' "$base_name" "$safe_release_tag" "$timestamp" "$extension"
}

state_file_for_install_dir() {
  printf '%s/.cliproxyapi-manager-state.macos.json\n' "$1"
}

set_state_install_dir() {
  STATE_FILE=$(state_file_for_install_dir "$1")
}

read_state_value_from_file() {
  state_file=$1
  key=$2
  if [ -z "$state_file" ] || [ ! -f "$state_file" ]; then
    return 1
  fi
  sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$state_file" | head -n 1
}

read_state_value() {
  key=$1
  read_state_value_from_file "$STATE_FILE" "$key"
}

read_legacy_state_value() {
  key=$1
  read_state_value_from_file "$LEGACY_STATE_FILE" "$key"
}

save_state() {
  install_dir=$1
  release_tag=$2
  set_state_install_dir "$install_dir"
  if [ -z "$release_tag" ]; then
    existing_release_tag=$(read_state_value "lastReleaseTag" || true)
    if [ -n "$existing_release_tag" ]; then
      release_tag=$existing_release_tag
    fi
  fi
  updated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  escaped_install_dir=$(json_escape "$install_dir")
  escaped_release_tag=$(json_escape "$release_tag")
  mkdir -p "$install_dir"
  cat > "$STATE_FILE" <<EOF
{
  "installDir": "$escaped_install_dir",
  "lastReleaseTag": "$escaped_release_tag",
  "updatedAt": "$updated_at"
}
EOF
  rm -f "$LEGACY_STATE_FILE"
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
  if [ -z "$previous" ]; then
    previous=$(read_legacy_state_value "installDir" || true)
  fi
  if [ -n "$previous" ]; then
    printf '\n上次安装目录：\n  %s\n' "$previous" >&2
    printf '默认安装目录：\n  %s\n' "$DEFAULT_INSTALL_DIR" >&2
    printf "安装目录（回车使用上次，输入 'default' 使用默认，或输入自定义路径）： " >&2
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

  printf '\n默认安装目录：\n  %s\n' "$DEFAULT_INSTALL_DIR" >&2
  printf '安装目录（回车使用默认）： ' >&2
  IFS= read -r input_path
  if [ -z "$input_path" ]; then
    input_path=$DEFAULT_INSTALL_DIR
  fi
  expand_install_path "$input_path"
}

resolve_install_dir() {
  requested_install_dir=$1
  interactive=$2

  if [ -n "$requested_install_dir" ]; then
    resolved=$(expand_install_path "$requested_install_dir")
    save_state "$resolved" ""
    printf '%s\n' "$resolved"
    return
  fi

  previous=$(read_legacy_state_value "installDir" || true)
  if [ -n "$previous" ]; then
    resolved=$(expand_install_path "$previous")
    save_state "$resolved" ""
    printf '%s\n' "$resolved"
    return
  fi

  default_exe=$(paths_for "$DEFAULT_INSTALL_DIR" exe)
  default_config=$(paths_for "$DEFAULT_INSTALL_DIR" config)
  if [ -f "$default_exe" ] || [ -f "$default_config" ]; then
    resolved=$(expand_install_path "$DEFAULT_INSTALL_DIR")
    set_state_install_dir "$resolved"
    printf '%s\n' "$resolved"
    return
  fi

  if [ "$interactive" = "yes" ]; then
    resolved=$(select_install_dir)
    save_state "$resolved" ""
    printf '%s\n' "$resolved"
    return
  fi

  resolved=$(expand_install_path "$DEFAULT_INSTALL_DIR")
  set_state_install_dir "$resolved"
  printf '%s\n' "$resolved"
}

paths_for() {
  install_dir=$1
  case "$2" in
    exe) printf '%s/cli-proxy-api\n' "$install_dir" ;;
    config) printf '%s/config.yaml\n' "$install_dir" ;;
    models) printf '%s/models.json\n' "$install_dir" ;;
    webui_key) printf '%s/webui-management-key.txt\n' "$install_dir" ;;
    auth) printf '%s/auth\n' "$install_dir" ;;
    backups) printf '%s/backups\n' "$install_dir" ;;
    downloads) printf '%s/downloads\n' "$install_dir" ;;
    logs) printf '%s/logs\n' "$install_dir" ;;
    stdout_log) printf '%s/logs/cli-proxy-api.stdout.log\n' "$install_dir" ;;
    stderr_log) printf '%s/logs/cli-proxy-api.stderr.log\n' "$install_dir" ;;
    auto_update_stdout_log) printf '%s/logs/auto-update.stdout.log\n' "$install_dir" ;;
    auto_update_stderr_log) printf '%s/logs/auto-update.stderr.log\n' "$install_dir" ;;
    auto_update_schedule) printf '%s/auto-update-schedule.txt\n' "$install_dir" ;;
    launch_agent_plist) printf '%s/Library/LaunchAgents/local.cliproxyapi.manager.autoupdate.plist\n' "$HOME" ;;
    pid_file) printf '%s/cli-proxy-api.pid\n' "$install_dir" ;;
    start_sh) printf '%s/start-cliproxyapi.sh\n' "$install_dir" ;;
    start_command) printf '%s/start-cliproxyapi.command\n' "$install_dir" ;;
  esac
}

ensure_install_layout() {
  install_dir=$1
  mkdir -p "$install_dir" "$(paths_for "$install_dir" auth)" "$(paths_for "$install_dir" backups)" "$(paths_for "$install_dir" downloads)" "$(paths_for "$install_dir" logs)"
}

update_cache_summary() {
  download_dir=$1
  if [ ! -d "$download_dir" ]; then
    printf '0|0\n'
    return
  fi
  item_count=$(find "$download_dir" -mindepth 1 -print | wc -l | tr -d ' ')
  total_kb=$(du -sk "$download_dir" 2>/dev/null | awk 'NR == 1 { print $1 }')
  [ -n "$total_kb" ] || total_kb=0
  printf '%s|%s\n' "$item_count" "$total_kb"
}

format_managed_storage_size() {
  total_kb=$1
  awk -v total_kb="$total_kb" 'BEGIN {
    if (total_kb >= 1048576) { printf "%.2f GB", total_kb / 1048576 }
    else if (total_kb >= 1024) { printf "%.2f MB", total_kb / 1024 }
    else { printf "%d KB", total_kb }
  }'
}

clear_update_cache() {
  install_dir=$1
  interactive=${2:-no}
  download_dir=$(paths_for "$install_dir" downloads)
  expected_download_dir="$install_dir/downloads"
  if [ "$download_dir" != "$expected_download_dir" ]; then
    warn "拒绝清理非安装目录 downloads 路径: $download_dir"
    return 1
  fi
  if [ ! -d "$download_dir" ]; then
    info "没有可清理的更新下载缓存"
    return 0
  fi
  if [ -L "$download_dir" ]; then
    warn "拒绝清理符号链接目录: $download_dir"
    return 1
  fi
  if find "$download_dir" -mindepth 1 -type l -print | grep -q .; then
    warn "更新缓存中包含符号链接，拒绝清理: $download_dir"
    return 1
  fi

  summary=$(update_cache_summary "$download_dir")
  item_count=${summary%%|*}
  total_kb=${summary#*|}
  if [ "$item_count" -eq 0 ]; then
    info "没有可清理的更新下载缓存"
    return 0
  fi
  info "更新下载缓存: $item_count 项，$(format_managed_storage_size "$total_kb")"
  if [ "$interactive" = "yes" ] && ! confirm_yes "清理上述更新下载缓存？不会删除 backups、auth、config.yaml、密钥或 logs。" "no"; then
    info "已取消清理更新下载缓存"
    return 0
  fi

  find "$download_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
  ok "已清理更新下载缓存: $download_dir"
}

old_managed_backups() {
  install_dir=$1
  backups=$(paths_for "$install_dir" backups)
  if [ ! -d "$backups" ]; then
    return 0
  fi
  if [ -L "$backups" ]; then
    warn "拒绝清理符号链接目录: $backups" >&2
    return 1
  fi
  if find "$backups" -mindepth 1 -type l -print | grep -q .; then
    warn "备份目录中包含符号链接，拒绝清理: $backups" >&2
    return 1
  fi

  for pattern in 'cli-proxy-api-*' 'config-*.yaml'; do
    find "$backups" -maxdepth 1 -type f -name "$pattern" -exec stat -f '%m %N' {} \; |
      sort -nr |
      awk 'NR > 3 { sub(/^[0-9]+ /, ""); print }'
  done
}

prune_old_managed_backups() {
  install_dir=$1
  interactive=${2:-no}
  old_backups=$(old_managed_backups "$install_dir") || return 1
  if [ -z "$old_backups" ]; then
    info "无需清理旧备份（每类最多保留最近 3 个）"
    return 0
  fi

  item_count=$(printf '%s\n' "$old_backups" | awk 'NF { count++ } END { print count + 0 }')
  total_kb=$(printf '%s\n' "$old_backups" | while IFS= read -r backup; do
    [ -n "$backup" ] && du -sk "$backup" 2>/dev/null | awk 'NR == 1 { print $1 }'
  done | awk '{ total += $1 } END { print total + 0 }')
  info "旧备份: $item_count 个，$(format_managed_storage_size "$total_kb")；每类保留最近 3 个"
  if [ "$interactive" = "yes" ] && ! confirm_yes "清理上述旧备份？不会删除最近 3 个核心程序备份和最近 3 个配置备份。" "no"; then
    info "已取消清理旧备份"
    return 0
  fi

  while IFS= read -r backup; do
    [ -n "$backup" ] && rm -f "$backup"
  done <<EOF
$old_backups
EOF
  ok "已清理旧备份；每类保留最近 3 个"
}

validate_model_catalog() {
  catalog_path=$1
  [ -f "$catalog_path" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$catalog_path" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8-sig") as handle:
        catalog = json.load(handle)
    if not isinstance(catalog, dict) or not catalog:
        raise ValueError("root")
    for group, models in catalog.items():
        if not isinstance(models, list):
            raise ValueError(group)
        seen = set()
        for model in models:
            if not isinstance(model, dict) or not isinstance(model.get("id"), str) or not model["id"].strip():
                raise ValueError(group)
            model_id = model["id"].strip()
            if model_id in seen:
                raise ValueError(model_id)
            seen.add(model_id)
except Exception:
    sys.exit(1)
PY
    return $?
  fi
  if command -v jq >/dev/null 2>&1; then
    jq -e 'type == "object" and length > 0 and all(.[]; type == "array" and all(.[]; type == "object" and (.id | type == "string" and (gsub("^\\s+|\\s+$"; "") | length) > 0)) and ([.[].id | gsub("^\\s+|\\s+$"; "")] | length) == ([.[].id | gsub("^\\s+|\\s+$"; "")] | unique | length))' "$catalog_path" >/dev/null 2>&1
    return $?
  fi
  return 1
}

install_model_catalog_file() {
  source_path=$1
  destination_path=$2
  temporary_path="$destination_path.tmp.$$"
  rm -f "$temporary_path"
  cp "$source_path" "$temporary_path" || return 1
  if ! validate_model_catalog "$temporary_path"; then
    rm -f "$temporary_path"
    return 1
  fi
  mv -f "$temporary_path" "$destination_path"
}

ensure_model_catalog() {
  install_dir=$1
  ensure_install_layout "$install_dir"
  installed_catalog=$(paths_for "$install_dir" models)
  if validate_model_catalog "$installed_catalog"; then
    printf '%s\n' "$installed_catalog"
    return 0
  fi
  repository_catalog="$PROJECT_ROOT/data/cliproxyapi-models.json"
  if validate_model_catalog "$repository_catalog" && install_model_catalog_file "$repository_catalog" "$installed_catalog"; then
    printf '%s\n' "$installed_catalog"
    return 0
  fi
  warn "没有可用的 CLIProxyAPI models.json。请联网执行安装/更新后重试。" >&2
  return 1
}

sync_model_catalog() {
  install_dir=$1
  ensure_install_layout "$install_dir"
  installed_catalog=$(paths_for "$install_dir" models)
  downloads=$(paths_for "$install_dir" downloads)
  for url in "${MODEL_CATALOG_URLS[@]}"; do
    temporary_path="$downloads/models-$$.json"
    rm -f "$temporary_path"
    if curl -fsSL --connect-timeout 10 --max-time 30 -H "User-Agent: cliproxyapi-manager" "$url" -o "$temporary_path" && validate_model_catalog "$temporary_path" && install_model_catalog_file "$temporary_path" "$installed_catalog"; then
      rm -f "$temporary_path"
      ok "模型目录已更新：$installed_catalog"
      return 0
    fi
    rm -f "$temporary_path"
    warn "模型目录源不可用，将尝试下一个源：$url"
  done
  ensure_model_catalog "$install_dir" >/dev/null 2>&1 || true
  return 0
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
  info "正在获取 $REPO 的最新发布信息"
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
printf '\n按回车关闭此窗口...'
read _unused
EOF

  chmod +x "$start_sh" "$start_command"
  ok "启动脚本已写入："
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
  service_status=$(service_status_text "$install_dir")
  was_running=0
  case "$service_status" in
    运行中*) was_running=1 ;;
  esac
  last_release_tag=$(read_state_value "lastReleaseTag" || true)
  if [ -z "$last_release_tag" ]; then
    last_release_tag="unknown-version"
  fi

  download_latest_release_json "$release_file" || return 1
  release_tag=$(release_tag_from_json "$release_file")
  asset_line=$(select_macos_asset "$release_file")
  if [ -z "$asset_line" ]; then
    warn "未找到 macOS 发布资产，请手动检查最新 release。"
    return 1
  fi

  asset_name=$(printf '%s' "$asset_line" | awk -F '\t' '{print $1}')
  asset_url=$(printf '%s' "$asset_line" | awk -F '\t' '{print $2}')
  download_path="$downloads/$asset_name"

  info "最新版本：$release_tag"
  info "正在下载：$asset_url"
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

  if [ "$was_running" -eq 1 ]; then
    info "检测到 CLIProxyAPI 正在运行，升级前先停止服务"
    stop_clip_proxy_api "$install_dir" || return 1
  fi

  if [ -f "$exe" ]; then
    backup_name=$(backup_file_name "cli-proxy-api" "" "$last_release_tag" "$timestamp")
    backup_path="$backups/$backup_name"
    if ! cp "$exe" "$backup_path"; then
      [ "$was_running" -eq 1 ] && start_clip_proxy_api "$install_dir" || true
      return 1
    fi
    info "已备份现有程序到 $backup_path"
  fi

  if ! cp "$new_binary" "$exe"; then
    [ "$was_running" -eq 1 ] && start_clip_proxy_api "$install_dir" || true
    return 1
  fi
  if ! chmod +x "$exe"; then
    [ "$was_running" -eq 1 ] && start_clip_proxy_api "$install_dir" || true
    return 1
  fi
  ok "已安装 $exe"
  write_start_scripts "$install_dir"

  info "正在检查可执行文件帮助输出"
  help_file="$downloads/help-$timestamp.txt"
  if "$exe" -h > "$help_file" 2>&1; then
    sed -n '1,20p' "$help_file"
  else
    sed -n '1,20p' "$help_file"
    warn "已安装的可执行文件未通过帮助检查"
    [ "$was_running" -eq 1 ] && start_clip_proxy_api "$install_dir" || true
    return 1
  fi

  save_state "$install_dir" "$release_tag"
  if [ "$was_running" -eq 1 ]; then
    info "升级完成，恢复启动 CLIProxyAPI"
    start_clip_proxy_api "$install_dir" || return 1
  fi
  sync_model_catalog "$install_dir"
  if ! clear_update_cache "$install_dir"; then
    warn "更新已完成，但未能清理更新下载缓存"
  fi
  if ! prune_old_managed_backups "$install_dir"; then
    warn "更新已完成，但未能清理旧备份"
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
    if ! confirm_yes "config.yaml 已存在，是否备份并覆盖？" "no"; then
      warn "保留现有 config.yaml"
      write_start_scripts "$install_dir"
      return 0
    fi
    backup_config="$backups/config-$timestamp.yaml"
    cp "$config" "$backup_config" || return 1
    info "已备份现有配置到 $backup_config"
  fi

  printf '本地端口（回车使用 8317）： '
  IFS= read -r port
  if [ -z "$port" ]; then
    port=8317
  fi
  case "$port" in
    *[!0-9]*)
      warn "端口必须是数字"
      return 1
      ;;
  esac
  if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
    warn "端口必须在 1 到 65535 之间"
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
  printf '%s\n' "$mgmt_key" > "$(paths_for "$install_dir" webui_key)"
  chmod 600 "$(paths_for "$install_dir" webui_key)" 2>/dev/null || true

  ok "配置已写入：$config"
  ok "WebUI 明文管理密钥已保存：$(paths_for "$install_dir" webui_key)"
  printf '\n管理密钥（用于 WebUI）：\n%s\n' "$mgmt_key"
  printf '\n客户端 API Key（用于 WorkBuddy）：\n%s\n\n' "$client_key"
  warn "请把这些密钥保存到本地密码管理器，不要提交或分享。"
  write_start_scripts "$install_dir"
  save_state "$install_dir" ""
}

strip_yaml_scalar() {
  value=$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  case "$value" in
    \"*\") value=${value#\"}; value=${value%\"} ;;
    \'*\') value=${value#\'}; value=${value%\'} ;;
  esac
  printf '%s' "$value"
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
        strip_yaml_scalar "$value"
        return 0
        ;;
    esac
  done < "$config"
}

yaml_section_scalar_value() {
  config=$1
  section=$2
  yaml_key=$3
  bom=$(printf '\357\273\277')
  section_prefix="$section:"
  key_prefix="$yaml_key:"
  in_section=0
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line#$bom}
    trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//')
    case "$line" in
      [![:space:]]*)
        case "$trimmed" in
          "$section_prefix") in_section=1 ;;
          *) in_section=0 ;;
        esac
        ;;
    esac
    if [ "$in_section" -eq 1 ]; then
      case "$trimmed" in
        "$key_prefix"*)
          value=${trimmed#*:}
          strip_yaml_scalar "$value"
          return 0
          ;;
      esac
    fi
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
      value=$(yaml_section_scalar_value "$config" "remote-management" "secret-key")
      ;;
    allow_remote)
      value=$(yaml_section_scalar_value "$config" "remote-management" "allow-remote" | tr '[:upper:]' '[:lower:]')
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

is_bcrypt_hash() {
  value=$1
  case "$value" in
    '$2a$'[0-9][0-9]'$'*|'$2b$'[0-9][0-9]'$'*|'$2y$'[0-9][0-9]'$'*) return 0 ;;
    *) return 1 ;;
  esac
}

webui_plain_management_key() {
  install_dir=$1
  config=$2
  key_file=$(paths_for "$install_dir" webui_key)
  config_key=$(config_value "$config" management_key "")

  if [ -f "$key_file" ]; then
    saved_key=$(sed -n '1p' "$key_file" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [ -n "$saved_key" ]; then
      printf '%s\n' "$saved_key"
      return 0
    fi
  fi

  if [ -n "$config_key" ] && ! is_bcrypt_hash "$config_key"; then
    printf '%s\n' "$config_key"
    return 0
  fi

  return 1
}

has_management_key() {
  config=$1
  if [ ! -f "$config" ]; then
    return 1
  fi
  [ -n "$(yaml_section_scalar_value "$config" "remote-management" "secret-key")" ]
}

assert_local_only_config() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  host=$(config_value "$config" host "127.0.0.1")
  allow_remote=$(config_value "$config" allow_remote "false")

  case "$host" in
    127.0.0.1|localhost|::1) ;;
    *)
      warn "不安全的配置 host：'$host'。此管理器只支持本机回环地址。"
      return 1
      ;;
  esac

  if [ "$allow_remote" = "true" ]; then
    warn "不安全的配置：remote-management.allow-remote 为 true。请先改为 false。"
    return 1
  fi
}

managed_process_state() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  pid_file=$(paths_for "$install_dir" pid_file)

  if [ ! -f "$pid_file" ]; then
    printf 'stopped|\n'
    return
  fi

  pid=$(sed -n '1p' "$pid_file" | tr -d '[:space:]')
  case "$pid" in
    ""|*[!0-9]*)
      printf 'stale|%s\n' "$pid"
      return
      ;;
  esac

  if kill -0 "$pid" 2>/dev/null; then
    process_command=$(ps -p "$pid" -o command= 2>/dev/null || true)
    case "$process_command" in
      "$exe "*)
        case "$process_command" in
          *" -config $config"|*" -config $config "*) printf 'running|%s\n' "$pid" ;;
          *) printf 'stale|%s\n' "$pid" ;;
        esac
        ;;
      *) printf 'stale|%s\n' "$pid" ;;
    esac
  else
    printf 'stale|%s\n' "$pid"
  fi
}

service_status_text() {
  install_dir=$1
  state_line=$(managed_process_state "$install_dir")
  state=${state_line%%|*}
  pid=${state_line#*|}

  case "$state" in
    running) printf '运行中 (PID %s)\n' "$pid" ;;
    stale) printf '未运行 (PID 文件已过期%s)\n' "$(test -n "$pid" && printf ': %s' "$pid" || printf '')" ;;
    *) printf '未运行\n' ;;
  esac
}

show_status_legacy_unused() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  logs=$(paths_for "$install_dir" logs)
  pid_file=$(paths_for "$install_dir" pid_file)
  host=$(config_value "$config" host "127.0.0.1")
  port=$(config_value "$config" port "8317")
  if has_management_key "$config"; then
    webui_key_status="已配置"
  else
    webui_key_status="未配置"
  fi

  printf '\n项目目录：    %s\n' "$PROJECT_ROOT"
  printf '状态文件：    %s\n' "$STATE_FILE"
  printf '安装目录：    %s\n' "$install_dir"
  printf '可执行文件：  %s [%s]\n' "$exe" "$(test -f "$exe" && printf true || printf false)"
  printf '配置文件：    %s [%s]\n' "$config" "$(test -f "$config" && printf true || printf false)"
  printf 'Host:         %s\n' "$host"
  printf '端口：        %s\n' "$port"
  printf '服务状态：    %s\n' "$(service_status_text "$install_dir")"
  printf 'PID 文件：    %s\n' "$pid_file"
  printf '日志目录：    %s\n' "$logs"
  printf 'WebUI 管理密钥：%s\n' "$webui_key_status"
}

start_clip_proxy_api() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  stdout_log=$(paths_for "$install_dir" stdout_log)
  stderr_log=$(paths_for "$install_dir" stderr_log)
  pid_file=$(paths_for "$install_dir" pid_file)

  ensure_install_layout "$install_dir"
  if [ ! -f "$exe" ]; then
    warn "未找到可执行文件，请先安装或更新。"
    return 1
  fi
  if [ ! -f "$config" ]; then
    warn "未找到 config.yaml，请先生成配置。"
    return 1
  fi
  assert_local_only_config "$install_dir" || return 1

  state_line=$(managed_process_state "$install_dir")
  if [ "${state_line%%|*}" = "running" ]; then
    ok "CLIProxyAPI 已在后台运行，PID: ${state_line#*|}"
    printf 'PID 文件：%s\n' "$pid_file"
    printf '日志目录：%s\n' "$(paths_for "$install_dir" logs)"
    return 0
  fi

  write_start_scripts "$install_dir"
  info "正在后台启动 CLIProxyAPI"
  (
    cd "$install_dir" || exit 1
    nohup "$exe" -config "$config" >"$stdout_log" 2>"$stderr_log" &
    echo $! > "$pid_file"
  )
  started_pid=$(sed -n '1p' "$pid_file" 2>/dev/null | tr -d '[:space:]')
  ok "CLIProxyAPI 已后台启动，PID: $started_pid"
  printf 'PID 文件：%s\n' "$pid_file"
  printf 'stdout 日志：%s\n' "$stdout_log"
  printf 'stderr 日志：%s\n' "$stderr_log"
}

stop_clip_proxy_api() {
  install_dir=$1
  pid_file=$(paths_for "$install_dir" pid_file)
  state_line=$(managed_process_state "$install_dir")
  state=${state_line%%|*}
  pid=${state_line#*|}

  case "$state" in
    running)
      info "正在停止 CLIProxyAPI，PID: $pid"
      kill "$pid" 2>/dev/null || true
      for _attempt in 1 2 3 4 5; do
        if kill -0 "$pid" 2>/dev/null; then
          sleep 1
        else
          rm -f "$pid_file"
          ok "CLIProxyAPI 已停止"
          return 0
        fi
      done
      warn "进程仍在运行，请稍后重试或手动检查 PID: $pid"
      return 1
      ;;
    stale)
      rm -f "$pid_file"
      ok "PID 文件已过期，已清理：$pid_file"
      ;;
    *)
      ok "CLIProxyAPI 未运行"
      ;;
  esac
}

health_check() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  host=$(config_value "$config" host "127.0.0.1")
  port=$(config_value "$config" port "8317")
  client_key=$(config_value "$config" client_key "")
  assert_local_only_config "$install_dir" || return 1

  if [ -z "$client_key" ]; then
    warn "config.yaml 中未找到 api-keys，请先运行 --config 生成配置。"
    return 1
  fi

  url="http://$host:$port/v1/models"
  info "GET $url"
  if curl -fsS -H "Authorization: Bearer $client_key" "$url" >/dev/null; then
    ok "API 可用性检查通过"
  else
    warn "API 可用性检查失败"
    return 1
  fi
}

open_webui() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  port=$(config_value "$config" port "8317")
  assert_local_only_config "$install_dir" || return 1
  url="http://localhost:$port/management.html"
  info "正在打开 $url"
  open "$url"
}

show_webui_info_legacy_unused() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)

  if [ ! -f "$config" ]; then
    warn "未找到 config.yaml，请先生成配置。"
    return 1
  fi
  assert_local_only_config "$install_dir" || return 1

  port=$(config_value "$config" port "8317")
  management_key=$(config_value "$config" management_key "")
  plain_management_key=$(webui_plain_management_key "$install_dir" "$config" || true)
  key_file=$(paths_for "$install_dir" webui_key)

  printf '\nWebUI：\n'
  printf 'http://localhost:%s/management.html\n' "$port"
  printf '\nWebUI 管理密钥：\n'
  if [ -n "$plain_management_key" ]; then
    printf '%s\n' "$plain_management_key"
  elif is_bcrypt_hash "$management_key"; then
    printf '<未找到 WebUI 明文密钥文件>\n'
  else
    printf '<未配置>\n'
  fi
  printf '\nWebUI 明文密钥文件：\n'
  if [ -f "$key_file" ]; then
    printf '%s\n' "$key_file"
  else
    printf '%s (不存在)\n' "$key_file"
  fi
  printf '\nremote-management.secret-key：\n'
  if [ -z "$management_key" ]; then
    printf '<未配置>\n'
  elif is_bcrypt_hash "$management_key"; then
    printf '<bcrypt 哈希，非 WebUI 登录明文，已隐藏>\n'
  else
    printf '%s\n' "$management_key"
  fi
}

codex_login() {
  install_dir=$1
  mode=$2
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)

  if [ ! -f "$exe" ]; then
    warn "未找到可执行文件，请先安装或更新。"
    return 1
  fi
  if [ ! -f "$config" ]; then
    warn "未找到 config.yaml，请先生成配置。"
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
    printf '客户端 API Key (wb-local-...)： '
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

  printf '\nWorkBuddy Base URL：\n'
  printf 'http://127.0.0.1:%s/v1\n' "$port"
  printf '\nWorkBuddy Chat Completions URL：\n'
  printf 'http://127.0.0.1:%s/v1/chat/completions\n' "$port"
  printf '\nWorkBuddy API Key：\n'
  if [ -n "$client_key" ]; then
    printf '%s\n' "$client_key"
  else
    printf '<从 config.yaml 的 api-keys 读取>\n'
  fi
  printf '\nWebUI：\n'
  printf 'http://localhost:%s/management.html\n' "$port"
  printf '\n请使用 /v1/models 的输出作为 Model 值。\n'
}

validate_schedule_time() {
  schedule_time=$1
  case "$schedule_time" in
    [0-9][0-9]:[0-9][0-9]) ;;
    *) return 1 ;;
  esac
  if ! printf '%s\n' "$schedule_time" | grep -Eq '^[0-9][0-9]:[0-9][0-9]$'; then
    return 1
  fi
  hour=${schedule_time%:*}
  minute=${schedule_time#*:}
  hour=$((10#$hour))
  minute=$((10#$minute))
  if [ "$hour" -gt 23 ]; then
    return 1
  fi
  if [ "$minute" -gt 59 ]; then
    return 1
  fi
  return 0
}

schedule_input_to_daily_cron() {
  schedule_input=$1
  if [ -z "$schedule_input" ]; then
    schedule_input="0 4 * * *"
  fi

  if validate_schedule_time "$schedule_input"; then
    hour=${schedule_input%:*}
    minute=${schedule_input#*:}
    hour=$((10#$hour))
    minute=$((10#$minute))
    cron_expression="$minute $hour * * *"
    printf '%s|%02d:%02d|%s|%s\n' "$cron_expression" "$hour" "$minute" "$hour" "$minute"
    return 0
  fi

  set -f
  set -- $schedule_input
  set +f
  if [ "$#" -ne 5 ]; then
    warn "请输入 HH:mm，或 5 字段 cron：0 4 * * *。"
    return 1
  fi
  if [ "$3" != "*" ] || [ "$4" != "*" ] || [ "$5" != "*" ]; then
    warn "当前只支持每日固定时间 cron：M H * * *。"
    return 1
  fi
  case "$1" in ""|*[!0-9]*)
    warn "cron 的分钟和小时必须是数字，例如 0 4 * * *。"
    return 1
    ;;
  esac
  case "$2" in ""|*[!0-9]*)
    warn "cron 的分钟和小时必须是数字，例如 0 4 * * *。"
    return 1
    ;;
  esac
  minute=$((10#$1))
  hour=$((10#$2))
  if [ "$minute" -gt 59 ] || [ "$hour" -gt 23 ]; then
    warn "cron 的分钟必须是 0-59，小时必须是 0-23。"
    return 1
  fi
  cron_expression="$minute $hour * * *"
  printf '%s|%02d:%02d|%s|%s\n' "$cron_expression" "$hour" "$minute" "$hour" "$minute"
}

read_schedule_expression_or_default() {
  printf '每日更新 cron（5 字段，回车使用 0 4 * * *；也可输入 HH:mm）： '
  IFS= read -r schedule_input
  schedule_input_to_daily_cron "$schedule_input"
}

xml_escape() {
  value=$1
  value=${value//&/&amp;}
  value=${value//</&lt;}
  value=${value//>/&gt;}
  value=${value//\"/&quot;}
  value=${value//\'/&apos;}
  printf '%s' "$value"
}

show_scheduled_update_status() {
  install_dir=$1
  plist=$(paths_for "$install_dir" launch_agent_plist)
  stdout_log=$(paths_for "$install_dir" auto_update_stdout_log)
  stderr_log=$(paths_for "$install_dir" auto_update_stderr_log)
  schedule_file=$(paths_for "$install_dir" auto_update_schedule)
  label="local.cliproxyapi.manager.autoupdate"

  print_title "定时自动更新"
  print_panel_row "Label" "$label"
  print_panel_row "plist" "$plist"
  print_panel_row "安装目录" "$install_dir"
  print_panel_row "stdout 日志" "$stdout_log"
  print_panel_row "stderr 日志" "$stderr_log"
  print_panel_row "计划文件" "$schedule_file"
  if [ -f "$schedule_file" ]; then
    cron_expression=$(sed -n 's/^cron=//p' "$schedule_file" | head -n 1)
    if [ -n "$cron_expression" ]; then
      print_panel_row "cron" "$cron_expression"
    fi
  fi
  if [ ! -f "$plist" ]; then
    print_panel_row "状态" "未开启"
    panel_divider
    return 0
  fi

  hour=$(sed -n '/<key>Hour<\/key>/{n; s/.*<integer>\([0-9][0-9]*\)<\/integer>.*/\1/p; q; }' "$plist")
  minute=$(sed -n '/<key>Minute<\/key>/{n; s/.*<integer>\([0-9][0-9]*\)<\/integer>.*/\1/p; q; }' "$plist")
  print_panel_row "状态" "已配置"
  if [ -n "$hour" ] && [ -n "$minute" ]; then
    print_panel_row "计划" "$(printf '每日 %02d:%02d' "$hour" "$minute")"
  fi
  if launchctl list "$label" >/dev/null 2>&1; then
    print_panel_row "launchctl" "已加载"
  else
    print_panel_row "launchctl" "未加载或等待下次登录加载"
  fi
  panel_divider
}

enable_scheduled_update() {
  install_dir=$1
  ensure_install_layout "$install_dir"
  schedule_line=$(read_schedule_expression_or_default) || return 1
  cron_expression=${schedule_line%%|*}
  schedule_rest=${schedule_line#*|}
  schedule_time=${schedule_rest%%|*}
  schedule_rest=${schedule_rest#*|}
  hour=${schedule_rest%%|*}
  minute=${schedule_rest#*|}
  plist=$(paths_for "$install_dir" launch_agent_plist)
  stdout_log=$(paths_for "$install_dir" auto_update_stdout_log)
  stderr_log=$(paths_for "$install_dir" auto_update_stderr_log)
  schedule_file=$(paths_for "$install_dir" auto_update_schedule)
  label="local.cliproxyapi.manager.autoupdate"
  manager="$SCRIPT_DIR/manage-cliproxyapi.sh"

  mkdir -p "$(dirname "$plist")"
  escaped_manager=$(xml_escape "$manager")
  escaped_install_dir=$(xml_escape "$install_dir")
  escaped_stdout_log=$(xml_escape "$stdout_log")
  escaped_stderr_log=$(xml_escape "$stderr_log")
  {
    printf 'cron=%s\n' "$cron_expression"
    printf 'time=%s\n' "$schedule_time"
  } > "$schedule_file"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$escaped_manager</string>
    <string>--install</string>
    <string>--install-dir</string>
    <string>$escaped_install_dir</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>$hour</integer>
    <key>Minute</key>
    <integer>$minute</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$escaped_stdout_log</string>
  <key>StandardErrorPath</key>
  <string>$escaped_stderr_log</string>
</dict>
</plist>
EOF
  launchctl unload "$plist" >/dev/null 2>&1 || true
  launchctl load "$plist"
  ok "已开启定时自动更新：$cron_expression（每日 $schedule_time）"
  printf 'LaunchAgent：%s\n' "$plist"
  printf 'stdout 日志：%s\n' "$stdout_log"
  printf 'stderr 日志：%s\n' "$stderr_log"
}

disable_scheduled_update() {
  install_dir=$1
  plist=$(paths_for "$install_dir" launch_agent_plist)
  label="local.cliproxyapi.manager.autoupdate"
  if [ -f "$plist" ]; then
    launchctl unload "$plist" >/dev/null 2>&1 || true
    rm -f "$plist"
    rm -f "$(paths_for "$install_dir" auto_update_schedule)"
    ok "已关闭定时自动更新：$label"
  else
    ok "定时自动更新未开启：$label"
  fi
}

normalize_model_id_list() {
  printf '%s\n' "$@" |
    tr ',' '\n' |
    sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
    awk 'length($0) > 0 && !seen[$0]++'
}

json_escape() {
  value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\t'/\\t}
  value=${value//$'\r'/\\r}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

is_image_generation_only_model() {
  model_id=$1
  normalized=$(printf '%s' "$model_id" | tr '[:upper:]' '[:lower:]')
  case "$normalized" in
    gpt-image-*|dall-e*|grok-imagine-image|grok-imagine-image-quality|grok-imagine-video|grok-imagine-video-1.5-preview) return 0 ;;
    *) return 1 ;;
  esac
}

model_id_in_list() {
  needle=$1
  list=$2
  while IFS= read -r item; do
    [ "$item" = "$needle" ] && return 0
  done <<EOF
$list
EOF
  return 1
}

show_model_choices() {
  available_model_ids=$1
  printf '\n可选模型：\n'
  number=1
  while IFS= read -r model_id; do
    [ -z "$model_id" ] && continue
    suffix=""
    if is_image_generation_only_model "$model_id"; then
      suffix="  (图片生成专用，跳过)"
    fi
    printf '  %s) %s%s\n' "$number" "$model_id" "$suffix"
    number=$((number + 1))
  done <<EOF
$available_model_ids
EOF
}

model_id_at_number() {
  number=$1
  available_model_ids=$2
  current=1
  while IFS= read -r model_id; do
    [ -z "$model_id" ] && continue
    if [ "$current" -eq "$number" ]; then
      printf '%s\n' "$model_id"
      return 0
    fi
    current=$((current + 1))
  done <<EOF
$available_model_ids
EOF
  return 1
}

available_model_count() {
  available_model_ids=$1
  count=0
  while IFS= read -r model_id; do
    [ -z "$model_id" ] && continue
    count=$((count + 1))
  done <<EOF
$available_model_ids
EOF
  printf '%s\n' "$count"
}

resolve_model_id_selection() {
  selection=$1
  available_model_ids=$2
  default_all=$3
  tokens=$(normalize_model_id_list "$selection")

  if [ -z "$tokens" ]; then
    if [ "$default_all" = "yes" ]; then
      printf '%s\n' "$available_model_ids"
    fi
    return 0
  fi

  resolved=""
  model_count=$(available_model_count "$available_model_ids")
  while IFS= read -r token; do
    [ -z "$token" ] && continue
    case "$token" in
      "*"|"all"|"ALL")
        resolved="${resolved}${available_model_ids}"$'\n'
        continue
        ;;
    esac

    if [[ "$token" =~ ^[0-9]+-[0-9]+$ ]]; then
      start=${token%-*}
      end=${token#*-}
      if [ "$start" -gt "$end" ]; then
        warn "无效的模型范围：$token"
        return 1
      fi
      number=$start
      while [ "$number" -le "$end" ]; do
        if [ "$number" -lt 1 ] || [ "$number" -gt "$model_count" ]; then
          warn "模型编号超出范围：$number"
          return 1
        fi
        resolved="${resolved}$(model_id_at_number "$number" "$available_model_ids")"$'\n'
        number=$((number + 1))
      done
      continue
    fi

    if [[ "$token" =~ ^[0-9]+$ ]]; then
      if [ "$token" -lt 1 ] || [ "$token" -gt "$model_count" ]; then
        warn "模型编号超出范围：$token"
        return 1
      fi
      resolved="${resolved}$(model_id_at_number "$token" "$available_model_ids")"$'\n'
      continue
    fi

    resolved="${resolved}${token}"$'\n'
  done <<EOF
$tokens
EOF

  printf '%s' "$resolved" | awk 'length($0) > 0 && !seen[$0]++'
}

models_response_ids() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.data[]?.id // empty'
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; data=json.load(sys.stdin); items=data.get("data", data if isinstance(data, list) else []); [print(x if isinstance(x, str) else x.get("id","")) for x in items if (isinstance(x, str) and x) or (isinstance(x, dict) and x.get("id"))]'
    return
  fi
  warn "未找到 jq 或 python3，无法解析 /v1/models。请使用 --model-ids 指定模型。"
  return 1
}

model_info_json_for_id() {
  model_id=$1
  if command -v jq >/dev/null 2>&1; then
    jq -c --arg model_id "$model_id" '(.data // .)[]? | select(type == "object" and .id == $model_id)' | head -n 1
    return
  fi
  if command -v python3 >/dev/null 2>&1; then
    MODEL_ID=$model_id python3 -c 'import json,os,sys; data=json.load(sys.stdin); items=data.get("data", data if isinstance(data, list) else []); target=os.environ["MODEL_ID"]; found=next((x for x in items if isinstance(x, dict) and x.get("id")==target), None); print(json.dumps(found, ensure_ascii=False, separators=(",",":")) if found else "")'
    return
  fi
  return 0
}

print_workbuddy_model_json() {
  model_id=$1
  chat_url=$2
  api_key_for_json=$3
  supports_images=$4
  model_info_json=$5
  include_token_limits=${6:-no}
  catalog_path=$7
  vendor=$8

  if ! command -v python3 >/dev/null 2>&1; then
    warn "client-config 需要 python3 来解析模型目录。" >&2
    return 1
  fi

  MODEL_ID=$model_id \
  MODEL_CHAT_URL=$chat_url \
  MODEL_API_KEY=$api_key_for_json \
  MODEL_SUPPORTS_IMAGES=$supports_images \
  MODEL_INCLUDE_TOKEN_LIMITS=$include_token_limits \
  MODEL_CATALOG_PATH=$catalog_path \
  MODEL_VENDOR=$vendor \
    python3 -c '
import json
import os
import sys

def normalized_array(value, sort_values=False):
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        return None
    result = []
    for item in value:
        normalized = item.strip().lower()
        if normalized and normalized not in result:
            result.append(normalized)
    if sort_values:
        result.sort()
    return result

def integer(value, positive=False):
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    if positive and value <= 0:
        return None
    return value

def token_value(candidate, model_id, field_name, primary_name, alias_name):
    primary = integer(candidate.get(primary_name), positive=True)
    alias = integer(candidate.get(alias_name), positive=True)
    if primary is not None and alias is not None and primary != alias:
        print(f"[WARN] {model_id} 的 {field_name} 字段别名冲突，已省略", file=sys.stderr)
        return None
    return primary if primary is not None else alias

with open(os.environ["MODEL_CATALOG_PATH"], encoding="utf-8-sig") as handle:
    catalog = json.load(handle)
model_id = os.environ["MODEL_ID"]
candidates = [model for models in catalog.values() if isinstance(models, list) for model in models if isinstance(model, dict) and isinstance(model.get("id"), str) and model["id"].strip() == model_id]
records = []
for candidate in candidates:
    record = {}
    display_name = candidate.get("display_name")
    if isinstance(display_name, str) and display_name.strip():
        record["displayName"] = display_name.strip()
    context_tokens = token_value(candidate, model_id, "contextTokens", "context_length", "inputTokenLimit")
    output_tokens = token_value(candidate, model_id, "outputTokens", "max_completion_tokens", "outputTokenLimit")
    if context_tokens is not None:
        record["contextTokens"] = context_tokens
    if output_tokens is not None:
        record["outputTokens"] = output_tokens
    parameters = normalized_array(candidate.get("supported_parameters"))
    if parameters is not None and "tools" in parameters:
        record["toolCall"] = True
    modalities = normalized_array(candidate.get("supportedInputModalities"), sort_values=True)
    if modalities is not None:
        record["inputModalities"] = modalities
        record["supportsImages"] = "image" in modalities
    thinking = candidate.get("thinking")
    if isinstance(thinking, dict):
        levels = normalized_array(thinking.get("levels"))
        minimum = integer(thinking.get("min"))
        maximum = integer(thinking.get("max"))
        valid_range = not (minimum is not None and maximum is not None and minimum > maximum)
        if valid_range and ((levels is not None and len(levels) > 0) or minimum is not None or maximum is not None):
            record["reasoningSupported"] = True
            if levels:
                record["reasoningLevels"] = levels
    records.append(record)

def merge(field):
    values = []
    keys = []
    for record in records:
        if field not in record:
            continue
        key = json.dumps(record[field], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        if key not in keys:
            keys.append(key)
            values.append(record[field])
    if len(values) > 1:
        print(f"[WARN] {model_id} 的 {field} 字段在模型目录中冲突，已省略", file=sys.stderr)
        return None
    return values[0] if values else None

info = {field: merge(field) for field in ("displayName", "contextTokens", "outputTokens", "toolCall", "supportsImages", "reasoningSupported", "reasoningLevels")}
if not candidates:
    print(f"[WARN] {model_id} 不在本地模型目录中，仅输出基础连接字段", file=sys.stderr)

explicit_supports_images = os.environ["MODEL_SUPPORTS_IMAGES"] == "true"
entry = {
    "id": model_id,
    "name": info.get("displayName") or model_id,
    "vendor": os.environ.get("MODEL_VENDOR") or "CLIProxyAPI",
    "url": os.environ["MODEL_CHAT_URL"],
    "apiKey": os.environ["MODEL_API_KEY"],
}
if info.get("toolCall") is True:
    entry["supportsToolCall"] = True
if explicit_supports_images:
    entry["supportsImages"] = True
elif info.get("supportsImages") is not None:
    entry["supportsImages"] = bool(info["supportsImages"])
if info.get("reasoningSupported") is True:
    entry["supportsReasoning"] = True
    allowed = ("low", "medium", "high", "xhigh")
    efforts = [level for level in (info.get("reasoningLevels") or []) if level in allowed]
    if efforts:
        entry["reasoning"] = {"supportedEfforts": efforts}
if os.environ.get("MODEL_INCLUDE_TOKEN_LIMITS") == "yes":
    if info.get("contextTokens") is not None:
        entry["maxInputTokens"] = info["contextTokens"]
    if info.get("outputTokens") is not None:
        entry["maxOutputTokens"] = info["outputTokens"]

text = json.dumps(entry, ensure_ascii=False, indent=6)
sys.stdout.write("\n".join("    " + line for line in text.splitlines()))
'
}

show_workbuddy_models_json() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  host=$(config_value "$config" host "127.0.0.1")
  port=$(config_value "$config" port "8317")
  client_key=$(config_value "$config" client_key "")
  assert_local_only_config "$install_dir" || return 1
  catalog_path=$(ensure_model_catalog "$install_dir") || return 1
  if ! command -v python3 >/dev/null 2>&1; then
    warn "client-config 需要 python3 来解析模型目录。" >&2
    return 1
  fi
  vendor=${CLIENT_CONFIG_VENDOR:-CLIProxyAPI}
  [ -n "$vendor" ] || vendor="CLIProxyAPI"

  model_ids=$(normalize_model_id_list "$WORKBUDDY_MODEL_IDS")
  include_token_limits=$WORKBUDDY_INCLUDE_TOKEN_LIMITS
  available_model_ids=""
  models_response_json=""
  prompted_model_ids=no
  if [ -z "$model_ids" ]; then
    if [ -z "$client_key" ]; then
      printf '客户端 API Key（用于读取 /v1/models）： '
      IFS= read -r client_key
    fi
    url="http://$host:$port/v1/models"
    models_response_json=$(curl -fsS -H "Authorization: Bearer $client_key" "$url") || return 1
    available_model_ids=$(printf '%s' "$models_response_json" | models_response_ids) || return 1
    if [ -z "$available_model_ids" ]; then
      warn "/v1/models 没有返回可用模型。"
      return 1
    fi
    show_model_choices "$available_model_ids"
    printf '选择模型（编号/范围/ID，逗号分隔；留空=全部）： '
    IFS= read -r input_model_ids
    model_ids=$(resolve_model_id_selection "$input_model_ids" "$available_model_ids" "yes") || return 1
    if confirm_yes "输出 maxInputTokens/maxOutputTokens？" "no"; then
      include_token_limits=yes
    else
      include_token_limits=no
    fi
    prompted_model_ids=yes
  fi

  if [ -z "$model_ids" ]; then
    warn "没有可输出的模型 ID。请先查询 /v1/models，或使用 --model-ids 指定。"
    return 1
  fi

  image_model_ids=$(normalize_model_id_list "$WORKBUDDY_IMAGE_MODEL_IDS")
  if [ "$prompted_model_ids" = "yes" ] && [ -n "$image_model_ids" ]; then
    image_model_ids=$(resolve_model_id_selection "$WORKBUDDY_IMAGE_MODEL_IDS" "$available_model_ids" "no") || return 1
  fi

  api_key_for_json=$client_key
  if [ -z "$api_key_for_json" ]; then
    printf 'WorkBuddy API Key（留空使用占位符）： '
    IFS= read -r api_key_for_json
  fi
  if [ -z "$api_key_for_json" ]; then
    api_key_for_json="<从 config.yaml 的 api-keys 读取>"
  fi

  all_image_models=no
  if model_id_in_list "*" "$image_model_ids" || model_id_in_list "all" "$image_model_ids"; then
    all_image_models=yes
  fi

  chat_url="http://127.0.0.1:$port/v1/chat/completions"
  output_count=0
  rendered_models=""
  separator=""
  while IFS= read -r model_id; do
    [ -z "$model_id" ] && continue
    if is_image_generation_only_model "$model_id"; then
      warn "跳过 $model_id：这是图片生成/编辑专用模型，不适合作为 WorkBuddy 聊天模型。" >&2
      continue
    fi
    supports_images=false
    if [ "$all_image_models" = "yes" ] || model_id_in_list "$model_id" "$image_model_ids"; then
      supports_images=true
    fi
    model_info_json=""
    if [ -n "$models_response_json" ]; then
      model_info_json=$(printf '%s' "$models_response_json" | model_info_json_for_id "$model_id")
    fi
    rendered_model=$(print_workbuddy_model_json "$model_id" "$chat_url" "$api_key_for_json" "$supports_images" "$model_info_json" "$include_token_limits" "$catalog_path" "$vendor") || return 1
    rendered_models="${rendered_models}${separator}${rendered_model}"
    separator=',
'
    output_count=$((output_count + 1))
  done <<EOF
$model_ids
EOF
  if [ "$output_count" -eq 0 ]; then
    warn "没有可输出的 WorkBuddy 聊天模型。gpt-image-* 只能走 /v1/images/generations 或 /v1/images/edits。"
    return 1
  fi
  printf '{\n'
  printf '  "models": [\n%s\n' "$rendered_models"
  printf '  ]\n'
  printf '}\n'
}

show_client_config() {
  install_dir=$1
  format=$(printf '%s' "${CLIENT_CONFIG_FORMAT:-workbuddy}" | tr '[:upper:]' '[:lower:]')
  case "$format" in
    workbuddy) show_workbuddy_models_json "$install_dir" ;;
    *)
      warn "不支持的客户端配置格式: $format。当前支持: workbuddy" >&2
      return 1
      ;;
  esac
}

run_action() {
  action=$1
  install_dir=$2
  case "$action" in
    status) show_status "$install_dir" ;;
    install) install_or_update "$install_dir" ;;
    config) generate_config "$install_dir" ;;
    start) start_clip_proxy_api "$install_dir" ;;
    stop) stop_clip_proxy_api "$install_dir" ;;
    health) health_check "$install_dir" ;;
    webui) open_webui "$install_dir" ;;
    webui-info) show_webui_info "$install_dir" ;;
    oauth) codex_login "$install_dir" browser ;;
    device-login) codex_login "$install_dir" device ;;
    models) query_models "$install_dir" ;;
    workbuddy) show_workbuddy_info "$install_dir" ;;
    client-config) show_client_config "$install_dir" ;;
    workbuddy-json)
      warn "workbuddy-json 已弃用；请改用 --client-config --format workbuddy" >&2
      CLIENT_CONFIG_FORMAT=workbuddy show_client_config "$install_dir"
      ;;
    schedule-status) show_scheduled_update_status "$install_dir" ;;
    schedule-enable) enable_scheduled_update "$install_dir" ;;
    schedule-disable) disable_scheduled_update "$install_dir" ;;
    cleanup)
      clear_update_cache "$install_dir" || return 1
      prune_old_managed_backups "$install_dir"
      ;;
    *) warn "未知操作：$action"; return 1 ;;
  esac
}

short_install_path() {
  path=$1
  case "$path" in
    "$HOME") path="~" ;;
    "$HOME"/*) path="~/${path#"$HOME"/}" ;;
  esac
  if [ "${#path}" -gt 72 ]; then
    printf '.../%s\n' "$(basename "$path")"
  else
    printf '%s\n' "$path"
  fi
}

menu_summary() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  port=$(config_value "$config" port "8317")
  service_text=$(service_status_text "$install_dir")

  if [ -f "$exe" ]; then
    exe_status="已安装"
  else
    exe_status="未安装"
  fi
  if [ -f "$config" ]; then
    config_status="已配置"
  else
    config_status="未配置"
  fi

  printf '服务：%s | 程序：%s | 配置：%s | WebUI：http://localhost:%s/management.html\n' "$service_text" "$exe_status" "$config_status" "$port"
}

show_menu_legacy_unused() {
  install_dir=$1
  while :; do
    short_path=$(short_install_path "$install_dir")
    summary=$(menu_summary "$install_dir")
    printf '\nCLIProxyAPI 本地管理器\n'
    printf '目录：%s\n' "$short_path"
    printf '摘要：%s\n\n' "$summary"
    printf '[安装配置]\n'
    printf '1. 安装或更新 CLIProxyAPI\n'
    printf '2. 生成本地 config.yaml\n\n'
    printf '[服务运行]\n'
    printf '3. 启动服务\n'
    printf '4. 停止服务\n'
    printf '5. 运行状态\n\n'
    printf '[WebUI]\n'
    printf '6. WebUI 信息\n'
    printf '7. 打开 WebUI\n\n'
    printf '[登录]\n'
    printf '8. Codex 浏览器 OAuth 登录\n'
    printf '9. Codex 设备码登录\n\n'
    printf '[检查集成]\n'
    printf '10. 健康检查\n'
    printf '11. 模型列表\n'
    printf '12. WorkBuddy 信息\n\n'
    printf '[设置]\n'
    printf 'D. 更改安装目录\n'
    printf 'Q. 退出\n'
    printf '请选择： '
    if ! IFS= read -r choice; then
      return 0
    fi

    case "$choice" in
      1) install_or_update "$install_dir" ;;
      2) generate_config "$install_dir" ;;
      3) start_clip_proxy_api "$install_dir" ;;
      4) stop_clip_proxy_api "$install_dir" ;;
      5) show_status "$install_dir" ;;
      6) show_webui_info "$install_dir" ;;
      7) open_webui "$install_dir" ;;
      8) codex_login "$install_dir" browser ;;
      9) codex_login "$install_dir" device ;;
      10) health_check "$install_dir" ;;
      11) query_models "$install_dir" ;;
      12) show_workbuddy_info "$install_dir" ;;
      D|d) install_dir=$(select_install_dir); save_state "$install_dir" "" ;;
      Q|q|0) return 0 ;;
      *) warn "未知选项：$choice" ;;
    esac
  done
}

service_status_label() {
  install_dir=$1
  state_line=$(managed_process_state "$install_dir")
  state=${state_line%%|*}
  pid=${state_line#*|}

  case "$state" in
    running) printf '运行中 (PID %s)\n' "$pid" ;;
    stale)
      if [ -n "$pid" ]; then
        printf '未运行 (PID 文件已过期: %s)\n' "$pid"
      else
        printf '未运行 (PID 文件已过期)\n'
      fi
      ;;
    *) printf '未运行\n' ;;
  esac
}

remote_management_secret_key_fast() {
  config=$1
  if [ ! -f "$config" ]; then
    return 1
  fi
  raw_value=$(awk '
    /^[^[:space:]]/ {
      in_remote = ($0 ~ /^remote-management:[[:space:]]*$/)
    }
    in_remote && /^[[:space:]]*secret-key:[[:space:]]*/ {
      sub(/^[[:space:]]*secret-key:[[:space:]]*/, "", $0)
      print
      exit
    }
  ' "$config")
  if [ -n "$raw_value" ]; then
    strip_yaml_scalar "$raw_value"
  fi
}

webui_key_status_text() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  key_file=$(paths_for "$install_dir" webui_key)
  management_key=$(remote_management_secret_key_fast "$config" || true)

  if [ -f "$key_file" ] && [ -s "$key_file" ]; then
    printf '明文可用\n'
  elif [ -z "$management_key" ]; then
    printf '未配置\n'
  elif is_bcrypt_hash "$management_key"; then
    printf '未找到明文文件\n'
  else
    printf '已配置\n'
  fi
}

show_status() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  logs=$(paths_for "$install_dir" logs)
  pid_file=$(paths_for "$install_dir" pid_file)
  host=$(config_value "$config" host "127.0.0.1")
  port=$(config_value "$config" port "8317")

  print_title "CLIProxyAPI 状态"
  print_panel_section "本机状态"
  print_panel_row "项目根目录" "$PROJECT_ROOT"
  print_panel_row "状态文件" "$STATE_FILE"
  print_panel_row "安装目录" "$install_dir"
  print_panel_row "程序" "$exe [$(test -f "$exe" && printf true || printf false)]"
  print_panel_row "配置" "$config [$(test -f "$config" && printf true || printf false)]"
  print_panel_row "服务" "$(service_status_label "$install_dir")"
  print_panel_row "Host" "$host"
  print_panel_row "端口" "$port"
  print_panel_row "API" "http://127.0.0.1:$port/v1"
  print_panel_row "WebUI" "http://localhost:$port/management.html"
  print_panel_row "WebUI 密钥" "$(webui_key_status_text "$install_dir")"
  print_panel_row "PID 文件" "$pid_file"
  print_panel_row "日志目录" "$logs"
  panel_divider
}

show_webui_info() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)

  if [ ! -f "$config" ]; then
    warn "未找到 config.yaml，请先生成配置。"
    return 1
  fi
  assert_local_only_config "$install_dir" || return 1

  port=$(config_value "$config" port "8317")
  management_key=$(config_value "$config" management_key "")
  plain_management_key=$(webui_plain_management_key "$install_dir" "$config" || true)
  key_file=$(paths_for "$install_dir" webui_key)

  print_title "WebUI 信息"
  print_panel_section "访问入口"
  print_panel_row "WebUI" "http://localhost:$port/management.html"
  print_panel_row "config.yaml" "$config"
  print_panel_section "管理密钥"
  if [ -n "$plain_management_key" ]; then
    print_panel_row "WebUI 管理密钥" "$plain_management_key"
  elif is_bcrypt_hash "$management_key"; then
    print_panel_row "WebUI 管理密钥" "<未找到 WebUI 明文密钥文件>"
  else
    print_panel_row "WebUI 管理密钥" "<未配置>"
  fi

  if [ -f "$key_file" ]; then
    print_panel_row "明文密钥文件" "$key_file"
  else
    print_panel_row "明文密钥文件" "<未找到>"
  fi

  if [ -z "$management_key" ]; then
    print_panel_row "remote-management.secret-key" "<未配置>"
  elif is_bcrypt_hash "$management_key"; then
    print_panel_row "remote-management.secret-key" "<bcrypt 哈希，已隐藏>"
  else
    print_panel_row "remote-management.secret-key" "$management_key"
  fi
  panel_divider
}

show_menu() {
  install_dir=$1
  while :; do
    exe=$(paths_for "$install_dir" exe)
    config=$(paths_for "$install_dir" config)
    port=$(config_value "$config" port "8317")
    if [ -f "$exe" ]; then
      exe_status="已安装"
    else
      exe_status="未安装"
    fi
    if [ -f "$config" ]; then
      config_status="已配置"
    else
      config_status="未配置"
    fi

    print_title "CLIProxyAPI 本地管理器"
    print_panel_section "本机状态"
    print_panel_row "短路径" "$(short_install_path "$install_dir")"
    print_panel_row "安装目录" "$install_dir"
    print_panel_row "程序" "$exe_status"
    print_panel_row "配置" "$config_status"
    print_panel_row "服务" "$(service_status_label "$install_dir")"
    print_panel_row "API" "http://127.0.0.1:$port/v1"
    print_panel_row "WebUI" "http://localhost:$port/management.html"
    print_panel_row "WebUI 密钥" "$(webui_key_status_text "$install_dir")"

    print_menu_section "安装配置"
    print_menu_pair "1)" "安装或更新 CLIProxyAPI" "2)" "生成本地 config.yaml"
    print_menu_section "服务运行"
    print_menu_pair "3)" "启动服务" "4)" "停止服务"
    print_menu_item "5)" "运行状态"
    print_menu_section "WebUI"
    print_menu_pair "6)" "WebUI 信息" "7)" "打开 WebUI"
    print_menu_section "登录"
    print_menu_pair "8)" "Codex 浏览器 OAuth 登录" "9)" "Codex 设备码登录"
    print_menu_section "检查集成"
    print_menu_pair "10)" "健康检查" "11)" "模型列表"
    print_menu_pair "12)" "WorkBuddy 信息" "13)" "客户端模型配置"
    print_menu_section "自动更新"
    print_menu_pair "14)" "查看定时更新" "15)" "开启/修改定时更新"
    print_menu_item "16)" "关闭定时更新"
    print_menu_section "存储清理"
    print_menu_item "17)" "清理下载缓存和旧备份"
    print_menu_section "设置"
    print_menu_pair "D)" "更改安装目录" "Q/0)" "退出"
    panel_divider
    printf '请选择操作 [0-17/D]: '
    if ! IFS= read -r choice; then
      return 0
    fi

    case "$choice" in
      1) install_or_update "$install_dir" ;;
      2) generate_config "$install_dir" ;;
      3) start_clip_proxy_api "$install_dir" ;;
      4) stop_clip_proxy_api "$install_dir" ;;
      5) show_status "$install_dir" ;;
      6) show_webui_info "$install_dir" ;;
      7) open_webui "$install_dir" ;;
      8) codex_login "$install_dir" browser ;;
      9) codex_login "$install_dir" device ;;
      10) health_check "$install_dir" ;;
      11) query_models "$install_dir" ;;
      12) show_workbuddy_info "$install_dir" ;;
      13)
        printf 'Vendor（回车使用 CLIProxyAPI）： ' >&2
        IFS= read -r CLIENT_CONFIG_VENDOR
        [ -n "$CLIENT_CONFIG_VENDOR" ] || CLIENT_CONFIG_VENDOR="CLIProxyAPI"
        CLIENT_CONFIG_FORMAT=workbuddy show_client_config "$install_dir"
        ;;
      14) show_scheduled_update_status "$install_dir" ;;
      15) enable_scheduled_update "$install_dir" ;;
      16) disable_scheduled_update "$install_dir" ;;
      17)
        if clear_update_cache "$install_dir" yes; then
          prune_old_managed_backups "$install_dir" yes
        fi
        ;;
      D|d) install_dir=$(select_install_dir); save_state "$install_dir" "" ;;
      Q|q|0) return 0 ;;
      *) warn "未知选项: $choice" ;;
    esac
  done
}

ACTION="menu"
REQUESTED_INSTALL_DIR=""
CLIENT_CONFIG_FORMAT="workbuddy"
CLIENT_CONFIG_VENDOR="CLIProxyAPI"
WORKBUDDY_MODEL_IDS=""
WORKBUDDY_IMAGE_MODEL_IDS=""
WORKBUDDY_INCLUDE_TOKEN_LIMITS=no
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --status) ACTION="status" ;;
    --install) ACTION="install" ;;
    --config) ACTION="config" ;;
    --start) ACTION="start" ;;
    --stop) ACTION="stop" ;;
    --health) ACTION="health" ;;
    --webui) ACTION="webui" ;;
    --webui-info) ACTION="webui-info" ;;
    --oauth) ACTION="oauth" ;;
    --device-login) ACTION="device-login" ;;
    --models) ACTION="models" ;;
    --workbuddy) ACTION="workbuddy" ;;
    --client-config) ACTION="client-config" ;;
    --workbuddy-json) ACTION="workbuddy-json" ;;
    --schedule-status) ACTION="schedule-status" ;;
    --schedule-enable) ACTION="schedule-enable" ;;
    --schedule-disable) ACTION="schedule-disable" ;;
    --cleanup) ACTION="cleanup" ;;
    --include-token-limits) WORKBUDDY_INCLUDE_TOKEN_LIMITS=yes ;;
    --format)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        warn "--format 需要格式参数"
        exit 1
      fi
      CLIENT_CONFIG_FORMAT=$1
      ;;
    --vendor)
      shift
      if [ "$#" -eq 0 ]; then
        warn "--vendor 需要名称参数"
        exit 1
      fi
      CLIENT_CONFIG_VENDOR=$1
      ;;
    --model-ids)
      shift
      if [ "$#" -eq 0 ]; then
        warn "--model-ids 需要模型 ID 参数"
        exit 1
      fi
      WORKBUDDY_MODEL_IDS=$1
      ;;
    --image-model-ids)
      shift
      if [ "$#" -eq 0 ]; then
        warn "--image-model-ids 需要模型 ID 参数"
        exit 1
      fi
      WORKBUDDY_IMAGE_MODEL_IDS=$1
      ;;
    --install-dir)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        warn "--install-dir 需要路径参数"
        exit 1
      fi
      case "$1" in
        -*)
          warn "--install-dir 需要路径参数"
          exit 1
          ;;
      esac
      REQUESTED_INSTALL_DIR=$1
      ;;
    "")
      ;;
    *)
      warn "未知参数：$1"
      show_help
      exit 1
      ;;
  esac
  shift
done

if [ "$ACTION" = "menu" ]; then
  INSTALL_DIR=$(resolve_install_dir "$REQUESTED_INSTALL_DIR" "yes")
else
  INSTALL_DIR=$(resolve_install_dir "$REQUESTED_INSTALL_DIR" "no")
fi
if [ "$ACTION" = "menu" ]; then
  show_menu "$INSTALL_DIR"
else
  run_action "$ACTION" "$INSTALL_DIR"
fi
