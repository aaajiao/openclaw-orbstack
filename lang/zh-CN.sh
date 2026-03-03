#!/bin/bash
# shellcheck disable=SC2034
# All variables are used externally via `source` in other scripts
# ============================================================================
# OpenClaw 中文语言包
# ============================================================================

# --- Step Titles ---
MSG_STEP_1="检查 OrbStack"
MSG_STEP_2="创建 Ubuntu VM"
MSG_STEP_3="安装 Docker"
MSG_STEP_4="安装 Node.js"
MSG_STEP_5="克隆并构建 OpenClaw"
MSG_STEP_6="构建沙箱镜像"
MSG_STEP_7="运行配置向导"
MSG_STEP_8="配置服务与便捷命令"

# --- Step 1: OrbStack ---
MSG_ERR_NO_ORBSTACK="未检测到 OrbStack"
MSG_INSTALL_ORBSTACK_1="请先安装："
MSG_INSTALL_ORBSTACK_2="  1. 访问 https://orbstack.dev 下载安装"
MSG_INSTALL_ORBSTACK_3="  2. 启动 OrbStack 完成初始化"
MSG_INSTALL_ORBSTACK_4="  3. 重新运行此脚本"
MSG_OK_ORBSTACK="OrbStack 已安装"

# --- Step 2: VM ---
MSG_OK_VM_EXISTS="虚拟机 '%s' 已存在"
MSG_INFO_STARTING_VM="启动虚拟机..."
MSG_INFO_CREATING_VM="创建虚拟机: %s (%s)"
MSG_OK_VM_READY="虚拟机已就绪"

# --- Step 3: Docker ---
MSG_OK_DOCKER_INSTALLED="Docker 已安装"
MSG_INFO_INSTALLING_DOCKER="安装 Docker Engine..."
MSG_OK_DOCKER_STARTED="Docker 服务已启动"

# --- Step 4: Node.js ---
MSG_OK_NODE_INSTALLED="Node.js 已安装"
MSG_INFO_NODE_UPGRADE="Node.js %s 版本过低，升级到 22.x..."
MSG_OK_NODE_UPGRADED="Node.js 已升级"
MSG_INFO_INSTALLING_NODE="安装 Node.js 22.x..."
MSG_OK_PNPM_INSTALLED="pnpm 已安装"
MSG_INFO_INSTALLING_PNPM="安装 pnpm..."

# --- Step 5: Build ---
MSG_INFO_REPO_EXISTS="仓库已存在，拉取最新代码..."
MSG_INFO_CLONING="克隆仓库..."
MSG_INFO_NPM_INSTALL="安装依赖 (pnpm install)..."
MSG_INFO_NPM_BUILD="编译项目 (pnpm build)..."
MSG_INFO_UI_BUILD="构建 Control UI..."
MSG_INFO_GLOBAL_INSTALL="全局安装 CLI..."
MSG_INFO_CHECKOUT_RELEASE="切换到最新发布版本: %s ..."
MSG_OK_BUILD_DONE="OpenClaw 构建完成 (CLI: openclaw)"
MSG_ERR_NO_VERSION="未找到稳定发布标签，请检查网络或上游仓库。"

# --- Step 6: Sandbox ---
MSG_INFO_SANDBOX_BASE="构建基础沙箱镜像 (sandbox-common 的构建依赖)..."
MSG_OK_SANDBOX_BASE="sandbox 基础镜像构建完成"
MSG_OK_SANDBOX_BASE_DF="sandbox 基础镜像构建完成 (Dockerfile)"
MSG_WARN_SANDBOX_BASE_FAIL="sandbox 基础镜像构建失败，sandbox-common 可能也会失败"
MSG_INFO_SANDBOX_BROWSER="构建浏览器沙箱镜像..."
MSG_OK_SANDBOX_BROWSER="sandbox-browser 镜像构建完成"
MSG_OK_SANDBOX_BROWSER_DF="sandbox-browser 镜像构建完成 (Dockerfile)"
MSG_WARN_SANDBOX_BROWSER_FAIL="sandbox-browser 镜像构建失败，跳过"
MSG_INFO_SANDBOX_COMMON="构建 common 沙箱镜像 (基于基础镜像，加装开发工具)..."
MSG_OK_SANDBOX_COMMON="sandbox-common 镜像构建完成"
MSG_WARN_SANDBOX_COMMON_FAIL="sandbox-common 镜像构建失败 (需要基础镜像先构建成功)"

