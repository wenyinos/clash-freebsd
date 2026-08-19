#!/usr/bin/env bash
# 注意：此文件被其他脚本 source，不设置 set -e 以避免影响调用方的错误处理策略
set -u  # 未定义变量报错

# shellcheck source=scripts/core/common.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/common.sh"
# shellcheck source=scripts/core/config.sh
source "${PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}/scripts/core/config.sh"

resolve_yq() {
  local arch os version file extracted_bin url tmp_dir tmp_file checksum_key

  arch="$(get_arch)"
  os="$(get_os)"
  version="${YQ_VERSION:-$DEFAULT_YQ_VERSION}"

  if [ -x "$(yq_bin)" ]; then
    return 0
  fi

  case "$os:$arch" in
    linux:amd64)
      file="yq_linux_amd64.tar.gz"
      extracted_bin="yq_linux_amd64"
      ;;
    linux:arm64)
      file="yq_linux_arm64.tar.gz"
      extracted_bin="yq_linux_arm64"
      ;;
    linux:armv7)
      file="yq_linux_arm.tar.gz"
      extracted_bin="yq_linux_arm"
      ;;
    freebsd:amd64)
      file="yq_freebsd_amd64.tar.gz"
      extracted_bin="yq_freebsd_amd64"
      ;;
    freebsd:arm64)
      file="yq_freebsd_arm64.tar.gz"
      extracted_bin="yq_freebsd_arm64"
      ;;
    *)
      die "暂不支持的 yq 目标：${os}/${arch}"
      ;;
  esac

  url="https://github.com/mikefarah/yq/releases/download/${version}/${file}"
  checksum_key="YQ_${version}_${os}_${arch}"
  tmp_dir="$(mktemp -d)"
  tmp_file="$tmp_dir/$file"

  trap 'rm -rf "'"${tmp_dir}"'" 2>/dev/null || true' EXIT

  if ! copy_bundled_asset "yq" "$version" "$file" "$tmp_file" "yq"; then
    download_file "$url" "$tmp_file" "yq" "$checksum_key"
  fi
  tar -xzf "$tmp_file" -C "$tmp_dir"

  if [ -f "$tmp_dir/$extracted_bin" ]; then
    install -m 0755 "$tmp_dir/$extracted_bin" "$(yq_bin)"
  elif [ -f "$tmp_dir/yq" ]; then
    install -m 0755 "$tmp_dir/yq" "$(yq_bin)"
  else
    rm -rf "$tmp_dir"
    die "解压后未找到 yq 可执行文件"
  fi

  rm -rf "$tmp_dir"
  trap - EXIT
}

resolve_mihomo() {
  # 检测旧版手动下载（GitHub）残留的 mihomo 二进制，提示卸载
  if [ -f "$BIN_DIR/mihomo" ]; then
    ui_warn "检测到旧版手动下载的 mihomo 二进制：$BIN_DIR/mihomo（新版已改为 pkg 管理）"
    ui_warn "请删除该文件，避免与 pkg 安装的 mihomo 混淆：rm -f \"$BIN_DIR/mihomo\""
  fi

  if [ -x "$(mihomo_bin)" ]; then
    return 0
  fi

  if ! is_root_user; then
    die_state "FreeBSD 通过 pkg 安装 mihomo 需要 root 权限" \
              "请通过 root 用户或 sudo 重新运行（或手动执行：pkg install -y mihomo）"
  fi

  info "FreeBSD 使用 pkg 安装 mihomo（版本以 pkg 仓库为准）"
  pkg install -y mihomo || die_state "pkg install mihomo 失败" \
            "请检查 pkg 源配置与网络（可先执行 pkg update）"
  [ -x "$(mihomo_bin)" ] || die "pkg 安装后 mihomo 仍不可执行：$(mihomo_bin)"
}

resolve_clash() {
  local arch os version version_no_v url_base tmp_file url downloaded="false"
  local candidates file

  arch="$(get_arch)"
  os="$(get_os)"
  version="${CLASH_VERSION:-$DEFAULT_CLASH_VERSION}"
  version_no_v="${version#v}"
  url_base="${CLASH_DOWNLOAD_BASE:-https://github.com/WindSpiritSR/clash/releases/download}"

  if [ "$os" = "freebsd" ]; then
    die_state "FreeBSD 当前仅支持 mihomo 内核，clash 内核自动安装不可用" \
              "请设置 KERNEL_TYPE=mihomo 后重新执行（例如：export KERNEL_TYPE=mihomo）"
  fi

  if [ -x "$(clash_bin)" ] \
    && [ "$(read_runtime_value "KERNEL_TYPE_INSTALLED" 2>/dev/null || true)" = "clash" ] \
    && [ "$(read_runtime_value "CLASH_VERSION_INSTALLED" 2>/dev/null || true)" = "$version" ]; then
    return 0
  fi

  case "$arch" in
    amd64)
      candidates="
clash-linux-amd64-${version}.gz
clash-linux-amd64-v${version_no_v}.gz
"
      ;;
    arm64)
      candidates="
