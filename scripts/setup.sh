#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python_bin="${DAS_SETUP_PYTHON:-python3.12}"
"$python_bin" -m venv "$project_dir/.venv"
"$project_dir/.venv/bin/python" -m pip install -r "$project_dir/requirements.txt"
"$project_dir/.venv/bin/python" "$project_dir/scripts/check_python.py"
