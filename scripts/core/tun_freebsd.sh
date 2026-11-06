#!/usr/bin/env bash
# FreeBSD TUN backend via tun2socks (mihomo kernel stays unchanged)
# 注意：此文件被其他脚本 source，不设置 set -e 以避免影响调用方的错误处理策略
set -u

tun_freebsd_bin() {
  echo "/usr/local/bin/tun2socks"
}

tun_freebsd_device() {
  echo "${CLASH_TUN_DEVICE:-tun0}"
}

tun_freebsd_addr() {
  echo "${CLASH_TUN_ADDR:-198.18.0.1}"
}

tun_freebsd_netmask() {
  echo "${CLASH_TUN_NETMASK:-255.254.0.0}"
}

tun_freebsd_pid_file() {
  echo "$RUNTIME_DIR/tun2socks.pid"
}

tun_freebsd_log_file() {
  echo "$LOG_DIR/tun2socks.log"
}

tun_freebsd_route_file() {
  echo "$RUNTIME_DIR/tun-direct-routes.list"
}

tun_freebsd_proxy_url() {
  local port
  port="$(read_env_value "MIXED_PORT" 2>/dev/null || echo 7890)"
  echo "socks5://127.0.0.1:${port}"
}

tun_freebsd_available() {
  [ "$(get_os 2>/dev/null || echo unknown)" = "freebsd" ] || return 1
  [ -x "$(tun_freebsd_bin)" ] || return 1

  if [ -e /dev/tun0 ] || [ -e /dev/tun ]; then
    return 0
  fi

  # FreeBSD 15 的 /dev/tun 为克隆设备，未实例化时不可见；用 if_tun 模块状态判断
  if command -v kldstat >/dev/null 2>&1 && kldstat -q -m if_tun 2>/dev/null; then
    return 0
  fi

  return 1
}

tun_freebsd_running() {
  local pid
  pid="$(cat "$(tun_freebsd_pid_file)" 2>/dev/null || true)"
  [ -n "${pid:-}" ] && ps -p "$pid" >/dev/null 2>&1
}

tun_freebsd_default_route_info() {
  route -n get default 2>/dev/null \
    | awk '/gateway:/{g=$2} /interface:/{i=$2} END{print g "|" i}'
}

tun_freebsd_exclude_nets() {
  if [ -n "${CLASH_TUN_EXCLUDE_NETS:-}" ]; then
    printf '%s\n' $CLASH_TUN_EXCLUDE_NETS
    return 0
  fi

  # 127.0.0.0/8 与组播路由由系统维护，不在此处增删，避免误删回环路由
  printf '%s\n' \
    10.0.0.0/8 \
    172.16.0.0/12 \
    192.168.0.0/16
}

tun_freebsd_proxy_server_ips() {
  local config_file="$RUNTIME_DIR/config.yaml" server ip

  [ -s "$config_file" ] || return 0

  while IFS= read -r server; do
    [ -n "${server:-}" ] || continue
    case "$server" in
      null|localhost)
        continue
        ;;
      127.*|0.0.0.0|::1|\[::1\])
        continue
        ;;
    esac

    if printf '%s' "$server" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "$server"
      continue
    fi

    if printf '%s' "$server" | grep -Eq '^[0-9a-fA-F:]+$'; then
      echo "$server"
      continue
    fi

    if command -v drill >/dev/null 2>&1; then
      drill "$server" A 2>/dev/null \
        | awk '/IN[[:space:]]+A[[:space:]]/{print $5}' \
        | grep -Ev '^127\.' || true
    fi
  done <<EOF
$("$(yq_bin)" eval '.proxies[].server // ""' "$config_file" 2>/dev/null || true)
EOF
}

tun_freebsd_add_direct_routes() {
  local gateway="$1"
  local route_file net ip
  route_file="$(tun_freebsd_route_file)"
  : > "$route_file"

  while IFS= read -r net; do
    [ -n "${net:-}" ] || continue
    if route add -net "$net" "$gateway" >/dev/null 2>&1; then
      printf '%s\n' "-net $net $gateway" >> "$route_file"
    fi
  done <<EOF
$(tun_freebsd_exclude_nets)
EOF

  while IFS= read -r ip; do
    [ -n "${ip:-}" ] || continue
    if route add -host "$ip" "$gateway" >/dev/null 2>&1; then
      printf '%s\n' "-host $ip $gateway" >> "$route_file"
    fi
  done <<EOF
$(tun_freebsd_proxy_server_ips)
EOF
}

tun_freebsd_remove_direct_routes() {
  local route_file kind target gateway
  route_file="$(tun_freebsd_route_file)"

  [ -f "$route_file" ] || return 0

  while read -r kind target gateway; do
    [ -n "${kind:-}" ] && [ -n "${target:-}" ] || continue
    route delete "$kind" "$target" >/dev/null 2>&1 || true
  done < "$route_file"

  rm -f "$route_file" 2>/dev/null || true
}

