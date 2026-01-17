#!/usr/bin/env bash
set -euo pipefail

task_file="${CLAWDLETS_CATTLE_TASK_FILE:-/var/lib/clawdlets/cattle/task.json}"
result_file="${CLAWDLETS_CATTLE_RESULT_FILE:-/var/lib/clawdlets/cattle/result.json}"
workspace_dir="${CLAWDLETS_CATTLE_WORKSPACE_DIR:-/var/lib/clawdlets/cattle/workspace}"
gateway_port="${CLAWDLETS_CATTLE_GATEWAY_PORT:-18789}"
auto_shutdown="${CLAWDLETS_CATTLE_AUTO_SHUTDOWN:-1}"
bootstrap_file="${CLAWDLETS_CATTLE_BOOTSTRAP_FILE:-/run/clawdlets/cattle/bootstrap.json}"
env_file="${CLAWDLETS_CATTLE_ENV_FILE:-/run/clawdlets/cattle/env}"

now_iso() {
  date -Iseconds
}

umask 077
mkdir -p "${workspace_dir}"

started_at="$(now_iso)"
gateway_log="${workspace_dir}/gateway.log"
agent_log="${workspace_dir}/agent.log"
state_dir="${workspace_dir}/state"
mkdir -p "${state_dir}"

fail() {
  local message="${1:-unknown error}"
  printf '%s\n' "error: ${message}" >&2

  jq -n \
    --arg status "error" \
    --arg startedAt "${started_at}" \
    --arg finishedAt "$(now_iso)" \
    --arg message "${message}" \
    --arg taskFile "${task_file}" \
    --arg resultFile "${result_file}" \
    --arg gatewayLog "${gateway_log}" \
    --arg agentLog "${agent_log}" \
    '{status:$status,startedAt:$startedAt,finishedAt:$finishedAt,error:{message:$message},paths:{taskFile:$taskFile,resultFile:$resultFile,gatewayLog:$gatewayLog,agentLog:$agentLog}}' \
    >"${result_file}.tmp"
  mv "${result_file}.tmp" "${result_file}"

  /etc/clawdlets/bin/cattle-callback || true

  if [[ "${auto_shutdown}" == "1" ]]; then
    systemctl poweroff || true
  fi

  exit 1
}

