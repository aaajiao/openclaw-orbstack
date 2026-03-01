# 沙箱系统

## AI 在哪里运行？(重要概念)

**AI 大脑不在沙箱里运行！** 这是最常见的误解。

```
☁️  云端 (Anthropic/OpenAI/Google 服务器)
     ↑ API 调用 (AI 大脑在这里思考)
     │
┌────┴─────────────────────────────────────┐
│  Gateway 进程 (VM 上，不在 Docker 里)      │
│  - 接收聊天消息 (Telegram/WhatsApp)        │
│  - 调用云端 AI API (Claude/GPT/Gemini)     │
│  - 处理 AI 返回的工具调用请求              │
│  - 分发工具执行到沙箱                      │
└────┬─────────────────┬───────────────────┘
     │                 │
     ▼                 ▼
┌─────────────┐  ┌─────────────┐
│ 代码沙箱     │  │ 浏览器沙箱   │
│ (Docker)    │  │ (Docker)    │
│ 执行 exec   │  │ 执行 browser │
│ read/write  │  │ Playwright  │
└─────────────┘  └─────────────┘
```

| 组件 | 位置 | 作用 |
|------|------|------|
| **AI 大脑** | ☁️ 云端 (Anthropic/OpenAI/Google) | 思考、推理、决策 |
| **Gateway** | VM 上 (非 Docker) | 协调器，转发消息和工具调用 |
| **沙箱** | Docker 容器 | **只执行工具**，不运行 AI |

**沙箱是 AI 的"手"**——当 AI 说"我要执行这段代码"，Gateway 把请求发到代码沙箱执行，然后把结果返回给云端 AI。

## 两个沙箱容器，三个 Docker 镜像

运行时只有**两个**沙箱容器，但构建了**三个** Docker 镜像（基础镜像是 common 的构建依赖）：

| 配置节 | 容器名 | 用途 |
|--------|--------|------|
| `sandbox.docker` | `openclaw-sandbox-common` | **代码执行沙箱** (exec, read, write, edit) |
| `sandbox.browser` | `openclaw-sandbox-browser` | **浏览器沙箱** (Playwright, Chromium) |

**注意**: `sandbox.docker` 这个名字容易误解，它不是"Docker 配置"，而是"代码执行沙箱的 Docker 容器配置"。

## 架构图

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  沙箱系统                                                                    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐│
│  │  Gateway 进程 (VM 宿主机)                                                ││
│  │  - 接收用户消息                                                          ││
│  │  - 管理 AI 模型调用 (云端提供商)                                          ││
│  │  - 分发工具执行到沙箱                                                    ││
│  └───────────────────────────────────┬─────────────────────────────────────┘│
│                                      │                                       │
│                    ┌─────────────────┴─────────────────┐                    │
│                    ▼                                   ▼                    │
│  ┌─────────────────────────────────┐  ┌─────────────────────────────────┐  │
│  │  代码执行沙箱                    │  │  浏览器沙箱                      │  │
│  │  (sandbox.docker 配置)          │  │  (sandbox.browser 配置)         │  │
│  │  容器: sandbox-common           │  │  容器: sandbox-browser          │  │
│  │                                 │  │                                 │  │
│  │  工具:                          │  │  工具:                          │  │
│  │  - exec (运行命令)              │  │  - browser (网页自动化)         │  │
│  │  - read/write/edit (文件)       │  │                                 │  │
│  │  - process (进程管理)           │  │  特性:                          │  │
│  │                                 │  │  - Chromium + CDP               │  │
│  │  预装软件:                       │  │  - Xvfb (有头模式)              │  │
│  │  - Node.js, npm                 │  │  - noVNC (可选)                 │  │
│  │  - Python 3                     │  │                                 │  │
│  │  - Go, Rust                     │  │  启动方式:                       │  │
│  │  - git, curl, jq                │  │  - autoStart: true (自动启动)   │  │
│  │                                 │  │                                 │  │
│  │  启动方式:                       │  │  安全:                          │  │
│  │  - 按需启动 (无 autoStart)       │  │  - network: bridge              │  │
│  │                                 │  │  - 独立容器                      │  │
│  │  安全:                          │  │                                 │  │
│  │  - network: bridge              │  │                                 │  │
│  │  - readOnlyRoot: true           │  │                                 │  │
│  │  - user: 501:501                │  │                                 │  │
│  │  - capDrop: ALL                 │  │                                 │  │
│  └─────────────────────────────────┘  └─────────────────────────────────┘  │
│                                                                              │
│  构建的沙箱镜像 (3 个镜像，2 个运行时容器):                                    │
│  1. openclaw-sandbox:bookworm-slim        - 基础镜像 (构建依赖，不直接使用)  │
│  2. openclaw-sandbox-common:bookworm-slim - 基于 1 + 开发工具 (代码执行)     │
│  3. openclaw-sandbox-browser:bookworm-slim - 独立构建，带 Chromium (浏览器)   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 为什么需要 Docker 沙箱？(重要)

**OrbStack VM 并不能隔离 Mac 文件系统！**

