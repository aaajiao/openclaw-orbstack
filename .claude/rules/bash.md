---
description: Rules for editing Bash shell scripts (.sh files)
globs: "*.sh"
---

# Bash Conventions

- Always `set -e` at top of scripts
- Constants: `UPPER_SNAKE_CASE`
- Functions: `lowercase` for utils, `snake_case` for complex logic
- Quoted heredoc delimiters (`'EOF'`) to prevent expansion; unquoted for expansion
- User-facing text: use `$MSG_*` variables from `lang/*.sh`, never hardcode
- Code comments: English

## macOS Compatibility

This project targets macOS. Use POSIX-compatible shell commands:
- No `grep -P` (use `grep -E` or awk instead)
- No GNU-only flags (`sed -i` needs `''` on macOS, `date` syntax differs)

## Validation

After editing any `.sh` file, run:
```bash
bash -n <file>          # syntax check
shellcheck <file>       # lint
```
