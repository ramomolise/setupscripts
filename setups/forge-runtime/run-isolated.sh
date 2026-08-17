#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: run-isolated.sh PROJECT_DIR [--] [COMMAND [ARGUMENTS...]]

Example:
  run-isolated.sh ~/Projects/ForgeAI -- hermes
EOF
}

[[ $# -ge 1 ]] || {
    usage >&2
    exit 2
}

project_dir=$1
shift
[[ ${1:-} == '--' ]] && shift

mkdir -p "$project_dir"
project_dir=$(cd -- "$project_dir" && pwd)
runtime_dir="$project_dir/.runtime"
mkdir -p \
    "$runtime_dir/hermes-home" \
    "$runtime_dir/cache" \
    "$runtime_dir/config" \
    "$runtime_dir/share" \
    "$runtime_dir/tmp"

export HERMES_HOME="$runtime_dir/hermes-home"
export XDG_CACHE_HOME="$runtime_dir/cache"
export XDG_CONFIG_HOME="$runtime_dir/config"
export XDG_DATA_HOME="$runtime_dir/share"
export TMPDIR="$runtime_dir/tmp"
export OLLAMA_HOST=${OLLAMA_HOST:-http://127.0.0.1:11434}

cd "$project_dir"
if (($#)); then
    exec "$@"
fi
exec hermes
