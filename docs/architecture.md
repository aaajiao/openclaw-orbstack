# 系统架构

## AI 在哪里运行？

**重要**: AI 大脑（LLM）运行在**云端**，不在本地！

```
☁️  云端 AI 服务器 (Anthropic Claude / OpenAI GPT / Google Gemini)
     ↑ HTTPS API 调用
     │ (AI 在这里"思考")
     │
┌────┴────────────────────────────────────────────────────────────────────────┐
│  OrbStack VM (openclaw-vm)                                                   │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  Gateway 进程 (协调器)                                                  │ │
│  │  - 接收聊天消息 (Telegram/WhatsApp/Web)                                 │ │
│  │  - 调用云端 AI API                                                      │ │
│  │  - 处理 AI 返回的工具调用                                               │ │
│  │  - 分发工具执行到沙箱                                                   │ │
│  └────────────────────────────┬───────────────────────────────────────────┘ │
│                               │                                              │
│               ┌───────────────┴───────────────┐                             │
│               ▼                               ▼                             │
│  ┌─────────────────────────┐  ┌─────────────────────────┐                   │
│  │ 代码执行沙箱 (Docker)    │  │ 浏览器沙箱 (Docker)      │                   │
│  │ sandbox.docker 配置      │  │ sandbox.browser 配置    │                   │
│  │                         │  │                         │                   │
│  │ exec, read, write, edit │  │ browser (Playwright)    │                   │
│  └─────────────────────────┘  └─────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

**沙箱是 AI 的"手"**——AI 在云端思考决策，通过 Gateway 指挥沙箱执行具体操作。

## 扩展能力

Gateway 还支持以下扩展能力：

| 能力 | 说明 | 配置位置 |
|------|------|----------|
| **Hooks** | 外部事件触发 AI 动作（如 GitHub push → 自动处理） | `hooks` |
| **Cron** | 定时任务（定期执行 AI 工作流） | `cron` |
| **Plugins** | 插件系统，扩展频道和功能 | `plugins` |
| **Skills** | 可复用能力包，按 Agent 隔离 | `skills` |
| **Talk Mode** | 实时语音对话（需 macOS/iOS/Android App） | `talk` |
| **$include** | 多文件配置，拆分管理大型配置 | 配置文件根级别 |

## 系统概览

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  macOS Host                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  OrbStack VM (openclaw-vm) - Ubuntu LTS                                 ││
│  │                                                                          ││
│  │  ┌─────────────────────────────────────────────────────────────────┐    ││
│  │  │  Gateway 进程 (Node.js, systemd 管理)                            │    ││
│  │  │  - Web UI :18789                                                 │    ││
│  │  │  - API Gateway                                                   │    ││
│  │  │  - Session Management                                            │    ││
│  │  │  - 直接调用 docker 命令管理沙箱容器                                │    ││
│  │  └───────────────────────────┬─────────────────────────────────────┘    ││
│  │                              │ docker exec/create/start                  ││
│  │                              ▼                                           ││
│  │  ┌─────────────────────────────────────────────────────────────────┐    ││
│  │  │  Docker Engine (仅供沙箱使用)                                     │    ││
│  │  │  ┌─────────────────────┐  ┌─────────────────────┐               │    ││
│  │  │  │ sandbox-common      │  │ sandbox-browser     │               │    ││
│  │  │  │ (代码执行)           │  │ (浏览器自动化)       │               │    ││
│  │  │  │                     │  │                     │               │    ││
│  │  │  │ - exec/read/write   │  │ - Chromium          │               │    ││
│  │  │  │ - network: bridge   │  │ - CDP protocol      │               │    ││
│  │  │  │ - 完全隔离           │  │ - 可访问网络         │               │    ││
│  │  │  └─────────────────────┘  └─────────────────────┘               │    ││
│  │  └─────────────────────────────────────────────────────────────────┘    ││
│  │                                                                          ││
│  │  Files in VM:                                                            ││
│  │  - ~/openclaw/          Git repo (Node.js 源码)                         ││
│  │  - ~/.openclaw/         配置、会话、工作区                               ││
│  └─────────────────────────────────────────────────────────────────────────┘│
│                                                                              │
│  Mac-side commands: ~/bin/openclaw-*                                        │
│  Access URL: http://openclaw-vm.orb.local:18789                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 为什么选择这个架构？

**官方推荐**: OpenClaw 设计为 Gateway 运行在宿主机，通过 Docker CLI 管理沙箱容器。

**安全优势**: 相比直接在 Mac 上运行，我们多了一层 VM 隔离：

| 攻击场景 | 直接安装 | OrbStack 架构 |
|---------|---------|--------------|
| 沙箱逃逸 | 危及 Mac | 只到 VM |
| Gateway 漏洞 | 危及 Mac | 只到 VM |
| 恶意代码 | 访问 Mac 文件 | 只访问 VM |
| 最坏情况 | 重装系统 | 删除 VM |

## 部署流程

```
步骤 1: 检查 OrbStack
    │   确认 Mac 上有 orb 命令
    ▼
步骤 2: 创建 Ubuntu VM
    │   orb create ubuntu openclaw-vm
    ▼
步骤 3: 安装 Docker
    │   curl -fsSL https://get.docker.com | sh
    │   (仅供沙箱容器使用)
    ▼
步骤 4: 安装 Node.js
    │   Node.js 22.x LTS + build-essential
    ▼
步骤 5: 克隆并构建 OpenClaw
    │   git clone + npm install + npm run build
    ▼
