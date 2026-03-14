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

# --- Progress indicator for long-running commands ---
_progress_pid=""
start_progress() {
    (while true; do sleep 10; printf "."; done) &
    _progress_pid=$!
}
stop_progress() {
    if [ -n "$_progress_pid" ]; then
        kill "$_progress_pid" 2>/dev/null || true
        wait "$_progress_pid" 2>/dev/null || true
        _progress_pid=""
        printf "\n"
    fi
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

# pnpm (via Corepack if available, otherwise npm global install)
info "$MSG_INFO_INSTALLING_PNPM"
vm_exec "sudo corepack enable 2>/dev/null || sudo npm install -g pnpm"
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
    vm_exec "cd ~/openclaw && git fetch --tags --force"
else
    info "$MSG_INFO_CLONING"
    vm_exec "git clone https://github.com/openclaw/openclaw.git ~/openclaw"
fi

# Get latest stable release tag (skip beta/rc/alpha pre-releases)
OPENCLAW_VERSION=$(vm_exec "cd ~/openclaw && git tag -l 'v*' | grep -v -e '-beta' -e '-rc' -e '-alpha' | sort -V | tail -1")
if [ -z "$OPENCLAW_VERSION" ]; then
    err "$MSG_ERR_NO_VERSION"
    exit 1
fi
info "$(printf "$MSG_INFO_CHECKOUT_RELEASE" "$OPENCLAW_VERSION")"
vm_exec "cd ~/openclaw && git checkout '$OPENCLAW_VERSION'"

# Derive npm package version from git tag (v2026.3.13 -> 2026.3.13)
NPM_VERSION="${OPENCLAW_VERSION#v}"

info "$MSG_INFO_NPM_INSTALL"
info "$MSG_INFO_NPM_BUILD"

# Try source build; fall back to prebuilt npm package on failure
if vm_exec "cd ~/openclaw && pnpm install && pnpm build && pnpm ui:build && sudo npm install -g ."; then
    ok "$MSG_BUILD_SOURCE_OK"
else
    warn "$MSG_BUILD_FAILED"
    info "$MSG_BUILD_FALLBACK"
    # shellcheck disable=SC2059
    info "$(printf "$MSG_BUILD_FALLBACK_VERSION" "$NPM_VERSION")"
    if vm_exec "sudo npm install -g openclaw@$NPM_VERSION"; then
        ok "$MSG_BUILD_FALLBACK_OK"
    else
        err "$MSG_BUILD_FALLBACK_FAIL"
        exit 1
    fi
fi

# Mark build as successful (used by openclaw-update to detect incomplete builds)
vm_exec "echo '$OPENCLAW_VERSION' > ~/.openclaw/.build-version"

ok "$MSG_OK_BUILD_DONE"

# ============================================================================
# Step 6/8
# ============================================================================
step 6 "$MSG_STEP_6"

info "$MSG_INFO_SANDBOX_BASE"
echo "$MSG_BUILD_PATIENCE"
start_progress
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-setup.sh'" 2>/dev/null; then
    stop_progress
    ok "$MSG_OK_SANDBOX_BASE"
elif vm_exec "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox:bookworm-slim -f Dockerfile.sandbox .'" 2>/dev/null; then
    stop_progress
    ok "$MSG_OK_SANDBOX_BASE_DF"
else
    stop_progress
    warn "$MSG_WARN_SANDBOX_BASE_FAIL"
fi

info "$MSG_INFO_SANDBOX_COMMON"
echo "$MSG_BUILD_PATIENCE"
start_progress
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-common-setup.sh'" 2>/dev/null; then
    stop_progress
    ok "$MSG_OK_SANDBOX_COMMON"
else
    stop_progress
    warn "$MSG_WARN_SANDBOX_COMMON_FAIL"
fi

info "$MSG_INFO_SANDBOX_BROWSER"
echo "$MSG_BUILD_PATIENCE"
start_progress
if vm_exec "cd ~/openclaw && sg docker -c './scripts/sandbox-browser-setup.sh'" 2>/dev/null; then
    stop_progress
    ok "$MSG_OK_SANDBOX_BROWSER"
elif vm_exec "cd ~/openclaw && sg docker -c 'docker build -t openclaw-sandbox-browser:bookworm-slim -f Dockerfile.sandbox-browser .'" 2>/dev/null; then
    stop_progress
    ok "$MSG_OK_SANDBOX_BROWSER_DF"
else
    stop_progress
    warn "$MSG_WARN_SANDBOX_BROWSER_FAIL"
fi

# Save per-image sandbox build hashes for staleness detection during updates
vm_exec "cd ~/openclaw && \
  cat Dockerfile.sandbox scripts/sandbox-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-base && \
  cat Dockerfile.sandbox-common scripts/sandbox-common-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-common && \
  cat Dockerfile.sandbox-browser scripts/sandbox-browser-setup.sh 2>/dev/null | sha256sum | cut -c1-64 > ~/.openclaw/.sandbox-hash-browser"

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
# 3rd element: "secretref" -> SecretRef object, "envvar" -> ${VAR} string
SENSITIVE_PATHS = [
    ("channels.telegram.botToken",                         "TG_BOT_TOKEN",      "secretref"),
    ("channels.discord.token",                             "DISCORD_TOKEN",     "secretref"),
    ("channels.slack.botToken",                            "SLACK_BOT_TOKEN",   "secretref"),
    ("channels.slack.appToken",                            "SLACK_APP_TOKEN",   "secretref"),
    ("channels.whatsapp.authToken",                        "WHATSAPP_AUTH_TOKEN","secretref"),
    ("channels.googlechat.serviceAccountKey",              "GOOGLECHAT_SA_KEY", "secretref"),
    ("gateway.auth.token",                                 "GATEWAY_AUTH_TOKEN","envvar"),
    ("agents.defaults.sandbox.docker.env.OPENAI_API_KEY",  "OPENAI_API_KEY",   "envvar"),
    ("agents.defaults.sandbox.docker.env.GOOGLE_API_KEY",  "GOOGLE_API_KEY",   "envvar"),
    ("agents.defaults.sandbox.docker.env.ANTHROPIC_API_KEY","ANTHROPIC_API_KEY","envvar"),
    ("agents.defaults.sandbox.docker.env.OPENROUTER_API_KEY","OPENROUTER_API_KEY","envvar"),
    ("agents.defaults.sandbox.docker.env.GROQ_API_KEY",    "GROQ_API_KEY",     "envvar"),
    ("agents.defaults.sandbox.docker.env.XAI_API_KEY",     "XAI_API_KEY",      "envvar"),
    ("agents.defaults.sandbox.docker.env.MISTRAL_API_KEY", "MISTRAL_API_KEY",  "envvar"),
    ("agents.defaults.sandbox.docker.env.CEREBRAS_API_KEY","CEREBRAS_API_KEY",  "envvar"),
    ("agents.defaults.sandbox.docker.env.DEEPSEEK_API_KEY","DEEPSEEK_API_KEY",  "envvar"),
    ("agents.defaults.sandbox.docker.env.OPENCODE_API_KEY","OPENCODE_API_KEY",  "envvar"),
    ("agents.defaults.sandbox.docker.env.ZAI_API_KEY",     "ZAI_API_KEY",      "envvar"),
    ("agents.defaults.sandbox.docker.env.TG_BOT_TOKEN",   "TG_BOT_TOKEN",     "envvar"),
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

is_ref = lambda v: (isinstance(v, str) and re.match(r"^\$\{.+\}$", v)) or (isinstance(v, dict) and "source" in v)

# Phase 1: Collect secrets from known paths
env_vars = {}     # VAR_NAME -> value
val_to_var = {}   # value -> VAR_NAME (for dedup)

for path, var_name, _ref_type in SENSITIVE_PATHS:
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

# Phase 2b: Scan auth-profiles.json for plaintext keys/tokens
ap_path = os.path.expanduser("~/.openclaw/agents/main/agent/auth-profiles.json")
ap = None
if os.path.exists(ap_path):
    with open(ap_path, "r") as f:
        ap = json.loads(strip_json5(f.read()))
    if isinstance(ap, dict):
        for provider, profile in ap.items():
            if not isinstance(profile, dict):
                continue
            for field, suffix in [("key", "_API_KEY"), ("token", "_TOKEN")]:
                val = profile.get(field)
                if val and isinstance(val, str) and not is_ref(val):
                    if val in val_to_var:
                        pass  # reuse existing var, replacement handled in Phase 5
                    else:
                        var_name = provider.upper().replace("-", "_") + suffix
                        env_vars[var_name] = val
                        val_to_var[val] = var_name

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

with open(env_path, "w") as f:
    f.write("# OpenClaw Environment Variables (auto-generated)\n")
    f.write("# Do not commit this file to version control\n\n")
    for k, v in existing.items():
        f.write('{}="{}"\n'.format(k, v))

os.chmod(env_path, 0o600)

# Phase 4: Replace inline secrets with refs in config
for path, var_name, ref_type in SENSITIVE_PATHS:
    val = get_nested(config, path)
    if val and isinstance(val, str) and not is_ref(val) and var_name in env_vars:
        if ref_type == "secretref":
            set_nested(config, path, {"source": "env", "provider": "default", "id": var_name})
        else:
            set_nested(config, path, "${" + var_name + "}")

if isinstance(skills, dict):
    for skill_name, skill_cfg in skills.items():
        if isinstance(skill_cfg, dict) and "apiKey" in skill_cfg:
            api_key = skill_cfg["apiKey"]
            if api_key and isinstance(api_key, str) and not is_ref(api_key):
                if api_key in val_to_var:
                    skill_cfg["apiKey"] = {"source": "env", "provider": "default", "id": val_to_var[api_key]}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

# Phase 5: Replace plaintext secrets in auth-profiles.json
ap_count = 0
if ap and isinstance(ap, dict):
    for provider, profile in ap.items():
        if not isinstance(profile, dict):
            continue
        for field in ("key", "token"):
            val = profile.get(field)
            if val and isinstance(val, str) and not is_ref(val) and val in val_to_var:
                profile[field] = {"source": "env", "provider": "default", "id": val_to_var[val]}
                ap_count += 1
    with open(ap_path, "w") as f:
        json.dump(ap, f, indent=2)

print(f"extracted {len(env_vars)} secret(s) to .env, {ap_count} auth-profile ref(s) updated")
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

# --- Create Mac convenience commands (delegate to refresh-mac-commands.sh) ---
OPENCLAW_LANG="$OPENCLAW_LANG_CODE" OPENCLAW_VM_NAME="$VM_NAME" bash "$SCRIPT_DIR/scripts/refresh-mac-commands.sh"
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
          "idleHours": 0,
          "maxAgeDays": 0
        }
      }
    }
  },
  "tools": {
    "sandbox": {
      "tools": {
        "allow": ["group:runtime", "group:fs", "group:sessions", "group:ui", "cron", "web_search", "web_fetch", "memory_search", "memory_get"],
        "deny": ["nodes", "gateway", "telegram", "whatsapp", "discord", "googlechat", "slack", "signal", "imessage"]
      }
    }
  },
  "browser": {
    "enabled": true,
    "noSandbox": true
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

vm_exec "rm -f /tmp/sandbox-config.json"

ok "$MSG_OK_SANDBOX_CONFIG"

# Check PATH and add to shell rc
_PATH_CHANGED=false
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
            _PATH_CHANGED=true
        fi
    else
        if ! grep -q 'export PATH="\$HOME/bin:\$PATH"' "$SHELL_RC" 2>/dev/null; then
            echo '' >> "$SHELL_RC"
            echo '# OpenClaw CLI' >> "$SHELL_RC"
            echo 'export PATH="$HOME/bin:$PATH"' >> "$SHELL_RC"
            info "$(printf "$MSG_INFO_PATH_ADDED" "$SHELL_RC")"
            _PATH_CHANGED=true
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
if [ "$_PATH_CHANGED" = true ]; then
    echo ""
    echo -e "  ${YELLOW}>>> $MSG_NOTE_OPEN_NEW_TERMINAL${NC}"
fi
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
