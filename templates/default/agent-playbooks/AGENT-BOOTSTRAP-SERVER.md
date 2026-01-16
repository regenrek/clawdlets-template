# AGENT-BOOTSTRAP-SERVER

Goal: new user runs this top to bottom. Agent drives commands, but stops on missing data.

Start point
- repo created by `clawdlets project init`
- CWD repo root (has `fleet/clawdlets.json`)
- choose `<host>` name

Rules
- do not use `--force` unless told
- `clawdlets bootstrap` runs doctor for nixos-anywhere and stops on missing data
- image mode skips doctor; avoid for first-time users

Inputs you must collect
- Hetzner token (HCLOUD_TOKEN)
- SSH pubkey file path
- admin CIDR (your IP /32)
- server type, disk device
- tailnet mode (tailscale or none)
- Discord tokens per bot
- LLM API keys referenced by `fleet.envSecrets`
- optional: GitHub token if base flake is private
- optional: self-update manifest URL (+ minisign public key/signature URL)

## Step 1: config (edit `fleet/clawdlets.json`)

Required fields
- `fleet.guildId`
- `fleet.bots` (list)
- `fleet.envSecrets`
- `hosts.<host>.enable = true`
- `hosts.<host>.diskDevice`
- `hosts.<host>.hetzner.serverType`
- `hosts.<host>.opentofu.adminCidr`
- `hosts.<host>.opentofu.sshPubkeyFile`
- `hosts.<host>.sshExposure.mode = "bootstrap"`
- `hosts.<host>.tailnet.mode = "tailscale" | "none"`

Optional self-update
- `hosts.<host>.selfUpdate.enable = true`
- `hosts.<host>.selfUpdate.manifestUrl = "https://<pages>/deploy/<host>/latest.json"`
- optional: `selfUpdate.publicKey` + `selfUpdate.signatureUrl`

## Step 2: deploy creds

```
clawdlets env init
```

- set `HCLOUD_TOKEN=...` in `.clawdlets/env`
- set `GITHUB_TOKEN=...` only if base flake is private

## Step 3: secrets (non-interactive)

```
clawdlets secrets init --host <host>
```

Fill `.clawdlets/secrets.json`:
- `adminPasswordHash` (YESCRYPT hash)
- `tailscaleAuthKey` (if tailnet=tailscale)
- `discordTokens.<bot>` for each bot
- `secrets.<secretName>` for LLM keys in `fleet.envSecrets`

Then:

```
clawdlets secrets init --host <host> --from-json .clawdlets/secrets.json --yes
```

## Step 4: bootstrap

```
clawdlets bootstrap --host <host>
```

If bootstrap fails, stop, fix missing values, then rerun. Do not pass `--force`.

## Step 5: after tailnet

```
clawdlets host set --host <host> --target-host admin@<tailscale-ip>
clawdlets host set --host <host> --ssh-exposure tailnet
clawdlets server deploy --host <host> --manifest deploy-manifest.<host>.json
clawdlets lockdown --host <host>
```

Notes
- `.clawdlets/secrets.json` is plaintext. Never commit.
- self-update requires CI to publish manifests (and signatures if using minisign).
