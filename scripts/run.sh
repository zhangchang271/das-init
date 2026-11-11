#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'Usage: %s CONFIG.json [edwav|ccf|preview|attenuation]\n' "$0" >&2
  exit 2
fi
config_path="$(realpath -- "$1")"
workflow_stage="${2:-}"
case "$workflow_stage" in
  ""|edwav|ccf|preview|attenuation) ;;
  *) printf 'Use interactive MATLAB for pick; unsupported batch stage: %s\n' "$workflow_stage" >&2; exit 2 ;;
esac
matlab_bin="${MATLAB_BIN:-matlab}"
export DAS_WORKFLOW_CONFIG="$config_path"
export DAS_WORKFLOW_STAGE="$workflow_stage"
cd -- "$project_dir"
exec "$matlab_bin" -batch "run_workflow(getenv('DAS_WORKFLOW_CONFIG'),getenv('DAS_WORKFLOW_STAGE'))"
