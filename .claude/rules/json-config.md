---
description: Rules for editing JSON/JSON5 configuration files
globs: "*.json,*.json5,*.example"
---

# JSON Configuration Rules

- Format: JSON5 (comments and trailing commas allowed)
- Indentation: 2 spaces
- Dynamic edits: use `jq`, never sed for JSON/YAML
- SecretRef objects are required for sensitive values; never use plaintext `${VAR}` strings

## Config Editing Workflow

1. Check upstream docs (https://docs.openclaw.ai/gateway/configuration) for field names and nesting
2. Read the current file to understand context
3. Edit
4. Validate JSON syntax: `jq . <file> > /dev/null` (for strict JSON) or visual check (for JSON5)
