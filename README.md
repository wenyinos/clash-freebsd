# Clash for FreeBSD (Deployment Guide)

> This README serves as the **primary FreeBSD deployment and operations document**.  
> Recommended kernel: `mihomo` (`KERNEL_TYPE=mihomo`).

Other languages: [🇨🇳 简体中文](README.zh.md)

---

## ✨ Core Features

- mihomo kernel installed via `pkg` (version tracks the pkg repository)
- Multi-subscription management and node switching (clash format only)
- Mixin patch mechanism
- One-click diagnostics with `clashctl doctor`
- FreeBSD `rc.d` service management (`freebsd-rc` backend)
- zashboard Web panel auto-download and deploy (visit `http://<ip>:9090/ui`)
- **Download integrity verification** with SHA256 checksums

## ⌨️ Command Overview

```text
clashon / clashoff
clashctl add|use|select|ls
clashctl status|doctor|logs
clashctl autostart on|off|status
clashctl config regen
clashctl update|upgrade
```

---

## 1. Environment Setup

The default login shell on FreeBSD may not be `bash`. Switch to `bash` before running the commands below:

```sh
bash
```

It is recommended to use the `root` account or a user with `sudo` privileges.

```sh
pkg update
pkg install -y bash curl unzip gtar gzip
```

Notes:
- Scripts are executed via `bash`.
- The `freebsd-rc` backend depends on `service` and `/usr/local/etc/rc.d`.

### 1.1 sudo Cannot Find clashctl (PATH Mismatch)

Symptom:

```text
sudo: clashctl: command not found
```

Cause: `sudo` uses `secure_path` by default, which usually does not include user directories (e.g., `/home/zemin/.local/bin`).

Temporary workaround (works immediately):

```sh
sudo /home/zemin/.local/bin/clashctl autostart on
sudo /home/zemin/.local/bin/clashctl autostart status
```

Permanent fix (recommended):

```sh
sudo visudo
```

Locate and modify (or add):

```text
Defaults secure_path="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin:/home/zemin/.local/bin"
```

After saving, you can use directly:

```sh
sudo clashctl autostart on
sudo clashctl autostart status
```

### 1.2 sudo Causes File Ownership Drift (.env / runtime)

Symptom (example):

```text
touch: /home/zemin/clash-freebsd/runtime/runtime-events.env: Permission denied
override rw-r--r--  root/zemin for /home/zemin/clash-freebsd/.env? (y/n [n])
```

Cause: Running `sudo clashctl ...` writes `.env` or `runtime/*` with `root` ownership, causing permission issues for subsequent non-root execution.

Recommendations:
- Use `sudo` only for commands that require root (e.g., `service`, `autostart`).
- Prefer non-root execution for other commands (e.g., `clashctl config regen`, `clashctl secret`, `clashctl logs`).

Fix ownership (one-time):

```sh
sudo chown zemin:zemin /home/zemin/clash-freebsd/.env
sudo chown -R zemin:zemin /home/zemin/clash-freebsd/runtime
```

## 2. Installation and Initialization

```sh
git clone --branch master --depth 1 https://github.com/wenyinos/clash-freebsd.git
cd clash-freebsd
export KERNEL_TYPE=mihomo
bash install.sh
```

First-time configuration:

```sh
clashctl add <subscription_url> <name>
clashctl use
clashctl select
clashon
clashctl status
```

## 3. FreeBSD Service Management (rc.d)

The default installation uses the `freebsd-rc` backend. Service name: `clash_freebsd`.

```sh
sudo service clash_freebsd status
sudo service clash_freebsd start
sudo service clash_freebsd stop
sudo service clash_freebsd restart
```

Manage kernel service auto-start:

```sh
sudo clashctl autostart on
sudo clashctl autostart status
sudo clashctl autostart off
```

Notes:
- `clashctl autostart on` only affects whether the rc.d service starts on system boot.
- `service` and `autostart` commands require root privileges (use root or `sudo`).
- FreeBSD auto-start config file: `/etc/rc.conf.d/clash_freebsd`.

## 4. TUN Mode (Not Supported on FreeBSD)

The current mihomo kernel does not support TUN on FreeBSD; `clashctl tun on` will fail with an explicit message.

Route diagnostics still work:

```sh
route -n get default
netstat -rn -f inet
```

## 5. Common Troubleshooting Commands

```sh
clashctl doctor
clashctl logs
clashctl logs mihomo
clashctl config regen
```

## 6. Uninstallation

```sh
bash uninstall.sh
```

Thoroughly clean runtime data:

```sh
bash uninstall.sh --purge-runtime
```

---

