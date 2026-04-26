# Clash for FreeBSD（部署文档）

> 本 README 已切换为 **FreeBSD 部署与运维主文档**。  
> 推荐内核：`mihomo`（`KERNEL_TYPE=mihomo`）。

## ✨ 核心特性

- 自动识别架构并下载对应运行依赖
- 多订阅管理与节点切换
- Tun 模式与路由诊断
- Mixin 补丁机制
- `clashctl doctor` 一键诊断
- FreeBSD `rc.d` 服务托管（`freebsd-rc` 后端）

## ⌨️ 命令一览

```text
clashon / clashoff
clashctl add|use|select|ls
clashctl status|doctor|logs
clashctl tun on|off|doctor
clashctl boot status
clashctl boot runtime on|off|status
clashctl config regen
clashctl update|upgrade
```

---

## 1. 环境准备

建议使用 `root` 或具备 `sudo` 权限账号。

```sh
pkg update
pkg install -y bash curl unzip gtar gzip
```

说明：
- 当前脚本通过 `bash` 执行。
- `freebsd-rc` 后端依赖 `service` 与 `/usr/local/etc/rc.d`。

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

开机自启：

```sh
clashctl boot runtime on
clashctl boot runtime status
clashctl boot runtime off
```

自启配置文件：`/etc/rc.conf.d/clash_freebsd`。

## 4. Tun 与路由诊断（FreeBSD）

Tun 设备通常为 `/dev/tun*`。

```sh
clashctl tun on
clashctl tun doctor
route -n get default
netstat -rn -f inet
```

Tun 未生效时优先检查：
- `ls -l /dev/tun*`
- 当前用户权限（建议 root）
- 默认路由是否已接管到 tun 接口

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
- [ ] 以 `root`（或 `sudo`）执行安装
- [ ] 预留端口：`7890`（mixed）、`9090`（controller）、`1053`（dns 可选）
- [ ] 已确认内核：`mihomo`

### 7.2 一次性部署命令

```sh
pkg update
pkg install -y bash curl unzip gtar gzip

git clone --branch master --depth 1 https://github.com/wenyinos/clash-freebsd.git
cd clash-freebsd

export KERNEL_TYPE=mihomo
bash install.sh
```

### 7.3 首次上线动作

```sh
clashctl add <订阅链接> <名称>
clashctl use
clashctl select
clashon
clashctl doctor
clashctl status
```

### 7.4 开机自启与服务验收

```sh
clashctl boot runtime on
clashctl boot runtime status
service clash_freebsd status
```

验收要点：
- `clashctl boot runtime status` 为 `on`
- `service clash_freebsd status` 显示运行中
- `clashctl status` 显示控制器可访问

### 7.5 PF 最小放行示例（可选）

```pf
pass in inet proto tcp from any to any port { 7890, 9090 }
pass in inet proto udp from any to any port { 1053 }
```

```sh
sockstat -4 -l | egrep '7890|9090|1053'
```

### 7.6 日常巡检命令

```sh
clashctl status
clashctl doctor
clashctl logs mihomo
route -n get default
netstat -rn -f inet
```

### 7.7 回滚/应急

```sh
clashoff
service clash_freebsd stop
clashctl boot runtime off
```

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

主机侧：
- [ ] `pkg update && pkg install -y bash curl unzip gtar gzip`
- [ ] `export KERNEL_TYPE=mihomo && bash install.sh`
- [ ] 完成 `clashctl add/use/select`
- [ ] `clashctl boot runtime on`

上线验收：

```sh
sockstat -4 -l | egrep '22|7890|9090|1053'
service clash_freebsd status
clashctl status
clashctl doctor
```

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
- [subconverter](https://github.com/tindy2013/subconverter)
- [zashboard](https://github.com/Zephyruso/zashboard)

## ⚠️ 特别声明

1. 本项目主要用于学习与研究 Shell 编程。
2. 请勿将本项目用于违反法律法规或组织政策的用途。
3. 使用者需自行承担部署与使用风险。
