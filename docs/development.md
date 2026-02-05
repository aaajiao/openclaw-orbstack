# Development Guide

## Code Style

### Bash Scripts

**Shebang & Safety**
```bash
#!/bin/bash
set -e  # Exit on error (REQUIRED)
```

**Variable Naming**
```bash
# Constants: UPPER_SNAKE_CASE
VM_NAME="openclaw-vm"
TOTAL_STEPS=8

# Local variables: lower_snake_case
local config_path="$HOME/.openclaw/openclaw.json"
```

**Function Naming**
```bash
# Short utility functions: lowercase
step()  { echo -e "\n${CYAN}[$1/$TOTAL_STEPS] $2${NC}"; }
ok()    { echo -e "${GREEN}  ✓ $1${NC}"; }
err()   { echo -e "${RED}  ✗ $1${NC}"; }

# Complex functions: snake_case
vm_exec() {
    orb -m "$VM_NAME" bash -c "$1"
}
```

**Heredocs**
```bash
# Variables NOT expanded (single-quoted delimiter)
cat > openclaw.json << 'EOFCONFIG'
{
  "key": "value"
}
EOFCONFIG

# Variables expanded (unquoted delimiter)
cat > script.sh << EOF
echo "VM is $VM_NAME"
EOF
```

### JSON Configuration

- 2-space indentation
- JSON5 format (comments and trailing commas allowed)
- Use `jq` for dynamic modifications

### Documentation

- README.md: English
- docs/README.zh-CN.md: Chinese
- Code comments: English
- User-facing script text: Internationalized via `lang/zh-CN.sh` and `lang/en.sh` (use `$MSG_*` variables, never hardcode)

## Error Handling

```bash
# Check command exists (use $MSG_* variables for user-facing text)
if ! command -v orb &> /dev/null; then
    err "$MSG_ERR_NO_ORBSTACK"
    exit 1
fi

# Conditional execution with fallback
vm_exec "some_command" || true  # Don't fail if command fails

# Check file/directory exists
if vm_exec "test -d ~/openclaw"; then
    # directory exists
fi
```

## Development Commands

```bash
# Validate bash syntax
bash -n openclaw-orbstack-setup.sh

# Run shellcheck (if installed)
shellcheck openclaw-orbstack-setup.sh

# Execute deployment (skip language prompt with OPENCLAW_LANG)
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh

# With custom options
OPENCLAW_LANG=en \
OPENCLAW_EXTRA_MOUNTS="$HOME/.ssh:/home/node/.ssh:ro" \
OPENCLAW_DOCKER_APT_PACKAGES="ffmpeg" \
bash openclaw-orbstack-setup.sh
```

## Testing Changes

```bash
# Dry run - syntax only
bash -n openclaw-orbstack-setup.sh

# Full test (creates real VM, use OPENCLAW_LANG to skip language prompt)
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh

# Clean slate test
orb delete openclaw-vm  # Remove VM
OPENCLAW_LANG=en bash openclaw-orbstack-setup.sh  # Fresh install
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `orb: command not found` | OrbStack not installed | Install from orbstack.dev |
| Docker permission denied | User not in docker group | `sudo usermod -aG docker $USER` |
| EBUSY on rename | Bind mount conflict | Script sets `OPENCLAW_STATE_DIR` |
| Container won't start | Config merge failed | Check `openclaw-logs` |
| Sandbox tools fail | Wrong image | Verify `common` image is used |
| Browser tool fails | Browser sandbox not built | Run `openclaw-sandbox-rebuild` or `sandbox-browser-setup.sh` |

### Debug Mode

```bash
# Verbose execution
OPENCLAW_LANG=en bash -x openclaw-orbstack-setup.sh

# Check Gateway status
orb -m openclaw-vm bash -c "openclaw gateway status"

# Check sandbox containers
orb -m openclaw-vm bash -c "docker ps -a | grep openclaw-sbx"

# View sandbox config
orb -m openclaw-vm bash -c "cat ~/.openclaw/openclaw.json | jq .agents.defaults.sandbox"
```
