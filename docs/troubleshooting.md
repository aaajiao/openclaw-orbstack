# 故障排查指南

> 🌐 This guide is currently Chinese-only. English essentials are covered in the [README](../README.md); the upstream OpenClaw docs at https://docs.openclaw.ai are fully in English.

本文档只覆盖 **OrbStack 架构特有的问题**。通用配置、频道、模型等问题请查看 [官方故障排查文档](https://docs.openclaw.ai/gateway/troubleshooting)。

## OrbStack 特有问题

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
bash openclaw-orbstack-setup.sh
```

**方法 2：手动添加环境变量**

```bash
openclaw-shell
nano ~/.openclaw/.env
# 添加: OPENCLAW_DISABLE_BONJOUR=1
openclaw gateway restart
```

#### 影响

禁用 Bonjour 后：
- 冲突警告消失，日志恢复正常
- 失去本地网络自动发现功能（可通过 `http://openclaw-vm.orb.local:18789` 直接访问）

---

### 2. Port 18789 is already in use

#### 症状

```
Port 18789 is already in use.
Gateway failed to start: gateway already running (pid XXX); lock timeout after 5000ms
```

#### 解决方案

**v2026.4.5+**：Gateway 会自动检测 PID recycling 和 stale lock 文件，大多数情况下重启即可恢复：

```bash
openclaw-restart
```

如果自动恢复失败，手动清理：

```bash
# 检查什么占用了端口
orb -m openclaw-vm bash -c 'ss -tlnp | grep 18789'

# 强制停止并重启
openclaw gateway stop
orb -m openclaw-vm bash -c 'sudo pkill -9 -f "openclaw"; sudo pkill -9 node; sleep 2'
openclaw gateway start
```

如果使用 Web UI 时看到这个错误，通常可以忽略 — 这只是说明 systemd 管理的 Gateway 已经在运行。

---

### 3. 浏览器沙箱 Chromium 崩溃 ("No usable sandbox!")

#### 症状

```
No usable sandbox! If this is a Debian system, please install the chromium-sandbox package to solve this problem.
```

#### 原因

OrbStack VM 内核限制 unprivileged user namespaces，Chromium 无法创建命名空间沙箱。

**v2026.3.1+** 已修复：Gateway 会自动传 `OPENCLAW_BROWSER_NO_SANDBOX=1` 给浏览器容器。

#### 解决方案

```bash
openclaw-update
```

---

### 4. Memory 目录问题

#### 症状

```
EISDIR: illegal operation on a directory
```

#### 解决方案

```bash
openclaw-shell
mkdir -p ~/.openclaw/memory && chmod 755 ~/.openclaw/memory
exit
openclaw-restart
```

---

## 换 API key / 改 .env 不生效

#### 症状

修改了 VM 里 `~/.openclaw/.env` 中**已有的值**（比如换新的 API key），重启 Gateway 后仍在用旧值（例如持续 401），而新 key 单独用 curl 验证明明是好的。

> **新增**变量不受此影响（比如上文 Bonjour 一节加 `OPENCLAW_DISABLE_BONJOUR=1`），改完 restart 即生效；只有**修改已有值**会踩这个坑。

#### 根因

systemd 服务通过 `EnvironmentFile=` 加载 `~/.openclaw/gateway.systemd.env`。这个文件是 `openclaw gateway install` / `openclaw doctor` 运行时从 `.env` 生成的**快照**，之后不会自动跟随 `.env` 变化。快照里的旧值以进程环境变量的身份注入，而 OpenClaw 的环境变量优先级是「进程环境最高、绝不覆盖」（见[官方环境变量文档](https://docs.openclaw.ai/help/environment)），所以 `.env` 里的新值永远赢不了快照里的旧值。

#### 解决方案

三条命令，**顺序敏感**：

```bash
openclaw-shell
openclaw gateway install --force                  # 重新生成服务定义 + gateway.systemd.env 快照
openclaw gateway restart                          # Gateway 进程加载新 env
openclaw sandbox recreate --agent main --force    # 沙箱容器的 env 是创建时烘焙的，必须重建
```

第三步仅在被换的 key 也配置在 `agents.defaults.sandbox.docker.env` 里时需要（AI 提供商的 key 基本都是）。顺序不能反：沙箱容器创建时从 Gateway 进程环境解析 `${VAR}` 引用，Gateway 没先重启就 recreate 会把旧 key 又烘进新容器。`/workspace` 是持久卷，recreate 不会丢数据。

#### 验证

```bash
grep <KEY名> ~/.openclaw/gateway.systemd.env    # 快照已含新值
docker ps --format '{{.Names}}'                 # 找到 sandbox 容器名
docker exec <容器名> env | grep <KEY名>          # 容器已拿到新值
```

---

## 诊断命令

```bash
openclaw-status                    # 查看服务状态
openclaw-logs                      # 实时日志
openclaw doctor                    # 健康检查 + 自动修复
openclaw-shell                     # 进入 VM 排查
```

---

## 重启服务

```bash
# 正常重启
openclaw-restart

# 强制重启（杀死所有进程）
openclaw gateway stop
orb -m openclaw-vm bash -c 'sudo pkill -9 -f "openclaw"; sudo pkill -9 node; sleep 2'
openclaw gateway start
```

---

## 完全卸载

```bash
# 交互式卸载 (逐步确认，可选删除 VM)
openclaw-uninstall

# 自动卸载 (跳过确认，保留 VM)
openclaw-uninstall --yes

# 自动卸载 + 删除 VM
openclaw-uninstall --yes --vm
```

如需重新部署：
```bash
bash openclaw-orbstack-setup.sh
```

---

## VM 备份和恢复

```bash
# 导出（备份）
orb export openclaw-vm ~/Desktop/openclaw-vm-backup.tar.zst

# 导入（恢复）
orb delete openclaw-vm
orb import -n openclaw-vm ~/Desktop/openclaw-vm-backup.tar.zst
```

> **注意**：`~/OrbStack/openclaw-vm/` 只是 VM 文件系统的挂载视图，不是本地副本。删除 VM 后该目录会消失。

---

## 获取帮助

1. 查看日志：`openclaw-logs`
2. 运行诊断：`openclaw doctor`
3. 查看 [官方故障排查文档](https://docs.openclaw.ai/gateway/troubleshooting)
4. 搜索 [GitHub Issues](https://github.com/openclaw/openclaw/issues)