| 组件 | Mac 文件访问 | 网络访问 |
|------|-------------|----------|
| OrbStack VM | ✅ 通过 `/mnt/mac` 完全访问 | ✅ 完全访问 |
| Docker 容器 | ❌ 只能看到挂载的 `/workspace` | ✅ Bridge 网络 |

Docker 容器是保护 Mac 文件的**唯一隔离层**:

```
Mac 文件系统 (/Users/*, Documents, Photos...)
     ↓ 自动挂载到
/mnt/mac (OrbStack VM 可完全访问)
     ↓ 但是
Docker 容器看不到！只能看到 /workspace
```

**不要设置 `sandbox.mode: "off"`** — 那样 AI 可以通过 `/mnt/mac` 访问你整个 Mac！

> 多 Agent 场景下，每个 Agent 可以覆盖沙箱配置（scope、网络、工具权限），详见 [multi-agent.md](multi-agent.md#沙箱与-docker-容器)。

## 默认配置

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "agent",
        "workspaceAccess": "rw",
        "workspaceRoot": "~/.openclaw/sandboxes",
        "docker": {
          "image": "openclaw-sandbox-common:bookworm-slim",
          "network": "bridge",
          "readOnlyRoot": true,
          "tmpfs": ["/tmp:exec,mode=1777", "/var/tmp", "/run"],
          "user": "501:501",
          "capDrop": ["ALL"],
          "memory": "1g",
          "cpus": 1,
          "pidsLimit": 256,
          "env": {
            "LANG": "C.UTF-8",
            "OPENAI_API_KEY": "sk-xxx",
            "GOOGLE_API_KEY": "AIzaSyxxx"
          }
        },
        "browser": {
          "enabled": true,
          "image": "openclaw-sandbox-browser:bookworm-slim",
          "autoStart": true,
          "autoStartTimeoutMs": 30000,
          "allowHostControl": true
        },
        "prune": {
          "idleHours": 24,
          "maxAgeDays": 7
        }
      }
    }
  },
  "tools": {
    "sandbox": {
      "tools": {
        "allow": ["group:runtime", "group:fs", "group:sessions", "group:ui"],
        "deny": ["canvas", "nodes", "cron", "gateway", "telegram", "whatsapp", "discord", "googlechat", "slack", "signal", "imessage"]
      }
    }
  },
  "browser": {
    "enabled": true
  }
}
```

## 安全模型

| 设置 | 安全收益 | 代价 |
|------|---------|------|
| `network: bridge` | 浏览器可访问网络 | 代码执行也有网络 (可接受 - Mac 文件仍受保护) |
| `readOnlyRoot: true` | 无法修改系统文件 | 无法安装软件 |
| `user: 501:501` | 匹配 macOS 用户权限 | - |
| `capDrop: ALL` | 无特殊 Linux 权限 | 系统调用受限 |
| `tmpfs: /tmp:exec` | Playwright 可在 /tmp 执行 | - |
| `workspaceAccess: rw` | - | 只能读写 workspace 文件 |
| Docker 隔离 | **Mac 文件系统受保护** | 只能看到挂载的 workspace |

### 网络配置选项

| 值 | 行为 | 使用场景 |
|----|------|----------|
| `bridge` | 完全网络访问 | **默认** - 浏览器自动化可用 |
| `none` | 无网络 | 最大隔离 (浏览器无法工作) |
| `host` | 共享宿主网络 | 不推荐 |

**为什么默认 `bridge` 而不是 `none`？**

- 浏览器自动化需要网络访问
- 真正的安全边界是**文件系统隔离**，不是网络
- Docker 容器看不到 Mac 文件，即使有网络访问

### 沙箱模式选项

| 模式 | 行为 | 浏览器可用？ | 推荐 |
|------|------|-------------|------|
| `off` | 不使用沙箱，直接在 VM 执行 | ❌ (VM 没有 GUI 浏览器) | **危险** - AI 可访问 `/mnt/mac` |
| `non-main` | 只有非主会话使用沙箱 | ⚠️ 只有非主会话 | 主会话无法用浏览器沙箱 |
| `all` | 所有会话都使用沙箱 | ✅ 全部可用 | **推荐** |

**为什么默认 `all` 而不是 `non-main`？**

- `non-main` 模式下，main session 直接在 VM 里运行
- VM 没有安装 GUI 浏览器，所以 main session 无法使用浏览器功能
- `all` 模式让所有会话都在 Docker 沙箱里运行，可以使用 sandbox-browser

### 工具组 (沙箱权限)

| 组 | 包含的工具 |
|----|-----------|
| `group:runtime` | exec, bash, process |
| `group:fs` | read, write, edit, apply_patch |
| `group:sessions` | sessions_list, sessions_history, sessions_send, sessions_spawn, session_status |
| `group:ui` | browser, canvas |

默认配置允许 `group:ui`（包含 browser），但 deny 了 `canvas`。

## 沙箱镜像

| 镜像 | 内容 | 角色 |
|------|------|------|
| `openclaw-sandbox:bookworm-slim` | 最小 Debian (bash, curl, git, jq) | **构建依赖** — sandbox-common 的基础层 |
| `openclaw-sandbox-common:bookworm-slim` | 基于上层 + Node, Python, Go, Rust | **运行时** — 代码执行沙箱 (`sandbox.docker`) |
| `openclaw-sandbox-browser:bookworm-slim` | 独立构建，Chromium, CDP, Xvfb | **运行时** — 浏览器沙箱 (`sandbox.browser`) |

> **Note**: Since v2026.2.20, upstream OpenClaw Dockerfiles pin base images by SHA256 digest (e.g., `node:22-bookworm@sha256:...`) for reproducible builds. The `openclaw-orbstack-setup.sh` script uses these pinned images automatically.

## 浏览器沙箱配置

| 设置 | 默认值 | 说明 |
|------|--------|------|
| `enabled` | `true` | 启用浏览器沙箱 |
| `autoStart` | `true` | 自动启动浏览器容器 |
| `autoStartTimeoutMs` | `30000` | 启动超时时间 (毫秒) |
| `allowHostControl` | `true` | 允许 `target="host"` 访问宿主浏览器 |

## 故障排查

### Browser sandbox 启动失败

检查容器日志：
```bash
docker logs openclaw-sbx-browser-agent-main-*
```

常见问题：
- `/tmp` 只读 → 确保 tmpfs 包含 `/tmp:exec,mode=1777`
- CDP 端口映射失败 → 删除旧容器重启

### 清理沙箱容器

```bash
# 删除所有沙箱容器
docker rm -f $(docker ps -aq --filter "name=openclaw-sbx") 2>/dev/null || true