步骤 6: 构建沙箱镜像
    │   ├── openclaw-sandbox:bookworm-slim        (基础镜像，构建依赖)
    │   ├── openclaw-sandbox-common:bookworm-slim  (基于基础镜像 + 开发工具)
    │   └── openclaw-sandbox-browser:bookworm-slim (独立构建，Chromium)
    ▼
步骤 7: 运行配置向导
    │   ./openclaw setup (交互式)
    │   - 配置 AI 提供商 API Key
    │   - 配置聊天频道
    │   - 自动提取敏感信息到 ~/.openclaw/.env
    ▼
步骤 8: 配置 systemd 和命令
        - 创建 openclaw-gateway.service (user-level systemd)
        - 在 Mac 上创建 ~/bin/openclaw-* 命令
        - 合并沙箱配置
```

## 创建的文件

### VM 内 (~/)

```
~/openclaw/                    # Git repo (源码)
  ├── dist/                    # 编译后的代码
  ├── node_modules/            # 依赖
  ├── package.json
  └── ...

~/.openclaw/                   # 配置目录
  ├── openclaw.json            # 主配置 (含沙箱设置, 用 ${VAR} 引用 .env)
  ├── .env                     # 敏感信息 (API keys, tokens, Bonjour 设置)
  ├── credentials/             # API keys, tokens
  ├── memory/                  # Memory 索引 (<agentId>.sqlite)
  ├── agents/                  # Agent 数据 (sessions 等)
  ├── workspace/               # Agent workspace
  │   ├── AGENTS.md            # Agent 指令
  │   ├── MEMORY.md            # 长期记忆 (可选)
  │   └── memory/              # 每日记忆 (YYYY-MM-DD.md)
  └── sandboxes/               # Sandbox workspaces
```

### systemd Service (user-level)

```
~/.config/systemd/user/openclaw-gateway.service
  - 由 openclaw onboard 自动创建
  - 通过 systemctl --user 管理
  - Environment:
    - NODE_ENV=production
    - OPENCLAW_DISABLE_BONJOUR=1    # 禁用 Bonjour 避免冲突
    - CLAWDBOT_DISABLE_BONJOUR=1    # 兼容旧版
```

**关于 Bonjour**：OrbStack 环境下，macOS 的 mDNSResponder 会与 Gateway 的 Bonjour 服务冲突，
导致 `hostname conflict` 警告循环。通过环境变量禁用 Bonjour 可解决此问题。
详见 [troubleshooting.md](troubleshooting.md#1-bonjour-hostname-conflict-警告)。

### Mac 端 (~/bin/)

```
~/bin/
  ├── openclaw               # CLI 入口 (透传参数)
  ├── openclaw-config        # 编辑配置
  ├── openclaw-status        # systemctl status
  ├── openclaw-logs          # journalctl -f
  ├── openclaw-restart       # systemctl restart
  ├── openclaw-stop          # systemctl stop
  ├── openclaw-start         # systemctl start
  ├── openclaw-shell         # 进入 VM
  ├── openclaw-doctor        # 运行诊断
  ├── openclaw-update        # 更新版本 (仅应用，--sandbox 重建镜像)
  └── openclaw-sandbox-rebuild # 重建沙箱镜像
```

## Gateway 与沙箱的通信

```
Gateway (VM 进程)
    │
    │  docker create/start/exec
    │  (直接调用 Docker CLI)
    ▼
┌─────────────────────────────────────────┐
│  Docker Engine                          │
│                                         │
│  sandbox-common        sandbox-browser  │
│  ┌─────────────┐      ┌─────────────┐  │
│  │ network:    │      │ network:    │  │
│  │   bridge    │      │   bridge    │  │
│  │ 代码执行     │      │ 浏览器控制   │  │
│  │             │      │             │  │
│  │ 配置节:      │      │ 配置节:      │  │
│  │ sandbox.    │      │ sandbox.    │  │
│  │   docker    │      │   browser   │  │
│  └─────────────┘      └─────────────┘  │
└─────────────────────────────────────────┘
```

### 两个沙箱的配置对应关系

| 配置节 | Docker 容器 | 用途 | 启动方式 |
|--------|-------------|------|----------|
| `sandbox.docker` | `openclaw-sandbox-common` | 代码执行 (exec, read, write) | 按需启动 |
| `sandbox.browser` | `openclaw-sandbox-browser` | 浏览器自动化 (Playwright) | `autoStart: true` |

> **v2026.2.21+**: The browser sandbox container now uses a dedicated Docker network (`openclaw-browser-net`) for network isolation. This is handled automatically by the upstream OpenClaw Docker setup — no configuration needed in `openclaw-orbstack-setup.sh`.

**注意**: `sandbox.docker` 这个配置名容易误解——它不是"Docker 通用配置"，而是"代码执行沙箱的配置"。

### 通信协议

- **代码沙箱**: 通过 Docker exec API 通信（网络可访问但 Mac 文件隔离）
- **浏览器沙箱**: 通过 CDP (Chrome DevTools Protocol) 通信

### 环境变量

沙箱容器的环境变量在 `sandbox.docker.env` 配置：

```json
{
  "sandbox": {
    "docker": {
      "env": {
        "LANG": "C.UTF-8",
        "OPENAI_API_KEY": "sk-xxx"
      }
    }
  }
}
```

**注意**: `OPENCLAW_GATEWAY_TOKEN` 由 Gateway 自动注入，不需要手动配置。

**重要**: Docker 容器是保护 Mac 文件的唯一隔离层。VM 通过 `/mnt/mac` 可访问 Mac 文件。

> 多 Agent 场景下容器隔离策略详见 [multi-agent.md](multi-agent.md#沙箱与-docker-容器)，沙箱完整安全模型详见 [sandbox.md](sandbox.md)。
