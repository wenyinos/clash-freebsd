# Clash for FreeBSD（部署文档）

> 本 README 已切换为 **FreeBSD 部署与运维主文档**。  
> 推荐内核：`mihomo`（`KERNEL_TYPE=mihomo`）。

## ✨ 核心特性

- mihomo 内核通过 `pkg` 安装，版本以 pkg 仓库为准（自动保持最新）
- 多订阅管理与节点切换（仅支持 clash 格式订阅）
- Mixin 补丁机制
- `clashctl doctor` 一键诊断
- FreeBSD `rc.d` 服务托管（`freebsd-rc` 后端）
- zashboard Web 面板自动下载部署（访问 `http://<ip>:9090/ui`）
- FreeBSD TUN 支持（`tun2socks` 后端，mihomo 内核保持不变）
- **下载完整性验证**：SHA256 校验和验证

## ⌨️ 命令一览

```text
clashon / clashoff
clashctl add|use|select|ls
clashctl status|doctor|logs
clashctl autostart on|off|status
clashctl tun on|off|status|doctor
clashctl config regen
clashctl update|upgrade
```

---

## 1. 环境准备

FreeBSD 默认登录 Shell 可能不是 `bash`，执行以下命令前请先切换到 `bash`：

```sh
bash
```

建议直接使用 `root`（FreeBSD 默认不带 `sudo`，可用 `su -` 切换）。

```sh
pkg update
pkg install -y bash curl unzip gtar gzip
```

说明：
- 当前脚本通过 `bash` 执行。
- `freebsd-rc` 后端依赖 `service` 与 `/usr/local/etc/rc.d`。

### 1.1 su 后找不到 clashctl（PATH 差异）

现象：

```text
su: clashctl: not found
```

原因：`su -` 切换到 root 后使用 root 的 `PATH`，通常不包含用户目录（如 `/home/<用户名>/.local/bin`）。user scope 安装的命令位于该目录。

临时用法（使用绝对路径）：

```sh
su -
/home/<用户名>/.local/bin/clashctl autostart on
/home/<用户名>/.local/bin/clashctl autostart status
```

永久修复（推荐使用 system scope 安装，命令写入 `/usr/local/bin`）：

```sh
bash install.sh system
```

### 1.2 root 执行导致文件属主漂移（.env / runtime）

现象（示例）：

```text
touch: /path/to/clash-freebsd/runtime/runtime-events.env: Permission denied
override rw-r--r--  root/<用户名> for /path/to/clash-freebsd/.env? (y/n [n])
```

原因：以 root 执行 `clashctl` 会把 `.env` 或 `runtime/*` 写成 `root` 属主，后续普通用户执行会权限不足。

建议（最小权限）：
- 仅对必须 root 的命令切换 root：`service`、`autostart`、`clashctl on/off`、`clashctl tun on/off`。
- 只读与诊断命令直接用普通用户执行：`clashctl status`、`clashctl doctor`、`clashctl logs`、`clashctl secret`、`clashctl ls`、`clashctl select`。

修复属主（一次性，需要 root）：

```sh
chown <用户名>:<用户组> /path/to/clash-freebsd/.env
chown -R <用户名>:<用户组> /path/to/clash-freebsd/runtime
```

## 2. 安装与初始化

```sh
git clone --branch master --depth 1 https://github.com/wenyinos/clash-freebsd.git
cd clash-freebsd
export KERNEL_TYPE=mihomo
bash install.sh
```

首次配置：

```sh
clashctl add <订阅链接> <名称>
clashctl use
clashctl select
clashctl select <策略组> <节点>   # 非交互直接切换，例如 clashctl select PROXY DIRECT
clashon
clashctl status
```

## 3. FreeBSD 服务管理（rc.d）

系统安装默认使用 `freebsd-rc` 后端，服务名：`clash_freebsd`。

```sh
service clash_freebsd status
service clash_freebsd start
service clash_freebsd stop
service clash_freebsd restart
```

管理内核服务开机自启：

```sh
clashctl autostart on
clashctl autostart status
clashctl autostart off
```

说明：
- `clashctl autostart on` 只影响 rc.d 服务是否随系统启动。
- `service`、`autostart`、`clashctl on/off` 需要 root 权限（请使用 root 或 `su -`）。
- 即使 autostart 为 off，`clashctl on` / `clashctl off` 仍可手动启停（内部使用 `onestart`/`onestop`）。
- FreeBSD 自启配置文件：`/etc/rc.conf.d/clash_freebsd`。

## 4. TUN 模式（FreeBSD / tun2socks）

上游 mihomo 内核不含 FreeBSD TUN 实现（sing-tun 仅支持 Linux/Windows/macOS），本项目通过 `tun2socks` 提供 TUN 后端，**mihomo 内核保持不变**。

依赖（安装时自动尝试安装）：

```sh
pkg install -y tun2socks
```

命令：

```sh
clashctl tun status
clashctl tun doctor
clashctl tun on
clashctl tun off
```

原理：`tun2socks` 创建 `/dev/tun` 设备，把流量经 `socks5://127.0.0.1:7890`（mihomo 混合端口）转发。

