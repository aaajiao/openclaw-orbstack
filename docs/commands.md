# CLI 命令参考

## 概览

在 Mac 上有两类命令可用：

1. **OrbStack 管理命令** (`openclaw-*`) - 我们为 OrbStack 架构添加的 14 个命令
2. **官方 CLI 命令** (`openclaw <command>`) - 透传到 VM 的 150+ 官方命令

---

## OrbStack 管理命令 (14 个)

这些命令在 `~/bin/` 目录下，用于管理 OrbStack VM 和服务：

### 核心命令

| 命令 | 功能 |
|------|------|
| **`openclaw`** | **CLI 透传** - 所有参数传到 VM 的官方 CLI |
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
| `openclaw-telegram` | Telegram Bot 管理 |
| `openclaw-whatsapp` | WhatsApp 登录 (扫码) |

```bash
# Telegram Bot 管理
openclaw-telegram                      # 查看帮助
openclaw-telegram add <bot_token>      # 添加 Bot (从 @BotFather 获取)
openclaw-telegram approve <code>       # 批准配对 (回执验证码)

# WhatsApp 登录
openclaw-whatsapp                      # 扫码登录
```

### 服务管理

| 命令 | 功能 |
|------|------|
| `openclaw-status` | 查看 Gateway 服务状态 (openclaw gateway status) |
| `openclaw-logs` | 实时日志 (openclaw logs --follow) |
| `openclaw-restart` | 重启服务 |
| `openclaw-stop` | 停止服务 |
| `openclaw-start` | 启动服务 |
| `openclaw-shell` | 进入 VM 终端 |
| `openclaw-doctor` | 运行诊断 (openclaw doctor) |
| `openclaw-update` | 更新版本 (`--sandbox` 重建镜像，`--force` 强制重建) |
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

`openclaw-update` 会先检查是否有新版本。如果已是最新，直接跳过构建流程：

```bash
openclaw-update          # 有新版本才更新，已是最新则跳过
openclaw-update --force  # 强制重新构建（即使已是最新版本）
openclaw-update --sandbox  # 同时重建沙箱 Docker 镜像
```

有新版本时的更新流程：
1. 获取最新 release tag
2. 检查 Node.js 版本 (需 >= 24)
3. 停止 Gateway 服务
4. 切换到新版本
5. 安装 — 主路径: `npm install -g openclaw@<version>` (预编译包)
6. 若主路径失败 — 兜底: `pnpm install && pnpm build && pnpm ui:build && sudo npm install -g .` (源码构建)
7. 检测沙箱镜像变化 (per-image hash 对比)
8. 修复 service 配置 (`openclaw doctor --fix`)
9. 启动服务

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
openclaw gateway call <method>             # 调用 Gateway RPC 方法
```

### 频道管理

```bash
# 列出与状态
openclaw channels list             # 列出所有频道
openclaw channels status           # 频道状态
openclaw channels status --deep    # 深度探测
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
openclaw models auth setup-token           # 设置 token
openclaw models auth paste-token           # 粘贴 token
openclaw models auth order                 # 管理认证优先级
```

### Agent 管理

```bash
openclaw agents list               # 列出 Agent
openclaw agents list --bindings    # 包含路由绑定
openclaw agents add <name>         # 添加新 Agent
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
```

> 多 Agent 路由配置详见 [官方文档](https://docs.openclaw.ai/gateway/configuration)。

### Skills 管理

```bash
openclaw skills list               # 列出所有 Skills
openclaw skills list --eligible    # 只显示可用的
openclaw skills list --verbose     # 显示缺失依赖
openclaw skills info <name>        # Skill 详情
openclaw skills check              # 检查状态摘要
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
openclaw config unset <path>       # 删除配置值
openclaw config schema             # 导出 JSON Schema (含标题和描述, v2026.4.5 enriched)
```

#### 配置验证

```bash
openclaw config validate           # 验证配置文件语法和结构
openclaw config validate --json    # JSON 格式输出，适用于 CI/CD 集成
```

检查 `openclaw.json` 的语法错误、未知字段、类型不匹配等问题。

### 浏览器控制

```bash
# 管理
openclaw browser status            # 浏览器状态
openclaw browser start             # 启动浏览器
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

# 交互
openclaw browser navigate <url>    # 导航到 URL
openclaw browser click             # 点击元素
openclaw browser type              # 输入文本
openclaw browser press             # 按键
openclaw browser hover             # 悬停
openclaw browser select            # 选择
openclaw browser upload            # 上传文件
openclaw browser fill              # 填充表单
openclaw browser evaluate          # 执行 JavaScript
openclaw browser pdf               # 导出 PDF

# 配置文件
openclaw browser profiles          # 列出配置文件
openclaw browser create-profile    # 创建配置文件
openclaw browser delete-profile    # 删除配置文件
```

### 定时任务

```bash
openclaw cron status               # 定时任务状态
openclaw cron list                 # 列出任务
openclaw cron add                  # 添加任务
openclaw cron edit <id>            # 编辑任务
openclaw cron enable <id>          # 启用任务
openclaw cron disable <id>         # 禁用任务
openclaw cron rm <id>              # 删除任务 (也可能是 cron delete，待实测确认)
openclaw cron runs                 # 查看运行记录
openclaw cron run <id>             # 手动触发任务
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
openclaw plugins doctor            # 插件诊断
```

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
```

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
openclaw sessions                  # 会话列表
openclaw sessions --active 60      # 最近 60 分钟活跃的
openclaw sessions --json           # JSON 格式输出
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

`acp`, `approvals`, `clawbot`, `daemon`, `exec-policy`, `flows`, `infer`, `system`, `node`, `nodes`, `devices`, `dns`, `docs`, `hooks`, `webhooks`, `directory`, `qr`, `security`, `tasks`, `tui`, `voicecall`

运行 `openclaw <command> --help` 查看详情。

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