# --- Step 7: Onboard ---
MSG_INFO_ONBOARD_INTRO="接下来进入交互式配置向导，请准备："
MSG_INFO_ONBOARD_API="  - AI 模型 API Key（支持 Anthropic / OpenAI / Google / OpenRouter / DeepSeek 等）"
MSG_INFO_ONBOARD_TOKEN="  - 聊天平台凭据（Telegram / WhatsApp / Discord / Slack 等）"
MSG_PRESS_ENTER="按 Enter 继续..."
MSG_OK_ONBOARD_DONE="配置向导完成"
MSG_INFO_EXTRACTING_ENV="提取敏感信息到 .env 文件..."
MSG_OK_ENV_EXTRACTED="敏感信息已提取到 ~/.openclaw/.env"
MSG_INFO_CREATING_MEMORY="创建 memory 索引目录..."
MSG_OK_MEMORY_CREATED="memory 索引目录已创建"

# --- Step 8: Service & Commands ---
MSG_INFO_CREATING_SERVICE="创建 systemd 服务..."
MSG_OK_GATEWAY_STARTED="Gateway 服务已启动"
MSG_WARN_GATEWAY_ISSUE="Gateway 服务启动可能有问题，请检查: openclaw-logs"
MSG_OK_COMMANDS_CREATED="便捷命令已创建"
MSG_INFO_SANDBOX_CONFIG="写入沙箱配置..."
MSG_OK_SANDBOX_CONFIG="沙箱配置已写入"
MSG_INFO_PATH_ADDED="已添加 ~/bin 到 PATH (%s)"

# --- Mac Command Embedded Text ---
# openclaw-config
MSG_CMD_CONFIG_OPENING="正在打开配置编辑器..."
MSG_CMD_CONFIG_SAVED="配置已保存。运行 openclaw-restart 使更改生效。"
MSG_CMD_CONFIG_BACKED_UP="已备份到: %s"
MSG_CMD_CONFIG_USAGE="用法: openclaw-config [edit|show|backup]"

# openclaw-update
MSG_CMD_UPDATE_USAGE="用法: openclaw-update [--sandbox] [--force]"
MSG_CMD_UPDATE_DESC="更新 OpenClaw 应用到最新版本。"
MSG_CMD_UPDATE_OPTIONS="选项:"
MSG_CMD_UPDATE_SANDBOX_OPT="  --sandbox    同时重建沙箱 Docker 镜像"
MSG_CMD_UPDATE_FORCE_OPT="  --force      即使已是最新版本也强制重新构建"
MSG_CMD_UPDATE_ALREADY_CURRENT="✅ 已是最新版本，无需更新。\n💡 如需强制重建: openclaw-update --force"
MSG_CMD_UPDATE_TIP="提示: 单独重建沙箱可用 openclaw-sandbox-rebuild"
MSG_CMD_UPDATE_UPDATING="🔄 正在更新 OpenClaw..."
MSG_CMD_UPDATE_STOPPING="  停止服务..."
MSG_CMD_UPDATE_PULLING="  拉取最新代码..."
MSG_CMD_UPDATE_INSTALLING="  安装依赖..."
MSG_CMD_UPDATE_BUILDING="  编译项目..."
MSG_CMD_UPDATE_UI="  构建 Control UI..."
MSG_CMD_UPDATE_REINSTALL="  重新安装 CLI..."
MSG_CMD_UPDATE_SANDBOX_REBUILD="  重建沙箱镜像..."
MSG_CMD_UPDATE_SANDBOX_CHANGED="  📦 检测到沙箱构建文件变化，自动重建镜像..."
MSG_CMD_UPDATE_SANDBOX_BASE="    构建基础镜像..."
MSG_CMD_UPDATE_SANDBOX_COMMON="    构建 common 镜像..."
MSG_CMD_UPDATE_SANDBOX_BROWSER="    构建浏览器镜像..."
MSG_CMD_UPDATE_SANDBOX_NOTE="  💡 已运行的容器仍使用旧镜像，重启后生效"
MSG_CMD_UPDATE_STARTING="  启动服务..."
MSG_CMD_UPDATE_DONE="✅ 更新完成！"
MSG_CMD_UPDATE_SANDBOX_HINT="💡 如需重建沙箱镜像: openclaw-update --sandbox"
MSG_CMD_UPDATE_NPM_REINSTALL="npm 缺失，正在重新安装 Node.js 软件包..."
MSG_CMD_UPDATE_RECOVER="  ⚠ 构建失败，正在使用上一版本重启服务..."
MSG_CMD_UPDATE_SANDBOX_COMMON_FAIL="    ✗ common 镜像构建失败"
MSG_CMD_UPDATE_SANDBOX_BROWSER_FAIL="    ✗ 浏览器镜像构建失败"
MSG_CMD_UPDATE_SANDBOX_PARTIAL="  ⚠ 部分沙箱镜像构建失败，下次更新将重试。"
MSG_CMD_UPDATE_PULL_WARN="  ⚠ 更新 openclaw-orbstack 仓库失败，使用缓存版本"

