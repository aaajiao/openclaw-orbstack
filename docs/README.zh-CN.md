# OpenClaw OrbStack

在 Mac 上通过 OrbStack 一键部署 OpenClaw 聊天机器人平台。

**[English](../README.md)**

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

脚本启动后会先让你选择语言（English / 中文），然后自动完成：创建 VM → 安装 Docker/Node.js → 构建 OpenClaw → 配置向导 → 启动服务

跳过语言选择提示，直接指定语言：

```bash
OPENCLAW_LANG=zh-CN bash openclaw-orbstack-setup.sh   # 中文
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh      # English
```

## 访问

Web 控制台: `http://openclaw-vm.orb.local:18789`

## 快速开始

```bash
# 添加 ~/bin 到 PATH (bash 用 ~/.bashrc, fish 用 ~/.config/fish/config.fish)
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

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

| 命令 | 功能 |
|------|------|
| `openclaw` | CLI 透传 (所有官方命令) |
| `openclaw-telegram` | Telegram 管理 (add/approve) |
| `openclaw-whatsapp` | WhatsApp 登录 |
| `openclaw-config` | 配置管理 |
| `openclaw-status` | 服务状态 |
| `openclaw-logs` | 实时日志 |
| `openclaw-restart` | 重启服务 |
| `openclaw-stop/start` | 停止/启动服务 |
| `openclaw-shell` | 进入 VM |
| `openclaw-doctor` | 运行诊断 |
| `openclaw-update` | 更新版本 (仅应用，`--sandbox` 重建镜像) |
| `openclaw-sandbox-rebuild` | 重建沙箱镜像 |

完整命令参考见 [commands.md](commands.md)

## 配置

配置文件: `~/.openclaw/openclaw.json` (VM 内)

```bash
openclaw-config edit     # 编辑
openclaw-config show     # 查看
openclaw-config backup   # 备份
```

详细配置说明见 [configuration-guide.md](configuration-guide.md)

## 故障排查

```bash
openclaw-status        # 服务状态
openclaw-logs          # 查看日志
openclaw doctor        # 运行诊断
openclaw-shell         # 进入 VM 排查
```

详细故障排查指南见 [troubleshooting.md](troubleshooting.md)

### 已安装用户升级

```bash
openclaw-update
```

会自动检测并修复旧版配置（如从系统级服务迁移到用户级服务）。

### 常见问题速查

| 问题 | 解决方案 |
|------|----------|
| Bonjour hostname conflict 警告 | 重新运行部署脚本或手动添加环境变量 |
| Port 18789 already in use | `openclaw-restart` 或 `openclaw-update` |
| Memory 目录错误 | `mkdir -p ~/.openclaw/memory` |
| Memory search 无法使用 | 在 agent auth-profiles.json 中添加 OpenAI/Google key |
| Mac 端命令过旧 | `cd openclaw-orbstack && git pull && bash scripts/refresh-mac-commands.sh` |

### Memory 目录问题

如果遇到 `EISDIR: illegal operation on a directory` 错误，手动创建 memory 索引目录：

```bash
openclaw-shell
mkdir -p ~/.openclaw/memory
chmod 755 ~/.openclaw/memory
exit
openclaw-restart
```

## 文档

| 文档 | 内容 |
|------|------|
| [commands.md](commands.md) | CLI 命令完整参考 |
| [architecture.md](architecture.md) | 系统架构说明 |
| [configuration-guide.md](configuration-guide.md) | 配置指南 |
| [multi-agent.md](multi-agent.md) | 多 Agent 配置（路由、多 Bot、沙箱隔离） |
| [skills.md](skills.md) | Skills 使用指南 |
| [sandbox.md](sandbox.md) | 沙箱安全模型 |
| [voice-tts.md](voice-tts.md) | 语音功能 |
| [troubleshooting.md](troubleshooting.md) | 故障排查指南 |

## License

MIT