fetch_secrets_env() {
  if [[ ! -f "${bootstrap_file}" ]]; then
    fail "bootstrap file missing: ${bootstrap_file}"
  fi

  local base_url token
  base_url="$(jq -r '.baseUrl // ""' "${bootstrap_file}" 2>/dev/null || true)"
  token="$(jq -r '.token // ""' "${bootstrap_file}" 2>/dev/null || true)"

  if [[ -z "${base_url}" || "${base_url}" == "null" ]]; then
    fail "invalid bootstrap.json (missing baseUrl)"
  fi
  if [[ -z "${token}" || "${token}" == "null" ]]; then
    fail "invalid bootstrap.json (missing token)"
  fi
  if [[ "${base_url}" != http://* && "${base_url}" != https://* ]]; then
    fail "invalid bootstrap.json baseUrl (expected http(s)): ${base_url}"
  fi

  local url
  url="${base_url%/}/v1/cattle/env"

  local resp tmp_env
  resp="$(mktemp -p /run/clawdlets/cattle clawdlets-cattle.env.XXXXXX.json)"
  tmp_env="$(mktemp -p /run/clawdlets/cattle clawdlets-cattle.env.XXXXXX.sh)"

  set +e
  curl -fsS \
    --connect-timeout 5 \
    --max-time 20 \
    --retry 5 \
    --retry-all-errors \
    --retry-delay 1 \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/json" \
    "${url}" \
    -o "${resp}"
  local rc="$?"
  set -e

  if [[ "${rc}" != "0" ]]; then
    rm -f "${resp}" "${tmp_env}" || true
    fail "failed to fetch env from control plane (${url}); curl exit ${rc}"
  fi

  local ok
  ok="$(jq -r '.ok // false' "${resp}" 2>/dev/null || true)"
  if [[ "${ok}" != "true" ]]; then
    local msg
    msg="$(jq -r '.error.message // "invalid response"' "${resp}" 2>/dev/null || true)"
    rm -f "${resp}" "${tmp_env}" || true
    fail "control plane env response rejected: ${msg}"
  fi

  jq -e '.env and (.env | type == "object")' "${resp}" >/dev/null 2>&1 || {
    rm -f "${resp}" "${tmp_env}" || true
    fail "control plane env response missing .env object"
  }

  jq -r '.env | to_entries[] | "export " + .key + "=" + (.value | @sh)' "${resp}" >"${tmp_env}"
  chmod 0400 "${tmp_env}"
  mv "${tmp_env}" "${env_file}"

  rm -f "${resp}" || true
  rm -f "${bootstrap_file}" || true

  # shellcheck disable=SC1090
  source "${env_file}"
}

if [[ ! -f "${task_file}" ]]; then
  fail "task file missing: ${task_file}"
fi

schema_version="$(jq -r '.schemaVersion // 1' "${task_file}" 2>/dev/null || true)"
if [[ -z "${schema_version}" || "${schema_version}" == "null" ]]; then
  fail "invalid task.json (missing schemaVersion)"
fi
if [[ "${schema_version}" != "1" ]]; then
  fail "unsupported task schemaVersion: ${schema_version} (expected 1)"
fi

task_id="$(jq -r '.taskId // \"\"' "${task_file}" 2>/dev/null || true)"
task_type="$(jq -r '.type // \"clawdbot.gateway.agent\"' "${task_file}" 2>/dev/null || true)"
message="$(jq -r '.message // \"\"' "${task_file}" 2>/dev/null || true)"

if [[ -z "${task_id}" ]]; then
  fail "invalid task.json (missing taskId)"
fi
if [[ -z "${message}" ]]; then
  fail "invalid task.json (missing message)"
fi
if [[ "${task_type}" != "clawdbot.gateway.agent" ]]; then
  fail "unsupported task type: ${task_type}"
fi

fetch_secrets_env

export CLAWDBOT_NIX_MODE="1"
export CLAWDBOT_STATE_DIR="${state_dir}"
export HOME="${workspace_dir}"

gateway_pid=""

cleanup() {
  if [[ -n "${gateway_pid}" ]]; then
    if kill -0 "${gateway_pid}" >/dev/null 2>&1; then
      kill "${gateway_pid}" >/dev/null 2>&1 || true
      wait "${gateway_pid}" >/dev/null 2>&1 || true
    fi
  fi
}
trap cleanup EXIT

(
  printf '%s\n' "starting clawdbot gateway on :${gateway_port}"
  exec clawdbot gateway --allow-unconfigured --bind loopback --port "${gateway_port}"
) >>"${gateway_log}" 2>&1 &
gateway_pid="$!"

ready="0"
for _ in $(seq 1 60); do
  if (echo >/dev/tcp/127.0.0.1/"${gateway_port}") >/dev/null 2>&1; then
    ready="1"
    break
  fi
  sleep 1
done
if [[ "${ready}" != "1" ]]; then
  fail "gateway did not become ready on 127.0.0.1:${gateway_port} (see ${gateway_log})"
fi

set +e
clawdbot gateway agent --url "ws://127.0.0.1:${gateway_port}" --message "${message}" >"${agent_log}" 2>&1
exit_code="$?"
set -e

status="ok"
if [[ "${exit_code}" != "0" ]]; then
  status="error"
fi

finished_at="$(now_iso)"

jq -n \
  --arg status "${status}" \
  --arg taskId "${task_id}" \
  --arg type "${task_type}" \
  --arg startedAt "${started_at}" \
  --arg finishedAt "${finished_at}" \
  --argjson exitCode "${exit_code}" \
  --arg taskFile "${task_file}" \
  --arg resultFile "${result_file}" \
  --arg gatewayLog "${gateway_log}" \
  --arg agentLog "${agent_log}" \
  '{status:$status,task:{id:$taskId,type:$type},startedAt:$startedAt,finishedAt:$finishedAt,exitCode:$exitCode,paths:{taskFile:$taskFile,resultFile:$resultFile,gatewayLog:$gatewayLog,agentLog:$agentLog}}' \
  >"${result_file}.tmp"
mv "${result_file}.tmp" "${result_file}"

/etc/clawdlets/bin/cattle-callback || true

if [[ "${auto_shutdown}" == "1" ]]; then
  systemctl poweroff || true
fi

exit "${exit_code}"
