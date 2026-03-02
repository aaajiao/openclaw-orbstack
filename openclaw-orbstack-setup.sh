#!/bin/bash
# ============================================================================
# OpenClaw OrbStack One-Click Deployment (Local Install)
#
# Architecture: Gateway runs directly on VM, sandboxes in Docker containers
#
#   Mac
#   └── OrbStack
#       └── Ubuntu VM (openclaw-vm)
#           ├── Gateway process (Node.js, managed by systemd)
#           └── Docker
#               ├── sandbox-common container
#               └── sandbox-browser container
#
# Run in Mac terminal:
#   bash openclaw-orbstack-setup.sh
#
# Prerequisites:
#   - macOS 12.3+
#   - OrbStack installed (https://orbstack.dev)
#
# Language:
#   Interactive selection at startup. Skip prompt with:
#     OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh
#     OPENCLAW_LANG=zh-CN bash openclaw-orbstack-setup.sh
#
# Steps (8 total):
#   1. Check OrbStack
#   2. Create Ubuntu VM
#   3. Install Docker Engine (for sandboxes)
#   4. Install Node.js 22.x LTS
#   5. Clone & build OpenClaw
#   6. Build sandbox images
#   7. Run configuration wizard
#   8. Configure systemd service + Mac commands
#
# ============================================================================

set -e

# --- Language Selection ---
# Resolve project root reliably
_SELF="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$_SELF")" && pwd)"

select_language() {
    # If explicitly set via env var, skip interactive prompt
    if [ -n "$OPENCLAW_LANG" ]; then
        echo "$OPENCLAW_LANG"
        return
    fi

    echo "" >&2
    echo "Choose language / 选择语言:" >&2
    echo "" >&2
    echo "  1) English" >&2
    echo "  2) 中文" >&2
    echo "" >&2
    while true; do
        read -rp "Enter 1 or 2 / 输入 1 或 2: " choice
        case "$choice" in
            1) echo "en"; return ;;
            2) echo "zh-CN"; return ;;
            *) echo "  Invalid choice / 无效选择, please enter 1 or 2 / 请输入 1 或 2" >&2 ;;
        esac
    done
}

OPENCLAW_LANG_CODE=$(select_language)
LANG_FILE="$SCRIPT_DIR/lang/${OPENCLAW_LANG_CODE}.sh"

if [ -f "$LANG_FILE" ]; then
    # shellcheck source=lang/en.sh
    source "$LANG_FILE"
else
    echo "Warning: Language file $LANG_FILE not found, falling back to English"
    source "$SCRIPT_DIR/lang/en.sh"
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Configuration (override via environment variables) ---
VM_NAME="${OPENCLAW_VM_NAME:-openclaw-vm}"
VM_DISTRO="${OPENCLAW_VM_DISTRO:-ubuntu}"
GATEWAY_PORT="${OPENCLAW_PORT:-18789}"
TOTAL_STEPS=8

# --- Output Functions ---
step()    { echo -e "\n${CYAN}[$1/$TOTAL_STEPS] $2${NC}"; }
ok()      { echo -e "${GREEN}  ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠ $1${NC}"; }
err()     { echo -e "${RED}  ✗ $1${NC}"; }
info()    { echo -e "  $1"; }

# --- VM Command Execution ---
vm_exec() {
    orb -m "$VM_NAME" bash -lc "$1"
}

# ============================================================================
# Step 1/8
# ============================================================================
step 1 "$MSG_STEP_1"

if ! command -v orb &> /dev/null; then
    err "$MSG_ERR_NO_ORBSTACK"
    echo ""
    echo "$MSG_INSTALL_ORBSTACK_1"
    echo "$MSG_INSTALL_ORBSTACK_2"
    echo "$MSG_INSTALL_ORBSTACK_3"
    echo "$MSG_INSTALL_ORBSTACK_4"
    exit 1
fi

ok "$MSG_OK_ORBSTACK: $(orb version 2>/dev/null || echo 'unknown')"

# ============================================================================
# Step 2/8
# ============================================================================
step 2 "$MSG_STEP_2"

if orb list 2>/dev/null | grep -qF "$VM_NAME"; then
    ok "$(printf "$MSG_OK_VM_EXISTS" "$VM_NAME")"
    if ! orb list 2>/dev/null | grep -F "$VM_NAME" | grep -q "running"; then
        info "$MSG_INFO_STARTING_VM"
        orb start "$VM_NAME"
    fi
else
    info "$(printf "$MSG_INFO_CREATING_VM" "$VM_NAME" "$VM_DISTRO")"
    orb create "$VM_DISTRO" "$VM_NAME"
fi

# Wait for VM to be ready (up to 30s)
for _ in $(seq 1 30); do
    if vm_exec "true" 2>/dev/null; then break; fi
    sleep 1
