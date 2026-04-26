#!/usr/bin/env bash

install_systemd_entry() {
  local unit_file
  unit_file="/etc/systemd/system/$(service_unit_name)"

  cat > "$unit_file" <<EOF
[Unit]
Description=clash-freebsd
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/clashctl start-direct
ExecStop=/usr/local/bin/clashctl stop-direct
ExecReload=/usr/local/bin/clashctl restart-direct
PIDFile=$RUNTIME_DIR/mihomo.pid
WorkingDirectory=$PROJECT_DIR
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  if systemd_service_autostart_preference_enabled; then
    systemctl enable "$(service_unit_name)" >/dev/null 2>&1 || true
  else
    systemctl disable "$(service_unit_name)" >/dev/null 2>&1 || true
  fi

  write_runtime_value "RUNTIME_BACKEND" "systemd"
  write_runtime_value "INSTALL_SCOPE" "$INSTALL_SCOPE"
}

remove_systemd_entry() {
  local unit_file
  unit_file="/etc/systemd/system/$(service_unit_name)"

  if [ -f "$unit_file" ]; then
    systemctl disable "$(service_unit_name)" >/dev/null 2>&1 || true
    rm -f "$unit_file"
    systemctl daemon-reload || true
    success "已删除 systemd 服务：$(service_unit_name)"
  fi
}

systemd_service_start() {
  systemctl start "$(service_unit_name)"
}

systemd_service_stop() {
  systemctl stop "$(service_unit_name)" >/dev/null 2>&1 || true
}

systemd_service_restart() {
  systemctl restart "$(service_unit_name)"
}

systemd_service_autostart_preference_enabled() {
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

systemd_service_autostart_enable() {
  systemctl enable "$(service_unit_name)" >/dev/null
  write_runtime_value "RUNTIME_BOOT_AUTOSTART" "true"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
}

systemd_service_autostart_disable() {
  systemctl disable "$(service_unit_name)" >/dev/null 2>&1 || true
  write_runtime_value "RUNTIME_BOOT_AUTOSTART" "false"
  write_runtime_value "RUNTIME_BOOT_AUTOSTART_EXPLICIT" "true"
}

systemd_service_autostart_status() {
  if systemctl is-enabled --quiet "$(service_unit_name)" 2>/dev/null; then
    echo "on"
  else
    echo "off"
  fi
}

systemd_service_status_text() {
  if systemctl is-active --quiet "$(service_unit_name)"; then
    echo "运行中"
    systemctl show "$(service_unit_name)" --property MainPID --value 2>/dev/null | awk '{print "进程号：" $1}'
  else
    echo "未运行"
  fi
}

systemd_service_logs() {
  journalctl -u "$(service_unit_name)" -n 200 --no-pager 2>/dev/null || {
    echo "未获取到 systemd 服务日志"
    return 0
  }
}
