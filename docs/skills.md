# Skills 使用指南

> 本文档是对官方文档的补充，面向 OrbStack 部署场景，讲清楚 Skills 的位置、加载规则和常见用法。

## 什么是 Skills？

Skills 是一组可复用的“能力包”，用于让 Agent 在对话中调用更高层的工具或流程。你可以把它理解为**可插拔的技能插件**：

- **不是模型**，而是模型可以调用的能力集合
- **可以按 Agent 隔离**，不同 Agent 加载不同技能
- **需要依赖/凭据时可单独配置**

## Skills 的加载位置

Skills 会从两个位置加载：

1. **全局共享目录**：`~/.openclaw/skills`
2. **Agent 专属目录**：`<workspace>/skills/`

> 多 Agent 场景下，每个 Agent 会优先使用自己 workspace 的 `skills/`，实现隔离。

## 常用命令

```bash
# 查看所有 Skills
openclaw skills list

# 只显示可用的 Skills（依赖齐全）
openclaw skills list --eligible

# 显示缺失依赖或不可用原因
openclaw skills list --verbose

# 查看某个 Skill 详情
openclaw skills info <name>

# 一键检查 Skills 状态摘要
openclaw skills check
```

> 若初次部署不想处理 Skills，可在向导时跳过：`openclaw onboard --skip-skills`。

## 配置项说明（openclaw.json）

在 `openclaw.json` 的 `skills` 节点中配置：

```json5
{
  skills: {
    // 允许的内置技能
    allowBundled: ["gemini", "peekaboo"],

    // 额外技能目录
    load: {
      // extraDirs: ["~/Projects/agent-scripts/skills"]
    },

    // 安装相关设置
    install: {
      preferBrew: true,
      nodeManager: "npm"
    },

    // 每个技能的配置（凭据/环境变量/开关）
    // entries: {
    //   "skill-name": {
    //     enabled: true,
    //     apiKey: "...",
    //     env: { KEY: "value" }
    //   }
    // }
  }
}
```

### 关键点

- **allowBundled**：允许启用内置 Skills（随 OpenClaw 提供）。
- **load.extraDirs**：额外的 Skills 搜索路径，适合团队共享目录。
- **entries**：为某个 Skill 单独配置参数（如 API Key / 环境变量）。

### Onboarding 工具配置文件默认值

v2026.3.2 起，新用户 onboarding 时默认工具配置文件为 `"messaging"`。这意味着新安装的 Agent 默认启用消息类工具（Telegram、WhatsApp 等），其他工具需要手动在 `skills.entries` 或工具权限中启用。

## 多 Agent 场景下的建议

- 将不同技能放在不同 Agent 的 workspace 下：
  - `~/.openclaw/workspace-A/skills/`
  - `~/.openclaw/workspace-B/skills/`
- 需要共享的技能放到全局目录：`~/.openclaw/skills`
- 若某个 Agent 不应拥有某技能，**不要**将该技能放入其 workspace。

## 常见问题

### 1) 为什么 skills list 显示不可用？
通常是依赖缺失或需要的凭据未配置。用 `openclaw skills list --verbose` 查看缺失项，然后在 `skills.entries` 中补齐参数。

### 2) skills 配置能热重载吗？
可以。`skills.*` 支持热重载（无需重启），详见 [configuration-guide.md](configuration-guide.md) 的“热重载”说明。

### 3) Skills 会影响安全性吗？
Skills 只是能力入口，实际执行仍受 **沙箱配置** 和 **工具权限** 约束。建议保持 `sandbox.mode: "all"`。

## 相关文档

- [configuration-guide.md](configuration-guide.md) — `skills.*` 配置详解
- [multi-agent.md](multi-agent.md) — 多 Agent 与 Skills 隔离
- [commands.md](commands.md) — Skills 命令参考