注意事项：
- 需要 root 权限；开启后默认路由切换到 `tun0`。
- 私有网段（`10/8`、`172.16/12`、`192.168/16`）、当前 SSH 对端与代理服务器 IP 会自动添加直连路由，避免 SSH 断连与流量回环。
- UDP 需要节点支持 UDP；DNS 建议使用支持 UDP 的节点。
- 可用环境变量调整：`CLASH_TUN_DEVICE`、`CLASH_TUN_ADDR`、`CLASH_TUN_NETMASK`、`CLASH_TUN_EXCLUDE_NETS`。
- 关闭后自动恢复原默认路由并销毁 TUN 设备。

## 5. 常用排障命令

```sh
clashctl doctor
clashctl logs
clashctl logs mihomo
clashctl config regen
```

## 6. 卸载

```sh
bash uninstall.sh
```

彻底清理运行时数据：

```sh
bash uninstall.sh --purge-runtime
```

---

## 7. 最小化服务器（无桌面）部署清单

### 7.1 基础检查（Checklist）

- [ ] 系统时间正确（NTP 正常）
- [ ] 可访问 GitHub（或已配置镜像/代理）
- [ ] 依赖已安装：`bash` `curl` `unzip` `gtar` `gzip`
- [ ] 以 `root` 执行安装（`su -`）
- [ ] 预留端口：`7890`（mixed）、`9090`（controller）、`1053`（dns 可选）
- [ ] 已确认内核：`mihomo`

### 7.2 PF 最小放行示例（可选）

```pf
pass in inet proto tcp from any to any port { 7890, 9090 }
pass in inet proto udp from any to any port { 1053 }
```

```sh
sockstat -4 -l | egrep '7890|9090|1053'
```

### 7.3 日常巡检命令

```sh
clashctl status
clashctl doctor
clashctl logs mihomo
route -n get default
netstat -rn -f inet
```

以上诊断命令均为只读，可直接用普通用户执行。

彻底回收：

```sh
bash uninstall.sh --purge-runtime
```

---

## 8. 云厂商场景模板（Vultr / OCI / 腾讯云）

### 8.1 通用模板（所有云通用）

控制台侧（安全组/防火墙）：
- [ ] TCP 入站：`22`
- [ ] TCP 入站：`7890`
- [ ] TCP 入站：`9090`（建议仅管理 IP）
- [ ] UDP 入站：`1053`（启用 DNS 接管时）
- [ ] 出站允许访问 GitHub/订阅地址

### 8.2 Vultr 模板

- [ ] 在 `Firewall Group` 添加入站规则（TCP: 22/7890/9090，UDP: 1053 可选）
- [ ] 确认防火墙策略已绑定目标实例
- [ ] 主机执行 `sockstat -4 -l` 校验监听

### 8.3 Oracle Cloud（OCI）模板

- [ ] 在 VCN 的 `Security List` 或 `NSG` 添加入站规则
- [ ] 校验 `Stateful/Stateless` 策略与回包路径
- [ ] 公网场景建议将 `9090` 限制为运维出口 IP

### 8.4 腾讯云（CVM）模板

- [ ] 在 CVM 安全组添加入站规则
- [ ] 若启用云防火墙，确认与安全组规则不冲突
- [ ] 若用弹性公网 IP，确认已正确绑定网卡

### 8.5 最小暴露建议（生产）

`9090` 建议只对白名单放行。若不需要公网控制台：

```sh
sed -i '' 's/^export EXTERNAL_CONTROLLER=.*/export EXTERNAL_CONTROLLER="127.0.0.1:9090"/' .env
clashctl config regen
clashoff && clashon
```

---

## 9. 仅内网管理模式模板（不暴露公网控制台）

### 9.1 控制面收敛（服务器执行）

```sh
sed -i '' 's/^export EXTERNAL_CONTROLLER=.*/export EXTERNAL_CONTROLLER="127.0.0.1:9090"/' .env
clashctl config regen
clashoff && clashon
```

如需同时收敛 mixed 端口：

```sh
sed -i '' 's/^export MIXED_PORT=.*/export MIXED_PORT="7890"/' .env
```

### 9.2 云防火墙/安全组策略

- [ ] 关闭公网 `9090`
- [ ] 仅保留 `22` 给运维出口 IP
- [ ] `7890` 按业务需要放行
- [ ] `1053` 默认不放公网

### 9.3 SSH 隧道访问控制台（运维端）

```sh
ssh -N -L 19090:127.0.0.1:9090 <user>@<server_ip>
```

本地访问：

```text
http://127.0.0.1:19090/ui
```

### 9.4 验收清单

```sh
sockstat -4 -l | egrep '22|7890|9090|1053'
```

- `9090` 仅绑定 `127.0.0.1`
- 公网不可直连 `9090`
- SSH 隧道访问 `19090` 正常

### 9.5 应急回切（临时公网运维）

```sh
sed -i '' 's/^export EXTERNAL_CONTROLLER=.*/export EXTERNAL_CONTROLLER="0.0.0.0:9090"/' .env
clashctl config regen
clashoff && clashon
```

完成运维后，请立即恢复内网模式并收紧安全组。

---

## 🔗 引用

- [mihomo](https://github.com/MetaCubeX/mihomo)
- [zashboard](https://github.com/Zephyruso/zashboard)

## ⚠️ 特别声明

1. 本项目主要用于学习与研究 Shell 编程。
2. 请勿将本项目用于违反法律法规或组织政策的用途。
3. 使用者需自行承担部署与使用风险。
