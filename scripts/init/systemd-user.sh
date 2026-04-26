#!/usr/bin/env bash

install_systemd_user_entry() {
  local user_dir unit_file
  user_dir="$HOME/.config/systemd/user"
  unit_file="$user_dir/$(service_unit_name)"

  mkdir -p "$user_dir"

  cat > "$unit_file" <<EOF
[Unit]
Description=clash-freebsd (user)
After=default.target

[Service]
Type=forking
ExecStart=$HOME/.local/bin/clashctl start-direct
ExecStop=$HOME/.local/bin/clashctl stop-direct
ExecReload=$HOME/.local/bin/clashctl restart-direct
PIDFile=$RUNTIME_DIR/mihomo.pid
WorkingDirectory=$PROJECT_DIR
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  if systemd_user_service_autostart_preference_enabled; then
    systemctl --user enable "$(service_unit_name)" >/dev/null 2>&1 || true
  else
    systemctl --user disable "$(service_unit_name)" >/dev/null 2>&1 || true
  fi

  write_runtime_value "RUNTIME_BACKEND" "systemd-user"
  write_runtime_value "INSTALL_SCOPE" "$INSTALL_SCOPE"
}

remove_systemd_user_entry() {
  local unit_file
  unit_file="$HOME/.config/systemd/user/$(service_unit_name)"

  if [ -f "$unit_file" ]; then
    systemctl --user disable "$(service_unit_name)" >/dev/null 2>&1 || true
    rm -f "$unit_file"
    systemctl --user daemon-reload || true
    success "已删除用户级 systemd 服务：$(service_unit_name)"
  fi
}

systemd_user_service_start() {
  systemctl --user start "$(service_unit_name)"
}

systemd_user_service_stop() {
  systemctl --user stop "$(service_unit_name)" >/dev/null 2>&1 || true
}

systemd_user_service_restart() {
  systemctl --user restart "$(service_unit_name)"
}

systemd_user_service_autostart_preference_enabled() {
  case "$(read_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" 2>/dev/null || echo false)" in
    true|1|yes|on)
      case "$(read_runtime_value "RUNTIME_BOOT_AUTOSTART" 2>/dev/null || echo true)" in
        false|0|no|off)
          return 1
          ;;
      esac
      ;;
  esac

  return 0
}

systemd_user_service_autostart_enable() {
  systemctl --user enable "$(service_unit_name)" >/dev/null
  write_runtime_value "RUNTIME_BOOT_AUTOSTART" "true"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
}

systemd_user_service_autostart_disable() {
  systemctl --user disable "$(service_unit_name)" >/dev/null 2>&1 || true
  write_runtime_value "RUNTIME_BOOT_AUTOSTART" "false"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
}

systemd_user_service_autostart_status() {
  if systemctl --user is-enabled --quiet "$(service_unit_name)" 2>/dev/null; then
    echo "on"
  else
    echo "off"
  fi
}

systemd_user_service_status_text() {
  if systemctl --user is-active --quiet "$(service_unit_name)"; then
    echo "运行中"
    systemctl --user show "$(service_unit_name)" --property MainPID --value 2>/dev/null | awk '{print "进程号：" $1}'
  else
    echo "未运行"
  fi
}

systemd_user_service_logs() {
  journalctl --user -u "$(service_unit_name)" -n 200 --no-pager 2>/dev/null || {
    echo "未获取到用户级 systemd 服务日志"
    return 0
  }
}
