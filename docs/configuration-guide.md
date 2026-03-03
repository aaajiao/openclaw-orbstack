# OpenClaw 配置完全指南

本文档提供 OpenClaw 配置的详细说明，帮助你快速上手并根据需要自定义配置。

## 目录

- [快速开始](#快速开始)
- [配置文件位置](#配置文件位置)
- [配置格式](#配置格式)
- [最小配置](#最小配置)
- [配置模板](#配置模板)
- [常见配置场景](#常见配置场景)
- [配置项详解](#配置项详解)

---

## 快速开始

### 1. 编辑配置

**推荐方式** - 使用 `openclaw-config` 命令：

```bash
# 编辑配置（自动处理权限）
openclaw-config edit

# 查看当前配置
openclaw-config show
```

**手动方式** - 进入 VM 后编辑：

```bash
openclaw-shell
sudo nano ~/.openclaw/openclaw.json
```

### 2. 填入必要信息

- **AI API Key**: 至少配置一个 AI 提供商 (Anthropic/OpenAI/Google)
- **聊天平台**: 配置 Telegram Bot Token 或其他平台凭据
- **允许列表**: 设置允许使用机器人的用户

### 3. 重启服务

```bash
openclaw-restart
```

---

## 配置文件位置

| 路径 | 说明 |
|------|------|
| `~/.openclaw/openclaw.json` | 主配置文件 |
| `~/.openclaw/agents/<agentId>/auth-profiles.json` | 认证配置 (OAuth + API Key) |
| `~/.openclaw/credentials/` | 平台凭据目录 |
| `~/.openclaw/workspace/` | 默认工作区 |

> **环境变量**: 可通过 `OPENCLAW_STATE_DIR` 自定义状态目录

---

## 配置格式

OpenClaw 使用 **JSON5** 格式，支持：

- 单行注释: `// 这是注释`
- 多行注释: `/* 这也是注释 */`
- 尾随逗号: `{ "key": "value", }`
- 无引号键名: `{ key: "value" }`

```json5
{
  // 这是一个 JSON5 配置示例
  identity: {
    name: "OpenClaw",
    emoji: "🦞",
  },
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
    }
  }
}
```

---

## 最小配置

只需几行就能运行：

```json5
{
  agents: { defaults: { workspace: "~/.openclaw/workspace" } },
  channels: { whatsapp: { allowFrom: ["+8613800138000"] } }
}
```

---

## 配置模板

完整配置模板位于 `templates/openclaw.json.example`，包含所有可用选项和详细注释。

### 快速配置示例

#### 推荐入门配置

```json5
{
  // 身份设置
  identity: {
    name: "小助手",
    theme: "helpful assistant",
    emoji: "🦞"
  },
  
  // Agent 配置
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "anthropic/claude-sonnet-4-5" },
    }
  },

  // WhatsApp 配置
  channels: {
    whatsapp: {
      allowFrom: ["+8613800138000"],
      groups: { "*": { requireMention: true } }
    }
  }
}
```

#### 多平台配置

```json5
{
  agents: { defaults: { workspace: "~/.openclaw/workspace" } },
  channels: {
    whatsapp: { allowFrom: ["+8613800138000"] },
    telegram: {
      enabled: true,
      botToken: "123456:ABC...",
      allowFrom: ["123456789"]
    },
    discord: {
      enabled: true,
      token: "YOUR_TOKEN",
      dm: { allowFrom: ["username"] }
    }
  }
}
```

---

## 常见配置场景

### 场景 1: 个人使用 (安全优先)

```json5
{
  identity: { name: "个人助手", emoji: "🤖" },
  
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "anthropic/claude-sonnet-4-5" },
      // 完全沙箱隔离 (浏览器需要网络，但 Mac 文件仍然隔离)
      sandbox: {
        mode: "all",
        scope: "session",
        workspaceAccess: "rw",
        docker: {
          network: "bridge",  // 浏览器自动化需要网络
          readOnlyRoot: true,
          user: "501:501"     // macOS 用户权限
        }
      }
    }
  },
  
  channels: {
    whatsapp: {
      dmPolicy: "allowlist",
      allowFrom: ["+8613800138000"],  // 只允许你自己
      groups: { "*": { requireMention: true } }
    }
  },
  
  tools: {
    elevated: {
      enabled: true,
      allowFrom: { whatsapp: ["+8613800138000"] }
    }
  }
}
```

### 场景 2: 团队使用 (多用户)

```json5
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "anthropic/claude-sonnet-4-5" },
      sandbox: { mode: "all", workspaceAccess: "rw" }  // all 模式支持浏览器
    }
  },
  
  channels: {
    telegram: {
      enabled: true,
      botToken: "YOUR_BOT_TOKEN",
      dmPolicy: "pairing",  // 配对码模式
      groups: {
        "*": { requireMention: true },
        "-1001234567890": {  // 团队群组
          requireMention: false,
          allowFrom: ["@admin", "@member1", "@member2"]
        }
      }
    }
  },
  
  // 工具权限控制
  tools: {
    elevated: {
      enabled: true,
      allowFrom: {
        telegram: ["admin_user_id"]  // 只有管理员有提权权限
      }
    }
  }
}
```

### 场景 3: 公开机器人 (最严格限制)

```json5
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      model: { primary: "anthropic/claude-haiku-4-5" },  // 使用便宜的模型
      sandbox: {
        mode: "all",
        scope: "session",
        workspaceAccess: "none",  // 无文件访问
        docker: {
          network: "bridge",  // 即使有网络，Mac 文件仍然隔离
          memory: "512m",
          cpus: 0.5
        }
      }
    }
  },
  
  channels: {
    telegram: {
      enabled: true,
      botToken: "YOUR_BOT_TOKEN",
      dmPolicy: "open",
      allowFrom: ["*"],  // open 模式需要 *
      groups: { "*": { requireMention: true } }
    }
  },
  
  // 严格工具限制
  tools: {
    allow: ["read"],  // 只允许读取
    deny: ["exec", "write", "edit", "browser", "apply_patch"],
    elevated: { enabled: false }
  },
  
  // 会话限制
  session: {
    reset: { mode: "idle", idleMinutes: 30 }  // 30 分钟空闲自动重置
  }
}
```

### 场景 4: 多 Agent 路由

多 Agent 允许不同渠道、账号或联系人使用不同的 Agent（独立人设、模型、沙箱）：

```json5
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
      sandbox: { mode: "all" }
    },
    list: [
      {
        id: "personal",
        default: true,
        workspace: "~/.openclaw/workspace-personal",
        model: { primary: "anthropic/claude-opus-4-6" }
      },
      {
        id: "work",
        workspace: "~/.openclaw/workspace-work",
        model: { primary: "anthropic/claude-sonnet-4-5" }
      }
    ]
  },
  bindings: [
    { agentId: "opus", match: { channel: "telegram" } },
    { agentId: "work", match: { channel: "whatsapp" } }
  ]
}
```

> 完整的多 Agent 配置指南（添加 Agent、多 Bot 绑定、路由规则、沙箱隔离）见 [multi-agent.md](multi-agent.md)。

---

## 配置项详解

### AI 模型配置

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `model.primary` | 主模型 | `"anthropic/claude-opus-4-6"` |
| `model.fallbacks` | 备用模型列表 | `["anthropic/claude-sonnet-4-5", "openai/gpt-5.1-codex"]` |
| `models` | 模型别名/目录 | `{ "anthropic/claude-opus-4-6": { alias: "opus" } }` |
| `imageModel` | 图像处理模型 | `{ primary: "openai/gpt-4o" }` |
| `pdfModel` | PDF 分析模型配置 | `{ provider: "anthropic", model: "claude-sonnet-4-6" }` |
| `pdfMaxBytesMb` | PDF 文件大小限制 | `30` (MB) |
| `pdfMaxPages` | PDF 最大页数 | `100` |

**内置提供商** (Pi-AI Catalog, 最少配置即可使用):

| 提供商 | 模型示例 | 认证环境变量 |
|--------|----------|-------------|
| `anthropic` | `anthropic/claude-opus-4-6`, `anthropic/claude-sonnet-4-6` | `ANTHROPIC_API_KEY` |
| `openai` | `openai/gpt-5.1-codex` | `OPENAI_API_KEY` |
| `openai-codex` | `openai-codex/gpt-5.3-codex` | OAuth (ChatGPT) |
| `opencode` | `opencode/claude-opus-4-6` | `OPENCODE_API_KEY` |
| `google` | `google/gemini-3-pro-preview`, `google/gemini-3.1-pro-preview` | `GEMINI_API_KEY` |
| `zai` | `zai/glm-4.7` | `ZAI_API_KEY` |
| `vercel-ai-gateway` | `vercel-ai-gateway/anthropic/claude-opus-4.6` | `AI_GATEWAY_API_KEY` |
| `openrouter` | `openrouter/anthropic/claude-opus-4-6` | `OPENROUTER_API_KEY` |
| `xai` | xAI 模型 | `XAI_API_KEY` |
| `groq` | Groq 模型 | `GROQ_API_KEY` |
| `cerebras` | Cerebras 模型 | `CEREBRAS_API_KEY` |
| `mistral` | Mistral 模型 | `MISTRAL_API_KEY` |
| `github-copilot` | GitHub Copilot 模型 | `COPILOT_GITHUB_TOKEN` |
| `huggingface` | Hugging Face 模型 | `HUGGINGFACE_HUB_TOKEN` |
| `kilo-gateway` | `kilo-router` (multi-model gateway) | `KILO_API_KEY` |
| `moonshot` | `moonshot-v1-128k` | `MOONSHOT_API_KEY` |

**自定义/代理提供商** (通过 `models.providers` 配置):

| 提供商 | 兼容协议 | 说明 |
|--------|----------|------|
| Moonshot AI (Kimi) | OpenAI 兼容 | 自定义 endpoint |
| Kimi Coding | Anthropic 兼容 | 自定义 endpoint |
| Qwen OAuth | 设备码流程 | 免费 tier |
| MiniMax | 自定义 endpoint | M2.5-highspeed (一等模型) |
| Ollama | OpenAI 兼容 | 本地运行 |
| vLLM | OpenAI 兼容 | 自托管 |
| LM Studio / LiteLLM | OpenAI 兼容 | 本地代理 |

自定义提供商配置示例：

```json5
{
  agents: {
    defaults: {
      models: {
        providers: {
          "my-proxy": {
            baseUrl: "https://api.example.com/v1",
            apiKey: "${MY_API_KEY}",
            api: "openai",  // openai | anthropic
            models: {
              "my-model": { name: "My Custom Model" }
            }
          }
        }
      }
    }
  }
}
```

### PDF 分析配置

v2026.3.2 新增 PDF 文件分析功能，通过 `pdfModel` 配置分析模型：

```json
"pdfModel": {
  "provider": "anthropic",
  "model": "claude-sonnet-4-6",
  "pdfMaxBytesMb": 30,
  "pdfMaxPages": 100
}
```

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `provider` | 模型提供商 | 继承主模型 |
| `model` | 分析模型 | 继承主模型 |
| `pdfMaxBytesMb` | 最大文件大小 (MB) | 30 |
| `pdfMaxPages` | 最大页数 | 100 |

### 聊天频道配置

#### WhatsApp

```json5
{
  channels: {
    whatsapp: {
      // DM 策略
      dmPolicy: "pairing",  // pairing | allowlist | open | disabled
      allowFrom: ["+8613800138000"],  // E.164 格式
      
      // 群组策略
      groupPolicy: "allowlist",
      groupAllowFrom: ["+8613800138000"],
      groups: {
        "*": { requireMention: true },
        "group-id": { requireMention: false }
      },
      
      // 其他设置
      sendReadReceipts: true,
      mediaMaxMb: 50
    }
  }
}
```

#### Telegram

```json5
{
  channels: {
    telegram: {
      enabled: true,
      botToken: "123456:ABC...",  // 从 @BotFather 获取
      
      dmPolicy: "pairing",
      allowFrom: ["123456789", "@username"],
      
      groups: {
        "*": { requireMention: true },
        "-1001234567890": {
          requireMention: false,
          systemPrompt: "保持回答简洁"
        }
      },
      
      historyLimit: 50,
      replyToMode: "first",
      streamMode: "partial",       // v2026.3.2 默认值从 "off" 变更为 "partial"
      disableAudioPreflight: false // v2026.3.2 新增：跳过 TTS 能力检查
    }
  }
}
```

#### Discord

```json5
{
  channels: {
    discord: {
      enabled: true,
      token: "YOUR_BOT_TOKEN",
      
      dm: {
        enabled: true,
        policy: "pairing",
        allowFrom: ["user_id", "username"]
      },
      
      guilds: {
        "server_id": {
          requireMention: false,
          channels: {
            "general": { allow: true },
            "help": { allow: true, requireMention: true }
          }
        }
      }
    }
  }
}
```

#### 更多频道

OpenClaw 支持 25+ 频道：

**内置频道** (开箱即用):
WhatsApp, Telegram, Discord, IRC, Slack, Google Chat, Signal, BlueBubbles (iMessage 替代), WebChat

**插件频道** (需单独安装):
Feishu (飞书), Mattermost, Microsoft Teams, LINE, Nextcloud Talk, Matrix, Nostr, Tlon, Twitch, Zalo（v2026.3.2 原生重写）

> iMessage (legacy) 已不推荐，建议使用 BlueBubbles 替代，功能更全面（支持编辑、反应、群管理）。

添加频道：
```bash
openclaw channels add                                  # 交互式
openclaw channels add --channel signal                 # 指定频道
openclaw channels add --channel googlechat --token <TOKEN>
```

---

### 沙箱配置

| 配置项 | 说明 | 选项 |
|--------|------|------|
| `mode` | 沙箱模式 | `off` / `non-main` / `all` |
| `scope` | 隔离范围 | `session` / `agent` / `shared` |
| `workspaceAccess` | 工作区权限 | `none` / `ro` / `rw` |
| `docker.network` | 网络模式 | `none` / `bridge` / `host` |
| `docker.memory` | 内存限制 | `"1g"`, `"512m"` |
| `docker.cpus` | CPU 限制 | `1`, `0.5` |

**推荐配置** (OrbStack 环境):

```json5
{
  sandbox: {
    mode: "all",           // 推荐: 所有会话使用沙箱 (保护 Mac 文件)
    scope: "agent",        // 每个 Agent 独立容器
    workspaceAccess: "rw", // 读写访问
    docker: {
      image: "openclaw-sandbox-common:bookworm-slim",
      network: "bridge",   // 浏览器自动化需要网络
      readOnlyRoot: true,
      tmpfs: ["/tmp:exec,mode=1777", "/var/tmp", "/run"],  // Playwright 需要
      user: "501:501",     // macOS 用户权限
      memory: "1g",
      cpus: 1,
      // 重要: 沙箱内需要的 API Key 必须在这里配置！
      env: {
        LANG: "C.UTF-8",
        OPENAI_API_KEY: "sk-xxx",
        GOOGLE_API_KEY: "AIzaSyxxx"
      }
    },
    browser: {
      enabled: true,
      autoStart: true,
      autoStartTimeoutMs: 30000,
      // 浏览器沙箱的环境变量单独配置
      env: {
        LANG: "C.UTF-8",
        OPENAI_API_KEY: "sk-xxx"
      }
    }
  }
}
```

> **注意**: OrbStack VM 通过 `/mnt/mac` 可访问 Mac 文件，所以 Docker 容器是唯一的隔离层。
> 即使设置 `network: "bridge"`，Mac 文件仍然受到保护，因为容器只能访问挂载的 `/workspace`。

> **重要**: 沙箱容器不会继承 Gateway 的环境变量！`sandbox.docker.env` 和 `sandbox.browser.env` 需要分别配置。详见 [sandbox.md](sandbox.md#environment-variables-重要)。

### Docker Namespace Join (v2026.2.24+)

v2026.2.24 起，Docker `network: "container:<id>"` 命名空间共享模式被**默认阻止**，防止沙箱容器共享其他容器的网络命名空间。

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `docker.dangerouslyAllowContainerNamespaceJoin` | `boolean` | `false` | 允许沙箱容器使用 `network: "container:<id>"` 模式 |

> 我们的默认配置使用 `network: "bridge"`，不受此变更影响。仅在需要容器间网络命名空间共享的高级场景中才需要设置为 `true`。

### Browser SSRF Protection

v2026.2.20 introduced SSRF (Server-Side Request Forgery) protection for the browser sandbox.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `browser.ssrfPolicy` | `string` | `"strict"` | SSRF protection policy: `"strict"` (block private network), `"warn"` (log only), `"off"` (disable) |
| `browser.dangerouslyAllowPrivateNetwork` | `boolean` | `false` | Allow browser sandbox to access private network addresses (debug only) |

```json5
browser: {
  ssrfPolicy: "strict",
  dangerouslyAllowPrivateNetwork: false
}
```

In OrbStack environments, the default `"strict"` policy is recommended. Only set `dangerouslyAllowPrivateNetwork: true` for local development/debugging.

### Heartbeat 心跳配置 (v2026.2.25+)

心跳允许 AI 在空闲时主动检查并发送消息。v2026.2.25 引入了 `directPolicy` 配置项：

```json5
{
  agents: {
    defaults: {
      heartbeat: {
        every: "30m",              // 心跳间隔
        target: "none",            // 投递目标: "none" | "last" | channel/peer
        directPolicy: "allow",    // "allow" | "block"
      }
    }
  }
}
```

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `heartbeat.every` | `string` | — | 心跳间隔 (`"30m"`, `"1h"`, `"2h"`) |
| `heartbeat.target` | `string` | `"none"` | 投递目标 (v2026.2.24 从 `"last"` 改为 `"none"`，需要主动 opt-in) |
| `heartbeat.directPolicy` | `string` | `"allow"` | DM 投递策略: `"allow"` 允许投递到私聊, `"block"` 只投递到群组/频道 |

> **版本变更记录**: v2026.2.24 曾将心跳 DM 投递默认改为阻止，v2026.2.25 恢复为 `"allow"` 并引入显式 `directPolicy` 配置。如需阻止心跳投递到私聊，设置 `directPolicy: "block"`。

支持 per-agent 覆盖:

```json5
{
  agents: {
    list: [{
      id: "public",
      heartbeat: { directPolicy: "block" }
    }]
  }
}
```

### 外部 Secrets 管理 (v2026.2.26+)

v2026.2.26 引入了外部 Secrets 管理工作流，允许从外部源拉取密钥并通过运行时快照机制激活：

```bash
openclaw secrets audit             # 审计当前 secrets 状态
openclaw secrets configure         # 配置外部 secrets 源
openclaw secrets apply             # 应用 secrets 快照到运行时
openclaw secrets reload            # 重新加载 secrets (不重启 Gateway)
```

**工作流**：
1. `openclaw secrets configure` — 设置外部 secrets 源（如 Vault、AWS Secrets Manager）
2. `openclaw secrets apply` — 从外部源拉取并创建运行时快照
3. `openclaw secrets reload` — 热加载新的 secrets（无需重启）
4. `openclaw secrets audit` — 检查 secrets 状态和过期情况

> 此功能补充了现有的 `.env` 文件管理方式，适合需要集中式密钥管理的团队场景。

### DM Allowlist 运行时继承 (v2026.2.26+)

v2026.2.26 加强了 DM allowlist 的运行时继承执行：

- **`dmPolicy: "allowlist"` 配合空 `allowFrom`**：现在会被**拒绝启动**（之前是静默忽略）
  - 运行 `openclaw doctor --fix` 可以自动修复（回退到 `dmPolicy: "pairing"`）
- **所有支持账户的频道**（WhatsApp、Telegram、Discord 等）现在统一执行 allowlist 继承规则
- 多账户场景下，子账户的 `allowFrom` 会继承父级默认值

### Channel Plugin 交互式引导 (v2026.2.26+)

插件频道现在支持 `configureInteractive` 和 `configureWhenConfigured` 钩子，允许插件在安装和配置时提供交互式引导流程。

### 模型 ID 规范化 (v2026.2.26+)

- **Gemini 裸模型 ID 规范化**：`gemini-3-pro` 等不带后缀的裸 ID 会自动规范化到 `-low` tier（如 `gemini-3-pro-low`）。建议在配置中使用完整模型 ID（如 `gemini-3-pro-preview`）。
- **MiniMax auth header 默认值修复**：MiniMax 提供商的 auth header 默认行为已修正。
- **Auth profiles 别名规范化**：`mode` → `type`、`apiKey` → `key` 别名现在会自动规范化。旧别名仍可使用，但建议更新到新名称。

### Security Trust Model (v2026.2.24+)

v2026.2.24 新增了 `security` 顶层配置块，支持多用户安全检测：

```json5
{
  security: {
    trust_model: {
      multi_user_heuristic: true  // 检测到多用户共享同一实例时发出警告
    }
  }
}
```

**多用户场景建议**:
- 确保 `sandbox.mode: "all"` (所有会话沙箱化)
- 使用工作区隔离 (`sandbox.scope: "session"`)
- 限制工具权限 (减少 `tools.allow` 范围)
- 不要在共享实例上配置个人身份/隐私信息

### ACP 调度（Agent Communication Protocol）

v2026.3.2 起 ACP 调度默认启用，允许代理间通过标准协议通信：

```json5
{
  acp: {
    dispatch: {
      enabled: true
    }
  }
}
```

如需禁用，设置 `"enabled": false`。

### TTS 语音配置

```json5
{
  messages: {
    tts: {
      auto: "inbound",  // off | always | inbound
      provider: "edge", // edge (免费) | openai | elevenlabs
      
      edge: {
        // 中文语音
        voice: "zh-CN-XiaoxiaoNeural"  // 女声
        // voice: "zh-CN-YunxiNeural"   // 男声
      }
    }
  }
}
```

**可用语音**:

| 语言 | 语音 ID | 性别 |
|------|---------|------|
| 中文 | `zh-CN-XiaoxiaoNeural` | 女 |
| 中文 | `zh-CN-YunxiNeural` | 男 |
| 中文 | `zh-CN-YunyangNeural` | 男 |
| 英文 | `en-US-JennyNeural` | 女 |
| 英文 | `en-US-GuyNeural` | 男 |

### Memory Search 配置

Memory Search 允许 AI 搜索历史记忆。**需要配置 embedding provider 才能工作**。

#### 基本配置

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        provider: "auto",  // auto | openai | gemini | local | ollama
        // auto 模式会按以下顺序尝试:
        // 1. local (如果配置了 modelPath)
        // 2. openai (如果有 API key)
        // 3. gemini (如果有 API key)
      }
    }
  }
}
```

#### 重要：配置 Embedding API Key

Memory Search 需要调用 embedding API 生成向量索引。**必须在 agent 的 auth-profiles.json 中配置 OpenAI 或 Google 的 API key**：

```bash
# 编辑 agent auth 文件
nano ~/.openclaw/agents/main/agent/auth-profiles.json
```

在 `profiles` 中添加：

```json
{
  "profiles": {
    "openai:default": {
      "type": "api_key",
      "provider": "openai",
      "key": "sk-你的OpenAI-Key"
    }
  },
  "lastGood": {
    "openai": "openai:default"
  }
}
```

#### 验证配置

```bash
openclaw memory status --deep
# 应显示 Provider: openai 而不是 "No API key found"
```

#### 构建索引

```bash
openclaw memory index
```

#### 高级配置

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        provider: "openai",
        model: "text-embedding-3-small",
        // Batch API (默认开启，便宜 50% 但较慢)
        remote: {
          batch: {
            enabled: true,    // 关闭则使用实时 API (快但贵)
            concurrency: 4
          }
        },
        // 混合搜索 (向量 + 文本)
        query: {
          hybrid: {
            enabled: true,
            vectorWeight: 0.7,
            textWeight: 0.3
          }
        }
      }
    }
  }
}
```

#### 使用本地 Embedding (免费)

如果不想用 OpenAI/Google API，可以使用本地模型：

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        provider: "local"
        // OpenClaw 会自动下载本地 embedding 模型
      }
    }
  }
}
```

#### 使用 Ollama 嵌入

v2026.3.2 新增 Ollama 作为嵌入提供商，支持完全本地化的向量搜索：

```json5
{
  agents: {
    defaults: {
      memorySearch: {
        provider: "ollama"
      }
    }
  }
}
```

需要在 VM 中安装并运行 Ollama 服务。

详见 [troubleshooting.md](troubleshooting.md#5-memory-search-无法使用--索引为空) 获取更多帮助。

---

### 工具权限配置

```json5
{
  tools: {
    // 工具配置文件 (预设)
    profile: "coding",  // minimal | coding | messaging | full
    
    // 允许的工具
    allow: ["exec", "read", "write", "edit", "browser"],
    
    // 禁止的工具
    deny: ["canvas", "cron", "gateway"],
    
    // 提权配置
    elevated: {
      enabled: true,
      allowFrom: {
        whatsapp: ["+8613800138000"],
        telegram: ["123456789"]
      }
    }
  }
}
```

**工具列表**:

| 工具 | 说明 |
|------|------|
| `exec` | 执行命令 |
| `read` | 读取文件 |
| `write` | 写入文件 |
| `edit` | 编辑文件 |
| `apply_patch` | 应用补丁 |
| `browser` | 浏览器操作 |
| `sessions_*` | 会话管理 |

---

## 环境变量支持

配置文件支持环境变量替换:

```json5
{
  auth: {
    profiles: {
      "anthropic:api": {
        provider: "anthropic",
        mode: "api_key"
      }
    }
  },
  
  // 使用环境变量
  gateway: {
    auth: {
      token: "${OPENCLAW_GATEWAY_TOKEN}"
    }
  }
}
```

**常用环境变量**:

| 变量 | 说明 |
|------|------|
| `ANTHROPIC_API_KEY` | Anthropic API Key |
| `OPENAI_API_KEY` | OpenAI API Key |
| `GOOGLE_API_KEY` | Google API Key |
| `TG_BOT_TOKEN` | Telegram Bot Token (沙箱内使用，不要用 `TELEGRAM_BOT_TOKEN`，该名被 Gateway 保留) |
| `DISCORD_TOKEN` | Discord Bot Token (沙箱内使用，不要用 `DISCORD_BOT_TOKEN`，该名被 Gateway 保留) |
| `OPENCLAW_STATE_DIR` | 状态目录 |
| `OPENCLAW_BROWSER_NO_SANDBOX` | Disable Chromium sandbox in browser container (not needed in OrbStack) |
| `OPENCLAW_TELEGRAM_DNS_RESULT_ORDER` | Override DNS result order for Telegram connections |
| `OPENCLAW_NODE_EXEC_HOST` | Override Node.js execution host for sandbox |

---

## 多文件配置 ($include)

OpenClaw 支持将配置拆分为多个文件，通过 `$include` 引用：

```json5
{
  // 引用单个文件
  $include: "./channels.json",

  // 引用多个文件
  $include: ["./agents.json", "./channels.json", "./tools.json"],

  // 其他配置项会与 include 的内容合并
  gateway: { port: 18789 }
}
```

- 支持嵌套引用，最多 10 层
- 后定义的字段覆盖先定义的（合并语义）
- 路径遍历防护：`$include` 路径不允许包含 `..` 或绝对路径，防止引用配置目录外的文件 (OC-09)
- 适合将 agents、channels、tools 等分离管理

---

## 配置热重载

Gateway 支持多种热重载模式，通过 `gateway.reload` 配置：

```json5
{
  gateway: {
    reload: {
      mode: "hybrid",     // hybrid | hot | restart | off
      debounceMs: 1000    // 防抖间隔
    }
  }
}
```

| 模式 | 行为 |
|------|------|
| `hybrid` | **默认** — 大部分字段热重载，少数需要重启的自动重启 |
| `hot` | 只热重载，需要重启的字段忽略 |
| `restart` | 所有变更都触发完整重启 |
| `off` | 禁用自动重载 |

**热重载支持情况**：

| 分类 | 字段 | 需要重启？ |
|------|------|-----------|
| 频道 | `channels.*`, `web` | 否 |
| Agent & 模型 | `agents`, `models`, `routing` | 否 |
| 自动化 | `hooks`, `cron`, `agent.heartbeat` | 否 |
| 会话 & 消息 | `session`, `messages` | 否 |
| 工具 & 媒体 | `tools`, `browser`, `skills`, `audio`, `talk` | 否 |
| UI & 其他 | `ui`, `logging`, `identity`, `bindings` | 否 |
| **Gateway 服务器** | `gateway.*` (port, bind, auth, TLS) | **是** |
| **基础设施** | `discovery`, `canvasHost`, `plugins` | **是** |

> 例外：`gateway.reload` 和 `gateway.remote` 的变更不会触发重启。

### HTTP Security Headers

v2026.2.21 added support for custom HTTP security response headers, useful when exposing the Gateway to the public internet.

```json5
gateway: {
  http: {
    securityHeaders: {
      "Strict-Transport-Security": "max-age=31536000",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY"
    }
  }
}
```

These headers are added to all Gateway HTTP responses. For OrbStack local-only access, this is optional. Enable it if you expose the Gateway via Tailscale or a reverse proxy.

---

## 会话配置

通过 `session` 控制会话范围和自动重置：

```json5
{
  session: {
    // DM 会话范围
    dmScope: "per-channel-peer",  // main | per-peer | per-channel-peer | per-account-channel-peer

    // 自动重置
    reset: {
      mode: "daily",       // daily | idle
      atHour: 4,           // mode: daily 时，每天几点重置 (0-23)
      idleMinutes: 30      // mode: idle 时，空闲多久后重置
    }
  }
}
```

| dmScope | 行为 |
|---------|------|
| `main` | 所有 DM 共享一个会话 |
| `per-peer` | 每个联系人独立会话 |
| `per-channel-peer` | 每个渠道+联系人独立会话 |
| `per-account-channel-peer` | 每个账号+渠道+联系人独立会话 |

**跨频道身份链接** (可选)：

```json5
{
  session: {
    identityLinks: {
      alice: ["telegram:123456789", "discord:987654321012345678"]
    }
  }
}
```

这样 alice 在 Telegram 和 Discord 上会共享同一个会话上下文。

### Session Parent Fork Limit (v2026.2.25+)

v2026.2.25 added `parentForkMaxTokens` to prevent oversized parent sessions from bricking child thread sessions (primarily affects Slack thread workflows).

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `session.parentForkMaxTokens` | `number` | `100000` | Maximum tokens inherited from parent session when forking threads |

```json5
session: {
  parentForkMaxTokens: 100000
}
```

### Session Disk Management

v2026.2.23 added disk-based session maintenance to prevent unbounded storage growth.

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `session.maintenance.maxDiskBytes` | `number` | `524288000` | Total disk quota for sessions (~500MB) |
| `session.maintenance.highWaterBytes` | `number` | `419430400` | Trigger cleanup when usage exceeds this (~400MB) |
| `session.maintenance.pruneOlderThanDays` | `number` | `30` | Delete sessions older than N days during cleanup |

```json5
session: {
  maintenance: {
    maxDiskBytes: 524288000,
    highWaterBytes: 419430400,
    pruneOlderThanDays: 30
  }
}
```

When disk usage exceeds `highWaterBytes`, sessions older than `pruneOlderThanDays` are automatically deleted until usage drops below the threshold.

---

## Hooks 配置

Hooks 允许外部系统向 Gateway 推送事件触发 AI 动作：

```json5
{
  hooks: {
    enabled: true,
    token: "${HOOKS_TOKEN}",           // 认证 token
    path: "/hooks",                     // 入口路径
    defaultSessionKey: "hooks",         // 默认会话 key
    allowRequestSessionKey: true,       // 允许请求指定会话 key
    allowedSessionKeyPrefixes: ["ci-"], // 允许的会话 key 前缀
    mappings: [
      {
        match: { source: "github", event: "push" },
        action: "message",
        agentId: "dev",
        deliver: { channel: "telegram", peer: "123456789" }
      }
    ]
  }
}
```

---

## 环境变量导入 (Shell Env)

Gateway 可以从 login shell 导入环境变量：

```json5
{
  env: {
    // 静态变量
    vars: {
      MY_VAR: "value"
    },
    // 从 login shell 导入
    shellEnv: {
      enabled: true,          // 或设置 OPENCLAW_LOAD_SHELL_ENV=1
      timeoutMs: 15000        // 导入超时 (默认 15 秒)
    }
  }
}
```

**环境变量加载优先级**（从高到低）：
1. 进程环境变量
2. 本地 `.env` 文件
3. 全局 `~/.openclaw/.env`
4. 配置文件 `env` 块
5. Login shell 导入（可选）

> **规则**：后加载的源不会覆盖已存在的变量。

---

## 定时任务 (Cron)

```json5
{
  cron: {
    enabled: true,
    maxConcurrentRuns: 3,       // 最大并发任务数
    sessionRetention: "7d"      // 会话保留时间
  }
}
```

通过 CLI 管理定时任务：`openclaw cron list`、`openclaw cron add` 等。

---

## 插件配置

```json5
{
  plugins: {
    // 插件列表
    list: [
      { id: "my-plugin", enabled: true }
    ]
  }
}
```

> 插件配置需要重启 Gateway 才能生效。通过 `openclaw plugins list` 查看可用插件。

---

## 配置验证

OpenClaw 使用严格的配置验证。如果配置无效：

1. Gateway 不会启动
2. 运行 `openclaw doctor` 查看具体问题
3. 运行 `openclaw doctor --fix` 自动修复

```bash
# 检查配置
openclaw-doctor