done
ok "$MSG_OK_VM_READY"

# ============================================================================
# Step 3/8
# ============================================================================
step 3 "$MSG_STEP_3"

if vm_exec "command -v docker &> /dev/null"; then
    ok "$MSG_OK_DOCKER_INSTALLED: $(vm_exec 'docker --version' 2>/dev/null)"
else
    info "$MSG_INFO_INSTALLING_DOCKER"
    vm_exec "curl -fsSL https://get.docker.com | sh"
    vm_exec "sudo usermod -aG docker \$USER"
fi

if ! vm_exec "sudo systemctl enable docker && sudo systemctl start docker"; then
    warn "Docker service setup had issues, attempting to continue..."
fi
ok "$MSG_OK_DOCKER_STARTED"

# ============================================================================
# Step 4/8
# ============================================================================
step 4 "$MSG_STEP_4"

REQUIRED_NODE_MAJOR=22

if vm_exec "command -v node &> /dev/null"; then
    NODE_VERSION=$(vm_exec 'node --version' 2>/dev/null)
    NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')
    if [ "$NODE_MAJOR" -ge "$REQUIRED_NODE_MAJOR" ]; then
        ok "$MSG_OK_NODE_INSTALLED: $NODE_VERSION"
    else
        info "$(printf "$MSG_INFO_NODE_UPGRADE" "$NODE_VERSION")"
        vm_exec "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
        vm_exec "sudo apt-get install -y nodejs"
        ok "$MSG_OK_NODE_UPGRADED: $(vm_exec 'node --version')"
    fi
else
    info "$MSG_INFO_INSTALLING_NODE"
    vm_exec "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
    vm_exec "sudo apt-get install -y nodejs"
    ok "$MSG_OK_NODE_INSTALLED: $(vm_exec 'node --version')"
fi

# Build tools
if ! vm_exec "sudo apt-get install -y build-essential git"; then
    warn "build-essential install had issues, attempting to continue..."
fi

# pnpm via Corepack (Node.js 22+ built-in, auto-downloads version from packageManager field)
info "$MSG_INFO_INSTALLING_PNPM"
vm_exec "corepack enable"
ok "$MSG_OK_PNPM_INSTALLED: $(vm_exec 'pnpm --version')"

# --- Pre-flight: disk space check (need ~5GB for clone + build + Docker images) ---
AVAIL_MB=$(vm_exec "df -m /home 2>/dev/null | awk 'NR==2{print \$4}'" 2>/dev/null || echo "0")
if [ "$AVAIL_MB" -lt 5000 ] 2>/dev/null; then
    warn "Low disk space in VM: ${AVAIL_MB}MB available, recommend at least 5000MB"
fi

# ============================================================================
# Step 5/8
# ============================================================================
step 5 "$MSG_STEP_5"

if vm_exec "test -d ~/openclaw"; then
    info "$MSG_INFO_REPO_EXISTS"
    vm_exec "cd ~/openclaw && git fetch --tags"
else
    info "$MSG_INFO_CLONING"
    vm_exec "git clone https://github.com/openclaw/openclaw.git ~/openclaw"
fi

# Get latest release tag from openclaw/openclaw repo
OPENCLAW_VERSION=$(vm_exec "cd ~/openclaw && git describe --tags \$(git rev-list --tags --max-count=1)")
info "$(printf "$MSG_INFO_CHECKOUT_RELEASE" "$OPENCLAW_VERSION")"
vm_exec "cd ~/openclaw && git checkout '$OPENCLAW_VERSION'"

info "$MSG_INFO_NPM_INSTALL"
vm_exec "cd ~/openclaw && pnpm install"

info "$MSG_INFO_NPM_BUILD"
vm_exec "cd ~/openclaw && pnpm build"

info "$MSG_INFO_UI_BUILD"
vm_exec "cd ~/openclaw && pnpm ui:build"

info "$MSG_INFO_GLOBAL_INSTALL"
vm_exec "cd ~/openclaw && sudo npm install -g ."

ok "$MSG_OK_BUILD_DONE"

# ============================================================================
# Step 6/8
# ============================================================================
step 6 "$MSG_STEP_6"

info "$MSG_INFO_SANDBOX_BASE"
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null; then
    ok "$MSG_OK_SANDBOX_BASE"
elif vm_exec "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox:bookworm-slim -f Dockerfile.sandbox .'" 2>/dev/null; then
    ok "$MSG_OK_SANDBOX_BASE_DF"
else
    warn "$MSG_WARN_SANDBOX_BASE_FAIL"
fi

info "$MSG_INFO_SANDBOX_BROWSER"
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null; then
    ok "$MSG_OK_SANDBOX_BROWSER"