## 7. Minimal Server (No Desktop) Deployment Checklist

### 7.1 Basic Checks (Checklist)

- [ ] System time is correct (NTP functioning)
- [ ] GitHub is accessible (or mirror/proxy configured)
- [ ] Dependencies installed: `bash` `curl` `unzip` `gtar` `gzip`
- [ ] Installation performed as `root` (or with `sudo`)
- [ ] Ports reserved: `7890` (mixed), `9090` (controller), `1053` (DNS, optional)
- [ ] Kernel confirmed: `mihomo`

### 7.2 PF Minimal Allow Example (Optional)

```pf
pass in inet proto tcp from any to any port { 7890, 9090 }
pass in inet proto udp from any to any port { 1053 }
```

```sh
sockstat -4 -l | egrep '7890|9090|1053'
```

### 7.3 Daily Inspection Commands

```sh
clashctl status
clashctl doctor
clashctl logs mihomo
route -n get default
netstat -rn -f inet
```

Full cleanup:

```sh
bash uninstall.sh --purge-runtime
```

---

## 8. Cloud Provider Scenario Templates (Vultr / OCI / Tencent Cloud)

### 8.1 General Template (All Clouds)

Console-side (security group / firewall):
- [ ] TCP inbound: `22`
- [ ] TCP inbound: `7890`
- [ ] TCP inbound: `9090` (recommended: management IP only)
- [ ] UDP inbound: `1053` (when DNS interception is enabled)
- [ ] Outbound: allow access to GitHub / subscription addresses

### 8.2 Vultr Template

- [ ] Add inbound rules in `Firewall Group` (TCP: 22/7890/9090, UDP: 1053 optional)
- [ ] Confirm firewall policy is bound to the target instance
- [ ] Run `sockstat -4 -l` on the host to verify listeners

### 8.3 Oracle Cloud (OCI) Template

- [ ] Add inbound rules in VCN `Security List` or `NSG`
- [ ] Verify `Stateful/Stateless` policy and return path
- [ ] For public-facing deployments, restrict `9090` to the ops egress IP

### 8.4 Tencent Cloud (CVM) Template

- [ ] Add inbound rules in the CVM security group
- [ ] If cloud firewall is enabled, confirm no conflicts with security group rules
- [ ] If using an elastic public IP, confirm it is correctly bound to the NIC

### 8.5 Minimal Exposure Recommendations (Production)

`9090` should be whitelist-only. If a public-facing console is not needed:

```sh
sed -i '' 's/^export EXTERNAL_CONTROLLER=.*/export EXTERNAL_CONTROLLER="127.0.0.1:9090"/' .env
clashctl config regen
clashoff && clashon
```

---

## 9. Intranet-Only Management Mode Template (No Public Console)

### 9.1 Control Plane Convergence (Server-side)

```sh
sed -i '' 's/^export EXTERNAL_CONTROLLER=.*/export EXTERNAL_CONTROLLER="127.0.0.1:9090"/' .env
clashctl config regen
clashoff && clashon
```

To also converge the mixed port:

```sh
sed -i '' 's/^export MIXED_PORT=.*/export MIXED_PORT="7890"/' .env
```

### 9.2 Cloud Firewall / Security Group Policy

- [ ] Disable public `9090`
- [ ] Only keep `22` open for the ops egress IP
- [ ] `7890` open according to business needs
- [ ] `1053` not exposed to the public by default

### 9.3 SSH Tunnel to Access Console (Ops-side)

```sh
ssh -N -L 19090:127.0.0.1:9090 <user>@<server_ip>
```

Local access:

```text
http://127.0.0.1:19090/ui
```

### 9.4 Acceptance Checklist

```sh
sockstat -4 -l | egrep '22|7890|9090|1053'
```

- `9090` is bound to `127.0.0.1` only
- `9090` is not accessible from the public internet
- SSH tunnel access via `19090` is working

### 9.5 Emergency Rollback (Temporary Public Ops)

```sh
sed -i '' 's/^export EXTERNAL_CONTROLLER=.*/export EXTERNAL_CONTROLLER="0.0.0.0:9090"/' .env
clashctl config regen
clashoff && clashon
```

After maintenance is complete, immediately revert to intranet mode and tighten security groups.

---

## 🔗 References

- [mihomo](https://github.com/MetaCubeX/mihomo)
- [zashboard](https://github.com/Zephyruso/zashboard)

## ⚠️ Disclaimer

1. This project is mainly for learning and researching Shell programming.
2. Do not use this project for purposes that violate laws, regulations, or organizational policies.
3. Users assume their own risks for deployment and usage.
