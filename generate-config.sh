#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/tmp/ss-config.yaml"

check_changed_files() {
  if [[ ${INPUT_MODE} == "diff" && -z "${CHANGED_FILES}" ]]; then
    echo "::notice::No files changed. Skipping scan."
    echo "skip=true" >> "${GITHUB_OUTPUT}"
    return 1
  fi
}

prepare_config() {
  if [[ -n "${USER_CONFIG_FILE:-}" ]]; then
    python3 -c "
import yaml, os

with open(os.environ['USER_CONFIG_FILE']) as f:
    cfg = yaml.safe_load(f) or {}

if not cfg.get('namespace'):
    cfg['namespace'] = os.environ['GITHUB_REPOSITORY'].split('/', 1)[-1]
if os.environ['INPUT_MODE'] == 'diff':
    cfg['ss'] = cfg.get('ss') or {}
    cfg['ss']['include'] = os.environ['CHANGED_FILES'].splitlines()

with open('${CONFIG_FILE}', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
"
  else
    python3 -c "
import yaml, os

cfg = {}
cfg['namespace'] = os.environ['GITHUB_REPOSITORY'].split('/', 1)[-1]
cfg['ss'] = {
    'include': os.environ['CHANGED_FILES'].splitlines() if os.environ['INPUT_MODE'] == 'diff'
               else ['.'],
}
cfg['output'] = {
    'format': 'SARIF',
    'file_path': '.fluidattacks-ss-results.sarif',
}

with open('${CONFIG_FILE}', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
"
  fi
}

# Authentication is best-effort: any problem falls back to an unauthenticated scan.
# A Group token already identifies the group, so "group" is only needed for OIDC.
build_auth_args() {
  SCAN_ARGS=()

  if [[ -n "${INTEGRATES_API_TOKEN:-}" ]]; then
    echo "Authenticating with a Group token"
    return 0
  fi

  if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
    echo "::warning::No credentials available (grant 'permissions: id-token: write' or provide 'api_token'; fork pull requests get neither). Running unauthenticated."
    return 0
  fi

  if [[ -z "${FLUID_GROUP:-}" ]]; then
    echo "::warning::'group' is required for OIDC authentication. Running unauthenticated."
    return 0
  fi

  if [[ ! "${FLUID_GROUP}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "::warning::Invalid 'group' value. Running unauthenticated."
    return 0
  fi

  echo "Authenticating group '${FLUID_GROUP}' with OIDC"
  SCAN_ARGS+=(--group "${FLUID_GROUP}")
}

run_scan() {
  build_auth_args
  echo "::group::Generated configuration"
  cat "${CONFIG_FILE}"
  echo "::endgroup::"

  local exit_code=0
  # Run from the workspace so include paths and the SARIF path resolve against it
  (cd "${GITHUB_WORKSPACE}" && ss scan ${SCAN_ARGS[@]+"${SCAN_ARGS[@]}"} --config "${CONFIG_FILE}") || exit_code=$?

  if [[ ${exit_code} -eq 0 ]]; then
    echo "vulnerabilities_found=false" >> "${GITHUB_OUTPUT}"
  elif [[ ${exit_code} -eq 1 ]]; then
    echo "vulnerabilities_found=true" >> "${GITHUB_OUTPUT}"
  else
    echo "::error::Scanner exited with code ${exit_code}"
    exit "${exit_code}"
  fi

  python3 -c "
import yaml, re
with open('${CONFIG_FILE}') as f:
    cfg = yaml.safe_load(f)
fmt = cfg.get('output', {}).get('format', '')
if fmt == 'SARIF':
    path = cfg['output']['file_path']
    sanitized = re.sub(r'[\r\n]', '', str(path))
    print('sarif_file=' + sanitized)
" >> "${GITHUB_OUTPUT}" 2> /dev/null || true
}

main() {
  if ! check_changed_files; then
    exit 0
  fi

  prepare_config
  echo "skip=false" >> "${GITHUB_OUTPUT}"
  run_scan
}

main