elif vm_exec "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox-browser:bookworm-slim -f Dockerfile.sandbox-browser .'" 2>/dev/null; then
    ok "$MSG_OK_SANDBOX_BROWSER_DF"
else
    warn "$MSG_WARN_SANDBOX_BROWSER_FAIL"
fi

info "$MSG_INFO_SANDBOX_COMMON"
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null; then
    ok "$MSG_OK_SANDBOX_COMMON"
else
    warn "$MSG_WARN_SANDBOX_COMMON_FAIL"
fi

# Save sandbox build hash for staleness detection during updates
vm_exec "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1 > ~/.openclaw/.sandbox-build-hash"

# ============================================================================
# Step 7/8
# ============================================================================
step 7 "$MSG_STEP_7"

echo ""
info "$MSG_INFO_ONBOARD_INTRO"
info "$MSG_INFO_ONBOARD_API"
info "$MSG_INFO_ONBOARD_TOKEN"
echo ""
echo -e "${YELLOW}$MSG_PRESS_ENTER${NC}"
read -r

vm_exec "mkdir -p ~/.openclaw ~/.openclaw/identity"

orb -m "$VM_NAME" openclaw onboard

ok "$MSG_OK_ONBOARD_DONE"

# --- Extract secrets from config into .env ---
info "$MSG_INFO_EXTRACTING_ENV"

# shellcheck disable=SC1012,SC1083
vm_exec 'python3 << "PYEOF"
import json, os, re

def strip_json5(text):
    """Strip JSON5 features (comments, trailing commas) for json.load()."""
    # Remove single-line comments (// ...)
    text = re.sub(r"(?<!:)//.*$", "", text, flags=re.MULTILINE)
    # Remove multi-line comments (/* ... */)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    # Remove trailing commas before } or ]
    text = re.sub(r",\s*([}\]])", r"\1", text)
    return text

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
env_path = os.path.expanduser("~/.openclaw/.env")

if not os.path.exists(config_path):
    print("config not found, skipping .env extraction")
    exit(0)

with open(config_path, "r") as f:
    config = json.loads(strip_json5(f.read()))

# --- Path-to-env-var mapping for known sensitive fields ---
SENSITIVE_PATHS = [
    ("channels.telegram.botToken",                         "TG_BOT_TOKEN"),
    ("channels.discord.token",                             "DISCORD_TOKEN"),
    ("channels.slack.botToken",                            "SLACK_BOT_TOKEN"),
    ("channels.slack.appToken",                            "SLACK_APP_TOKEN"),
    ("channels.whatsapp.authToken",                        "WHATSAPP_AUTH_TOKEN"),
    ("channels.googlechat.serviceAccountKey",              "GOOGLECHAT_SA_KEY"),
    ("gateway.auth.token",                                 "GATEWAY_AUTH_TOKEN"),
    ("agents.defaults.sandbox.docker.env.OPENAI_API_KEY",  "OPENAI_API_KEY"),
    ("agents.defaults.sandbox.docker.env.GOOGLE_API_KEY",  "GOOGLE_API_KEY"),
    ("agents.defaults.sandbox.docker.env.ANTHROPIC_API_KEY","ANTHROPIC_API_KEY"),
    ("agents.defaults.sandbox.docker.env.OPENROUTER_API_KEY","OPENROUTER_API_KEY"),
    ("agents.defaults.sandbox.docker.env.GROQ_API_KEY",    "GROQ_API_KEY"),
    ("agents.defaults.sandbox.docker.env.XAI_API_KEY",     "XAI_API_KEY"),
    ("agents.defaults.sandbox.docker.env.MISTRAL_API_KEY", "MISTRAL_API_KEY"),
    ("agents.defaults.sandbox.docker.env.CEREBRAS_API_KEY","CEREBRAS_API_KEY"),
    ("agents.defaults.sandbox.docker.env.DEEPSEEK_API_KEY","DEEPSEEK_API_KEY"),
    ("agents.defaults.sandbox.docker.env.OPENCODE_API_KEY","OPENCODE_API_KEY"),
    ("agents.defaults.sandbox.docker.env.ZAI_API_KEY",     "ZAI_API_KEY"),
    ("agents.defaults.sandbox.docker.env.TG_BOT_TOKEN",   "TG_BOT_TOKEN"),
]

def get_nested(obj, path):
    for key in path.split("."):
        if isinstance(obj, dict) and key in obj:
            obj = obj[key]
        else:
            return None
    return obj

def set_nested(obj, path, value):
    keys = path.split(".")
    for key in keys[:-1]:
        if key not in obj or not isinstance(obj[key], dict):
            return
        obj = obj[key]
    if keys[-1] in obj:
        obj[keys[-1]] = value

