# 故障排查指南

## 常见问题

### 1. Bonjour hostname conflict 警告

#### 症状

日志中持续出现以下警告，数字不断递增：

```
gateway hostname conflict resolved; newHostname="openclaw-(127)"
gateway name conflict resolved; newName="openclaw-vm (128)"
gateway hostname conflict resolved; newHostname="openclaw-(128)"
```

#### 原因

这是 OpenClaw 的 [已知 Bug (Issue #3238)](https://github.com/openclaw/openclaw/issues/3238)。

Gateway 使用 `ciao` 库注册 Bonjour/mDNS 服务时，用了系统的 hostname。但在 OrbStack VM 环境中：

1. macOS 的 mDNSResponder 已经占用了这个主机名
2. ciao 探测时发现"冲突"，递增到 `(2)`
3. 再探测又冲突，递增到 `(3)`
4. **无限循环** → 数字一直增长

#### 解决方案

**方法 1：重新运行部署脚本（推荐）**

最新版本的 `openclaw-orbstack-setup.sh` 已经包含了修复，会自动禁用 Bonjour。

```bash
# 重新运行部署脚本会重新生成 systemd 服务文件
bash openclaw-orbstack-setup.sh
```

**方法 2：手动添加环境变量**

```bash
# 进入 VM
openclaw-shell

# 编辑 .env 文件（Gateway 启动时会读取）
nano ~/.openclaw/.env

# 添加以下两行：
# OPENCLAW_DISABLE_BONJOUR=1
# CLAWDBOT_DISABLE_BONJOUR=1

# 重启 Gateway
openclaw gateway restart
```

> **注意**: 当前版本使用 user-level systemd service (`openclaw-gateway.service`)，
> 由 `openclaw onboard` 自动创建，通过 `systemctl --user` 管理。
> 不再使用旧版的 `/etc/systemd/system/openclaw.service`。

**验证修复**

检查环境变量是否生效：

```bash
openclaw-shell
env | grep -i BONJOUR
```

应该看到：
```
OPENCLAW_DISABLE_BONJOUR=1
CLAWDBOT_DISABLE_BONJOUR=1
```

#### 影响

禁用 Bonjour 后：
- ✅ 冲突警告消失
- ✅ 减少日志膨胀
- ✅ Gateway 正常工作
- ⚠️ 失去本地网络自动发现功能（一般不需要，可通过 `http://openclaw-vm.orb.local:18789` 直接访问）

#### 参考

- [OpenClaw Issue #3238](https://github.com/openclaw/openclaw/issues/3238)
- [官方文档: Bonjour/mDNS](https://docs.openclaw.ai/gateway/bonjour)

---

### 2. Port 18789 is already in use

#### 症状

```
Port 18789 is already in use.
Gateway failed to start: gateway already running (pid XXX); lock timeout after 5000ms
```

#### 原因

- 已有一个 Gateway 进程在运行
- 或者端口被其他程序占用

#### 解决方案

```bash
# 检查什么占用了端口
orb -m openclaw-vm bash -c 'ss -tlnp | grep 18789'

# 如果是旧的 gateway 进程，强制停止并重启
openclaw-stop
orb -m openclaw-vm bash -c 'sudo pkill -9 -f "openclaw"; sudo pkill -9 node; sleep 2'
openclaw-start
```

如果使用 Web UI 时看到这个错误，通常可以忽略 - 这只是说明 systemd 管理的 Gateway 已经在运行。

---

### 3. Gateway already running (使用 Web UI 时)

#### 症状

使用 Web UI 控制台时，日志显示：

```
Gateway failed to start: gateway already running (pid XXX)
Gateway service appears enabled. Stop it first.
```

#### 原因

这是**正常现象**。Web UI 检测到 Gateway 已经由 systemd 管理并运行中，所以不需要再启动。

#### 解决方案

**无需处理** - Gateway 正常工作，Web UI 也能正常使用。这只是信息提示，不是错误。

---

### 4. Memory 目录问题

#### 症状

```
EISDIR: illegal operation on a directory
```

#### 解决方案

```bash
openclaw-shell
mkdir -p ~/.openclaw/memory
chmod 755 ~/.openclaw/memory
exit
openclaw-restart
```

---

### 5. 浏览器沙箱 Chromium 崩溃 ("No usable sandbox!")

#### 症状

浏览器工具无法使用，Gateway 日志中出现：

```
No usable sandbox! If this is a Debian system, please install the chromium-sandbox package to solve this problem.
```

或者浏览器容器启动后立即退出。

#### 原因

OrbStack VM 内核限制 unprivileged user namespaces，Chromium 无法创建自己的命名空间沙箱。需要 `OPENCLAW_BROWSER_NO_SANDBOX=1` 环境变量让 Chromium 以 `--no-sandbox` 模式启动。

**v2026.3.1+**：上游已修复（PR #29879），Gateway 会自动传此变量给浏览器容器，升级即可解决。

#### 解决方案

升级到 v2026.3.1+：

```bash
openclaw-update
```

---

### 6. Memory Search 无法使用 / 索引为空

#### 症状

运行 `openclaw memory status --deep` 显示：

```
No API key found for provider "openai"
No API key found for provider "google"
```

或者显示 `Indexed: 0/N files`，索引文件是空的。

#### 原因

Memory Search 功能需要 **embedding API** 来生成向量索引，但没有配置对应的 API key。

OpenClaw 的 memory 系统有两层：

| 目录 | 用途 |
|------|------|
| `~/.openclaw/workspace/memory/*.md` | 原始记忆文件（Markdown，AI 写入） |
| `~/.openclaw/memory/*.sqlite` | 向量索引（需要 embedding API 生成） |

安装脚本只创建了空目录，**没有配置 embedding provider**。

#### 解决方案

**步骤 1：为 agent 添加 OpenAI API key**

```bash
openclaw-shell

# 编辑 auth 文件
nano ~/.openclaw/agents/main/agent/auth-profiles.json
```

在 `profiles` 里添加 OpenAI（注意要放在 `profiles: {}` **内部**）：

```json
{
  "version": 1,
  "profiles": {
    "现有的配置...": {},
    "openai:default": {
      "type": "api_key",
      "provider": "openai",
      "key": "sk-你的OpenAI-API-Key"
    }
  },
  "lastGood": {
    "openai": "openai:default"
  }
}
```

**步骤 2：验证配置**

```bash
openclaw memory status --deep
```

应该显示 `Provider: openai` 而不是报错。

**步骤 3：构建索引**

```bash
openclaw memory index
```

⚠️ **注意**：默认使用 OpenAI Batch API（便宜 50% 但较慢），可能需要几分钟。

如果想要实时索引（快但贵），编辑配置：

```bash
openclaw-config edit
```

添加：

```json5
agents: {
  defaults: {
    memorySearch: {
      remote: {
        batch: { enabled: false }
      }
    }
  }
}
```

**步骤 4：验证索引完成**

```bash
openclaw memory status --deep
# 应显示 Indexed: N/N files · M chunks
# Dirty: no
```

#### 替代方案：使用本地 embedding（免费，无需 API）

如果不想用 OpenAI API，可以配置本地模型：

```json5
agents: {
  defaults: {
    memorySearch: {
      provider: "local"
    }
  }
}
```

OpenClaw 会自动下载本地 embedding 模型。

---

### 7. 服务状态检查

#### 常用诊断命令

```bash
# 查看服务状态
openclaw-status

# 查看实时日志
openclaw-logs

# 运行官方诊断
openclaw doctor

# 进入 VM 排查
openclaw-shell

# 查看进程
orb -m openclaw-vm bash -c 'ps aux | grep openclaw'

# 查看端口占用
orb -m openclaw-vm bash -c 'ss -tlnp | grep 18789'

# 查看 systemd 服务状态
orb -m openclaw-vm bash -c 'systemctl --user status openclaw-gateway'
```

---

## 重启服务

### 正常重启

```bash
openclaw-restart
```

### 强制重启（杀死所有进程）

```bash
openclaw-stop
orb -m openclaw-vm bash -c 'sudo pkill -9 -f "openclaw"; sudo pkill -9 node; sleep 2'
openclaw-start
```

---

## 完全重置

如果遇到无法解决的问题，可以删除 VM 重新部署：

```bash
# 删除 VM（会丢失所有数据！）
orb delete openclaw-vm

# 重新运行部署脚本
bash openclaw-orbstack-setup.sh
```

⚠️ **注意**：这会丢失所有会话数据和配置，需要重新配对 WhatsApp/Telegram。

---

## 获取帮助

1. 查看日志：`openclaw-logs`
2. 运行诊断：`openclaw doctor`
3. 查看 [官方文档](https://docs.openclaw.ai/gateway/troubleshooting)
4. 搜索 [GitHub Issues](https://github.com/openclaw/openclaw/issues)
