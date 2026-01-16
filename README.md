# clawdlets-template

Project templates for clawdlets.

## Templates

- `templates/default/` — canonical clawdlets project template (fleet + infra + agent-playbooks).

## Usage

```bash
clawdlets project init --template regenrek/clawdlets-template --template-path templates/default
```

## Notes

- Keep template contents in `templates/default/`.
- CI runs `nix flake check` + `clawdlets doctor --scope repo` against the template.
