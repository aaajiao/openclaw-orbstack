# 多 Agent 配置指南

## 概览

OpenClaw 支持在一个 Gateway 中运行多个隔离的 Agent，每个 Agent 拥有独立的工作目录、认证、会话和模型配置。通过路由绑定（bindings），可以将不同渠道、账号或联系人的消息分发给不同的 Agent。

### 核心概念

| 概念 | 说明 |
|------|------|
| **agentId** | Agent 唯一标识，对应一个独立的"大脑"（工作目录 + 认证 + 会话） |
| **accountId** | 渠道账号实例，如 Telegram 的多个 Bot 账号 |
| **binding** | 路由规则，根据 channel / accountId / peer 将消息分发到指定 Agent |

### 每个 Agent 独立拥有

- **Workspace** - 工作目录（`AGENTS.md`、`SOUL.md`、`IDENTITY.md` 等人设文件）
- **Agent dir** - 状态目录（认证、模型注册、per-agent 配置）
- **Session store** - 会话历史，位于 `~/.openclaw/agents/<agentId>/sessions`

---

## 添加 Agent

```bash
# 添加一个名为 "work" 的 Agent
openclaw agents add work --workspace ~/.openclaw/workspace-work

# 设置 Agent 身份
openclaw agents set-identity --agent work --name "WorkBot" --emoji "💼"

# 从 IDENTITY.md 文件加载身份
openclaw agents set-identity --agent work --from-identity

# 验证
openclaw agents list --bindings
```

添加后，OpenClaw 会自动创建：
- 工作目录：`~/.openclaw/workspace-work`
- 状态目录：`~/.openclaw/agents/work/agent`

---

## 添加多个 Telegram Bot

如果需要多个 Bot 分别对应不同 Agent，先添加第二个 Bot 账号：

### 步骤 1：添加 Bot 账号

```bash
# 第一个 Bot 的 accountId 默认是 "default"，无需额外操作
# 添加第二个 Bot，指定 accountId
openclaw channels add --channel telegram --account work-bot --name "Work Bot" --token <BOT_TOKEN>

# 验证
openclaw channels list
```

### 步骤 2：配置多账号

也可以直接在 `openclaw.json` 的 `channels.telegram.accounts` 中配置：

```json5
{
  channels: {
    telegram: {
      accounts: {
        default: {
          name: "Personal Bot",
          botToken: "123456:ABC..."
        },
        "work-bot": {
          name: "Work Bot",
          botToken: "987654:XYZ..."
        }
      }
    }
  }
}
```

