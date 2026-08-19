#!/usr/bin/env bash
# 注意：此文件被其他脚本 source，不设置 set -e 以避免影响调用方的错误处理策略
set -u  # 未定义变量报错

freebsd_service_name() {
  echo "clash_freebsd"
}

freebsd_service_file() {
  echo "/usr/local/etc/rc.d/$(freebsd_service_name)"
}

freebsd_rc_conf_file() {
  echo "/etc/rc.conf.d/$(freebsd_service_name)"
}

freebsd_require_root() {
  is_root_user || die_state "FreeBSD rc.d 模式需要 root 权限" "请通过 root 用户或 sudo 重新运行"
}

write_freebsd_autostart_value() {
  kv_write "$(freebsd_rc_conf_file)" "$(freebsd_service_name)_enable" "$1"
}

install_freebsd_entry() {
  local service_file clashctl_target runtime_dir project_dir

  freebsd_require_root

  service_file="$(freebsd_service_file)"
  clashctl_target="$(clashctl_entry_target)"
  runtime_dir="$RUNTIME_DIR"
  project_dir="$PROJECT_DIR"

  cat > "$service_file" <<EOF
#!/bin/sh
#
# PROVIDE: $(freebsd_service_name)
# REQUIRE: NETWORKING
# KEYWORD: shutdown
#

. /etc/rc.subr

name="$(freebsd_service_name)"
rcvar="\${name}_enable"
clashctl_bin="${clashctl_target}"
pidfile="${runtime_dir}/mihomo.pid"

start_cmd="\${name}_start"
stop_cmd="\${name}_stop"
restart_cmd="\${name}_restart"
status_cmd="\${name}_status"

$(freebsd_service_name)_start() {
  cd "${project_dir}" || exit 1
  "\${clashctl_bin}" start-direct
}

$(freebsd_service_name)_stop() {
  cd "${project_dir}" || exit 1
  "\${clashctl_bin}" stop-direct
}

$(freebsd_service_name)_restart() {
  $(freebsd_service_name)_stop || true
  $(freebsd_service_name)_start
}

$(freebsd_service_name)_status() {
  if [ -f "\${pidfile}" ]; then
    pid=\$(cat "\${pidfile}" 2>/dev/null || true)
    if [ -n "\${pid}" ] && kill -0 "\${pid}" 2>/dev/null; then
      echo "\${name} is running (pid: \${pid})"
      return 0
    fi
  fi

  echo "\${name} is not running"
  return 1
}

load_rc_config "\${name}"
: \${clash_freebsd_enable:="NO"}

run_rc_command "\$1"
EOF

  chmod +x "$service_file"

  if freebsd_service_autostart_preference_enabled; then
    freebsd_service_autostart_enable >/dev/null 2>&1 || true
  else
    freebsd_service_autostart_disable >/dev/null 2>&1 || true
  fi

  write_runtime_value "RUNTIME_BACKEND" "freebsd-rc"
  write_runtime_value "INSTALL_SCOPE" "$INSTALL_SCOPE"
}

remove_freebsd_entry() {
  local service_file conf_file

  freebsd_require_root

  service_file="$(freebsd_service_file)"
  conf_file="$(freebsd_rc_conf_file)"

  freebsd_service_stop >/dev/null 2>&1 || true

  [ -f "$service_file" ] && rm -f "$service_file"
  [ -f "$conf_file" ] && rm -f "$conf_file"

  success "已删除 FreeBSD rc.d 服务：$(freebsd_service_name)"
}

freebsd_service_start() {
  freebsd_require_root
  service "$(freebsd_service_name)" start
}

freebsd_service_stop() {
  freebsd_require_root
  service "$(freebsd_service_name)" stop >/dev/null 2>&1 || true
}

freebsd_service_restart() {
  freebsd_require_root
  service "$(freebsd_service_name)" restart
}

freebsd_service_autostart_preference_enabled() {
  case "$(read_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" 2>/dev/null || echo false)" in
    true|1|yes|on)
      case "$(read_runtime_value "RUNTIME_BOOT_AUTOSTART" 2>/dev/null || echo true)" in
        false|0|no|off)
          return 1
          ;;
      esac
      return 0
      ;;
  esac

  return 1
}

freebsd_service_autostart_enable() {
  freebsd_require_root
  write_freebsd_autostart_value "YES"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART" "true"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
}

freebsd_service_autostart_disable() {
  freebsd_require_root
  write_freebsd_autostart_value "NO"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART" "false"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
}

freebsd_service_autostart_status() {
  local file value
  file="$(freebsd_rc_conf_file)"

  if [ -f "$file" ]; then
    value="$(sed -nE "s/^[[:space:]]*$(freebsd_service_name)_enable=['\"]?([^'\"]*)['\"]?$/\1/p" "$file" | head -n 1 | tr '[:upper:]' '[:lower:]')"
  fi

  # rc.conf.d 未覆盖时回退读取 /etc/rc.conf（用户可能用 sysrc 写入）
  [ -n "${value:-}" ] || value="$(sysrc -n "$(freebsd_service_name)_enable" 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)"

  case "${value:-}" in
    yes|true|1|on)
      echo "on"
      ;;
    *)
      echo "off"
      ;;
  esac
}

freebsd_service_status_text() {
  local pid
  if service "$(freebsd_service_name)" onestatus >/dev/null 2>&1; then
    echo "运行中"
    if [ -f "$RUNTIME_DIR/mihomo.pid" ]; then
      pid="$(cat "$RUNTIME_DIR/mihomo.pid" 2>/dev/null || true)"
      [ -n "${pid:-}" ] && echo "进程号：$pid"
    fi
  else
    echo "未运行"
  fi
}

freebsd_service_logs() {
  if [ ! -f "$LOG_DIR/mihomo.out.log" ]; then
    echo "日志文件不存在"
    return 0
  fi

  tail -n 200 "$LOG_DIR/mihomo.out.log"
}