# 重启 gateway
openclaw-restart
```

### `OPENCLAW_BROWSER_NO_SANDBOX`

Controls Chromium's internal sandbox within the browser container. When set to `1`, Chromium launches with `--no-sandbox --disable-setuid-sandbox`.

In OrbStack environments, this is **required** — OrbStack VM kernel restricts unprivileged user namespaces, causing Chromium to crash with "No usable sandbox!". The installer automatically applies a Docker image overlay that bakes this env var into the browser image. If you manually rebuild the browser image, run `openclaw-sandbox-rebuild` (which includes the overlay) rather than building the image directly.

> **Note**: Upstream OpenClaw v2026.2.27+ (PR #29879) also passes this env var at container runtime, making the image overlay redundant but harmless as belt-and-suspenders protection.

## 环境变量 (重要)

**沙箱容器不会继承 Gateway 的环境变量！** 如果需要在沙箱内使用 API Key，必须在 `sandbox.docker.env` 中显式配置。

### 配置位置说明

| 配置位置 | 作用域 | 示例用途 |
|---------|--------|---------|
| 顶层 `env: {}` | Gateway 进程 | Gateway 内部使用的变量 |
| `sandbox.docker.env` | Main sandbox 容器 | 代码执行时需要的 API Key |
| `sandbox.browser.env` | Browser sandbox 容器 | 浏览器自动化需要的变量 |

**三个位置是独立的，不会自动继承。**

### 正确配置示例

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "env": {
            "LANG": "C.UTF-8",
            "OPENAI_API_KEY": "sk-xxx",
            "ANTHROPIC_API_KEY": "sk-ant-xxx",
            "GOOGLE_API_KEY": "AIzaSyxxx"
          }
        },
        "browser": {
          "enabled": true,
          "autoStart": true
        }
      }
    }
  }
}
```

**注意**: `OPENCLAW_GATEWAY_TOKEN` 由 Gateway 自动注入到沙箱容器，不需要手动配置。

### 常见错误

❌ **错误**: 在顶层 `env` 配置 API Key，期望沙箱能用

```json
{
  "env": {
    "OPENAI_API_KEY": "sk-xxx"  // 这只给 Gateway 用，沙箱看不到！
  }
}
```

✅ **正确**: 在 `sandbox.docker.env` 配置

```json
{
  "agents": {
    "defaults": {
      "sandbox": {
        "docker": {
          "env": {
            "OPENAI_API_KEY": "sk-xxx"  // 沙箱容器可以使用
          }
        }
      }
    }
  }
}
```

### 保留变量名 (不能传递到沙箱)

以下变量名被 OpenClaw Gateway 内部使用，**不会传递到沙箱容器**：

| 变量名 | 原因 | 替代名称 |
|--------|------|---------|
| `TELEGRAM_BOT_TOKEN` | Gateway 用于连接 Telegram | `TG_BOT_TOKEN` |
| `DISCORD_BOT_TOKEN` | Gateway 用于连接 Discord | `DISCORD_TOKEN` |

如果需要在沙箱内使用这些 token，请改用替代名称：

```json
{
  "sandbox": {
    "docker": {
      "env": {
        "TG_BOT_TOKEN": "123456:ABC...",  // ✅ 可以传递
        "TELEGRAM_BOT_TOKEN": "..."       // ❌ 会被过滤
      }
    }
  }
}
```