# 自动修复
openclaw-doctor --fix
```

v2026.3.2 新增 `openclaw config validate` 命令，支持更细粒度的配置验证：

```bash
openclaw config validate           # 验证配置语法
openclaw config validate --json    # JSON 格式输出（适用于 CI）
```

检查 `openclaw.json` 的语法错误、未知字段、类型不匹配等问题。

---

## 常见问题

### Q: 如何获取 Telegram Bot Token?

1. 在 Telegram 中搜索 `@BotFather`
2. 发送 `/newbot`
3. 按提示设置 bot 名称
4. 获得 Token (格式: `123456789:ABCdefGHI...`)

### Q: WhatsApp 如何登录?

```bash
openclaw-whatsapp
```
扫描显示的二维码即可。

### Q: 如何切换模型?

在聊天中发送 `/model anthropic/claude-opus-4-6` 即可临时切换。

### Q: 配置热重载支持哪些选项?

热重载 (无需重启):
- `agents.defaults.*` (大部分)
- `tools.*`
- `bindings`
- `channels.*.allowFrom`
- `skills.*`
- `session.*`
- `hooks.mappings`

需要重启:
- `gateway.port` 及其他 gateway 服务器设置
- `channels.*.botToken`
- `plugins.*`
- `discovery`、`canvasHost`

---

## 参考资料

- [官方文档](https://docs.openclaw.ai/gateway/configuration)
- [配置示例](https://docs.openclaw.ai/gateway/configuration-examples)
- [GitHub 仓库](https://github.com/openclaw/openclaw)