is_ref = lambda v: isinstance(v, str) and re.match(r"^\$\{.+\}$", v)

# Phase 1: Collect secrets from known paths
env_vars = {}     # VAR_NAME -> value
val_to_var = {}   # value -> VAR_NAME (for dedup)

for path, var_name in SENSITIVE_PATHS:
    val = get_nested(config, path)
    if val and isinstance(val, str) and not is_ref(val):
        if var_name not in env_vars:
            env_vars[var_name] = val
            val_to_var[val] = var_name

# Phase 2: Scan skills.entries.*.apiKey dynamically
skills = get_nested(config, "skills.entries")
if isinstance(skills, dict):
    for skill_name, skill_cfg in skills.items():
        if isinstance(skill_cfg, dict) and "apiKey" in skill_cfg:
            api_key = skill_cfg["apiKey"]
            if api_key and isinstance(api_key, str) and not is_ref(api_key):
                if api_key in val_to_var:
                    # Reuse existing var name (e.g. same key as OPENAI_API_KEY)
                    var_name = val_to_var[api_key]
                else:
                    var_name = skill_name.upper().replace("-", "_") + "_API_KEY"
                    env_vars[var_name] = api_key
                    val_to_var[api_key] = var_name

if not env_vars:
    print("no secrets found, writing minimal .env")

# Phase 3: Write .env (merge with existing if present)
existing = {}
if os.path.exists(env_path):
    with open(env_path, "r") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                existing[k.strip()] = v.strip()

existing.update(env_vars)
existing["OPENCLAW_DISABLE_BONJOUR"] = "1"
existing["CLAWDBOT_DISABLE_BONJOUR"] = "1"

with open(env_path, "w") as f:
    f.write("# OpenClaw Environment Variables (auto-generated)\n")
    f.write("# Do not commit this file to version control\n\n")
    for k, v in existing.items():
        f.write('{}="{}"\n'.format(k, v))

os.chmod(env_path, 0o600)

# Phase 4: Replace inline secrets with ${VAR} references in config
for path, var_name in SENSITIVE_PATHS:
    val = get_nested(config, path)
    if val and isinstance(val, str) and not is_ref(val) and var_name in env_vars:
        set_nested(config, path, "${" + var_name + "}")

if isinstance(skills, dict):
    for skill_name, skill_cfg in skills.items():
        if isinstance(skill_cfg, dict) and "apiKey" in skill_cfg:
            api_key = skill_cfg["apiKey"]
            if api_key and isinstance(api_key, str) and not is_ref(api_key):
                if api_key in val_to_var:
                    skill_cfg["apiKey"] = "${" + val_to_var[api_key] + "}"

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print(f"extracted {len(env_vars)} secret(s) to .env")
PYEOF'

ok "$MSG_OK_ENV_EXTRACTED"

info "$MSG_INFO_CREATING_MEMORY"
vm_exec "mkdir -p ~/.openclaw/memory && chmod 755 ~/.openclaw/memory"
ok "$MSG_OK_MEMORY_CREATED"

# ============================================================================
# Step 8/8
# ============================================================================
step 8 "$MSG_STEP_8"

# --- Enable user-level systemd service (created by openclaw onboard) ---
info "$MSG_INFO_CREATING_SERVICE"

# Enable lingering so user services start at boot without login
vm_exec "sudo loginctl enable-linger \$(whoami)"

# Enable and start the official user-level gateway service
vm_exec "systemctl --user enable openclaw-gateway.service"
vm_exec "openclaw gateway start"

# Wait for Gateway to be ready (up to 15s)
for _ in $(seq 1 15); do
    if vm_exec "openclaw gateway status 2>/dev/null | grep -q 'RPC probe.*ok'"; then break; fi
    sleep 1
done

if vm_exec "openclaw gateway status 2>/dev/null | grep -q 'RPC probe.*ok'"; then
    ok "$MSG_OK_GATEWAY_STARTED"
else
    warn "$MSG_WARN_GATEWAY_ISSUE"
fi

# --- Create Mac convenience commands ---
mkdir -p ~/bin

# Save language preference and VM name for generated commands
cat > ~/bin/.openclaw-lang << LANG_EOF
OPENCLAW_LANG=$OPENCLAW_LANG_CODE
LANG_EOF

cat > ~/bin/.openclaw-vm << VM_EOF
OPENCLAW_VM=$VM_NAME
VM_EOF

cat > ~/bin/openclaw-status << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -c "openclaw gateway status"
EOF

cat > ~/bin/openclaw-logs << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -c "openclaw logs --follow"
EOF

cat > ~/bin/openclaw-restart << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -c "openclaw gateway restart"
EOF

