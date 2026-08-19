# FreeBSD 平台脚本错误分析报告

> 日期：2026-08-19
> 分析范围：`scripts/init/freebsd.sh` 全文、`scripts/core/runtime.sh` 全文、`config.sh`/`clashctl.sh`/`common.sh` 中全部 FreeBSD 分支、`install.sh`/`uninstall.sh` 入口，并核实上游 mihomo v1.19.23 / metacubex/sing-tun v0.4.17 / subconverter v0.9.0 的源码与发布资产。
> 结论：**发现 3 个严重错误、3 个中等问题、3 个轻微问题**。

---

## 🔴 严重问题（功能性破坏）

### 1. TUN 功能在 FreeBSD 上根本不可用，且脚本无任何防护

**证据链**（均来自上游真实源码）：

- mihomo v1.19.23 的 `go.mod` 依赖 `github.com/metacubex/sing-tun v0.4.17`
- 该库 `tun_other.go`（构建标签 `!(linux || windows || darwin)`，即 FreeBSD）：

  ```go
  func New(config Options) (Tun, error) {
      return nil, os.ErrInvalid
  }
  ```

  **TUN 设备创建在 FreeBSD 上直接失败**；同库 `monitor_other.go` 的 `NewNetworkUpdateMonitor` / `NewDefaultInterfaceMonitor` 同样返回 `os.ErrInvalid`
- mihomo `listener/sing_tun/server.go:331-336`（v1.19.23）：

  ```go
  if options.AutoRoute || options.AutoDetectInterface {
      networkUpdateMonitor, err = tun.NewNetworkUpdateMonitor(log.SingLogger)
      if err != nil {
          err = E.Cause(err, "create NetworkUpdateMonitor")
          return   // 致命错误，TUN 监听启动失败
      }
  ```

- mihomo 仓库无任何 FreeBSD TUN 实现文件（仅有 darwin/linux/android/windows 变体）

**脚本侧表现**：`clashctl tun on` → `sync_tun_target_state` → `regenerate_config`（`mihomo -t` 只验语法、不验 TUN，可通过）→ 重启后 mihomo TUN 监听失败但进程继续运行 → `tun_effective_check` 得到 `traffic-same-as-host` → 用户只看到 **partial（部分生效）**，而非"平台不支持"。

**加重项**：

| 位置 | 问题 |
|------|------|
| `config.sh:281-283` | `tun_auto_route()` 默认 `true` 且无 OS 门控（对比 `tun_auto_redirect_default()` 有 linux 门控） |
| `config.sh:745` | `auto-detect-interface` 默认 `true` |
| `config/template.yaml:9-10` | 模板即写入 `auto-route: true` / `auto-detect-interface: true` |

AGENTS.md 自述"auto-route and auto-redirect are Linux-only features"，与代码行为矛盾。即使未来 sing-tun 支持 FreeBSD TUN，这两个 `true` 也会先撞上监视器的 `ErrInvalid`。

**修复建议**：
1. `tun_auto_route()`、`auto-detect-interface` 在 FreeBSD 上默认 `false`
2. `cmd_tun_on`（clashctl.sh:4624）在 FreeBSD 上直接 `die_state` 明确告知"当前 mihomo 内核不支持 FreeBSD TUN"
3. doctor 中把 `/dev/tun*` 设备存在性与"内核能力支持"区分开，避免虚假信心

---

### 2. `is_port_in_use()` 在 FreeBSD 上恒返回"端口空闲"

**位置**：`scripts/core/common.sh:1668-1682`

```bash
ss -lnt ...        # FreeBSD 无 ss 命令（iproute2 是 Linux 专属），跳过
netstat -lnt ...   # FreeBSD netstat 无 -l/-t 选项
                   # （已查 man.freebsd.org 确认，SYNOPSIS 为 [-46AaCLnPRSTWx]）
                   # → netstat 报错被 2>/dev/null 吞掉 → 输出为空
                   # → grep 无匹配 → 永远 return 1（"未占用"）
```

**级联影响**：

- 端口自动避让（clashctl.sh:154-175）**永不生效**：7890 被占用时 mihomo 直接绑定失败，只能靠事后 grep `mihomo.out.log` 的兜底检测报 broken
- doctor 端口检查（clashctl.sh:3385-3440）在 FreeBSD 上永远误报"未监听"
- `start_subconverter`（config.sh:3012）：`subconverter_running && is_port_in_use` 恒 false → **即使 subconverter 正常运行监听，也判定为启动失败并 return 1**

**修复建议**：增加 FreeBSD 分支，使用 `sockstat -4 -l -p "$port"`（README 自己用的就是 FreeBSD 正确命令 `sockstat -4 -l`，此处疑似 Linux 版脚本移植残留）。

---

### 3. subconverter 自动下载 Linux 二进制，FreeBSD 上无法执行

**位置**：`scripts/core/runtime.sh:318-323`

`resolve_subconverter()` 只按 CPU 架构选包、不看操作系统：

```bash
amd64) file="subconverter_linux64.tar.gz" ;;
arm64) file="subconverter_aarch64.tar.gz" ;;
```

已核实 tindy2013/subconverter v0.9.0 发布资产：**仅 linux32/linux64/armv7/aarch64/darwin/win，无任何 FreeBSD 构建**。

**影响**：

- `install.sh:25` 会在 FreeBSD 上"成功"下载一个无法 exec 的 Linux ELF（`runtime/subconverter/subconverter`）
- `clashctl add`（convert 类型订阅）触发 `start_subconverter` → exec format error → 报"启动失败"
- doctor（clashctl.sh:3087）只检查 `-x` 可执行位 → 显示"subconverter 已安装"，**掩盖真实问题**
- `resources/bin/README.md` 明确写着 FreeBSD 使用 `subconverter_linux64.tar.gz`——说明是有意为之，但方案不成立（除非用户手动配置 Linuxulator，脚本从未配置）

