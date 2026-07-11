# OpenClaw OrbStack

在 Mac 上通过 OrbStack 一键部署 [OpenClaw](https://github.com/openclaw/openclaw) 聊天机器人平台。

[![English](https://img.shields.io/badge/Docs-English-blue?style=flat-square)](../README.md)

## 这是什么？

[OpenClaw](https://github.com/openclaw/openclaw) 是一个开源的个人 AI 助手，运行在你自己的设备上。

本项目（**openclaw-orbstack**）是一个**部署工具**——自动化 macOS 上的 OpenClaw 安装和 OrbStack VM 配置。默认使用预编译 npm 包安装（源码编译作为后备方案）。下方的架构（Gateway 进程 + Docker 沙箱）是 [OpenClaw 官方设计](https://docs.openclaw.ai/install)，不是我们发明的。我们只是把它打包成一键安装器，并提供 Mac 端便捷命令。

## 架构

```
☁️  云端 AI (Anthropic/OpenAI/Google)  ← AI 大脑在这里
     ↑ API 调用
     │
Mac ─┼─────────────────────────────────────────────────
     │
└── OrbStack
    └── Ubuntu VM (openclaw-vm)
        │
        ├── Gateway 进程 (协调器，不在 Docker 里)
        │   - 接收聊天消息
        │   - 调用云端 AI
        │   - 分发工具执行到沙箱
        │
        └── Docker (两个沙箱容器)
            ├── sandbox-common (代码执行)   ← sandbox.docker 配置
            └── sandbox-browser (浏览器)    ← sandbox.browser 配置
```

**重要概念**:
- ☁️ AI 大脑运行在**云端** (Anthropic/OpenAI/Google 服务器)
- 🔧 沙箱是 AI 的"手"——只执行工具，不运行 AI
- 📦 系统只有**两个**沙箱：代码执行 + 浏览器

**优势**:
- ✅ 符合 OpenClaw 官方推荐架构
- ✅ Gateway 能正常管理沙箱容器
- ✅ VM 隔离层保护 Mac 安全

## 前置条件

- macOS 12.3+
- [OrbStack](https://orbstack.dev) 已安装

## 安装

```bash
git clone https://github.com/aaajiao/openclaw-orbstack.git
cd openclaw-orbstack
bash openclaw-orbstack-setup.sh
```

脚本启动后会先让你选择语言（English / 中文），然后自动完成：创建 VM → 安装 Docker 和 Node.js → 安装 OpenClaw（通过 npm）→ 构建沙箱镜像 → 配置向导 → 启动服务

跳过语言选择提示，直接指定语言：

```bash
OPENCLAW_LANG=zh-CN bash openclaw-orbstack-setup.sh   # 中文
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh      # English
```

## 访问

Web 控制台: `http://openclaw-vm.orb.local:18789`

## 更新

有**两条**更新命令，它们**互相配合（compose）**。`openclaw-selfupdate` 负责选**通道（channel）**——即你处在哪个 wrapper release（stable，或用 `--pre` 切到经验证的 beta）；`openclaw-update` 再把这个 wrapper 对齐的 OpenClaw 版本装进 VM。通常按顺序连用：先选通道，再把它应用到 VM。

| 命令 | 更新什么 | 运行在 | 角色 |
|------|---------|--------|------|
| `openclaw-selfupdate` | **本 wrapper**（openclaw-orbstack —— `openclaw-*` 命令与脚本） | Mac 本机 | 选**通道**——把 wrapper 移到 stable tag、经验证的 beta（`--pre`）、或钉住/回滚的 tag |
| `openclaw-update` | **OpenClaw 本身**（VM 里的 AI 大脑） | VM 内 | 安装**当前 wrapper 对齐的** OpenClaw 版本 |

`openclaw-selfupdate` 不直接碰 VM——但它落到的那个 wrapper tag **决定了下一次 `openclaw-update` 会装哪个 OpenClaw 版本**。所以两条命令是连用的，不是各干各的。

### `openclaw-update` —— 把 OpenClaw 装进 VM

```bash
openclaw-update                     # 安装当前 wrapper 对齐的 OpenClaw 版本
openclaw-update --version=<tag>     # 安装 / 回滚到指定 OpenClaw 版本
openclaw-update --sandbox           # 同时重建沙箱 Docker 镜像
openclaw-update --force             # 即使已是最新也强制重建
```

- **跟随 wrapper 的版本**。默认它装的是当前 wrapper *对齐*的 OpenClaw 版本——即 wrapper 的 `VERSION`（镜像一个真实的上游 OpenClaw 版本），而**不是**简单的“上游最新 stable”。所以当 `openclaw-selfupdate --pre` 把你切到 beta wrapper 后，直接跑 `openclaw-update` 装的就是对应的 OpenClaw beta。
- **不会静默降级**。若 wrapper 对齐的目标版本比 VM 里已构建的**更旧**，除非加 `--force`，否则拒绝执行。要有意回滚就用 `--version=<tag>`（该路径豁免降级保护）。
- **基于 npm、诚实**。装完预编译 npm 包后会**轮询确认 Gateway 真正启动成功**；包不完整就停下报错（给日志提示），而不是悄悄掉进又长又花屏的源码编译。
- **自愈**。自动检测并修复旧版安装——比如把老的系统级服务迁到当前用户级服务，或重建丢失的插件目录。
- **保持 git checkout 同步**。`~/openclaw` 检出始终对齐目标 tag，因为沙箱 Docker 镜像就是从这个仓库构建的。

### `openclaw-selfupdate` —— 选通道（更新 wrapper 本身）

```bash
openclaw-selfupdate                 # 切到最新的 stable wrapper release
openclaw-selfupdate --pre           # 切到最新版本，含经验证的 pre-release（beta/rc/alpha）
openclaw-selfupdate --version=<tag> # 钉到指定 wrapper tag —— 例如 v2026.6.6（可回滚）
```

- **按 release 锁定的通道选择器**。默认检出最新 **stable** tag；`--pre` 切到最新版本（含经验证的 beta）；`--version=` 精确钉任意 tag，可回滚。
- **默认 / `--pre` 从不降级**。若当前检出已包含目标版本就是 no-op；只有显式 `--version=` 才能切到更旧的 tag。
- **只跑在 Mac 上，但并非与 OpenClaw 无关**。它只操作本地仓库检出、重新生成 `~/bin/openclaw-*` 命令，**从不直接碰 VM 本身**——但你落到的那个 tag **决定了下一次 `openclaw-update` 跟随哪个通道**。

### 组合用法

```bash
# 切到 beta 线 —— VM 里的 OpenClaw 会走到对应的 beta：
openclaw-selfupdate --pre
openclaw-update

# 留在 / 回到 stable：
openclaw-selfupdate
openclaw-update
```

> **说明**：`openclaw-selfupdate` 目前是**可选（opt-in）**命令。当你的检出在分支上时，`refresh-mac-commands.sh` 仍会自动 `git pull` wrapper 仓库的 `main` 分支，所以分支用户会自动保持最新。用 `openclaw-selfupdate` 钉某个 tag 会让仓库进入 detached HEAD，这个自动 pull 会尊重这一点、不会把你的锁定改掉。把 `openclaw-selfupdate` 变成**唯一**的 wrapper 分发方式（即彻底移除这段 auto-pull 逻辑），这个完整切换推迟到 v2026.7.1 line 的**第一个 stable release**。

### 版本 & 发布模型

wrapper 版本始终**镜像一个真实的上游 OpenClaw 版本**——我们从不自己编版本号。

| 上游 OpenClaw | wrapper release | 如何获取 |
|--------------|-----------------|---------|
| stable 版本 | 发布为 **Latest** | `openclaw-selfupdate` |
| 经验证 / 测试过的 **beta** | 发布为 **pre-release** | `openclaw-selfupdate --pre` |

当前状态（示意，实时对照见 [GitHub Releases](https://github.com/aaajiao/openclaw-orbstack/releases)）：wrapper stable 为 **v2026.6.11**（Latest）；**v2026.7.1-beta.5** 作为 pre-release 提供。

## 快速开始

```bash
# PATH 在安装时已自动配置 — 打开新终端窗口即可使用

# 查看服务状态
openclaw-status

# 查看日志
openclaw-logs

# Telegram Bot 配对
openclaw-telegram add <bot_token>      # 添加 Bot
openclaw-telegram approve <code>       # 回执验证码

# WhatsApp 登录
openclaw-whatsapp

# 编辑配置
openclaw-config edit

# 使用官方 CLI (150+ 命令)
openclaw --help
openclaw status
openclaw channels list
openclaw doctor
```

## Mac 端命令

共 16 个命令，由 `scripts/refresh-mac-commands.sh` 中的统一命令表生成；其中 5 个已弃用为兼容别名——仍可正常使用，但会在 stderr 打印一行 `[deprecated]` 提示并指向原生替代命令，移除推迟到未来某个 stable release。

| 命令 | 功能 |
|------|------|
| `openclaw` | CLI 透传 (所有官方命令) — 推荐优先用它，而非下面的已弃用别名 |
| `openclaw-telegram` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw channels add --channel telegram --token <token>` / `openclaw pairing approve telegram <code>` |
| `openclaw-whatsapp` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw channels login --channel whatsapp` |
| `openclaw-config` | 配置管理 |
| `openclaw-status` | 服务状态 |
| `openclaw-logs` | 实时日志 |
| `openclaw-restart` | 重启服务 |
| `openclaw-stop/start` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw gateway stop` / `openclaw gateway start` |
| `openclaw-shell` | 进入 VM |
| `openclaw-doctor` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw doctor` |
| `openclaw-update` | 更新 **VM 内上游 OpenClaw** (`--sandbox` 重建镜像，`--force` 强制重建，`--version=<tag>` 装指定版本) |
| `openclaw-selfupdate` | 更新 **wrapper 本身** (`--pre` 收 pre-release，`--version=<tag>` 锁定/回滚) |
| `openclaw-sandbox-rebuild` | 重建沙箱镜像 |
| `openclaw-codex-login` | 绑定 ChatGPT 订阅（Codex CLI device-code 登录，可选） |
| `openclaw-uninstall` | 完全卸载 |

完整命令参考见 [commands.md](commands.md)

## 配置

配置文件: `~/.openclaw/openclaw.json` (VM 内)

```bash
openclaw-config edit     # 编辑
openclaw-config show     # 查看
openclaw-config backup   # 备份
```

详细配置说明见 https://docs.openclaw.ai/gateway/configuration

## 故障排查

```bash
openclaw-status        # 服务状态
openclaw-logs          # 查看日志
openclaw doctor        # 运行诊断
openclaw-shell         # 进入 VM 排查
```

详细故障排查指南见 [troubleshooting.md](troubleshooting.md)

### 已安装用户升级

两条更新命令**互相配合**：`openclaw-selfupdate` 选通道（哪个 wrapper release），`openclaw-update` 再把该 wrapper 对齐的 OpenClaw 装进 VM。完整说明见上方 [「## 更新」](#更新) 一节，或 [commands.md 更新命令详情](commands.md#更新命令详情)。

### 常见问题速查

| 问题 | 解决方案 |
|------|----------|
| Bonjour hostname conflict 警告 | 重新运行部署脚本或手动添加环境变量 |
| Port 18789 already in use | `openclaw-restart` 或 `openclaw-update` |
| Memory 目录错误 | `mkdir -p ~/.openclaw/memory` |
| Memory search 无法使用 | 在 agent auth-profiles.json 中添加 OpenAI/Google key |
| Wrapper 命令过期/需刷新 | `openclaw-selfupdate` |

### Memory 目录问题

如果遇到 `EISDIR: illegal operation on a directory` 错误，手动创建 memory 索引目录：

```bash
openclaw-shell
mkdir -p ~/.openclaw/memory
chmod 755 ~/.openclaw/memory
exit
openclaw-restart
```

### 备份和恢复

```bash
orb export openclaw-vm ~/Desktop/backup.tar.zst   # 导出 VM 快照
orb import -n openclaw-vm ~/Desktop/backup.tar.zst # 从快照恢复
```

详见 [troubleshooting.md](troubleshooting.md)。

## 文档

| 文档 | 内容 |
|------|------|
| [commands.md](commands.md) | CLI 命令完整参考 |
| [architecture.md](architecture.md) | 系统架构说明 |
| [troubleshooting.md](troubleshooting.md) | 故障排查 (OrbStack 特有) |
| [development.md](development.md) | 开发指南 |

## License

MIT
