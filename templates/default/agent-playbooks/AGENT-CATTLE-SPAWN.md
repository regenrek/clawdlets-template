# AGENT-CATTLE-SPAWN

Goal: spawn ephemeral task VM (“cattle”) on Hetzner. Run once. Poweroff. Reap by TTL.

Prereqs (must be true)
- cattle image uploaded to Hetzner (custom image id/name)
- `fleet/clawdlets.json`:
  - `cattle.enabled=true`
  - `cattle.hetzner.image="<id-or-name>"`
  - `cattle.hetzner.maxInstances` sane
  - `hosts.<host>.sshAuthorizedKeys` non-empty
- secrets present + decryptable (sops):
  - `tailscale_auth_key`
  - provider key(s) for model (via `fleet.envSecrets`)
- operator has Tailscale + can reach tailnet

Identity
- create:

```
clawdlets identity add --name rex
```

- edit:
  - `identities/rex/SOUL.md`
  - `identities/rex/config.json` (set `model.primary` if you don’t want host default)

Task file (schemaVersion 1)
- write `task.json`:

```json
{
  "schemaVersion": 1,
  "taskId": "issue-42",
  "type": "clawdbot.gateway.agent",
  "message": "Fix issue #42 in repo ...",
  "callbackUrl": ""
}
```

Spawn (dry-run first)

```
clawdlets cattle spawn --host <host> --identity rex --task-file ./task.json --ttl 2h --dry-run
```

Spawn (real)

```
clawdlets cattle spawn --host <host> --identity rex --task-file ./task.json --ttl 2h
```

Observe

```
clawdlets cattle list --host <host>
clawdlets cattle logs --host <host> <id-or-name> --follow
clawdlets cattle ssh --host <host> <id-or-name>
```

Cleanup

```
clawdlets cattle reap --host <host> --dry-run
clawdlets cattle reap --host <host>
clawdlets cattle destroy --host <host> <id-or-name>
clawdlets cattle destroy --host <host> --all
```

Notes
- Default access: tailnet-only (no public SSH).
- Hostname: cattle uses Hetzner server name; resolve via `tailscale ip --1 --4 <server-name>`.
- Keep identity small: injected via cloud-init user-data (32KiB limit).