tun_freebsd_restore_default_route() {
  local gateway interface

  gateway="$(read_tun_value "TUN_ORIG_GATEWAY" 2>/dev/null || true)"
  interface="$(read_tun_value "TUN_ORIG_INTERFACE" 2>/dev/null || true)"

  if [ -n "${gateway:-}" ]; then
    route change default "$gateway" >/dev/null 2>&1 && return 0
    route delete default >/dev/null 2>&1 || true
    route add default "$gateway" >/dev/null 2>&1 && return 0
  fi

  if [ -n "${interface:-}" ]; then
    route change default -interface "$interface" >/dev/null 2>&1 && return 0
    route delete default >/dev/null 2>&1 || true
    route add default -interface "$interface" >/dev/null 2>&1 && return 0
  fi

  return 1
}

tun_freebsd_on() {
  local device pid_file log_file route_info gateway interface i

  is_root_user || die_state "FreeBSD TUN（tun2socks）需要 root 权限" "请切换到 root 用户（su -）后重新运行"
  tun_freebsd_available || {
    die_state "FreeBSD TUN 依赖 tun2socks 与 /dev/tun" \
              "请先执行：pkg install -y tun2socks（并确认 if_tun 内核模块可用）"
  }

  status_is_running || die_state "代理内核未运行" "clashon"
  proxy_controller_reachable 2>/dev/null || die_state "控制器不可访问" "clashctl doctor"

  device="$(tun_freebsd_device)"
  pid_file="$(tun_freebsd_pid_file)"
  log_file="$(tun_freebsd_log_file)"

  if tun_freebsd_running; then
    info "tun2socks 已在运行（pid=$(cat "$pid_file" 2>/dev/null || true)）"
    return 0
  fi

  mkdir -p "$LOG_DIR"

  if ifconfig "$device" >/dev/null 2>&1; then
    ifconfig "$device" destroy >/dev/null 2>&1 || true
  fi

  route_info="$(tun_freebsd_default_route_info)"
  gateway="${route_info%%|*}"
  interface="${route_info##*|}"
  [ -n "${gateway:-}" ] || die_state "无法解析当前默认网关" "route -n get default"
  [ -n "${interface:-}" ] || die_state "无法解析当前默认接口" "route -n get default"

  write_tun_value "TUN_FREEBSD_BACKEND" "tun2socks"
  write_tun_value "TUN_DEVICE" "$device"
  write_tun_value "TUN_ORIG_GATEWAY" "$gateway"
  write_tun_value "TUN_ORIG_INTERFACE" "$interface"

  nohup "$(tun_freebsd_bin)" \
    -device "tun://$device" \
    -proxy "$(tun_freebsd_proxy_url)" \
    -loglevel info \
    > "$log_file" 2>&1 &
  echo $! > "$pid_file"

  i=0
  while [ "$i" -lt 10 ]; do
    ifconfig "$device" >/dev/null 2>&1 && break
    sleep 1
    i=$((i + 1))
  done

  if ! ifconfig "$device" >/dev/null 2>&1; then
    kill "$(cat "$pid_file" 2>/dev/null || true)" >/dev/null 2>&1 || true
    rm -f "$pid_file" 2>/dev/null || true
    die_state "tun2socks 未能创建 TUN 设备：$device" "查看日志：clashctl logs tun2socks"
  fi

  ifconfig "$device" inet "$(tun_freebsd_addr)" netmask "$(tun_freebsd_netmask)" up \
    || die_state "无法为 $device 配置地址" "ifconfig $device"

  tun_freebsd_add_direct_routes "$gateway"

  if ! route change default -interface "$device" >/dev/null 2>&1; then
    route delete default >/dev/null 2>&1 || true
    route add default -interface "$device" >/dev/null 2>&1 \
      || die_state "无法将默认路由切换到 $device" "route -n get default"
  fi

  set_tun_enabled "true"
  write_tun_value "TUN_STACK" "tun2socks"
  write_tun_value "TUN_EFFECTIVE" "true"
  mark_tun_last_action "on" "success" "tun2socks"
  mark_tun_last_verification "success" "effective"

  success "TUN 已开启（tun2socks -> $(tun_freebsd_proxy_url)）"
  info "设备：$device，原默认路由：$gateway（$interface）"
}

tun_freebsd_off() {
  local device pid_file pid

  is_root_user || die_state "FreeBSD TUN（tun2socks）需要 root 权限" "请切换到 root 用户（su -）后重新运行"

  device="$(read_tun_value "TUN_DEVICE" 2>/dev/null || true)"
  [ -n "${device:-}" ] || device="$(tun_freebsd_device)"
  pid_file="$(tun_freebsd_pid_file)"

  tun_freebsd_restore_default_route || warn "默认路由恢复失败，请手动检查：route -n get default"
  tun_freebsd_remove_direct_routes

  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [ -n "${pid:-}" ] && ps -p "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    sleep 1
    ps -p "$pid" >/dev/null 2>&1 && kill -9 "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$pid_file" 2>/dev/null || true

  ifconfig "$device" destroy >/dev/null 2>&1 || true

  set_tun_enabled "false"
  write_tun_value "TUN_EFFECTIVE" "false"
  write_tun_value "TUN_STACK" ""
  mark_tun_last_action "off" "success" "tun2socks"
  mark_tun_last_verification "success" "disabled"

  success "TUN 已关闭"
}

