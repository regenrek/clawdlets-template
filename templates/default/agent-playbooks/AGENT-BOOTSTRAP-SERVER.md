# AGENT-BOOTSTRAP-SERVER

Goal: human-friendly day0. Agent drives step-by-step, asks for missing values, prefers interactive wizards.

Start point
- empty dir ok (agent runs `clawdlets project init`)
- OR existing repo root (has `fleet/clawdlets.json`)
- choose `<host>` name (Hetzner host, e.g. `clawdlets-fleet-beta-6`)

Rules
- do not use `--force` unless told
- `clawdlets bootstrap` runs doctor for `nixos-anywhere` and stops on missing data
- image mode skips doctor; avoid for first-time users

Day0 defaults (Hetzner-focused)
- `sshExposure=bootstrap` (public SSH open only for bootstrap window)
- `diskDevice=/dev/sda`
- `cache.garnix.private.enable=false` (enable later, after stable deploy)

Inputs to collect (agent asks)
- Hetzner token (`HCLOUD_TOKEN`)
- SSH pubkey file path
- admin CIDR (your IP `/32`)
- server type
- tailnet mode (`tailscale` or `none`)
- Discord tokens per bot
- LLM API keys referenced by `fleet.envSecrets`
- optional: GitHub token if base flake is private
- optional: self-update manifest URL (+ minisign public key/signature URL)

If you want fully scripted, see `AGENT-BOOTSTRAP-SERVER-AUTO.md`.

Day0 command map (use these)
- `clawdlets project init` (wizard)
- `clawdlets env init`
- `clawdlets fleet set`
- `clawdlets bot add --interactive`
- `clawdlets host add`
- `clawdlets host set-default`
- `clawdlets host set`
- `clawdlets config set`
- `clawdlets config validate`
- `clawdlets secrets init --interactive`
- `clawdlets secrets verify`
- `clawdlets doctor --strict`
- `clawdlets bootstrap`
- `clawdlets server deploy`
- `clawdlets server audit`
- `clawdlets lockdown`

## Step 1: project init (wizard)

```
clawdlets project init
```

Agent collects: repo dir, `<host>`, and any template prompts.

## Step 2: deploy creds

```
clawdlets env init
```

Agent writes `.clawdlets/env` (gitignored):
- set `HCLOUD_TOKEN=...`
- set `GITHUB_TOKEN=...` only if base flake is private

## Step 3: fleet config (agent-guided)

Set guild id:

```
clawdlets fleet set --guild-id <discord-guild-id>
```

Add bots (wizard):

```
clawdlets bot add --interactive
```

Repeat per bot id.

## Step 4: host config (agent-guided)

Create host entry and make it default:

```
clawdlets host add --host <host>
clawdlets host set-default --host <host>
```

Set day0 host fields (agent asks, then runs):

```
clawdlets host set --host <host> --enable true
clawdlets host set --host <host> --ssh-exposure bootstrap
clawdlets host set --host <host> --disk-device /dev/sda
clawdlets host set --host <host> --server-type <hetzner-type>
clawdlets host set --host <host> --admin-cidr <your-ip>/32
clawdlets host set --host <host> --ssh-pubkey-file ~/.ssh/id_ed25519.pub
clawdlets host set --host <host> --tailnet tailscale
```

Force day0 Garnix private cache off (avoids netrc requirement during early boots):

```
clawdlets config set --path hosts.<host>.cache.garnix.private.enable --value-json false
```

Validate config:

```
clawdlets config validate
```

Optional self-update
- `hosts.<host>.selfUpdate.enable = true`
- `hosts.<host>.selfUpdate.manifestUrl = "https://<pages>/deploy/<host>/latest.json"`
- optional: `selfUpdate.publicKey` + `selfUpdate.signatureUrl`

## Step 5: secrets (wizard)

```
clawdlets secrets init --interactive --host <host>
```

Agent prompts for:
- `admin_password_hash` (YESCRYPT)
- `tailscale_auth_key` (if `tailnet=tailscale`)
- `discord_token_<bot>` for each bot
- LLM/provider keys referenced by `fleet.envSecrets` (e.g. `z_ai_api_key`)

Then verify:

```
clawdlets secrets verify --host <host>
```

## Step 6: doctor gate (must be green)

```
clawdlets doctor --host <host> --scope bootstrap --strict
```

## Step 7: bootstrap

```
clawdlets bootstrap --host <host>
```

Bootstrap prints host + IPv4. Set SSH target for follow-up steps:

```
clawdlets host set --host <host> --target-host admin@<ipv4>
```

## Step 8: tailscale cutover + lockdown (recommended)

Wait until the host appears in Tailscale, then:

```
clawdlets host set --host <host> --target-host admin@<tailscale-ip>
clawdlets host set --host <host> --ssh-exposure tailnet
clawdlets server audit --host <host>
clawdlets lockdown --host <host>
```

## Step 9: deploy + verify

```
clawdlets server deploy --host <host>
clawdlets server status --host <host>
```

Notes
- If bootstrap fails, stop, fix missing values, then rerun. Don’t pass `--force`.
- `.clawdlets/secrets.json` (if you use it) is plaintext. Never commit.
- `server deploy --manifest ...` exists for CI/self-update flows; not required for day0.
- self-update requires CI to publish manifests (and signatures if using minisign).
