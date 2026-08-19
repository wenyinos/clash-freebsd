# 内置运行依赖

如果安装时 GitHub 下载太慢，可以把 yq 提前放到本目录。安装和 `clashctl upgrade` 会优先读取这里的文件；没有匹配文件时，仍会回退到原来的下载逻辑。

Clash 是兼容内核，固定走远程下载，不使用本目录中的本地资源。FreeBSD 下 mihomo 由 pkg 管理，无需放置资源文件。

默认目录结构（推荐）：

```text
resources/bin/
  yq/
    yq_freebsd_amd64.tar.gz
    yq_freebsd_arm64.tar.gz
```

FreeBSD 当前正式支持 `amd64`、`arm64`。版本号要和 `.env` 里的 `YQ_VERSION` 对应。脚本只按当前目标文件名精确命中，不会扫描目录，也不会自动选择最高版本；如果本地没有对应文件，会继续联网下载。

yq 兼容旧路径 `resources/bin/<category>/<version>/<file>`，但默认推荐直接使用 `resources/bin/<category>/<file>`。

可选开关：

```bash
export CLASH_BUNDLED_ASSET_ENABLED=false
export CLASH_BUNDLED_ASSET_DIR=/path/to/assets
```

`Country.mmdb` 仍放在 `resources/geo/Country.mmdb` 或 `resources/geo/country.mmdb`。