cat > ~/bin/openclaw-stop << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -c "openclaw gateway stop"
EOF

cat > ~/bin/openclaw-start << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -c "openclaw gateway start"
EOF

cat > ~/bin/openclaw-shell << EOF
#!/bin/bash
orb -m "$VM_NAME"
EOF

# --- Helper: load language for commands ---
_LANG_LOADER='
# Load language
_OPENCLAW_LANG="en"
if [ -f "$HOME/bin/.openclaw-lang" ]; then source "$HOME/bin/.openclaw-lang"; _OPENCLAW_LANG="${OPENCLAW_LANG:-en}"; fi
_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/.." && pwd)"
_LANG_FILE=""
for _d in "$_SCRIPT_DIR/lang" "/usr/local/share/openclaw/lang" "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")/../lang"; do
    if [ -f "$_d/${_OPENCLAW_LANG}.sh" ]; then _LANG_FILE="$_d/${_OPENCLAW_LANG}.sh"; break; fi
done
if [ -n "$_LANG_FILE" ]; then source "$_LANG_FILE"; fi
'

# openclaw (CLI passthrough) - no language needed
cat > ~/bin/openclaw << EOF
#!/bin/bash
set -e
if [ \$# -eq 0 ]; then
    set -- "--help"
fi
ARGS=\$(printf '%q ' "\$@")
orb -m "$VM_NAME" bash -c "openclaw \$ARGS"
EOF

# openclaw-config - needs language
cat > ~/bin/openclaw-config << CMDEOF
#!/bin/bash
$_LANG_LOADER
ACTION="\${1:-edit}"

case "\$ACTION" in
    edit)
        echo "\$MSG_CMD_CONFIG_OPENING"
        orb -m $VM_NAME bash -c "nano ~/.openclaw/openclaw.json 2>/dev/null || vi ~/.openclaw/openclaw.json"
        echo "\$MSG_CMD_CONFIG_SAVED"
        ;;
    show)
        orb -m $VM_NAME bash -c "cat ~/.openclaw/openclaw.json"
        ;;
    backup)
        BACKUP="openclaw-config-\$(date +%Y%m%d-%H%M%S).json"
        orb -m $VM_NAME bash -c "cat ~/.openclaw/openclaw.json" > "\$BACKUP"
        printf "\$MSG_CMD_CONFIG_BACKED_UP\n" "\$BACKUP"
        ;;
    *)
        echo "\$MSG_CMD_CONFIG_USAGE"
        ;;
esac
CMDEOF

# openclaw-update - needs language
cat > ~/bin/openclaw-update << CMDEOF
#!/bin/bash
set -e
$_LANG_LOADER

SANDBOX=false
for arg in "\$@"; do
    case "\$arg" in
        --sandbox) SANDBOX=true ;;
        --help|-h)
            echo "\$MSG_CMD_UPDATE_USAGE"
            echo ""
            echo "\$MSG_CMD_UPDATE_DESC"
            echo ""
            echo "\$MSG_CMD_UPDATE_OPTIONS"
            echo "\$MSG_CMD_UPDATE_SANDBOX_OPT"
            echo ""
            echo "\$MSG_CMD_UPDATE_TIP"
            exit 0
            ;;
    esac
done

# Auto-detect stale system-level service and self-repair
if grep -q "systemctl status openclaw" ~/bin/openclaw-status 2>/dev/null; then
    echo "\$MSG_UPDATE_AUTO_UPGRADE"
    # VM: migrate from system-level to user-level service
    orb -m $VM_NAME bash -c "sudo systemctl stop openclaw 2>/dev/null || true"
    orb -m $VM_NAME bash -c "sudo systemctl disable openclaw 2>/dev/null || true"
    orb -m $VM_NAME bash -c "sudo rm -f /etc/systemd/system/openclaw.service && sudo systemctl daemon-reload"
    orb -m $VM_NAME bash -c "sudo loginctl enable-linger \\\$(whoami)"
    orb -m $VM_NAME bash -c "systemctl --user enable openclaw-gateway.service 2>/dev/null || true"
    # Mac: fix stale commands
    cat > ~/bin/openclaw-status << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -c "openclaw gateway status"
FIXEOF
    cat > ~/bin/openclaw-logs << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -c "openclaw logs --follow"
FIXEOF
    cat > ~/bin/openclaw-restart << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -c "openclaw gateway restart"
FIXEOF
    cat > ~/bin/openclaw-stop << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -c "openclaw gateway stop"
FIXEOF
    cat > ~/bin/openclaw-start << 'FIXEOF'