tun_freebsd_status() {
  local device pid

  device="$(read_tun_value "TUN_DEVICE" 2>/dev/null || true)"
  [ -n "${device:-}" ] || device="$(tun_freebsd_device)"
  pid="$(cat "$(tun_freebsd_pid_file)" 2>/dev/null || true)"

  echo
  echo "🧪 Tun 状态（FreeBSD / tun2socks）"
  echo

  if [ "$(tun_enabled)" = "true" ] && tun_freebsd_running; then
    echo "🐱 当前状态：已开启"
  else
    echo "❗ 当前状态：未开启"
  fi

  echo "🔧 后端：tun2socks"
  echo "💻 设备：$device"
  if [ -n "${pid:-}" ] && ps -p "$pid" >/dev/null 2>&1; then
    echo "🧩 tun2socks：运行中（pid=$pid）"
  else
    echo "🧩 tun2socks：未运行"
  fi
  echo "🔗 上游：$(tun_freebsd_proxy_url)"

  if command -v ifconfig >/dev/null 2>&1 && ifconfig "$device" >/dev/null 2>&1; then
    echo "🌐 默认路由：$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
  fi

  if tun_freebsd_available; then
    echo "✅ 环境检查：tun2socks 与 /dev/tun 可用"
  else
    echo "🚨 环境检查：缺少 tun2socks 或 /dev/tun"
  fi

  if tun_freebsd_running; then
    echo "👉 下一步：clashctl tun off"
  else
    echo "👉 下一步：clashctl tun on"
  fi
  echo
}

tun_freebsd_doctor() {
  local device

  device="$(tun_freebsd_device)"

  echo
  echo "🐱 Tun 诊断（FreeBSD / tun2socks）"
  echo

  if [ -x "$(tun_freebsd_bin)" ]; then
    echo "✔ tun2socks：$("$(tun_freebsd_bin)" -version 2>&1 | head -n 1)"
  else
    echo "✘ tun2socks 未安装（pkg install -y tun2socks）"
  fi

  if [ -e /dev/tun0 ] || [ -e /dev/tun ] || kldstat -q -m if_tun 2>/dev/null; then
    echo "✔ /dev/tun：可用（if_tun 已加载）"
  else
    echo "✘ /dev/tun：不可用（检查 if_tun 内核模块）"
  fi

  if command -v kldstat >/dev/null 2>&1; then
    if kldstat -q -m if_tun 2>/dev/null || [ -e /dev/tun ]; then
      echo "✔ if_tun：已加载或内建"
    else
      echo "⚠ if_tun：未加载（kldload if_tun）"
    fi
  fi

  if status_is_running; then
    echo "✔ mihomo：运行中"
  else
    echo "✘ mihomo：未运行（clashon）"
  fi

  if proxy_controller_reachable 2>/dev/null; then
    echo "✔ 控制器：可访问"
  else
    echo "✘ 控制器：不可访问（clashctl doctor）"
  fi

  if tun_freebsd_running; then
    echo "✔ tun2socks：运行中（pid=$(cat "$(tun_freebsd_pid_file)" 2>/dev/null || true)）"
  else
    echo "ℹ tun2socks：未运行"
  fi

  if ifconfig "$device" >/dev/null 2>&1; then
    echo "✔ 设备 $device：已创建"
    echo "   默认路由接口：$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
  else
    echo "ℹ 设备 $device：未创建"
  fi

  echo
  echo "📜 说明："
  echo "  FreeBSD 上 mihomo 内核不含 TUN 实现（上游 sing-tun 无 FreeBSD 支持）"
  echo "  本后端用 tun2socks 创建 TUN，并经 mihomo 的 SOCKS 端口转发"
  echo "  UDP 需要节点支持 UDP；DNS 建议使用支持 UDP 的节点或配置 mihomo DNS"
  echo
}

resolve_tun2socks() {
  [ "$(get_os 2>/dev/null || echo unknown)" = "freebsd" ] || return 0
  [ -x "$(tun_freebsd_bin)" ] && return 0

  if ! is_root_user; then
    warn "tun2socks 未安装；TUN 功能不可用（可稍后执行 pkg install -y tun2socks）"
    return 0
  fi

  info "FreeBSD 使用 pkg 安装 tun2socks（TUN 后端）"
  pkg install -y tun2socks >/dev/null 2>&1 \
    || warn "tun2socks 安装失败；TUN 功能不可用（可稍后手动安装）"
  return 0
}