**修复建议**：FreeBSD 上默认禁用 convert 流程并给出明确报错；或文档说明需手动放置 FreeBSD 构建（社区第三方）/ 启用 Linuxulator。

---

## 🟡 中等问题

### 4. TUN 引导提示在 FreeBSD 上给出 Linux 建议

**位置**：`clashctl.sh:1636-1640`（`tun_container_runtime_hint_lines`）

- 缺 `ip` 命令时提示："Debian/Ubuntu 可安装：apt update && apt install -y iproute2"——FreeBSD 无 apt 且不需要 ip 命令
- 缺 `capsh` 时提示"请检查容器启动参数"——FreeBSD 主机无容器/capability 概念

对比 `tun_problem_lines`（clashctl.sh:5698-5700）正确做了 `[ "$(get_os)" != "freebsd" ]` 门控——同一文件内两处行为不一致。

### 5. 端口自动避让范围与文档不符

| 端口 | 代码（clashctl.sh:165,175） | 文档（AGENTS.md / README） |
|------|------|------|
| Controller | `9000-9199` | `9090-9199` |
| DNS | `1053-1999` | `1053-1199` |

### 6. `uninstall.sh:33` 的 `\|\| true` 兜不住 `die`

`service_stop || true` 在 freebsd-rc 后端下非 root 执行时：`freebsd_require_root` → `die` → `exit 1` **直接中止整个卸载脚本**，`|| true` 对 `exit` 无效，后续清理项（rc.d 文件、clashctl 入口等）全部静默跳过。建议在 uninstall 开头显式检查 root 并输出完整说明。

---

## 🟢 轻微问题

### 7. 安装默认开启开机自启

`freebsd.sh:91-95` + `132-144`：`freebsd_service_autostart_preference_enabled` 默认返回 0 → `install_freebsd_entry` 默认写 `clash_freebsd_enable="YES"`。而 rc.d 模板第 84 行默认值是 `NO`，两者不一致；默认自启行为未在 README 说明。

### 8. 自启状态只读 `/etc/rc.conf.d/clash_freebsd`

`freebsd.sh:160-178`：用户若用 `sysrc clash_freebsd_enable=YES` 写入 `/etc/rc.conf`，`clashctl autostart status` 仍显示 off。

### 9. `stop_runtime` 的 kill 间隔

`runtime.sh:631-634`：`kill` 后固定 `sleep 1` 即 `kill -9`，TUN/路由清理中的 mihomo 可能被过早强杀。FreeBSD 下暂无实际影响（TUN 本就不可用），列为观察项。

---

## ✅ 已验证无错误的部分

| 模块 | 结论 |
|------|------|
| rc.d 脚本生成（freebsd.sh:35-87） | PROVIDE/REQUIRE/KEYWORD: shutdown、rcvar、load_rc_config、`service` 调用均正确；boot 时 PATH 含 `/usr/local/bin`（/etc/rc 设置），bash/curl 可用 |
| `resolve_mihomo` FreeBSD 资产名 | compatible/v1/v3/plain/amd64/arm64 候选全部真实存在于 v1.19.23 发布页 |
| `resolve_yq` | `yq_freebsd_amd64/arm64.tar.gz` 存在，解包名处理正确 |
| `resolve_clash` | 明确拒绝 FreeBSD（die_state），正确 |
| `default_route_dev` / `ui_lan_ip` | `route -n get default` + `ifconfig` 的 FreeBSD 分支正确，且有 `ip` 命令优先级回退 |
| `tun_device_exists` / jail 检测 | `/dev/tun*` 检查、`security.jail.jailed` 检测正确 |
| `kv_write` 写 rc.conf | 自动 `mkdir -p /etc/rc.conf.d`，无 `export` 前缀符合 rc.conf 格式 |
| geo 数据准备 | Country.mmdb 缓存/回退逻辑无平台问题 |
| 卸载/重装流程 | rc.d、completion、alias wrapper 清理路径完整 |

---

## 修复优先级建议

1. **P0 - `is_port_in_use()`**：纯脚本 bug，加 `sockstat` 分支即可修复（一行级改动），同时修复 doctor 误报与 subconverter 误判
2. **P0 - TUN 防护**：FreeBSD 上 `tun on` 明确报错"内核不支持"，避免用户陷入 partial 状态排查；`auto-route`/`auto-detect-interface` 默认 false
3. **P1 - subconverter**：产品决策——FreeBSD 默认禁用 convert 流程，或文档明确要求手动放置 FreeBSD 构建/启用 Linuxulator
4. **P2**：提示文案的 FreeBSD 门控、端口范围文档对齐、uninstall root 检查

---

## 参考来源

- [FreeBSD netstat(1) 手册](https://man.freebsd.org/cgi/man.cgi?query=netstat&sektion=1) — 确认无 `-l`/`-t` 选项
- [metacubex/sing-tun v0.4.17 tun_other.go](https://github.com/metacubex/sing-tun/blob/v0.4.17/tun_other.go) — FreeBSD TUN 创建返回 `os.ErrInvalid`
- [MetaCubeX/mihomo v1.19.23 listener/sing_tun/server.go](https://github.com/MetaCubeX/mihomo/blob/v1.19.23/listener/sing_tun/server.go) — AutoRoute/AutoDetectInterface 触发致命错误路径
- [tindy2013/subconverter v0.9.0 发布资产](https://github.com/tindy2013/subconverter/releases/tag/v0.9.0) — 无 FreeBSD 构建
- [BSD 手册：Mihomo](https://book.bsdcn.org/fu-lu-i-gong-ju-yu-zi-yuan/mihomo)