#!/bin/bash
orb -m $VM_NAME bash -c "openclaw gateway start"
FIXEOF
    chmod +x ~/bin/openclaw-status ~/bin/openclaw-logs ~/bin/openclaw-restart ~/bin/openclaw-stop ~/bin/openclaw-start
    echo "\$MSG_UPDATE_AUTO_UPGRADE_DONE"
fi

# Ensure .env exists with at least Bonjour vars
if ! orb -m $VM_NAME bash -c 'test -f ~/.openclaw/.env' 2>/dev/null; then
    orb -m $VM_NAME bash -c 'mkdir -p ~/.openclaw && printf "# OpenClaw Environment Variables\nOPENCLAW_DISABLE_BONJOUR=1\nCLAWDBOT_DISABLE_BONJOUR=1\n" > ~/.openclaw/.env && chmod 600 ~/.openclaw/.env'
    echo "  \$MSG_UPDATE_ENV_CREATED"
fi

echo "\$MSG_CMD_UPDATE_UPDATING"

echo "\$MSG_CMD_UPDATE_STOPPING"
orb -m $VM_NAME bash -lc "openclaw gateway stop"

echo "\$MSG_CMD_UPDATE_PULLING"
orb -m $VM_NAME bash -lc "cd ~/openclaw && git fetch --tags"
LATEST_TAG=\$(orb -m $VM_NAME bash -lc "cd ~/openclaw && git describe --tags \\\$(git rev-list --tags --max-count=1)")
echo "  -> \$LATEST_TAG"
orb -m $VM_NAME bash -lc "cd ~/openclaw && git checkout '\$LATEST_TAG'"

# Ensure Corepack is enabled (auto-downloads pnpm from packageManager field)
orb -m $VM_NAME bash -lc "corepack enable" 2>/dev/null || true

echo "\$MSG_CMD_UPDATE_INSTALLING"
orb -m $VM_NAME bash -lc "cd ~/openclaw && pnpm install"

echo "\$MSG_CMD_UPDATE_BUILDING"
orb -m $VM_NAME bash -lc "cd ~/openclaw && pnpm build"

echo "\$MSG_CMD_UPDATE_UI"
orb -m $VM_NAME bash -lc "cd ~/openclaw && pnpm ui:build"

echo "\$MSG_CMD_UPDATE_REINSTALL"
orb -m $VM_NAME bash -lc "cd ~/openclaw && sudo npm install -g ."

# Auto-detect sandbox Dockerfile changes
OLD_HASH=\$(orb -m $VM_NAME bash -lc "cat ~/.openclaw/.sandbox-build-hash 2>/dev/null || echo none")
NEW_HASH=\$(orb -m $VM_NAME bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1")
if [ "\$OLD_HASH" != "\$NEW_HASH" ]; then
    SANDBOX=true
    echo "\$MSG_CMD_UPDATE_SANDBOX_CHANGED"
fi

if [ "\$SANDBOX" = true ]; then
    echo "\$MSG_CMD_UPDATE_SANDBOX_REBUILD"
    echo "\$MSG_CMD_UPDATE_SANDBOX_BASE"
    orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null || true
    echo "\$MSG_CMD_UPDATE_SANDBOX_COMMON"
    orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null || true
    echo "\$MSG_CMD_UPDATE_SANDBOX_BROWSER"
    orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null || true
    echo "\$MSG_CMD_UPDATE_SANDBOX_NOTE"
    # Save new sandbox build hash
    orb -m $VM_NAME bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1 > ~/.openclaw/.sandbox-build-hash"
fi

echo "\$MSG_CMD_UPDATE_STARTING"
orb -m $VM_NAME bash -lc "openclaw gateway start"

echo "\$MSG_CMD_UPDATE_DONE"
if [ "\$SANDBOX" = false ]; then
    echo "\$MSG_CMD_UPDATE_SANDBOX_HINT"
fi
CMDEOF

# openclaw-sandbox-rebuild - needs language
cat > ~/bin/openclaw-sandbox-rebuild << CMDEOF
#!/bin/bash
set -e
$_LANG_LOADER

echo "\$MSG_CMD_REBUILD_START"

echo "\$MSG_CMD_REBUILD_BASE"
if orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BASE_OK"
elif orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox:bookworm-slim -f Dockerfile.sandbox .'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BASE_OK_DF"
else
    echo "\$MSG_CMD_REBUILD_BASE_FAIL"
fi

echo "\$MSG_CMD_REBUILD_COMMON"
if orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_COMMON_OK"
else
    echo "\$MSG_CMD_REBUILD_COMMON_FAIL"
fi

echo "\$MSG_CMD_REBUILD_BROWSER"
if orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BROWSER_OK"
elif orb -m $VM_NAME bash -lc "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox-browser:bookworm-slim -f Dockerfile.sandbox-browser .'" 2>/dev/null; then
    echo "\$MSG_CMD_REBUILD_BROWSER_OK_DF"
else
    echo "\$MSG_CMD_REBUILD_BROWSER_FAIL"
fi

# Save new sandbox build hash
orb -m $VM_NAME bash -lc "cd ~/openclaw && cat Dockerfile.sandbox Dockerfile.sandbox-browser scripts/sandbox-setup.sh scripts/sandbox-common-setup.sh scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -d' ' -f1 > ~/.openclaw/.sandbox-build-hash"

echo ""
echo "\$MSG_CMD_REBUILD_DONE"
echo "\$MSG_CMD_REBUILD_NOTE"
CMDEOF

# openclaw-telegram - needs language
cat > ~/bin/openclaw-telegram << CMDEOF
#!/bin/bash
$_LANG_LOADER
ACTION="\${1:-help}"

case "\$ACTION" in
    add)
        if [ -z "\$2" ]; then
            echo "\$MSG_CMD_TG_ADD_USAGE"
            echo "\$MSG_CMD_TG_ADD_HINT"
            exit 1
        fi
        orb -m $VM_NAME bash -c "openclaw channels add --channel telegram --token \$(printf '%q' "\$2")"
        ;;
    approve)
        if [ -z "\$2" ]; then
            echo "\$MSG_CMD_TG_APPROVE_USAGE"
            echo "\$MSG_CMD_TG_APPROVE_HINT"
            exit 1
        fi
        orb -m $VM_NAME bash -c "openclaw pairing approve telegram \$(printf '%q' "\$2")"
        ;;
    *)
        echo "\$MSG_CMD_TG_TITLE"
        echo ""
        echo "\$MSG_CMD_TG_USAGE"
        echo "\$MSG_CMD_TG_ADD_DESC"
        echo "\$MSG_CMD_TG_APPROVE_DESC"
        echo ""
        echo "\$MSG_CMD_TG_ALT"
        echo "\$MSG_CMD_TG_ALT_CMD"
        ;;