# openclaw-sandbox-rebuild
MSG_CMD_REBUILD_START="🔨 正在重建沙箱 Docker 镜像..."
MSG_CMD_REBUILD_BASE="  构建基础沙箱镜像..."
MSG_CMD_REBUILD_BASE_OK="  ✓ sandbox 基础镜像构建完成"
MSG_CMD_REBUILD_BASE_OK_DF="  ✓ sandbox 基础镜像构建完成 (Dockerfile)"
MSG_CMD_REBUILD_BASE_FAIL="  ✗ sandbox 基础镜像构建失败（sandbox-common 可能也会失败）"
MSG_CMD_REBUILD_COMMON="  构建 common 沙箱镜像..."
MSG_CMD_REBUILD_COMMON_OK="  ✓ sandbox-common 镜像构建完成"
MSG_CMD_REBUILD_COMMON_FAIL="  ✗ sandbox-common 镜像构建失败"
MSG_CMD_REBUILD_BROWSER="  构建浏览器沙箱镜像..."
MSG_CMD_REBUILD_BROWSER_OK="  ✓ sandbox-browser 镜像构建完成"
MSG_CMD_REBUILD_BROWSER_OK_DF="  ✓ sandbox-browser 镜像构建完成 (Dockerfile)"
MSG_CMD_REBUILD_BROWSER_FAIL="  ✗ sandbox-browser 镜像构建失败"
MSG_CMD_REBUILD_DONE="✅ 沙箱镜像重建完成！"
MSG_CMD_REBUILD_NOTE="💡 已运行的容器仍使用旧镜像，运行 openclaw-restart 使新镜像生效"
MSG_CMD_REBUILD_PARTIAL="  ⚠ 部分镜像构建失败，未保存哈希，下次更新将重试。"

# openclaw-telegram
MSG_CMD_TG_ADD_USAGE="用法: openclaw-telegram add <bot_token>"
MSG_CMD_TG_ADD_HINT="从 @BotFather 获取 token"
MSG_CMD_TG_APPROVE_USAGE="用法: openclaw-telegram approve <pairing_code>"
MSG_CMD_TG_APPROVE_HINT="输入 Bot 发给你的配对码"
MSG_CMD_TG_TITLE="Telegram Bot 管理"
MSG_CMD_TG_USAGE="用法:"
MSG_CMD_TG_ADD_DESC="  openclaw-telegram add <bot_token>      添加 Bot (从 @BotFather 获取)"
MSG_CMD_TG_APPROVE_DESC="  openclaw-telegram approve <code>       批准配对 (回执验证码)"
MSG_CMD_TG_ALT="或直接使用:"
MSG_CMD_TG_ALT_CMD="  openclaw channels login --channel telegram"


