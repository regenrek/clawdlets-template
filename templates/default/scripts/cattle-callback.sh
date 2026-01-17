#!/usr/bin/env bash
set -euo pipefail

task_file="${CLAWDLETS_CATTLE_TASK_FILE:-/var/lib/clawdlets/cattle/task.json}"
result_file="${CLAWDLETS_CATTLE_RESULT_FILE:-/var/lib/clawdlets/cattle/result.json}"

if [[ ! -f "${task_file}" ]]; then
  exit 0
fi
if [[ ! -f "${result_file}" ]]; then
  exit 0
fi

callback_url="$(jq -r '.callbackUrl // ""' "${task_file}" 2>/dev/null || true)"
if [[ -z "${callback_url}" || "${callback_url}" == "null" ]]; then
  exit 0
fi

curl -fsS \
  -X POST \
  -H "Content-Type: application/json" \
  --data-binary "@${result_file}" \
  "${callback_url}" >/dev/null