clash-linux-arm64-${version}.gz
clash-linux-arm64-v${version_no_v}.gz
clash-linux-armv8-${version}.gz
clash-linux-armv8-v${version_no_v}.gz
"
      ;;
    armv7)
      candidates="
clash-linux-armv7-${version}.gz
clash-linux-armv7-v${version_no_v}.gz
"
      ;;
    *)
      die "暂不支持的 Clash 架构：$arch"
      ;;
  esac

  tmp_file="$(mktemp)"
  rm -f "$tmp_file"

  for file in $candidates; do
    url="${url_base}/${version}/${file}"

    if download_file "$url" "$tmp_file" "clash"; then
      downloaded="true"
      break
    fi
  done

  [ "$downloaded" = "true" ] || {
    rm -f "$tmp_file"
    die "Clash 内核下载失败，请检查版本或在 .env 中覆盖 CLASH_DOWNLOAD_BASE / CLASH_VERSION"
  }

  gzip -dc "$tmp_file" > "$(clash_bin)"
  chmod +x "$(clash_bin)"
  rm -f "$tmp_file"

  write_runtime_value "KERNEL_TYPE_INSTALLED" "clash"
  write_runtime_value "CLASH_VERSION_INSTALLED" "$version"
}

resolve_runtime_kernel() {
  case "$(runtime_kernel_type)" in
    mihomo)
      resolve_mihomo
      write_runtime_value "KERNEL_TYPE_INSTALLED" "mihomo"
      write_runtime_value "MIHOMO_VERSION_INSTALLED" "pkg-managed"
      ;;
    clash)
      resolve_clash
      ;;
    *)
      die "未知内核类型：$(runtime_kernel_type)"
      ;;
  esac
}


ensure_runtime_config_ready() {
  local config_file last_file now reason

  config_file="$RUNTIME_DIR/config.yaml"
  last_file="$RUNTIME_DIR/config.last.yaml"

  if [ -s "$config_file" ] && test_runtime_config "$config_file" >/dev/null 2>&1; then
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_USED" "false"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_TIME" ""
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_REASON" ""
    write_runtime_event_value "RUNTIME_LAST_RISK_LEVEL" "$(calculate_runtime_risk_level)"
    mark_runtime_config_source "runtime"
    return 0
  fi

  reason="当前运行配置不可用"
  warn "当前运行配置不可用，尝试回退到上一次成功配置"

  [ -s "$last_file" ] || die "当前配置不可用，且不存在可回退的最后成功配置：$last_file"

  if test_runtime_config "$last_file" >/dev/null 2>&1; then
    cp -f "$last_file" "$config_file"
    now="$(now_datetime)"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_USED" "true"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_TIME" "$now"
    write_runtime_event_value "RUNTIME_LAST_FALLBACK_REASON" "$reason"
    write_runtime_event_value "RUNTIME_LAST_RISK_LEVEL" "$(calculate_runtime_risk_level)"
    mark_runtime_config_source "last_good"
    success "已回退到最后成功配置"
    return 0
  fi

  die "最后成功配置也不可用：$last_file"
}

tun_public_ip_without_proxy_env() {
  local ip route_dev

  route_dev="$(default_route_dev 2>/dev/null || true)"
  if [ -n "${route_dev:-}" ] && ! printf '%s\n' "$route_dev" | grep -Eiq '(tun|utun|mihomo|clash|meta)'; then
    ip="$(
      env \
        -u http_proxy \
        -u https_proxy \
        -u HTTP_PROXY \
        -u HTTPS_PROXY \
        -u all_proxy \
        -u ALL_PROXY \
        curl --interface "$route_dev" -fsSL --connect-timeout 3 --max-time 6 https://ip.sb 2>/dev/null \
        | head -n 1 \
        | tr -d '\r' \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    )"

    if [ -n "${ip:-}" ]; then
      echo "$ip"
      return 0
    fi
  fi

  env \
    -u http_proxy \
    -u https_proxy \
    -u HTTP_PROXY \
    -u HTTPS_PROXY \
    -u all_proxy \
    -u ALL_PROXY \
    curl -fsSL --connect-timeout 3 --max-time 6 https://ip.sb 2>/dev/null \
    | head -n 1 \
    | tr -d '\r' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