esac
CMDEOF

cat > ~/bin/openclaw-doctor << EOF
#!/bin/bash
set -e
ARGS=\$(printf '%q ' "\$@")
orb -m "$VM_NAME" bash -c "openclaw doctor \$ARGS"
EOF

cat > ~/bin/openclaw-whatsapp << EOF
#!/bin/bash
set -e
orb -m "$VM_NAME" bash -c "openclaw channels login --channel whatsapp"
EOF

chmod +x ~/bin/openclaw-*
chmod +x ~/bin/openclaw
ok "$MSG_OK_COMMANDS_CREATED"

# --- Write default sandbox configuration ---
info "$MSG_INFO_SANDBOX_CONFIG"

vm_exec 'cat > /tmp/sandbox-config.json << '\''SANDBOX_EOF'\''
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "all",
        "scope": "agent",
        "workspaceAccess": "rw",
        "workspaceRoot": "~/.openclaw/sandboxes",
        "docker": {
          "image": "openclaw-sandbox-common:bookworm-slim",
          "containerPrefix": "openclaw-sbx-",
          "workdir": "/workspace",
          "readOnlyRoot": true,
          "tmpfs": ["/tmp:exec,mode=1777", "/var/tmp", "/run"],
          "network": "bridge",
          "user": "501:501",
          "capDrop": ["ALL"],
          "env": {
            "LANG": "C.UTF-8"
          },
          "pidsLimit": 256,
          "memory": "1g",
          "memorySwap": "2g",
          "cpus": 1
        },
        "browser": {
          "enabled": true,
          "image": "openclaw-sandbox-browser:bookworm-slim",
          "autoStart": true,
          "autoStartTimeoutMs": 30000,
          "allowHostControl": true
        },
        "prune": {
          "idleHours": 24,
          "maxAgeDays": 7
        }
      }
    }
  },
  "tools": {
    "sandbox": {
      "tools": {
        "allow": ["group:runtime", "group:fs", "group:sessions", "group:ui", "cron", "web_search", "web_fetch", "memory_search", "memory_get"],
        "deny": ["canvas", "nodes", "gateway", "telegram", "whatsapp", "discord", "googlechat", "slack", "signal", "imessage"]
      }
    }
  },
  "browser": {
    "enabled": true
  }
}
SANDBOX_EOF'

vm_exec 'cd ~/openclaw && python3 << "PYEOF"
import json, re
import os

