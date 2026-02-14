# CLI 命令参考

## 概览

在 Mac 上有两类命令可用：

1. **OrbStack 管理命令** (`openclaw-*`) - 我们为 OrbStack 架构添加的 13 个命令
2. **官方 CLI 命令** (`openclaw <command>`) - 透传到 VM 的 150+ 官方命令

---

## OrbStack 管理命令 (13 个)

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
| `openclaw-logs` | 实时日志 (journalctl -f) |
| `openclaw-restart` | 重启服务 |
| `openclaw-stop` | 停止服务 |
| `openclaw-start` | 启动服务 |
| `openclaw-shell` | 进入 VM 终端 |
| `openclaw-doctor` | 运行诊断 (openclaw doctor) |
| `openclaw-update` | 更新版本 (仅应用，`--sandbox` 重建镜像) |
| `openclaw-sandbox-rebuild` | 重建沙箱 Docker 镜像 |

### 更新命令详情

`openclaw-update` 默认只更新应用（不重建沙箱镜像）：
1. 停止 Gateway 服务
2. 获取最新 release tag 并切换
3. 安装依赖 (`npm install`)
4. 编译项目 (`npm run build`)
5. 构建 Control UI (`pnpm ui:build`)
6. 重新安装 CLI (`npm install -g .`)
7. 启动服务

使用 `--sandbox` 标志同时重建沙箱镜像：
```bash
openclaw-update --sandbox
```

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

openclaw doctor                    # 健康检查 + 快速修复
openclaw doctor --repair           # 自动修复
openclaw doctor --force            # 强制修复
openclaw doctor --deep             # 扫描系统服务

openclaw health                    # Gateway 健康状态
openclaw logs                      # Gateway 日志
openclaw logs --follow             # 实时日志
openclaw logs --lines 100          # 指定行数
```

### Gateway 管理

```bash
openclaw gateway status                    # Gateway 状态
openclaw gateway status --deep             # 深度扫描
openclaw gateway health                    # 健康检查
openclaw gateway probe                     # 完整可达性探测
openclaw gateway discover                  # Bonjour 发现
openclaw gateway usage-cost                # 使用成本摘要

# 生命周期管理 (OrbStack 环境下一般用 openclaw-start/stop/restart 快捷命令)
openclaw gateway run                       # 前台运行 Gateway
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
openclaw channels status --probe   # 探测凭据
openclaw channels capabilities     # 提供商能力
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
openclaw models auth login-github-copilot  # GitHub Copilot 登录
openclaw models auth setup-token           # 设置 token
openclaw models auth paste-token           # 粘贴 token
openclaw models auth order get             # 查看认证优先级
openclaw models auth order set             # 设置认证优先级
openclaw models auth order clear           # 清除认证优先级
```

### Agent 管理

```bash
openclaw agents list               # 列出 Agent
openclaw agents list --bindings    # 包含路由绑定
openclaw agents add <name>         # 添加新 Agent
openclaw agents add --workspace <dir>
openclaw agents set-identity       # 更新身份
openclaw agents delete <id>        # 删除 Agent

# 发送消息
openclaw agent -m "消息内容"
openclaw agent -m "hello" --to +86...
openclaw agent -m "test" --agent <id>
openclaw agent -m "think" --thinking high
openclaw agent -m "local" --local  # 本地运行
```

> 多 Agent 路由配置、多 Bot 绑定详见 [multi-agent.md](multi-agent.md)。

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
openclaw config get <path>         # 获取配置值
openclaw config set <path> <value> # 设置配置值
openclaw config unset <path>       # 删除配置值
```

### 浏览器控制

```bash
openclaw browser status            # 浏览器状态
openclaw browser start             # 启动浏览器
openclaw browser stop              # 停止浏览器
openclaw browser tabs              # 列出标签页
openclaw browser screenshot        # 截图
openclaw browser navigate <url>    # 导航到 URL
openclaw browser click             # 点击元素
openclaw browser type              # 输入文本
openclaw browser cookies           # 管理 cookies
openclaw browser storage           # 管理存储
```

### 定时任务

```bash
openclaw cron status               # 定时任务状态
openclaw cron list                 # 列出任务
openclaw cron add                  # 添加任务
openclaw cron enable <id>          # 启用任务
openclaw cron disable <id>         # 禁用任务
openclaw cron delete <id>          # 删除任务
openclaw cron runs                 # 查看运行记录
openclaw cron edit <id>            # 编辑任务
```

### 消息发送

```bash
openclaw message send --target <dest> --message "内容"
openclaw message send --media <file>
openclaw message broadcast         # 群发
openclaw message poll              # 创建投票
openclaw message react             # 添加反应
openclaw message read              # 读取消息
openclaw message edit              # 编辑消息
openclaw message delete            # 删除消息
openclaw message pin               # 置顶消息
openclaw message search            # 搜索消息
```

### 内存/记忆

```bash
openclaw memory status             # 内存索引状态
openclaw memory status --deep      # 探测 embedding
openclaw memory index              # 重建索引
openclaw memory index --force      # 强制重建
openclaw memory search <query>     # 搜索记忆
```

### 插件

```bash
openclaw plugins list              # 列出插件
openclaw plugins list --enabled    # 只显示启用的
openclaw plugins info <id>         # 插件详情
openclaw plugins install <source>  # 安装插件
openclaw plugins enable <id>       # 启用插件
openclaw plugins disable <id>      # 禁用插件
openclaw plugins update            # 更新插件
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
openclaw completion --shell bash           # 生成 bash 补全脚本
openclaw completion --shell fish           # 生成 fish 补全脚本
openclaw completion --shell powershell     # 生成 PowerShell 补全脚本

openclaw completion --install              # 安装补全脚本到 shell 配置
openclaw completion --install --yes        # 跳过确认直接安装
```

### 其他

```bash
openclaw sessions                  # 会话列表
openclaw sessions --active 60      # 最近 60 分钟活跃的

openclaw dashboard                 # 打开控制面板
openclaw dashboard --no-open       # 只打印 URL

openclaw reset                     # 重置配置/状态
openclaw uninstall                 # 卸载

openclaw update                    # 更新 CLI
openclaw update --check            # 检查更新

openclaw --version                 # 版本
openclaw --help                    # 帮助
```

### 高级命令

以下命令主要用于开发和系统集成，一般用户无需使用：

`acp`, `system`, `nodes`, `devices`, `dns`, `docs`, `hooks`, `webhooks`, `directory`, `security`, `tui`, `talk`

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

| 变量 | 用途 | 默认值 |
|------|------|--------|
| `OPENCLAW_DISABLE_BONJOUR` | 禁用 Bonjour/mDNS 广播 | `1` (已启用) |
| `CLAWDBOT_DISABLE_BONJOUR` | 禁用 Bonjour (兼容旧版) | `1` (已启用) |
| `NODE_ENV` | Node.js 环境 | `production` |

### OpenClaw 路径环境变量

| 变量 | 用途 | 默认值 |
|------|------|--------|
| `OPENCLAW_HOME` | 覆盖 home 目录 | `~` |
| `OPENCLAW_STATE_DIR` | 覆盖状态目录 | `~/.openclaw` |
| `OPENCLAW_CONFIG_PATH` | 覆盖配置文件路径 | `~/.openclaw/openclaw.json` |
| `OPENCLAW_LOAD_SHELL_ENV` | 从 login shell 导入环境变量 | 未设置 |
| `OPENCLAW_SHELL_ENV_TIMEOUT_MS` | shell 环境导入超时 | `15000` |

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
