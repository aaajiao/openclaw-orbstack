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

`openclaw-update` 是**唯一**的更新命令。它先更新 wrapper（本仓库，重新生成 `~/bin/openclaw-*` 命令），再把 wrapper 对齐的 OpenClaw 版本装进 VM——一条命令搞定，老用户的肌肉记忆重新生效。

```bash
openclaw-update                     # 跟随当前通道（见下表）
openclaw-update --pre               # 切到 beta 通道（会记住）
openclaw-update --stable            # 切回 stable 通道（会记住）
openclaw-update --version=<tag>     # 把 wrapper + OpenClaw 一起钉到指定 tag（可回滚）
openclaw-update --sandbox           # 同时重建沙箱 Docker 镜像
openclaw-update --force             # 强制重建 / 允许降级
```

| 参数 | wrapper 通道 | 说明 |
|------|-------------|------|
| *(默认)* | 跟随**当前**通道 | 分支检出 → 更新命令自己 `git pull` 分支；检出在 stable tag 上 → 跟随最新 stable tag；检出在 beta tag 上 → 跟随含 pre-release 的最新 tag |
| `--pre` | **beta** 通道，会记住 | 切到含经验证 pre-release 的最新 tag，之后一直停留在这条线，直到 `--stable` |
| `--stable` | **stable** 通道，会记住 | 切回最新 stable tag；由此触发的 VM 侧 OpenClaw 降级通常仍需要 `--force`（或等下一个 stable） |
| `--version=<tag>` | **钉版本（pinned）** | 若存在对应的 wrapper tag `<tag>`，会把 wrapper 与 OpenClaw **一起**钉住——之后再跑一次不带参数的 `openclaw-update` 会保持这个钉住状态并提示；`--pre`/`--stable` 会恢复跟随通道。若没有匹配的 wrapper tag，则只钉 OpenClaw 版本（与旧行为一致） |

- **不会静默降级 OpenClaw**。若目标版本比 VM 里已构建的**更旧**，除非加 `--force`，否则拒绝执行（`--version=` 钉版本路径豁免）。
- **基于 npm、诚实**。装完预编译 npm 包后会**轮询确认 Gateway 真正启动成功**；包不完整就停下报错（给日志提示），而不是悄悄掉进又长又花屏的源码编译。
- **自愈**。自动检测并修复旧版安装——比如把老的系统级服务迁到当前用户级服务，或重建丢失的插件目录。
- **保持 git checkout 同步**。`~/openclaw` 检出始终对齐目标 tag，因为沙箱 Docker 镜像就是从这个仓库构建的。

> **说明**：自 v2026.7.1 起，`refresh-mac-commands.sh` 不再自动 `git pull` wrapper 仓库——分支检出时由 `openclaw-update` 自己拉取 `main`，其内建的 wrapper 阶段成为唯一交付路径。钉某个 tag 会让仓库进入 detached HEAD，更新会尊重这一点、不会把你的锁定改掉。

### 版本 & 发布模型

wrapper 版本始终**镜像一个真实的上游 OpenClaw 版本**——我们从不自己编版本号。

| 上游 OpenClaw | wrapper release | 如何获取 |
|--------------|-----------------|---------|
| stable 版本 | 发布为 **Latest** | `openclaw-update --stable` |
| 经验证 / 测试过的 **beta** | 发布为 **pre-release** | `openclaw-update --pre` |

当前状态（示意，实时对照见 [GitHub Releases](https://github.com/aaajiao/openclaw-orbstack/releases)）：wrapper stable 为 **v2026.7.1**（Latest）。

## 快速开始

```bash
# PATH 在安装时已自动配置 — 打开新终端窗口即可使用

# 查看服务状态
openclaw-status

# 查看日志
openclaw-logs

# Telegram Bot 配对
openclaw channels add --channel telegram --token <bot_token>   # 添加 Bot
openclaw pairing approve telegram <code>                       # 回执验证码

# WhatsApp 登录
openclaw channels login --channel whatsapp

# 编辑配置
openclaw-config edit

# 使用官方 CLI (150+ 命令)
openclaw --help
openclaw status
openclaw channels list
openclaw doctor
```

## Mac 端命令

共 10 个命令，由 `scripts/refresh-mac-commands.sh` 中的统一命令表生成。曾经的 5 个兼容别名（`openclaw-stop`、`openclaw-start`、`openclaw-doctor`、`openclaw-whatsapp`、`openclaw-telegram`）已彻底移除，请改用原生命令；重新生成命令时会顺带清理 `~/bin` 里的旧别名文件。

| 命令 | 功能 |
|------|------|
| `openclaw` | CLI 透传 (所有官方命令) |
| `openclaw-config` | 配置管理 |
| `openclaw-status` | 服务状态 |
| `openclaw-logs` | 实时日志 |
| `openclaw-restart` | 重启服务 |
| `openclaw-shell` | 进入 VM |
| `openclaw-update` | **更新一切：wrapper + OpenClaw**（通道：`--pre`/`--stable`；另有 `--version=<tag>`、`--sandbox`、`--force`） |
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

`openclaw-update` 一条命令搞定：先更新 wrapper（选通道），再把对齐的 OpenClaw 装进 VM。完整说明见上方 [「## 更新」](#更新) 一节，或 [commands.md 更新命令详情](commands.md#更新命令详情)。

### 常见问题速查

| 问题 | 解决方案 |
|------|----------|
| Bonjour hostname conflict 警告 | 重新运行部署脚本或手动添加环境变量 |
| Port 18789 already in use | `openclaw-restart` 或 `openclaw-update` |
| Memory 目录错误 | `mkdir -p ~/.openclaw/memory` |
| Memory search 无法使用 | 在 agent auth-profiles.json 中添加 OpenAI/Google key |
| Wrapper 命令过期/需刷新 | `openclaw-update` |

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