> - `default` 是省略 `accountId` 时使用的默认账号
> - 顶层 `channels.telegram` 的通用设置（dmPolicy、群组策略等）对所有账号生效，除非在账号级别覆盖
> - 频道相关配置详见 [configuration-guide.md](configuration-guide.md#telegram)

### 步骤 3：配置路由绑定

将不同 Bot 路由到不同 Agent（见下方路由绑定配置）。如果不配 binding，未匹配的消息自动回退到默认 Agent（`main`）。

---

## 路由绑定配置

在 `openclaw.json` 中配置 `agents.list` 和 `bindings`：

### 场景一：按渠道分流

Telegram 用强模型，WhatsApp 用快速模型：

```json5
{
  agents: {
    list: [
      { id: "opus", workspace: "~/.openclaw/workspace-opus" },
      { id: "chat", workspace: "~/.openclaw/workspace-chat" }
    ]
  },
  bindings: [
    { agentId: "opus", match: { channel: "telegram" } },
    { agentId: "chat", match: { channel: "whatsapp" } }
  ]
}
```

### 场景二：按账号分流

两个 Telegram Bot 分别对应不同 Agent：

```json5
{
  agents: {
    list: [
      { id: "home", workspace: "~/.openclaw/workspace-home" },
      { id: "work", workspace: "~/.openclaw/workspace-work" }
    ]
  },
  bindings: [
    { agentId: "home", match: { channel: "telegram", accountId: "personal-bot" } },
    { agentId: "work", match: { channel: "telegram", accountId: "work-bot" } }
  ]
}
```

### 场景三：按联系人分流（Peer 级别）

同一个 Telegram Bot，特定联系人用 Opus，其余用快速模型：

```json5
{
  bindings: [
    { agentId: "opus", match: { channel: "telegram",
      peer: { kind: "dm", id: "123456789" } } },
    { agentId: "chat", match: { channel: "telegram" } }
  ]
}
```

> Telegram peer id 是用户的数字 ID，可通过 `openclaw channels peers` 查看。

### 场景四：一个 Bot 服务多人

不同联系人路由到各自独立的 Agent：

```json5
{
  bindings: [
    { agentId: "alex", match: { channel: "telegram",
      peer: { kind: "dm", id: "123456001" } } },
    { agentId: "mia",  match: { channel: "telegram",
      peer: { kind: "dm", id: "123456002" } } }
  ]
}
```

> 回复仍然来自同一个 Telegram Bot，不会暴露 Agent 身份。

---

## 路由优先级

匹配规则按以下顺序，最具体的优先：

| 优先级 | 匹配类型 | 说明 |
|--------|----------|------|
| 1 (最高) | `peer` | 精确匹配联系人或群组 |
| 2 | `guildId` | Discord 服务器 |
| 3 | `teamId` | Slack 团队 |
| 4 | `accountId` | 渠道账号 |
| 5 | `channel` | 渠道级别 |
| 6 (最低) | 默认 | 未匹配时回退到 default Agent（`main`） |

---

## Per-Agent 模型配置

每个 Agent 可以覆盖全局默认模型：

```json5
{
  agents: {
    list: [
      {
        id: "work",
        workspace: "~/.openclaw/workspace-work",
        // 字符串形式：只覆盖主模型
        model: "openrouter/anthropic/claude-sonnet-4"
      },
      {
        id: "opus",
        workspace: "~/.openclaw/workspace-opus",
        // 对象形式：覆盖主模型和 fallback
        model: {
          primary: "opencode/claude-opus-4-6",
          fallbacks: ["openrouter/anthropic/claude-sonnet-4"]
        }
      }
    ]
  }
}
```

查看特定 Agent 的模型状态：

```bash
openclaw models status --agent work
openclaw models status --agent opus --json
```

---

## 沙箱与 Docker 容器

### 镜像 vs 容器：共享模板，独立实例

所有 Agent 共用同一套 Docker 镜像（3 个），不需要为新 Agent 额外构建镜像。Gateway 会自动为每个 Agent 按 `scope` 配置创建独立的容器实例：

```
Docker 镜像（共享，构建时创建）             运行时容器（按需创建，per-agent 隔离）
┌──────────────────────────────┐      ┌──────────────────────────────┐
│ sandbox-common:bookworm-slim │─────→│ openclaw-sbx-main-xxxx       │ ← Agent main
│ (代码执行)                    │─────→│ openclaw-sbx-work-xxxx       │ ← Agent work
│                              │─────→│ openclaw-sbx-family-xxxx     │ ← Agent family
├──────────────────────────────┤      ├──────────────────────────────┤
│ sandbox-browser:bookworm-slim│─────→│ openclaw-sbx-browser-main-xx │ ← Agent main
│ (浏览器)                      │─────→│ openclaw-sbx-browser-work-xx │ ← Agent work
└──────────────────────────────┘      └──────────────────────────────┘
```

- **镜像** = 模板，所有 Agent 共享，只在 `openclaw-update --sandbox` 时重建
- **容器** = 实例，每个 Agent 各自独立，文件系统互不可见

### `scope` 参数：容器隔离粒度

通过 `sandbox.scope` 控制容器如何分配：

| scope | 行为 | 容器数量 | 适用场景 |
|-------|------|---------|---------|
| `"session"` | 每个会话一个容器 | 最多 | 需要会话级别完全隔离 |
| `"agent"` | 每个 Agent 一个容器 | 适中 | **默认** — 同一 Agent 所有会话共享容器 |
| `"shared"` | 多个 Agent 共享容器 | 最少 | 需要跨 Agent 协作 |

以默认的 `scope: "agent"` 为例，添加 `work` Agent 后的容器分布：

```
Agent main  → 代码沙箱容器 (独立) + 浏览器沙箱容器 (独立)
Agent work  → 代码沙箱容器 (独立) + 浏览器沙箱容器 (独立)
```

两个 Agent 用的是同一个镜像，但运行在各自独立的容器中。

### Per-Agent 沙箱配置覆盖

每个 Agent 可以覆盖全局沙箱默认值，实现不同的安全策略：

```json5
{
  agents: {
    defaults: {
      sandbox: {
        mode: "all",
        scope: "agent"        // 全局默认
      }
    },
    list: [
      {
        id: "family",
        workspace: "~/.openclaw/workspace-family",
        sandbox: {
          mode: "all",
          scope: "session",          // 覆盖：每个聊天独立容器
          workspaceAccess: "none",   // 禁止文件访问
          docker: { network: "none" } // 禁止网络
        },
        tools: {
          allow: ["exec", "read"],
          deny: ["write", "edit"]
        }
      },
      {
        id: "dev",
        workspace: "~/.openclaw/workspace-dev",
        sandbox: { mode: "off" }    // 覆盖：不使用沙箱 (危险)
      }
    ]
  }
}
```

### 沙箱相关命令

```bash
# 查看沙箱配置解释
openclaw sandbox explain --agent main
openclaw sandbox explain --agent work

# 重建特定 Agent 的沙箱容器
openclaw sandbox recreate --agent work

# 列出所有运行中的沙箱容器
openclaw sandbox list
```

> 详细的沙箱架构、安全模型和环境变量配置见 [sandbox.md](sandbox.md)。

---

## 管理命令一览

```bash
# Agent 管理
openclaw agents list                       # 列出所有 Agent
openclaw agents list --bindings            # 包含路由绑定
openclaw agents add <name>                 # 添加新 Agent
openclaw agents add <name> --workspace <dir>  # 指定工作目录
openclaw agents set-identity --agent <id>  # 更新身份
openclaw agents delete <id>               # 删除 Agent

# 模型状态
openclaw models status --agent <id>        # 查看 Agent 模型状态
openclaw models status --agent <id> --json # JSON 格式输出

# 沙箱
openclaw sandbox recreate --agent <id>     # 重建 Agent 沙箱
openclaw sandbox explain --agent <id>      # 解释 Agent 沙箱配置

# 发送消息到指定 Agent
openclaw agent -m "test" --agent <id>
```

---

## 注意事项

- **认证隔离**：每个 Agent 的认证 profile 独立存储在各自的 `agentDir` 下，互不共享。需要共享时手动复制 `auth-profiles.json`。
- **禁止共用 agentDir**：多个 Agent 不能指向同一个 `agentDir`，否则会导致认证和会话冲突。
- **Skills 隔离**：每个 Agent 通过各自 workspace 的 `skills/` 目录加载 Skills，`~/.openclaw/skills` 为全局共享。
- **Sub-Agent 限制**：Sub-agent 不能再嵌套 sub-agent（无递归展开）。可以为 sub-agent 配置更便宜的模型以节省开销。

---

## 相关文档

**项目内文档：**

- [sandbox.md](sandbox.md) — 沙箱架构、安全模型、环境变量配置
- [configuration-guide.md](configuration-guide.md) — 完整配置指南（含频道、模型、工具权限）
- [commands.md](commands.md) — CLI 命令参考（Agent 管理、模型、沙箱命令）
- [architecture.md](architecture.md) — 系统架构概览

**官方文档：**

- [Multi-Agent Routing](https://docs.openclaw.ai/concepts/multi-agent)
- [Agent Runtime](https://docs.openclaw.ai/concepts/agent)
- [Agents CLI](https://docs.openclaw.ai/cli/agents)
- [Telegram Channel](https://docs.openclaw.ai/channels/telegram)
- [Sub-Agents](https://docs.openclaw.ai/tools/subagents)
- [配置文件参考](https://docs.openclaw.ai/gateway/configuration)
