# Identities

Identities are portable agent personalities + preferences, stored in-repo.

Layout:

```
identities/
  <name>/
    SOUL.md
    config.json
    skills/
    memory/
```

Notes
- Keep `SOUL.md` + `config.json` small: cattle injects them via cloud-init `user_data` (32KiB limit).
- `skills/` and `memory/` are reserved for future phases (orchestrator / syncing).

