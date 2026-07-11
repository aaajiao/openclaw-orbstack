# 开发指南

## 代码风格

### Bash 脚本

**Shebang 和安全设置**
```bash
#!/bin/bash
set -e  # 遇错即停 (必须)
```

**变量命名**
```bash
# 常量: UPPER_SNAKE_CASE
VM_NAME="openclaw-vm"
TOTAL_STEPS=8

# 局部变量: lower_snake_case
local config_path="$HOME/.openclaw/openclaw.json"
```

**函数命名**
```bash
# 简短工具函数: lowercase
step()  { echo -e "\n${CYAN}[$1/$TOTAL_STEPS] $2${NC}"; }
ok()    { echo -e "${GREEN}  ✓ $1${NC}"; }
err()   { echo -e "${RED}  ✗ $1${NC}"; }

# 复杂函数: snake_case
vm_exec() {
    orb -m "$VM_NAME" bash -lc "$1"
}
```

**Heredocs**
```bash
# 不展开变量 (单引号分隔符)
cat > openclaw.json << 'EOFCONFIG'
{
  "key": "value"
}
EOFCONFIG

# 展开变量 (无引号分隔符)
cat > script.sh << EOF
echo "VM is $VM_NAME"
EOF
```

### JSON 配置

- 2 空格缩进
- JSON5 格式 (允许注释和尾逗号)
- 动态修改用 `jq`，不用 sed

### 文档和国际化

- README.md: 英文
- docs/README.zh-CN.md: 中文
- 代码注释: 英文
- 用户可见文本: 通过 `lang/en.sh` 和 `lang/zh-CN.sh` 国际化 (使用 `$MSG_*` 变量，禁止硬编码)

## 错误处理

```bash
# 检查命令是否存在 (用户可见文本必须用 $MSG_*)
if ! command -v orb &> /dev/null; then
    err "$MSG_ERR_NO_ORBSTACK"
    exit 1
fi

# 允许失败的执行
vm_exec "some_command" || true

# 检查文件/目录是否存在
if vm_exec "test -d ~/openclaw"; then
    # 目录存在
fi
```

## 安装策略

安装脚本 (`openclaw-orbstack-setup.sh`) 和更新脚本 (`scripts/commands/update.sh`) 采用相同的两级策略：

1. **主路径**: `npm install -g openclaw@<version>` — 预编译 npm 包 (快速、可靠)
2. **兜底**: `pnpm install && pnpm build && pnpm ui:build && sudo npm install -g .` — 源码构建 (仅在 npm registry 不可用或包不完整时)

无论安装方式如何，git checkout (`~/openclaw`) 始终保留在目标 tag，因为沙箱 Docker 镜像从 repo 的 Dockerfile 构建。

更新完成后会运行 `openclaw doctor --fix`，确保 systemd service 入口路径与当前安装方式一致，并安装 bundled plugin 依赖。此后 `update.sh` 会轮询 Gateway 是否真正进入 `running` 健康态；启动失败时自动 `openclaw update repair` 自愈一次（补齐缺失的 bundled plugin 目录），仍失败则如实报错。

## 两条更新命令

本 wrapper 提供两条作用在不同层的更新命令，各有独立脚本：

| 命令 | 脚本 | 作用对象 | 触碰 VM？ |
|------|------|----------|-----------|
| `openclaw-update` | `scripts/commands/update.sh` | VM 内的上游 OpenClaw（npm 包 + `~/openclaw` checkout） | 是 |
| `openclaw-selfupdate` | `scripts/commands/selfupdate.sh` | 这个 wrapper 项目（Mac 上的 repo clone + `~/bin/openclaw-*`） | 否 |

`openclaw-selfupdate` 按 release tag 把 repo checkout 成 **detached HEAD**（默认取最新 stable tag，`--pre` 取含 pre-release 的最新 tag，`--version=<tag>` 精确锁定/回滚）。默认与 `--pre` 路径**从不降级**（目标 tag 已是 HEAD 祖先则 no-op）；只有 `--version=` 豁免此规则。

**detached-HEAD 守卫**（两处配合，别拆开改）：

- `refresh-mac-commands.sh` 在 detached HEAD 时**跳过**它自身的静默 `git pull`，因此 `openclaw-selfupdate` 重新生成命令不会撤销刚锁定的 tag。
- `~/bin/openclaw-update` 只在 HEAD 处于**分支**时才 `git pull` 拉取 wrapper 代码；detached HEAD（= 被 selfupdate 锁定）时保持锁定、不 pull、不告警。

把 wrapper 交付完全切到 `openclaw-selfupdate`（移除 `openclaw-update` 里那段 auto-pull）的动作推迟到 v2026.7.1 stable 线——现在的最新 stable tag（v2026.6.11）尚未携带 `openclaw-selfupdate`，提前切会 strand 用户。

## 开发命令

```bash
# 语法检查
bash -n openclaw-orbstack-setup.sh

# Lint 检查
shellcheck openclaw-orbstack-setup.sh

# 执行部署 (跳过语言选择)
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh
```

## 测试变更

```bash
# 仅语法检查
bash -n openclaw-orbstack-setup.sh

# 完整测试 (会创建真实 VM)
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh

# 全新测试
orb delete openclaw-vm
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh
```

## 故障排查

| 症状 | 原因 | 修复 |
|------|------|------|
| `orb: command not found` | 未安装 OrbStack | 从 orbstack.dev 安装 |
| Docker permission denied | 用户不在 docker 组 | `sudo usermod -aG docker $USER` |
| EBUSY on rename | 绑定挂载冲突 | 脚本会设置 `OPENCLAW_STATE_DIR` |
| 容器无法启动 | 配置合并失败 | 检查 `openclaw-logs` |
| 沙箱工具失败 | 镜像错误 | 确认使用 `common` 镜像 |
| 浏览器工具失败 | 浏览器沙箱未构建 | 运行 `openclaw-sandbox-rebuild` |

### 调试模式

```bash
# 详细执行
OPENCLAW_LANG=en bash -x openclaw-orbstack-setup.sh

# 检查 Gateway 状态
orb -m openclaw-vm bash -lc "openclaw gateway status"

# 检查沙箱容器
orb -m openclaw-vm bash -lc "docker ps -a | grep openclaw-sbx"

# 查看沙箱配置
orb -m openclaw-vm bash -lc "cat ~/.openclaw/openclaw.json | jq .agents.defaults.sandbox"
```