# --- Completion Output ---
MSG_FINAL_COMPLETE="部署完成！"
MSG_FINAL_ARCH="架构:"
MSG_FINAL_ARCH_DETAIL_1="  Mac → OrbStack → Ubuntu VM"
MSG_FINAL_ARCH_DETAIL_2="                   ├── Gateway (systemd 服务)"
MSG_FINAL_ARCH_DETAIL_3="                   └── Docker (沙箱容器)"
MSG_FINAL_ACCESS="访问地址"
MSG_FINAL_MAC_COMMANDS="Mac 端命令:"
MSG_FINAL_CMD_CLI="CLI 入口 (透传所有参数)"
MSG_FINAL_CMD_CONFIG="编辑配置"
MSG_FINAL_CMD_STATUS="服务状态"
MSG_FINAL_CMD_LOGS="实时日志"
MSG_FINAL_CMD_RESTART="重启服务"
MSG_FINAL_CMD_UPDATE="更新版本 (仅应用，--sandbox 重建镜像)"
MSG_FINAL_CMD_REBUILD="重建沙箱镜像"
MSG_FINAL_CMD_DOCTOR="运行诊断"
MSG_FINAL_CMD_SHELL="进入 VM"
MSG_FINAL_SANDBOX_TITLE="沙箱容器 (由 Gateway 按需创建):"
MSG_FINAL_SANDBOX_COMMON="  - openclaw-sandbox-common   代码执行 (bridge 网络)"
MSG_FINAL_SANDBOX_BROWSER="  - openclaw-sandbox-browser  浏览器自动化"
MSG_FINAL_NEXT_STEPS="后续步骤:"
MSG_FINAL_NEXT_CONFIGURE_DESC="重新运行配置向导"
MSG_FINAL_NEXT_DASHBOARD_DESC="打开 Web 控制面板"
MSG_FINAL_NEXT_CHANNELS_DESC="查看已连接的渠道"
MSG_FINAL_NEXT_DOCS="  文档: https://docs.openclaw.ai/start/getting-started"

# --- refresh-mac-commands.sh ---
MSG_REFRESH_START="🔄 正在重新生成 Mac 端便捷命令..."
MSG_REFRESH_DONE="✅ Mac 端便捷命令已更新！"
MSG_REFRESH_LIST_HEADER="已生成以下命令:"
MSG_REFRESH_CMD_CLI="  openclaw                CLI 透传"
MSG_REFRESH_CMD_STATUS="  openclaw-status         服务状态"
MSG_REFRESH_CMD_LOGS="  openclaw-logs           实时日志"
MSG_REFRESH_CMD_RESTART="  openclaw-restart        重启服务"
MSG_REFRESH_CMD_STARTSTOP="  openclaw-stop/start     停止/启动"
MSG_REFRESH_CMD_SHELL="  openclaw-shell          进入 VM"
MSG_REFRESH_CMD_CONFIG="  openclaw-config         配置管理"
MSG_REFRESH_CMD_UPDATE="  openclaw-update         更新版本"
MSG_REFRESH_CMD_REBUILD="  openclaw-sandbox-rebuild 重建沙箱镜像"
MSG_REFRESH_CMD_DOCTOR="  openclaw-doctor         运行诊断"
MSG_REFRESH_CMD_TELEGRAM="  openclaw-telegram       Telegram 管理"
MSG_REFRESH_CMD_WHATSAPP="  openclaw-whatsapp       WhatsApp 登录"
MSG_REFRESH_PATH_HINT="确保 ~/bin 在 PATH 中: export PATH=\"\$HOME/bin:\$PATH\""

# --- openclaw-update auto-repair ---
MSG_UPDATE_AUTO_UPGRADE="🔧 检测到旧版服务配置，正在自动修复..."
MSG_UPDATE_AUTO_UPGRADE_DONE="✓ 服务配置已修复，继续更新..."
MSG_UPDATE_ENV_CREATED="✓ 已创建 ~/.openclaw/.env（Bonjour 配置）"