def strip_json5(text):
    """Strip JSON5 features (comments, trailing commas) for json.load()."""
    text = re.sub(r"(?<!:)//.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
    text = re.sub(r",\s*([}\]])", r"\1", text)
    return text

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
sandbox_path = "/tmp/sandbox-config.json"

if os.path.exists(config_path):
    with open(config_path, "r") as f:
        config = json.loads(strip_json5(f.read()))
    with open(sandbox_path, "r") as f:
        sandbox = json.load(f)

    # Deep merge agents.defaults.sandbox
    if "agents" not in config:
        config["agents"] = {}
    if "defaults" not in config["agents"]:
        config["agents"]["defaults"] = {}
    config["agents"]["defaults"]["sandbox"] = sandbox["agents"]["defaults"]["sandbox"]

    # Merge tools.sandbox.tools
    if "tools" not in config:
        config["tools"] = {}
    if "sandbox" not in config["tools"]:
        config["tools"]["sandbox"] = {}
    config["tools"]["sandbox"]["tools"] = sandbox["tools"]["sandbox"]["tools"]

    # Merge browser
    config["browser"] = sandbox["browser"]

    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print("merged")
else:
    print("config not found, skipping sandbox merge")
PYEOF'

ok "$MSG_OK_SANDBOX_CONFIG"

# Check PATH and add to shell rc
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    # Detect active shell and its rc file
    _SHELL_NAME=$(basename "${SHELL:-/bin/bash}")
    case "$_SHELL_NAME" in
        zsh)  SHELL_RC="$HOME/.zshrc" ;;
        fish) SHELL_RC="$HOME/.config/fish/config.fish" ;;
        *)    SHELL_RC="$HOME/.bashrc" ;;
    esac

    if [ "$_SHELL_NAME" = "fish" ]; then
        mkdir -p "$(dirname "$SHELL_RC")"
        if ! grep -q 'set -gx PATH \$HOME/bin' "$SHELL_RC" 2>/dev/null; then
            echo '' >> "$SHELL_RC"
            echo '# OpenClaw CLI' >> "$SHELL_RC"
            echo 'set -gx PATH $HOME/bin $PATH' >> "$SHELL_RC"
            info "$(printf "$MSG_INFO_PATH_ADDED" "$SHELL_RC")"
        fi
    else
        if ! grep -q 'export PATH="\$HOME/bin:\$PATH"' "$SHELL_RC" 2>/dev/null; then
            echo '' >> "$SHELL_RC"
            echo '# OpenClaw CLI' >> "$SHELL_RC"
            echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
            info "$(printf "$MSG_INFO_PATH_ADDED" "$SHELL_RC")"
        fi
    fi
fi

# ============================================================================
# Complete
# ============================================================================
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}$MSG_FINAL_COMPLETE${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "$MSG_FINAL_ARCH"
echo "$MSG_FINAL_ARCH_DETAIL_1"
echo "$MSG_FINAL_ARCH_DETAIL_2"
echo "$MSG_FINAL_ARCH_DETAIL_3"
echo ""
echo "$MSG_FINAL_ACCESS: http://${VM_NAME}.orb.local:${GATEWAY_PORT}"
echo ""
echo "$MSG_FINAL_MAC_COMMANDS"
echo ""
echo -e "  ${GREEN}openclaw${NC}              $MSG_FINAL_CMD_CLI"
echo -e "  ${GREEN}openclaw-config${NC}       $MSG_FINAL_CMD_CONFIG"
echo -e "  ${GREEN}openclaw-status${NC}       $MSG_FINAL_CMD_STATUS"
echo -e "  ${GREEN}openclaw-logs${NC}         $MSG_FINAL_CMD_LOGS"
echo -e "  ${GREEN}openclaw-restart${NC}      $MSG_FINAL_CMD_RESTART"
echo -e "  ${GREEN}openclaw-update${NC}       $MSG_FINAL_CMD_UPDATE"
echo -e "  ${GREEN}openclaw-sandbox-rebuild${NC} $MSG_FINAL_CMD_REBUILD"
echo -e "  ${GREEN}openclaw-doctor${NC}       $MSG_FINAL_CMD_DOCTOR"
echo -e "  ${GREEN}openclaw-shell${NC}        $MSG_FINAL_CMD_SHELL"
echo ""
echo "$MSG_FINAL_SANDBOX_TITLE"
echo "$MSG_FINAL_SANDBOX_COMMON"
echo "$MSG_FINAL_SANDBOX_BROWSER"
echo ""
echo "$MSG_FINAL_NEXT_STEPS"
echo ""
echo -e "  ${GREEN}openclaw configure${NC}       $MSG_FINAL_NEXT_CONFIGURE_DESC"
echo -e "  ${GREEN}openclaw dashboard${NC}       $MSG_FINAL_NEXT_DASHBOARD_DESC"
echo -e "  ${GREEN}openclaw channels list${NC}   $MSG_FINAL_NEXT_CHANNELS_DESC"
echo ""
echo "$MSG_FINAL_NEXT_DOCS"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
