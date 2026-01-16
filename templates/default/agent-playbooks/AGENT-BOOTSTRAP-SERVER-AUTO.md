# AGENT-BOOTSTRAP-SERVER-AUTO (non-interactive)

Goal: agent runs end-to-end with deterministic commands. No prompts. If a required input is missing, stop and ask.

Day0 defaults (Hetzner-focused)
- `sshExposure=bootstrap` (public SSH open only for bootstrap window)
- `diskDevice=/dev/sda`
- `cache.garnix.private.enable=false` (enable later, after stable deploy)

Assumptions (must already be true)
- repo exists (created earlier, e.g. via `clawdlets project init`)
- `fleet/clawdlets.json` filled (no placeholders for day0)
- `.clawdlets/env` exists and has deploy creds (`HCLOUD_TOKEN=...`; optional `GITHUB_TOKEN=...`)
- secrets JSON exists at `.clawdlets/secrets.json` (plaintext; never commit)
  - includes required secrets for this host (discord tokens, `tailscale_auth_key` if tailscale, LLM keys, etc.)

Day0 command map (auto)
- `clawdlets config validate`
- `clawdlets host add`
- `clawdlets host set-default`
- `clawdlets host set`
- `clawdlets config set`
- `clawdlets secrets init --fromJson ... --yes`
- `clawdlets secrets verify`
- `clawdlets doctor --strict`
- `clawdlets bootstrap`
- `clawdlets server deploy`
- `clawdlets server audit`
- `clawdlets lockdown`

## Step 0: validate config

```
clawdlets config validate
```

## Step 1: write host config (no prompts)

```
clawdlets host add --host <host>
clawdlets host set-default --host <host>

clawdlets host set --host <host> --enable true
clawdlets host set --host <host> --ssh-exposure bootstrap
clawdlets host set --host <host> --disk-device /dev/sda
clawdlets host set --host <host> --server-type <hetzner-type>
clawdlets host set --host <host> --admin-cidr <your-ip>/32
clawdlets host set --host <host> --ssh-pubkey-file ~/.ssh/id_ed25519.pub
clawdlets host set --host <host> --tailnet tailscale

# day0: keep Garnix private cache off
clawdlets config set --path hosts.<host>.cache.garnix.private.enable --value-json false
```

## Step 2: write secrets (no prompts)

```
clawdlets secrets init --host <host> --fromJson .clawdlets/secrets.json --yes
clawdlets secrets verify --host <host>
```

## Step 3: doctor gate (fail fast)

```
clawdlets doctor --host <host> --scope bootstrap --strict
```

## Step 4: bootstrap

```
clawdlets bootstrap --host <host>
```

Bootstrap prints host + IPv4. Set SSH target for follow-up steps:

```
clawdlets host set --host <host> --target-host admin@<ipv4>
```

## Step 5: tailscale cutover + lockdown (recommended)

Wait until the host appears in Tailscale, then:

```
clawdlets host set --host <host> --target-host admin@<tailscale-ip>
clawdlets host set --host <host> --ssh-exposure tailnet
clawdlets server audit --host <host>
clawdlets lockdown --host <host>
```

## Step 6: deploy + verify

```
clawdlets server deploy --host <host>
clawdlets server status --host <host>
```

## Later: enable Garnix private cache (only when ready)

Prereq: have netrc content ready (doctor blocks deploy if enabled but missing `garnix_netrc` secret).

```
clawdlets host set --host <host> --garnix-private-cache true --garnix-netrc-secret garnix_netrc --garnix-netrc-path /etc/nix/netrc
clawdlets secrets init --host <host> --fromJson .clawdlets/secrets.json --yes
clawdlets doctor --host <host> --strict
clawdlets server deploy --host <host>
```
