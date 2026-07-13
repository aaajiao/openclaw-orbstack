# CLI 命令参考

> 🌐 This guide is currently Chinese-only. English essentials are covered in the [README](../README.md); the upstream OpenClaw docs at https://docs.openclaw.ai are fully in English.

## 概览

在 Mac 上有两类命令可用：

1. **OrbStack 管理命令** (`openclaw-*`) - 我们为 OrbStack 架构添加的 15 个（其中 5 个为已弃用兼容别名）命令
2. **官方 CLI 命令** (`openclaw <command>`) - 透传到 VM 的 150+ 官方命令

> **`openclaw-update` 是唯一的更新命令**（详见 [更新命令详情](#更新命令详情)）：先更新**这个 wrapper（openclaw-orbstack）本身**（`~/bin/openclaw-*` 命令和安装/更新脚本，只跑在 Mac 上），再把 wrapper 对齐的**上游 OpenClaw** 装进 VM（AI 大脑本体）。`--pre`/`--stable` 切换/记住通道，`--version=<tag>` 可钉版本；隐藏参数 `--wrapper-only` 只跑 wrapper 那一段、不碰 VM。

---

## OrbStack 管理命令 (15 个，其中 5 个为已弃用兼容别名)

这些命令在 `~/bin/` 目录下，用于管理 OrbStack VM 和服务，由 `scripts/refresh-mac-commands.sh` 中的命令表统一生成。其中 5 个（`openclaw-stop`、`openclaw-start`、`openclaw-doctor`、`openclaw-whatsapp`、`openclaw-telegram`）已弃用为兼容别名：仍可正常使用，但运行时会在 stderr 打印一行 `[deprecated]` 提示，指向对应的原生命令；移除计划推迟到未来某个 stable release。

### 核心命令

推荐优先使用通用透传命令 `openclaw <command>`，而非记忆各个专用别名——它直接对应官方 CLI 语义，覆盖面也更广。

| 命令 | 功能 |
|------|------|
| **`openclaw`** | **CLI 透传** - 所有参数传到 VM 的官方 CLI（推荐首选） |
| **`openclaw-config`** | 配置管理 (edit/show/backup) |

```bash
# openclaw 透传示例
openclaw --help
openclaw status
openclaw channels list
openclaw doctor

# openclaw-config 示例
openclaw-config edit     # 编辑配置
openclaw-config show     # 查看配置
openclaw-config backup   # 备份到本地
```

### 频道快捷命令

| 命令 | 功能 |
|------|------|
| `openclaw-telegram` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw channels add --channel telegram --token <token>` / `openclaw pairing approve telegram <code>` |
| `openclaw-whatsapp` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw channels login --channel whatsapp` |

```bash
# Telegram Bot 管理（已弃用别名，仍可用，会打印 [deprecated] 提示）
openclaw-telegram                      # 查看帮助
openclaw-telegram add <bot_token>      # 添加 Bot (从 @BotFather 获取)
openclaw-telegram approve <code>       # 批准配对 (回执验证码)

# WhatsApp 登录（已弃用别名，仍可用，会打印 [deprecated] 提示）
openclaw-whatsapp                      # 扫码登录
```

### AI 认证

| 命令 | 功能 |
|------|------|
| `openclaw-codex-login` | 绑定 ChatGPT 订阅（Codex CLI device-code 登录） |

```bash
openclaw-codex-login                   # 启动 device-code OAuth 登录
                                       # 输出验证 URL + 6 位数 code
                                       # 在 Mac 浏览器打开 URL 输入 code 完成
```

**何时需要**：仅当你想用 ChatGPT/Codex 订阅服务 `openai/gpt-*` 模型时。不绑定也能用 — Gateway 自动 fallback 到 OpenAI API key（前提是已在配置里设置 `OPENAI_API_KEY`）。

**机制**：上游 v2026.5.14+（PR #82117）在 OpenClaw 自身 OAuth refresh 失败时，从 VM 内 `~/.codex/auth.json` 读取 Codex CLI 的 token 作为 runtime fallback。该文件由 `codex login` 写入并由 Codex CLI 自行 refresh。
- 安装脚本 / 升级脚本会自动安装/升级 Codex CLI（VM 内 `npm install -g @openai/codex`）
- Login 是一次性操作 — token 由 Codex CLI 自动维护
- 不需要 codex CLI 跑后台进程；OpenClaw 只读 `auth.json` 文件

详见 [troubleshooting.md](troubleshooting.md) "ChatGPT 订阅认证" 章节。

### 服务管理

| 命令 | 功能 |
|------|------|
| `openclaw-status` | 查看 Gateway 服务状态 (openclaw gateway status) |
| `openclaw-logs` | 实时日志 (openclaw logs --follow) |
| `openclaw-restart` | 重启服务 |
| `openclaw-stop` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw gateway stop` |
| `openclaw-start` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw gateway start` |
| `openclaw-shell` | 进入 VM 终端 |
| `openclaw-doctor` | 已弃用（兼容别名，仍可用）→ 原生替代：`openclaw doctor` |
| `openclaw-update` | **更新一切：wrapper + OpenClaw**（通道：`--pre`/`--stable`；另有 `--version=<tag>`、`--sandbox`、`--force`；隐藏参数 `--wrapper-only` 只跑 wrapper 阶段） |
| `openclaw-sandbox-rebuild` | 重建沙箱 Docker 镜像 |
| `openclaw-uninstall` | 完全卸载 (`--vm` 同时删除虚拟机) |

### 卸载命令详情

`openclaw-uninstall` 完全清理所有 OpenClaw 组件：

```bash
openclaw-uninstall              # 交互式 (逐步确认)
openclaw-uninstall --yes        # 跳过确认 (默认保留 VM)
openclaw-uninstall --yes --vm   # 跳过确认并删除 VM
```

清理内容：
- **VM 内**: Gateway 服务、Docker 沙箱容器/镜像、npm 全局包、配置文件、源代码
- **Mac 端**: `~/bin/openclaw-*` 命令、Shell 配置中的 PATH 条目
- **可选**: 删除整个 OrbStack VM

### 更新命令详情

`openclaw-update` 是**唯一**的更新命令：它先更新**这个 wrapper（openclaw-orbstack）本身**（`~/bin/openclaw-*` + 安装/更新脚本，只跑在 Mac 上），再把 wrapper 对齐的**上游 OpenClaw** 装进 VM（AI 大脑本体）。内部分两个阶段执行，但对用户是一条命令。

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
| *(默认)* | 跟随**当前**通道 | 分支检出 → `git pull`（过渡期做法，见下方说明）；检出在 stable tag 上 → 跟随最新 stable tag；检出在 beta tag 上 → 跟随含 pre-release 的最新 tag |
| `--pre` | **beta** 通道，会记住 | 切到含经验证 pre-release 的最新 tag，之后一直停留在这条线，直到 `--stable` |
| `--stable` | **stable** 通道，会记住 | 切回最新 stable tag；由此触发的 VM 侧 OpenClaw 降级通常仍需要 `--force`（或等下一个 stable） |
| `--version=<tag>` | **钉版本（pinned）** | 若存在对应的 wrapper tag `<tag>`，会把 wrapper 与 OpenClaw **一起**钉住——之后再跑一次不带参数的 `openclaw-update` 会保持这个钉住状态并提示；`--pre`/`--stable` 会恢复跟随通道。若没有匹配的 wrapper tag，则只钉 OpenClaw 版本（与旧行为一致） |

**两个内部阶段**：

1. **阶段一（wrapper）**：按上表参数把 `~/openclaw-orbstack` 仓库检出/切换到目标 wrapper tag（或跟随分支 `git pull`），并重新生成所有 `~/bin/openclaw-*` 命令。完全跑在 Mac 主机上，不碰 VM。可用隐藏参数 `--wrapper-only` 只跑这一段。
2. **阶段二（OpenClaw）**：读取阶段一落地后的 wrapper `VERSION`（除非 `--version=<tag>` 显式指定 OpenClaw tag），把这个版本装进 VM——停止 Gateway、切换 `~/openclaw` checkout、`npm install -g openclaw@<version>`、必要时重建沙箱镜像、`openclaw doctor --fix`、启动服务并轮询健康态。

装完后会**轮询 Gateway 是否真的进入 `running` 健康态**（不只看 start 是否派发成功）；若启动失败，会自动 `openclaw update repair` 自愈一次（重新拉齐缺失的 bundled plugin 目录），仍失败则如实报错并给出日志提示，不静默假成功。

**钉版本标记**：`--version=<tag>` 命中已存在的 wrapper tag 时，会在 `~/bin/.openclaw-pin` 写入这个钉住状态；之后不带参数的 `openclaw-update` 会读到这个标记、保持钉住并提示，而不是悄悄回到跟随通道。`--pre` / `--stable` 会清掉这个标记，恢复跟随对应通道。

> **当前 wrapper 的自更新行为（过渡期）**：默认通道推断时，只有当 repo 处于**分支** HEAD 时才会静默 `git pull` 拉取本 wrapper 的最新代码；若 HEAD 处于 **detached**（说明用户之前用 `--pre`/`--stable`/`--version=` 锁定了某个 release tag），则**保持锁定、不 pull、不告警**，让分支用户和 tag-pinned 用户共存。彻底移除这段 auto-pull（因为 `openclaw-update` 现在已经内含 wrapper 更新阶段）的动作推迟到 v2026.7.1 stable 线——那时才会有携带这套单命令模型的 stable tag。

**版本/发布模型**：wrapper 版本永远镜像一个**真实存在的上游 OpenClaw 版本**（不自造版本号）——上游 **stable → 本项目 Latest release**，经我们验证的上游 **beta → pre-release**。当前 `main` = `v2026.6.11`（Latest），`v2026.7.1-beta.6` 作为 pre-release 存在。想抢先体验就 `openclaw-update --pre`。

**行为要点**：
- 切通道 / 钉版本会把 repo checkout 到 tag（**detached HEAD 是刻意的**）。`refresh-mac-commands.sh` 在 detached HEAD 时会跳过它自身的静默 `git pull`，因此重新生成命令**不会**撤销这个锁定。
- 想回到跟随分支的滚动更新，`cd` 进 repo 目录 `git checkout main` 即可，之后默认通道会恢复静默 pull。
- 不静默降级 OpenClaw：若目标版本比 VM 里已构建的**更旧**，除非加 `--force`，否则拒绝执行（`--version=` 钉版本路径豁免）。

或单独重建沙箱镜像：
```bash
openclaw-sandbox-rebuild
```

> 沙箱镜像很少需要更新，只在上游 Dockerfile 变化时需要。已运行的容器仍使用旧镜像，需重启后生效。

---

## 官方 CLI 命令 (150+)

通过 `openclaw <command>` 访问所有官方命令。以下是常用命令分类：

### 状态与诊断

```bash
openclaw status                    # 频道健康 + 会话摘要
openclaw status --all              # 完整诊断 (可粘贴)
openclaw status --deep             # 探测所有频道
openclaw status --usage            # 模型使用量/配额
openclaw status --json             # JSON 格式输出
# v2026.4.22: /status 新增 `Runner:` 字段 (embedded pi / CLI-backed / ACP harness
# 如 codex (acp/acpx) / gemini (acp/acpx))；fast mode 启用时显示 `Fast` 字段
# v2026.5.20: /status 在 session 被 pin 到非默认模型时显示配置默认、当前 pinned model、
# 切回 hint 和 docs 链接（不再静默处理 pinned-model 偏移）
# v2026.5.28: status 输出新增当前活跃 subagent 详情（active subagent details）
# v2026.6.9: /status footer 新增 session duration 段 (如 "duration 2h 14m")，sessionStartedAt 可用时显示 (#88988)

openclaw doctor                    # 健康检查 + 报告问题 (不自动修复)
openclaw doctor --fix              # 自动修复: config 迁移、systemd 修复、plugin 依赖、stale lock 清理
openclaw doctor --repair           # --fix 的别名
openclaw doctor --force            # 与 --fix/--repair 组合: 覆盖自定义 supervisor 配置
openclaw doctor --deep             # 深度扫描系统服务 (launchd/systemd/schtasks)
openclaw doctor --non-interactive  # 无人值守: 仅安全迁移，跳过需确认的操作 (重启/服务/沙箱)
openclaw doctor --yes              # 接受默认值，跳过交互提示
openclaw doctor --generate-gateway-token  # 生成 Gateway 认证 token (仅当未配置时)

openclaw health                    # Gateway 健康状态
openclaw health --json             # JSON 格式输出
openclaw logs                      # Gateway 日志
openclaw logs --follow             # 实时日志
openclaw logs --limit 100          # 指定行数
openclaw logs --json               # JSON 格式输出
openclaw logs --local-time         # 本地时区显示
```

### Gateway 管理

```bash
openclaw gateway status                    # Gateway 状态
openclaw gateway status --deep             # 深度扫描系统服务
openclaw gateway status --json             # v2026.5.20+ (#56222): 包含 running Gateway version
                                           # (fallback 到 status RPC 数据，read probe 也可用)
openclaw gateway health                    # 健康检查
openclaw gateway probe                     # 完整可达性探测
openclaw gateway discover                  # Bonjour 发现

# 生命周期管理 (OrbStack 环境下一般用 openclaw-start/stop/restart 快捷命令)
openclaw gateway run                       # 前台运行 Gateway
openclaw gateway run --port 18789          # 指定端口
openclaw gateway run --auth token          # Token 认证模式
openclaw gateway run --auth password       # 密码认证模式
openclaw gateway run --verbose             # 详细日志
openclaw gateway install                   # 安装 Gateway 服务
openclaw gateway uninstall                 # 卸载 Gateway 服务
openclaw gateway start                     # 启动 Gateway 服务
openclaw gateway stop                      # 停止 Gateway 服务
openclaw gateway restart                   # 重启 Gateway 服务
openclaw gateway restart --force           # 强制重启 (v2026.5.2+)，跳过 active task 延迟器
openclaw gateway restart --wait <duration> # 重启等待 (v2026.5.2+)，例如 --wait 30s
openclaw gateway call <method>             # 调用 Gateway RPC 方法
```

### 频道管理

```bash
# 列出与状态
openclaw channels list             # 列出已配置频道 (v2026.5.7+ 仅频道，不再包含 model auth/usage)
openclaw channels list --all       # v2026.5.7+: 包含 bundled + catalog 频道 (#78456)
openclaw channels status           # 频道状态
openclaw channels status --deep    # 深度探测
openclaw channels status --channel <name>  # v2026.5.12+ (#80706): 仅探单一频道，避免同时启动其他频道 monitor
openclaw channels capabilities     # 提供商能力
openclaw channels resolve          # 频道/用户名 → ID 解析
openclaw channels logs             # 频道日志

# 添加频道
openclaw channels add                              # 交互式添加
openclaw channels add --channel telegram --token <TOKEN>
openclaw channels add --channel discord --token <TOKEN>
openclaw channels add --channel slack --token <TOKEN>

# 登录/登出
openclaw channels login                            # WhatsApp 登录 (扫码)
openclaw channels login --channel whatsapp
openclaw channels logout
openclaw channels remove
```

### 配对管理 (Pairing)

当 `dmPolicy="pairing"` (默认) 时，陌生用户私聊 Bot 会收到配对码，需要管理员批准。

```bash
# 查看待批准的配对请求
openclaw pairing list telegram
openclaw pairing list discord
openclaw pairing list --channel telegram --json

# 批准配对
openclaw pairing approve telegram <CODE>           # 批准 Telegram 用户
openclaw pairing approve discord <CODE>            # 批准 Discord 用户
openclaw pairing approve telegram <CODE> --notify  # 批准并通知用户
```

**配对流程**:
1. 用户私聊 Bot → Bot 返回 8 位配对码 (如 `ABCD1234`)
2. 管理员运行 `openclaw pairing approve telegram ABCD1234`
3. 用户被加入 allowlist，可以正常使用

**dmPolicy 设置**:
| 策略 | 行为 |
|------|------|
| `pairing` | **(默认)** 陌生用户获得配对码，批准后可用 |
| `allowlist` | 只有 allowFrom 列表中的用户可用 |
| `open` | 任何人都可用 (需配合 `allowFrom: ["*"]`) |
| `disabled` | 禁用私聊 |

```json
{
  "channels": {
    "telegram": {
      "dmPolicy": "pairing",
      "allowFrom": ["123456789"]
    }
  }
}
```

### 模型管理

```bash
# 状态
openclaw models status                     # 配置的模型状态
openclaw models status --probe             # 探测 API 认证
openclaw models status --check             # 认证即将过期时退出非零
openclaw models status --agent <id>        # 指定 Agent 的模型状态
openclaw models list               # 列出配置的模型
openclaw models list --all         # 完整模型目录

# 设置
openclaw models set <model>        # 设置默认模型
openclaw models set-image <model>  # 设置图像模型
openclaw models scan               # 扫描 OpenRouter 免费模型

# 聊天命令 (v2026.4.22+)
# /models                          # 浏览已配置 provider
# /models add <provider> <modelId> # ⚠️ v2026.4.24 起已废弃 (#71175)
#                                  # 调用会返回 deprecation message，不再写入配置
#                                  # provider 菜单也移除了 add 选项

# 别名
openclaw models aliases list
openclaw models aliases add <alias> <model>
openclaw models aliases remove <alias>

# 回退模型
openclaw models fallbacks list             # 列出回退模型
openclaw models fallbacks add <model>      # 添加回退模型
openclaw models fallbacks remove <model>   # 移除回退模型
openclaw models fallbacks clear            # 清除所有回退模型

# 图像回退模型
openclaw models image-fallbacks list       # 列出图像回退模型
openclaw models image-fallbacks add <model>
openclaw models image-fallbacks remove <model>
openclaw models image-fallbacks clear

# 认证
openclaw models auth add                   # 交互式添加认证
openclaw models auth login                 # 提供商登录流程
openclaw models auth login --provider <id> # 指定提供商登录
                                           # v2026.5.12+: --provider openai 默认走 ChatGPT/Codex 账号登录
                                           # 要走 API-key 走: --provider openai --method api-key
openclaw models auth login --provider openai --method api-key  # v2026.5.12+ 显式 API-key 路径
openclaw models auth setup-token           # 设置 token
openclaw models auth paste-token           # 粘贴 token
openclaw models auth order                 # 管理认证优先级
openclaw models auth list                  # v2026.5.4+: 列出 saved per-agent auth profiles (不 dump secrets)
openclaw models auth list --provider <id>  # v2026.5.4+: 仅列出指定 provider
openclaw models auth list --json           # v2026.5.4+: JSON 格式输出
```

### Agent 管理

```bash
openclaw agents list               # 列出 Agent
openclaw agents list --bindings    # 包含路由绑定
openclaw agents add <name>         # 添加新 Agent (v2026.6.1+ 不再依赖 provider catalog 在线，离线也能加)
openclaw agents add --workspace <dir>
openclaw agents set-identity       # 更新身份
openclaw agents delete <id>        # 删除 Agent

# 路由绑定管理 (v2026.2.26+)
openclaw agents bindings           # 列出所有路由绑定
openclaw agents bind <agentId>     # 添加路由绑定
openclaw agents unbind <agentId>   # 移除路由绑定

# 发送消息
openclaw agent -m "消息内容"
openclaw agent -m "hello" --to +86...
openclaw agent -m "test" --agent <id>
openclaw agent -m "think" --thinking high
openclaw agent -m "local" --local  # 本地运行
openclaw agent --message-file <path>  # v2026.6.11 (#93351): 从文件读取消息内容（长文/多行）
```

> 多 Agent 路由配置详见 [官方文档](https://docs.openclaw.ai/gateway/configuration)。

### 通用聊天命令

| 命令 | 功能 | 版本 |
|------|------|------|
| `/btw <message>` | 插入旁支问题，不影响主线对话节奏 | — |
| `/side <message>` | `/btw` 的别名 | v2026.5.3+ (#76934 同 PR) |
| `/steer <message>` | 在当前 session 跑动时打断/引导，不开新 turn；session idle 时直接走普通流程 | v2026.5.3+ (#76934) |
| `/context map` | 发送当前 session context contributors 的 treemap 图（直观看谁占多少 token） | v2026.5.12+ (#79867) |
| `/name [<title>]` | 重命名当前 session（写 label，trim/非空/≤512 字符，跨 store 唯一）；无参数显示当前名 + 本地推导建议（不修改）；仅授权发送者 | v2026.6.9 (#88581) |

### Skills 管理

```bash
openclaw skills list               # 列出所有 Skills
openclaw skills list --eligible    # 只显示可用的
openclaw skills list --verbose     # 显示缺失依赖
openclaw skills info <name>        # Skill 详情
openclaw skills check              # 检查状态摘要
openclaw skills install <name> --global  # v2026.5.19+ (#74466): 安装到 shared managed skills
openclaw skills update <name> --global   # v2026.5.19+ (#74466): 同上,对 shared 范围更新
# v2026.6.5+ (#90478): skills install 支持 ClawHub 上以 GitHub 仓库为后端的 skill
#   (按 pinned commit 下载 + install-policy 校验 + 安装后上报 telemetry)
```

### 配置管理

```bash
openclaw setup                     # 初始化配置
openclaw setup --workspace <dir>   # 指定工作区
openclaw setup --wizard            # 运行向导

openclaw onboard                   # 完整设置向导
openclaw onboard --non-interactive
openclaw onboard --skip-channels
openclaw onboard --skip-skills

openclaw configure                 # 配置向导
openclaw config file               # 显示当前配置文件路径
openclaw config get <path>         # 获取配置值
openclaw config set <path> <value> # 设置配置值
openclaw config set --merge <path> <json>  # v2026.4.22+: 合并到 map/list (provider-scoped 默认行为)
openclaw config set --replace <path> <json> # v2026.4.22+: 完全替换 map/list (显式 clobber)
openclaw config unset <path>       # 删除配置值
openclaw config unset <path> --dry-run        # v2026.5.16-beta.*+: 预览不写入
openclaw config unset <path> --dry-run --json # v2026.5.16-beta.*+: JSON 输出（与 set/patch 对齐）
openclaw config schema             # 导出 JSON Schema (含标题和描述, v2026.4.5 enriched)
```

#### 配置验证

```bash
openclaw config validate           # 验证配置文件语法和结构
openclaw config validate --json    # JSON 格式输出，适用于 CI/CD 集成
```

检查 `openclaw.json` 的语法错误、未知字段、类型不匹配等问题。

#### doctor --fix 迁移 (v2026.4.23+)

升级到 v2026.4.23 后**推荐跑一次** `openclaw doctor --fix`：会把旧的 main-session dreaming cron job 迁移到新的 isolated lightweight agent turn 形态（#70737 解耦的配套迁移）。不跑的话旧 cron 条目会被标记 stale 但仍按新路径执行，不影响功能。

#### doctor --fix 迁移 (v2026.4.25+)

升级到 v2026.4.25 后**强烈推荐再跑一次** `openclaw doctor --fix`：

1. **修复 #71761 transcript 污染**：v2026.4.24 的 embedded runtime context 会以可见 user prompt 写入会话，doctor 会自动检测并合并这些被复制的 prompt-rewrite 分支。
2. **`agentRuntime.id` 字段迁移**：旧的 runtime-policy 配置自动迁移到 canonical `agentRuntime.id`（#71957）。
3. **冷注册表迁移**：`plugins/installs.json` 取代 `plugins/installed-index.json`，doctor 会刷新冷注册表索引。

### 浏览器控制

```bash
# 管理
openclaw browser status            # 浏览器状态
openclaw browser start             # 启动浏览器
openclaw browser start --headless  # v2026.4.25+: 一次性 headless 启动 (不修改持久化配置)
openclaw browser stop              # 停止浏览器
openclaw browser reset-profile     # 重置浏览器配置

# 标签页
openclaw browser tabs              # 列出标签页
openclaw browser open <url>        # 新标签打开 URL
openclaw browser close             # 关闭标签页
openclaw browser focus             # 激活标签页

# 检查
openclaw browser screenshot        # 截图
openclaw browser snapshot          # 捕获 DOM 状态
openclaw browser doctor            # v2026.4.24+: 浏览器就绪诊断 (managed Chromium 启动前置检查)
openclaw browser doctor --deep     # v2026.4.25+: 实时 snapshot 探测 + iframe-aware role / cursor-clickable 检测

# 交互
openclaw browser navigate <url>    # 导航到 URL
openclaw browser click             # 点击元素
openclaw browser click-coords      # v2026.4.24+: 视口坐标点击 (#54452, managed + existing-session)
openclaw browser type              # 输入文本
openclaw browser press             # 按键
openclaw browser hover             # 悬停
openclaw browser select            # 选择
openclaw browser upload            # 上传文件
openclaw browser fill              # 填充表单
openclaw browser evaluate          # 执行 JavaScript
openclaw browser evaluate --timeout-ms <ms>  # v2026.5.19+ (#83447): 单次 evaluate 自定义超时
openclaw browser dialog --dialog-id <id>     # v2026.5.19+: 应答页面 modal 对话框(snapshot 会返回 pending dialog 列表)
openclaw browser pdf               # 导出 PDF

# 配置文件
openclaw browser profiles          # 列出配置文件
openclaw browser create-profile    # 创建配置文件
openclaw browser delete-profile    # 删除配置文件
```

> v2026.4.24+ 默认 `actionTimeoutMs: 60000` (60s)，避免长浏览器等待在客户端边界过早超时。
> 配置项: `browser.actionTimeoutMs`，per-profile 可覆盖 `browser.profiles.<name>.headless`。

### 定时任务

```bash
openclaw cron status               # 定时任务状态
openclaw cron list                 # 列出任务
openclaw cron list --json          # v2026.5.7+: 含 status 字段 (disabled/running/ok/error/skipped/idle, #78701)
openclaw cron show <id> --json     # v2026.5.7+: 同上 status 字段
# v2026.6.9: cron list 输出更紧凑 (#93395); cron list/show 人类可读输出也解析 lastRunStatus (#93245)
openclaw cron get <id>             # v2026.5.12+ (#75117): 按 id 查看单个 job (优先用这个而非 show)
openclaw cron add                  # 添加任务
openclaw cron edit <id>            # 编辑任务
openclaw cron edit <id> --clear-model  # v2026.6.9 (#91625): 清除某 job 的 model override (回落到默认模型)
openclaw cron enable <id>          # 启用任务
openclaw cron disable <id>         # 禁用任务
openclaw cron rm <id>              # 删除任务 (也可能是 cron delete，待实测确认)
openclaw cron runs                 # 查看运行记录
openclaw cron run <id>             # 手动触发任务
openclaw cron run <id> --wait --timeout 30s --poll 1s  # v2026.5.16-beta.*+: 阻塞等待运行完成
openclaw cron runs --run-id <run>  # v2026.5.16-beta.*+: 按运行 ID 精确过滤

# v2026.4.27+: Telegram forum topic 投递保留 (cron add/edit)
openclaw cron add --thread-id <topicId>     # 跨调度保留 Telegram forum topic
openclaw cron edit <id> --thread-id <topicId>
```

### 消息发送

```bash
# 基础
openclaw message send --target <dest> --message "内容"
openclaw message broadcast         # 群发
openclaw message poll              # 创建投票
openclaw message react             # 添加反应
openclaw message reactions         # 查看反应
openclaw message read              # 读取消息
openclaw message edit              # 编辑消息
openclaw message delete            # 删除消息
openclaw message search            # 搜索消息

# 预演 (dry-run) — send/broadcast/poll 支持，不实际发送
openclaw message send --target <dest> --message "内容" --dry-run   # v2026.6.9 (#94684): 打印 "[dry-run] would run send via <channel>"；--json 输出含 dryRun:true

# 置顶
openclaw message pin               # 置顶消息
openclaw message unpin             # 取消置顶
openclaw message pins              # 列出置顶消息

# 话题
openclaw message thread create     # 创建话题
openclaw message thread list       # 列出话题
openclaw message thread reply      # 回复话题

# 服务器管理 (Discord/Slack)
openclaw message role info         # 角色信息
openclaw message channel list      # 频道列表
openclaw message member info       # 成员信息
openclaw message event list        # 事件列表
openclaw message event create      # 创建事件
```

### 内存/记忆

```bash
openclaw memory status             # 内存索引状态
openclaw memory status --deep      # 探测 embedding
openclaw memory status --index     # 包含索引统计
openclaw memory index              # 重建索引
openclaw memory index --force      # 强制重建
openclaw memory search <query>     # 搜索记忆 (位置参数)
openclaw memory search --query <text>  # 搜索记忆 (命名参数)
openclaw memory search --max-results 10  # 限制结果数量

# 记忆梦境 (实验性, v2026.4.5+)
# 自动将短期记忆提升为长期记忆，通过 light/deep/REM 三阶段后台处理
# 产出写入顶层 dreams.md，不进入默认 recall，需显式读取
openclaw memory rem-harness        # REM 预览工具 (查看待提升记忆)
openclaw memory rem-harness --path <dir>  # 历史 daily notes 回放补填 (v2026.4.9+)
openclaw memory promote-explain    # 解释提升决策

# Memory Wiki (v2026.4.7+, memory-wiki 插件)
# 结构化知识库：claim/evidence 字段、矛盾聚类、新鲜度加权搜索
openclaw wiki status               # wiki 状态 (vault、bridge、页面统计)
openclaw wiki sync                 # 同步 wiki 数据
openclaw wiki query <text>         # 搜索 wiki
openclaw wiki apply                # 应用 wiki 操作
openclaw wiki digest               # 获取编译摘要
openclaw wiki lint                 # claim 健康检查 (矛盾检测)
```

**聊天命令**:

| 命令 | 功能 |
|------|------|
| `/dreaming status` | 查看梦境状态 |
| `/dreaming on\|off` | 开关梦境 |
| `/dreaming help` | 帮助 |
| `/active-memory status` | 查看 Active Memory 状态 (含延迟、召回字数) |
| `/active-memory on` | 当前会话开启 Active Memory |
| `/active-memory off` | 当前会话关闭 Active Memory |
| `/verbose on` | 显示 Active Memory 调试信息 (延迟、召回内容) |
| `/tts latest` | v2026.4.25+: 朗读最新一条回复 (按需重读，含去重) |
| `/tts chat on\|off\|default` | v2026.4.25+: 当前会话级 auto-TTS 覆盖 |
| `/tts persona <name>` | v2026.4.25+: 切换声线人格 (provider-aware, 70748) |
| `/tts audio` / `/tts status` | 上次音频 / TTS 当前状态 |

配置（在 `plugins.entries.memory-core.config.dreaming` 中设置）：
```json5
{
  "plugins": {
    "entries": {
      "memory-core": {
        "config": {
          "dreaming": {
            "enabled": true,
            "frequency": "0 3 * * *"  // cron 表达式，默认每天凌晨 3 点
          }
        }
      }
    }
  }
}
```

产出位置：`memory/.dreams/`（机器状态）、`DREAMS.md`（人类可读）、`MEMORY.md`（长期提升）。
Control UI 的 Dreams 面板也可查看梦境日志。

### Memory Wiki 导入 (v2026.4.11+)

Memory Wiki 支持从 ChatGPT 导出文件导入对话历史，在 Control UI Dreams 面板新增：
- **Imported Insights** — 查看导入的源对话编译后的 wiki 页面
- **Memory Palace** — 浏览完整源页面

导入通过 Control UI 的 Dreams 面板操作，非 CLI 命令。

### 插件

```bash
openclaw plugins list              # 列出插件
openclaw plugins info <id>         # 插件详情
openclaw plugins install <source>  # 安装插件
openclaw plugins install <npm> --pin  # 从 npm 安装并锁定版本
openclaw plugins install <source> --force  # 替换已有目标 (v2026.4.5+)
openclaw plugins enable <id>       # 启用插件
openclaw plugins disable <id>      # 禁用插件
openclaw plugins uninstall <id>    # 卸载插件
openclaw plugins update <id>       # 更新单个插件
openclaw plugins update --all      # 更新所有插件

# 插件开发工具 (v2026.5.16-beta.*+) — 配合 defineToolPlugin SDK
openclaw plugins init <dir>        # 初始化简单工具插件脚手架
openclaw plugins build <dir>       # 编译/打包带 manifest 元数据
openclaw plugins validate <dir>    # 校验 manifest + 类型化工具声明
openclaw plugins doctor            # 插件诊断
openclaw plugins registry          # v2026.4.25+: 检查持久化冷注册表 (plugins/installs.json)
openclaw plugins registry --refresh # v2026.4.25+: 强制重建注册表 (修复 stale entries)
openclaw plugins deps              # v2026.4.29+: 检查 bundled 插件 runtime 依赖（不阻塞 doctor）
openclaw plugins deps --repair     # v2026.4.29+: 修复缺失/破损的 bundled runtime deps
```

> v2026.4.29 引入独立 `plugins deps` inspect/repair，专门处理 bundled 插件 runtime-deps tarball；v4.27 缺 chokidar/sqlite-vec/ajv 类问题主要靠这条命令排查。打包路径走 script-free package-manager 默认值，不破坏 JSON 输出，也不阻塞无冲突的其他依赖。

> v2026.4.25 起插件启动改用持久化冷注册表 (`plugins/installs.json`)，普通启动不再扫描 manifest。
> `OPENCLAW_DISABLE_PERSISTED_PLUGIN_REGISTRY` 标记为 deprecated break-glass，遇问题先跑 `plugins registry --refresh` 或 `doctor --fix`。

### 沙箱

```bash
# 列出沙箱
openclaw sandbox list                      # 列出沙箱容器
openclaw sandbox list --browser            # 列出浏览器沙箱
openclaw sandbox list --session <id>       # 按会话过滤

# 重建沙箱
openclaw sandbox recreate                  # 重建沙箱
openclaw sandbox recreate --all            # 重建所有沙箱
openclaw sandbox recreate --browser        # 重建浏览器沙箱
openclaw sandbox recreate --agent <name>   # 重建指定 Agent 的沙箱
openclaw sandbox recreate --force          # 强制重建 (不确认)

# 解释配置
openclaw sandbox explain                   # 解释沙箱配置
openclaw sandbox explain --agent <id>      # 指定 Agent
```

### Shell 自动补全

```bash
openclaw completion                        # 生成 zsh 补全脚本 (默认)
openclaw completion --shell bash           # 生成 bash 补全脚本 (短形式: -s)
openclaw completion --shell fish           # 生成 fish 补全脚本
openclaw completion --shell powershell     # 生成 PowerShell 补全脚本

openclaw completion --install              # 安装补全脚本到 shell 配置 (短形式: -i)
openclaw completion --install --yes        # 跳过确认直接安装 (短形式: -y)
```

### Secrets 管理 (v2026.2.26+)

```bash
openclaw secrets audit             # 审计 secrets (明文检测、未解析 ref 等)
openclaw secrets audit --check     # 有发现时退出非零 (CI 适用)
openclaw secrets configure         # 交互式 secrets 提供商配置
openclaw secrets apply             # 执行保存的计划并清除明文残留
openclaw secrets apply --dry-run   # 预览操作
openclaw secrets reload            # 重新解析 SecretRef 并热替换运行时快照
```

> 外部 Secrets 管理详见 [官方文档](https://docs.openclaw.ai/gateway/configuration)。

> v2026.3.2: SecretRef 扩展至 64 个目标位置，覆盖更多配置字段。

### 安全审计

```bash
openclaw security audit            # 安全审计
openclaw security audit --deep     # 深度扫描
openclaw security audit --fix      # 自动修复
```

### Hooks 管理

```bash
openclaw hooks list                # 列出 hooks
openclaw hooks info <name>         # Hook 详情
openclaw hooks check               # 检查 hooks 状态
openclaw hooks enable <name>       # 启用 hook
openclaw hooks disable <name>      # 禁用 hook
openclaw hooks install <source>    # 安装 hook
openclaw hooks update <name>       # 更新 hook
```

### 执行策略管理 (v2026.4.10+)

```bash
openclaw exec-policy show               # 查看当前 exec 策略
openclaw exec-policy preset <name>      # 应用预设策略
openclaw exec-policy set <key> <value>  # 设置策略字段
```

同步 `tools.exec.*` 配置与本地 exec 审批文件。v2026.4.12 增强：node-host rejection 加固、回滚安全保护、同步冲突检测。

### 推理工作流 (v2026.4.7+)

```bash
# openclaw infer — 提供商推理命令中心
# 支持模型推理、媒体生成、Web 搜索、嵌入等任务
# 自动回退认证、尺寸/分辨率自动映射到最接近的支持选项
openclaw infer --help              # 查看所有子命令
openclaw infer models              # 模型推理
openclaw infer media               # 媒体生成 (图像/视频/音乐)
openclaw infer web                 # Web 搜索
openclaw infer embedding           # 嵌入向量

# v2026.4.25+ image 子命令通用 flags:
openclaw infer image generate --background <transparent|opaque>  # 通用 (alias --openai-background)
openclaw infer image generate --output-format png|jpeg           # fal/兼容 provider
openclaw infer image edit --size <WxH>                           # 编辑尺寸
openclaw infer image edit --aspect-ratio <比例>                  # 比例覆盖
openclaw infer image edit --resolution <分辨率>                  # 分辨率覆盖
openclaw infer image edit --count <n>                            # v2026.6.11 (#95300): 生成 n 张，与 image generate 对齐

# v2026.4.27+ image describe 透传 prompt + 超时 (#63700)
openclaw infer image describe --prompt "..."        # 自定义视觉指令传给 Ollama/OpenAI/Google/OpenRouter
openclaw infer image describe --timeout-ms 60000    # 慢本地模型预算
openclaw infer image describe-many --prompt "..." --timeout-ms 60000
```

### Voice Call (v2026.4.24+)

```bash
openclaw voicecall setup           # 初始化 Voice Call 配置
openclaw voicecall smoke           # dry-run 默认的就绪冒烟测试 (Twilio/provider)
```

> v4.24 新增 `openclaw_agent_consult` realtime 工具，电话中的 AI 可以问"全 OpenClaw agent" 拿更深入答案。

### Matrix 验证 (v2026.4.24+)

```bash
openclaw matrix verify self        # 在 CLI 端建立 self-device 的 cross-signing 信任 (#70401)
openclaw matrix verify status      # 查看 verify 状态

# v2026.4.26+: Matrix E2EE 一键引导
openclaw matrix encryption setup   # 启用 Matrix 加密、bootstrap recovery、打印 verification 状态
```

### Codex Computer Use (v2026.4.27+)

```bash
openclaw codex computer-use status        # 查看 Codex Computer Use 是否就绪 (MCP 服务器 fail-closed 检查)
openclaw codex computer-use install       # 安装 / 接入 marketplace 发现的桌面控制 MCP
```

> v4.27 新增 (#72094)：为 Codex-mode agent 启用桌面控制需要 fail-closed MCP server 检查；本机 desktop control 在 Codex 模式下可通过此命令族管理。可与 `cua-driver mcp`、PeekabooBridge 协同。

### Nodes 多主机 (v2026.4.26+)

```bash
openclaw nodes list                          # 列出 paired-node（v4.26 默认改为 effective paired-node 视图，与 nodes status 对齐）
openclaw nodes status                        # 节点状态
openclaw nodes remove --node <id|name|ip>    # 清理过期 paired-node 记录（无需手编 state 文件）
```

> 多 Mac/多机部署见 `memory/multi_mac_setup.md`：Mac A (Gateway) + Mac B (Node) 通过 pairing 协作。

### 配置迁移 (v2026.4.26+)

```bash
openclaw migrate                             # 启动迁移向导
openclaw migrate --plan                      # 仅打印迁移计划
openclaw migrate --dry-run                   # 模拟运行，不写入
openclaw migrate --json                      # 机器可读输出
openclaw migrate --backup                    # 迁移前自动备份
```

> bundled 导入器：**Claude Code/Desktop**（指令、MCP servers、skills、command prompts、archive/manual-review state）+ **Hermes**（NousResearch 的 config/memory/plugin hints/model providers/MCP servers/skills/credentials）。包含 onboarding 检测和 archive-only report 副本。

### Google Meet (v2026.4.24+)

```bash
openclaw googlemeet doctor --oauth # OAuth + 浏览器状态诊断
openclaw googlemeet recover-tab    # 接管已开的 Meet tab，避免重复打开
```

> 需要个人 Google OAuth；支持 Chrome 与 Twilio realtime + paired-node Chrome；可导出会议记录、转写、smart notes、参与者会话。

### 备份管理 (v2026.3.8+)

```bash
openclaw backup create                     # 创建本地状态备份
openclaw backup create --only-config       # 仅备份配置
openclaw backup create --no-include-workspace  # 排除工作区
openclaw backup verify <archive>           # 验证备份完整性
```

> 备份包含 manifest 和 payload 验证。在破坏性操作（如 `reset`、`uninstall`）时会提供备份建议。

### 其他

```bash
openclaw sessions                  # 会话列表 (v2026.5.4+ 默认仅返回最新 100 行)
openclaw sessions list             # v2026.5.16-beta.*+ (#81163): list 别名，与其他子命令保持一致
openclaw sessions --active 60      # 最近 60 分钟活跃的
openclaw sessions --json           # JSON 格式输出
openclaw sessions --limit <n|all>  # v2026.5.4+ (#77500): 显式行数 (n) 或 all 取消上限
openclaw sessions cleanup          # 会话维护
openclaw sessions cleanup --dry-run    # 预览清理操作
openclaw sessions cleanup --enforce    # 强制执行清理

# 会话压缩检查点 (v2026.4.7+)
# Control UI Sessions 面板可查看压缩检查点、分支/恢复压缩前状态
openclaw sessions checkpoint       # 查看压缩检查点
openclaw sessions branch <id>      # 从检查点分支 (恢复压缩前状态)
openclaw sessions restore <id>     # 恢复到指定检查点

openclaw dashboard                 # 打开控制面板
openclaw dashboard --no-open       # 只打印 URL

openclaw reset                     # 重置配置/状态
openclaw reset --dry-run           # 预览重置操作
openclaw uninstall                 # 卸载
openclaw uninstall --all --yes     # 卸载全部 (跳过确认)

openclaw update                    # 更新 CLI

openclaw --version                 # 版本
openclaw --help                    # 帮助

# 代理验证 (v2026.5.2+, #73438)
openclaw proxy validate            # 验证 effective proxy 配置 + 可达性 + allow/deny 行为
```

### 全局 Flags

所有命令均支持以下全局 flags：

| Flag | 功能 |
|------|------|
| `--dev` | 使用隔离的开发环境状态 |
| `--profile <name>` | 使用命名配置 |
| `--no-color` | 禁用 ANSI 颜色 |
| `--json` | 机器可读的 JSON 输出 |
| `-V, --version` | 打印版本 |

### 高级命令

以下命令主要用于开发和系统集成，一般用户无需使用：

`acp`, `approvals`, `clawbot`, `daemon`, `exec-policy`, `flows`, `infer`, `system`, `node`, `nodes`, `devices`, `dns`, `docs`, `hooks`, `webhooks`, `directory`, `qr`, `security`, `tasks`, `tui`

运行 `openclaw <command> --help` 查看详情。

#### openclaw tasks maintenance --json (v2026.5.20+)

```bash
openclaw tasks maintenance --json          # 检视 stale-running task 的清理决策
```

v5.20 (#84691) 起 `--json` 输出对每个 retained 或 reconcile candidate 列出 backing-session、cron、CLI、wedged-subagent 状态，便于排查为什么某个 task 没被自动清理。基础 `openclaw tasks maintenance` 命令本身更早就存在。

#### sessions_spawn forkedContext (v2026.4.23+)

Agent 通过 `sessions_spawn` 原生工具派生子 session 时，可选 `forkedContext: true` 让子 agent 继承 requester 的 transcript（非默认）。适合需要共享上下文的协作子任务；默认仍是 clean isolated，避免上下文污染。

#### /codex plugins 子命令 (v2026.5.19+)

在 chat 里直接管理 native Codex 插件,不用手改 config:

- `/codex plugins list` — 列出已配置的 Codex 插件
- `/codex plugins enable <name>` — 启用一个
- `/codex plugins disable <name>` — 禁用一个

注:这是 Codex app-server 自带的 native 插件管理面,跟 OpenClaw 顶层 `openclaw plugins` 是两套体系(OpenClaw plugins 服务 wrapper / channels / runtime,Codex plugins 服务 Codex harness 内部工具)。

#### openclaw meeting-notes (v2026.5.22+)

```bash
openclaw meeting-notes             # 只读访问已捕获的会议记录
```

v5.22 引入的会议记录功能,实现在一个 **source-only 外部插件**里(不打包进 core npm),提供 auto-start 捕获配置、手动 transcript 导入、以及只读的 `openclaw meeting-notes` CLI;首个 live source 是 Discord voice。

注:这是 **opt-in 外部插件**,默认不安装。本 OrbStack wrapper 不预装它——只有显式安装该插件后 `openclaw meeting-notes` 才可用。

#### Skill Workshop (v2026.5.31+)

让 agent 从聊天里**受管地创建/更新 workspace skill**——不是直接写活的 `SKILL.md`,而是先生成一份 **proposal(`PROPOSAL.md` 草案)**,只有 `apply` 才会落成正式 skill。只动 workspace `skills/` 根,不碰 bundled / plugin / ClawHub / system skill。

生命周期:`create/update → pending`,`revise → pending`,`apply → applied`,`reject → rejected`,`quarantine → quarantined`,目标 skill 在 apply 前被改则 `→ stale`(hash 绑定失效)。只有 `pending` 能 revise/apply/reject/quarantine。

聊天里直接说需求即可(agent 调 `skill_workshop` 工具,返回 proposal id):

```text
做一个叫 morning-catchup 的 skill，跑我周一收件箱例程。
给我看 morning-catchup 这个 proposal。
应用 morning-catchup proposal。
```

对应 CLI:

```bash
openclaw skills workshop propose-create --name <name> --description "..." --proposal ./PROPOSAL.md
openclaw skills workshop propose-update <skill> --proposal ./PROPOSAL.md
openclaw skills workshop list                       # 列出 proposal
openclaw skills workshop inspect <proposal-id>      # 查看细节
openclaw skills workshop revise <proposal-id> --proposal ./PROPOSAL.md
openclaw skills workshop apply <proposal-id>        # 唯一会写活 skill 的动作
openclaw skills workshop reject <proposal-id> --reason "..."
openclaw skills workshop quarantine <proposal-id> --reason "..."
```

附带支持文件用 `--proposal-dir <dir>`(目录须含 `PROPOSAL.md`,支持文件只能放 `assets/` `examples/` `references/` `scripts/` `templates/`)。

配置在 `skills.workshop`:`autonomous.enabled`(默认 `false`,关掉 agent 自主从对话信号生成 proposal)、`approvalPolicy`(`"pending"` = agent 发起的 apply/reject/quarantine 前要审批 prompt,`"auto"` = 跳过)、`maxPending: 50`、`maxSkillBytes: 40000`。默认很保守——非 `apply` 不会改活文件,且 apply 前会重跑 scanner、写 rollback 元数据,可恢复。

---

## OrbStack VM 管理

```bash
orb list                           # 列出 VM
orb -m openclaw-vm bash            # 进入 VM
orb -m openclaw-vm bash -c "..."   # 在 VM 中执行命令
orb stop openclaw-vm               # 停止 VM
orb start openclaw-vm              # 启动 VM
orb delete openclaw-vm             # 删除 VM (危险!)
orb export openclaw-vm backup.tar.zst   # 导出 VM 快照
orb import -n openclaw-vm backup.tar.zst # 从快照恢复 VM
```

---

## 环境变量

### 部署时可选的环境变量

| 变量 | 用途 | 示例 |
|------|------|------|
| `OPENCLAW_VM_NAME` | VM 名称 | `my-openclaw` |
| `OPENCLAW_PORT` | Gateway 端口 | `19000` |

### Gateway 运行时环境变量

这些环境变量已在 systemd 服务中配置：

| 变量 | 用途 | 配置位置 |
|------|------|----------|
| `OPENCLAW_DISABLE_BONJOUR` | 禁用 Bonjour/mDNS 广播 | 主 service (`onboard` 设置) |
| `NODE_ENV` | Node.js 环境 | 主 service (`onboard` 设置) |
| `NODE_COMPILE_CACHE` | Node 编译缓存，加速重复启动 | drop-in (`openclaw-orbstack.conf`) |
| `OPENCLAW_NO_RESPAWN` | 跳过 self-respawn，减少启动开销 | drop-in (`openclaw-orbstack.conf`) |
| `PATH` | 钉死为规范值，防止版本管理器目录污染 Gateway 环境 | drop-in (`99-openclaw-orbstack-path.conf`) |

### OpenClaw 路径环境变量

| 变量 | 用途 | 默认值 |
|------|------|--------|
| `OPENCLAW_HOME` | 覆盖 home 目录 | `~` |
| `OPENCLAW_STATE_DIR` | 覆盖状态目录 | `~/.openclaw` |
| `OPENCLAW_CONFIG_PATH` | 覆盖配置文件路径 | `~/.openclaw/openclaw.json` |
| `OPENCLAW_LOAD_SHELL_ENV` | 从 login shell 导入环境变量 | 未设置 |
| `OPENCLAW_SHELL_ENV_TIMEOUT_MS` | shell 环境导入超时 | `15000` |
| `OPENCLAW_BROWSER_NO_SANDBOX` | Disable Chromium sandbox in browser container | 未设置 |
| `OPENCLAW_TELEGRAM_DNS_RESULT_ORDER` | Override DNS result order for Telegram | 未设置 |
| `OPENCLAW_NODE_EXEC_HOST` | Override Node.js execution host for sandbox | 未设置 |

---

## 故障排查命令

### 检查服务状态

```bash
# 查看服务状态
openclaw-status

# 查看实时日志
openclaw-logs

# 进入 VM 排查
openclaw-shell
```

### 进程和端口诊断

```bash
# 查看 Gateway 进程
orb -m openclaw-vm bash -c 'ps aux | grep openclaw'

# 查看端口占用
orb -m openclaw-vm bash -c 'ss -tlnp | grep 18789'

# 查看进程环境变量
orb -m openclaw-vm bash -c 'cat /proc/$(pgrep -f openclaw-gateway | head -1)/environ | tr "\0" "\n" | grep -i bonjour'

# 查看 systemd 服务状态
orb -m openclaw-vm bash -c 'systemctl --user status openclaw-gateway'
```

### 强制重启服务

```bash
# 杀死所有进程并重启
openclaw-stop
orb -m openclaw-vm bash -c 'sudo pkill -9 -f "openclaw"; sudo pkill -9 node; sleep 2'
openclaw-start
```

详细故障排查指南见 [troubleshooting.md](troubleshooting.md)