tun_public_ip_with_current_route() {
  env \
    -u http_proxy \
    -u https_proxy \
    -u HTTP_PROXY \
    -u HTTPS_PROXY \
    -u all_proxy \
    -u ALL_PROXY \
    curl -fsSL --connect-timeout 3 --max-time 6 https://ip.sb 2>/dev/null \
    | head -n 1 \
    | tr -d '\r' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

tun_traffic_effective_check() {
  local host_ip current_ip

  host_ip="$(tun_public_ip_without_proxy_env 2>/dev/null || true)"
  current_ip="$(tun_public_ip_with_current_route 2>/dev/null || true)"

  if [ -z "${host_ip:-}" ]; then
    echo "host-ip-unavailable"
    return 1
  fi

  if [ -z "${current_ip:-}" ]; then
    echo "current-ip-unavailable"
    return 1
  fi

  if [ "$current_ip" != "$host_ip" ]; then
    echo "ok"
    return 0
  fi

  echo "traffic-same-as-host"
  return 1
}

tun_effective_check() {
  local config_tun_enabled controller_ok traffic_result

  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || true)"

  if [ "$(tun_enabled)" != "true" ]; then
    echo "disabled-in-state"
    return 1
  fi

  if [ "${config_tun_enabled:-false}" != "true" ]; then
    echo "disabled-in-runtime-config"
    return 1
  fi

  if ! status_is_running 2>/dev/null; then
    echo "runtime-not-running"
    return 1
  fi

  controller_ok="false"
  if proxy_controller_reachable 2>/dev/null; then
    controller_ok="true"
  fi

  if [ "$controller_ok" != "true" ]; then
    echo "controller-unreachable"
    return 1
  fi

  traffic_result="$(tun_traffic_effective_check 2>/dev/null || true)"
  [ -n "${traffic_result:-}" ] || traffic_result="traffic-unknown"

  if [ "$traffic_result" = "ok" ]; then
    echo "ok"
    return 0
  fi

  echo "$traffic_result"
  return 1
}

tun_disable_check() {
  local config_tun_enabled

  config_tun_enabled="$(runtime_config_tun_enabled 2>/dev/null || true)"

  if [ "$(tun_enabled)" = "true" ]; then
    echo "state-still-enabled"
    return 1
  fi

  if [ "${config_tun_enabled:-false}" = "true" ]; then
    echo "runtime-config-still-enabled"
    return 1
  fi

  if status_is_running 2>/dev/null; then
    if ! proxy_controller_reachable 2>/dev/null; then
      echo "runtime-restarted-but-controller-unreachable"
      return 1
    fi
  fi

  echo "ok"
  return 0
}

wait_runtime_controller_ready() {
  local max_try="${1:-8}"
  local i=0

  while [ "$i" -lt "$max_try" ]; do
    if proxy_controller_reachable 2>/dev/null; then
      return 0
    fi

    sleep 1
    i=$((i + 1))
  done

  return 1
}

start_runtime() {
  local config_file="$RUNTIME_DIR/config.yaml"

  resolve_runtime_kernel
  if [ -s "$config_file" ]; then
    ensure_mihomo_geodata_ready "$config_file" || die "因 GEOIP 依赖未就绪，当前配置无法启动：$config_file"
  fi

  ensure_runtime_config_ready
  ensure_mihomo_geodata_ready "$config_file" || die "因 GEOIP 依赖未就绪，当前配置无法启动：$config_file"

  if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
    local old_pid
    old_pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${old_pid:-}" ] && kill -0 "$old_pid" 2>/dev/null; then
      if proxy_controller_reachable 2>/dev/null; then
        warn "Mihomo 已在运行：pid=$old_pid"
        return 0
      fi

      warn "Mihomo 进程仍在运行但控制器不可访问，正在重启以加载当前配置"
      stop_runtime || true
    else
      rm -f "$RUNTIME_DIR/mihomo.pid"
    fi
  fi

  nohup "$(runtime_kernel_bin)" -f "$config_file" -d "$RUNTIME_DIR" \
    > "$LOG_DIR/mihomo.out.log" 2>&1 &

  echo $! > "$RUNTIME_DIR/mihomo.pid"

  if ! wait_runtime_controller_ready 8; then
    warn "$(runtime_kernel_name) 已启动，但控制器未在预期时间内可访问"
    local new_pid
    new_pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    [ -n "${new_pid:-}" ] && kill -0 "$new_pid" 2>/dev/null || return 1
  fi

  success "$(runtime_kernel_name) 已启动：pid=$(cat "$RUNTIME_DIR/mihomo.pid")"
}

stop_runtime() {
  local pid_file="$RUNTIME_DIR/mihomo.pid"

  [ -f "$pid_file" ] || {
    warn "Mihomo 当前未运行"
    return 0
  }

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"

  if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  fi

  rm -f "$pid_file"
  success "Mihomo 已停止"
}

runtime_status_text() {
  if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
    local pid
    pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
      echo "运行中"
      echo "进程号：$pid"
      return 0
    fi
  fi

  echo "未运行"
}

clean_runtime_state() {
  stop_runtime || true
  clear_build_meta || true
  clear_runtime_event_file || true

  rm -f "$RUNTIME_DIR/config.yaml" 2>/dev/null || true
  rm -f "$(runtime_meta_file)" 2>/dev/null || true
  rm -f "$RUNTIME_DIR"/*.pid 2>/dev/null || true
  rm -f "$RUNTIME_DIR"/*.lock 2>/dev/null || true

  rm -rf "$LOG_DIR" 2>/dev/null || true
  mkdir -p "$LOG_DIR"

  rm -rf "$RUNTIME_DIR/profiles" 2>/dev/null || true
  rm -rf "$RUNTIME_DIR/generated" 2>/dev/null || true
  rm -rf "$RUNTIME_DIR/tmp" 2>/dev/null || true
  rm -rf "$(runtime_dashboard_dir)" 2>/dev/null || true
  clear_shell_proxy_persist_state || true

  mkdir -p "$RUNTIME_DIR" "$BIN_DIR" "$LOG_DIR"
}
