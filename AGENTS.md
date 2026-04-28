# AGENTS.md - Clash for FreeBSD

## Project Overview

This is a **bash-based deployment and management tool** for Clash/Mihomo proxy on FreeBSD systems. It's NOT a traditional software project with tests/linting - it's an **operational tool** composed entirely of shell scripts.

**Key insight**: There are no unit tests, no package manager, no build system. The "build" is the shell script execution itself.

## Architecture

### Directory Structure
- `scripts/core/` - Main logic (clashctl.sh, config.sh, runtime.sh, common.sh)
- `scripts/init/` - Platform initialization (freebsd.sh, script.sh)
- `config/` - YAML templates (template.yaml, mixin.yaml, profiles.yaml)
- `runtime/` - **Gitignored** runtime state, logs, PID files, generated configs
- `resources/bin/` - Bundled binaries (yq, mihomo, subconverter)
- `resources/dashboard/` - Web UI assets (dist.zip)

### Entry Points
- `install.sh` - Main installer (sources scripts/core/* and scripts/init/*)
- `uninstall.sh` - Cleanup script
- `clashctl` - CLI tool (installed to `~/.local/bin/` or `/usr/local/bin/`)

## Critical Technical Details

### Dependencies
**Required system packages**: `bash curl unzip gtar gzip`

**Bundled tools** (auto-downloaded if missing):
- `yq` v4.52.4 - YAML processor (heavily used throughout)
- `mihomo` v1.19.23 - Proxy kernel (recommended)
- `subconverter` v0.9.0 - Subscription converter

### Port Allocation
- `7890` - Mixed proxy port (HTTP/SOCKS5)
- `9090` - External controller (REST API)
- `1053` - DNS listener

**Important**: Ports auto-resolve on conflict (7890-7999, 9090-9199, 1053-1199 ranges).

### File Locations (Runtime)
- `.env` - Main configuration (sourced by all scripts)
- `runtime/config.yaml` - Generated Mihomo config
- `runtime/subscriptions.yaml` - Subscription database
- `runtime/mihomo.pid` - Process PID file
- `runtime/install.env` - Installation metadata
- `runtime/build.env` - Build status tracking
- `runtime/tun.env` - TUN mode state

### FreeBSD-Specifics
- Service name: `clash_freebsd`
- rc.d script: `/usr/local/etc/rc.d/clash_freebsd`
- rc.conf: `/etc/rc.conf.d/clash_freebsd`
- TUN devices: `/dev/tun*` (not `/dev/net/tun` like Linux)

## Development Guidelines

### Working with Scripts
1. **All scripts use `set -euo pipefail`** - strict error handling
2. **Always source dependencies**: `source "$PROJECT_DIR/scripts/core/common.sh"`
3. **Use `yq` for YAML manipulation** - never raw sed/awk on YAML
4. **Logging functions**: `log()`, `info()`, `success()`, `warn()`, `error()`, `die()`

### State Management Pattern
```bash
# Read runtime value
read_runtime_value "KEY" 2>/dev/null || true

# Write runtime value
write_runtime_value "KEY" "value"

# Read from .env
read_env_value "KEY" 2>/dev/null || true

# Write to .env
write_env_value "KEY" "value"
```

### Key Functions to Know
- `init_project_context "$PROJECT_DIR"` - Sets up path variables
- `load_env_if_exists` - Sources .env file
- `detect_install_scope auto` - Determines system vs user install
- `ensure_required_commands` - Validates dependencies
- `resolve_runtime_kernel` - Downloads/installs mihomo or clash
- `generate_config` - Builds runtime/config.yaml from subscription

### Error Handling Pattern
```bash
die "Error message"                    # Fatal error
die_state "Error" "Next step hint"     # With actionable hint
die_missing "Thing" "clashctl doctor"  # Missing dependency
```

## Common Operations

### Installation Flow
```bash
bash install.sh                    # Full install
bash install.sh user               # User-scope only
bash install.sh system             # System-scope (requires root)
```

### CLI Commands (after install)
```bash
clashctl add <url> <name>          # Add subscription
clashctl use                       # Switch subscription
clashctl select                    # Switch node
clashon                            # Start proxy
clashoff                           # Stop proxy
clashctl doctor                    # Diagnostics
clashctl status                    # Status overview
clashctl tun on|off                # TUN mode
clashctl autostart on|off|status   # FreeBSD boot service
```

### Regenerate Config
```bash
clashctl config regen              # Rebuild runtime/config.yaml
```

## Configuration Structure

### .env Variables (Critical)
```bash
KERNEL_TYPE="mihomo"               # or "clash"
CLASH_SUBSCRIPTION_URL=""          # Subscription URL
CLASH_CONTROLLER_SECRET=""         # API secret (auto-generated if empty)
MIXED_PORT="7890"
EXTERNAL_CONTROLLER="0.0.0.0:9090"
CLASH_DNS_PORT="1053"
CLASH_AUTO_UPDATE_SUBSCRIPTIONS="true"
CLASH_BUNDLED_ASSET_ENABLED="true" # Use resources/bin/ binaries
```

### Subscription Format
Subscriptions are stored in `runtime/subscriptions.yaml`:
```yaml
active: default
sources:
  default:
    type: clash           # or "convert" for subconverter
    url: "https://..."
    enabled: true
```

### Mixin System
`runtime/mixin.yaml` allows overriding/appending to generated config:
```yaml
override: {}              # Deep merge overrides
prepend:
  proxies: []             # Prepend to arrays
  proxy-groups: []
  rules: []
append:
  proxies: []             # Append to arrays
  proxy-groups: []
  rules: []
```

## Testing & Validation

### No Test Suite
This project has **no automated tests**. Validation is done through:
1. `clashctl doctor` - Runtime diagnostics
2. `clashctl status` - State verification
3. Manual testing on FreeBSD systems

### Config Validation
```bash
# Validate YAML syntax
yq eval '.' runtime/config.yaml

# Test config with mihomo
mihomo -t -f runtime/config.yaml -d runtime/
```

### Text Encoding Check (CI)
```bash
bash .github/scripts/check-text-encoding.sh
```

## Quirks & Gotchas

### 1. Root vs Non-Root
- **Root required**: `service`, `autostart`, `tun on/off`
- **Non-root preferred**: `clashctl config regen`, `clashctl logs`, `clashctl secret`
- **Warning**: Running `sudo clashctl ...` can cause `.env` ownership drift

### 2. Subscription Auto-Update
Default: `CLASH_AUTO_UPDATE_SUBSCRIPTIONS="true"`
When disabled: `clashctl add` still works, but auto-fetch is blocked.

### 3. GitHub Mirror System
Downloads use mirror pool with fallback:
- `CLASH_GH_PROXY` - Custom proxy prefix
- `CLASH_GH_PROXY_POOL` - Multiple mirrors
- Automatic failover and cooldown (1800s)

### 4. Subconverter Integration
- Runs on `127.0.0.1:25500` (localhost only)
- Auto-starts when needed
- Converts various subscription formats to Clash YAML
- Logs: `runtime/logs/subconverter.log`

### 5. TUN Mode Specifics
- FreeBSD: `/dev/tun*` devices
- Linux: `/dev/net/tun`
- Requires root or `NET_ADMIN` capability
- Auto-route and auto-redirect are Linux-only features

### 6. Config Generation Pipeline
```
template.yaml + profiles.yaml → base config
    ↓
subscription download/convert
    ↓
normalize_runtime_config() → inject ports, TUN, DNS settings
    ↓
apply_runtime_mixin() → override/prepend/append
    ↓
test_runtime_config() → validate with mihomo -t
    ↓
runtime/config.yaml
```

### 7. Port Conflict Resolution
If preferred ports are in use, automatically finds alternatives:
- Mixed port: 7890-7999
- Controller: 9090-9199
- DNS: 1053-1199

### 8. Dashboard Assets
- Bundled: `resources/dashboard/dist.zip` or `resources/dashboard/dist/`
- Deployed to: `runtime/dashboard/`
- **Blocks install if missing** (not optional)

## File Editing Guidelines

### DO
- Use `yq` for YAML modifications
- Follow existing logging patterns (`info`, `warn`, `die`)
- Preserve `set -euo pipefail` in all scripts
- Use `write_env_value` / `read_env_value` for .env
- Use `write_runtime_value` / `read_runtime_value` for runtime state

### DON'T
- Use `sed`/`awk` on YAML files
- Hardcode paths (use `$PROJECT_DIR`, `$RUNTIME_DIR`, etc.)
- Skip error handling in critical paths
- Modify `runtime/config.yaml` directly (regenerate instead)

## Debugging

### Check Logs
```bash
clashctl logs                      # Mihomo logs
clashctl logs mihomo               # Same
cat runtime/logs/subconverter.log  # Subconverter logs
```

### Check State
```bash
clashctl status --verbose          # Detailed status
clashctl doctor                    # Environment check
cat runtime/install.env            # Installation metadata
cat runtime/build.env              # Build status
cat runtime/tun.env                # TUN state
```

### Common Issues
1. **Port conflict**: `sockstat -4 -l | grep 7890`
2. **Permission denied**: Check `.env` and `runtime/` ownership
3. **Subscription failed**: `clashctl doctor` + check `runtime/logs/`
4. **TUN not working**: Verify `/dev/tun*` exists and is readable

## References

- [mihomo](https://github.com/MetaCubeX/mihomo) - Proxy kernel
- [subconverter](https://github.com/tindy2013/subconverter) - Subscription converter
- [zashboard](https://github.com/Zephyruso/zashboard) - Web UI
