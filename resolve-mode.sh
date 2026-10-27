#!/usr/bin/env bash
set -euo pipefail

out() { echo "$1" >> "${GITHUB_OUTPUT}"; }

# Resolve config file
if [[ -n "${SCAN_CONFIG_PATH:-}" ]]; then
  RESOLVED="${GITHUB_WORKSPACE}/${SCAN_CONFIG_PATH}"
  if [[ ! -f "${RESOLVED}" ]]; then
    echo "::error::scan_config_path '${SCAN_CONFIG_PATH}' not found in repository"
    exit 1
  fi
  out "config_file=${RESOLVED}"
else
  out "config_file="
fi

case "${SCANNER_MODE:-}" in
  "" | full)
    # Default: full scan
    out "mode=full"
    exit 0
    ;;
  diff) ;;
  *)
    echo "::error::Invalid scanner_mode '${SCANNER_MODE}'. Use 'full' or 'diff'."
    exit 1
    ;;
esac

# Diff mode is only valid on push and pull_request events
if [[ "${GITHUB_EVENT_NAME}" == "pull_request" ]]; then
  out "mode=diff"
  out "base_sha=${PR_BASE_SHA}"
  exit 0
fi

if [[ "${GITHUB_EVENT_NAME}" == "push" ]]; then
  DEFAULT_BRANCH=$(git remote show origin | grep 'HEAD branch' | awk '{print $NF}')
  CURRENT_BRANCH="${GITHUB_REF#refs/heads/}"

  # Default branch: diff against the commit before the push
  if [[ "${CURRENT_BRANCH}" == "${DEFAULT_BRANCH}" ]]; then
    if [[ -n "${GITHUB_BEFORE:-}" && ! "${GITHUB_BEFORE}" =~ ^0+$ ]]; then
      out "mode=diff"
      out "base_sha=${GITHUB_BEFORE}"
    else
      echo "::warning::No base SHA available for differential scan. Falling back to full scan."
      out "mode=full"
    fi
    exit 0
  fi

  # Any other branch: diff against default branch
  out "mode=diff"
  out "base_sha=$(git rev-parse "origin/${DEFAULT_BRANCH}")"
  exit 0
fi

# Other events (schedule, workflow_dispatch, etc.) have no base to compare against
echo "::warning::Differential scan is not supported on '${GITHUB_EVENT_NAME}' events. Falling back to full scan."
out "mode=full"
