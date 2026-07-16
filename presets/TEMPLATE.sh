#!/usr/bin/env bash
# TEMPLATE for a project-local preset: a thin `exec kibana-cli <default flags>`
# wrapper that bakes in the filters one keeps re-typing for a given project.
#
# How to use this template (see also "Пресеты" in SKILL.md):
#   1. Copy into the project as .kibana-cli/<name>.sh (next to .kibana-cli/env)
#      and `chmod +x` it.
#   2. Replace the placeholder flags below with the project's defaults:
#      index pattern, cluster/container filters, noise excludes, etc.
#   3. Keep "$@" last — callers append/override flags freely
#      (later flags win for scalars like --since; repeatable flags accumulate).
#   4. Document one usage example in the header comment.
#
# Example invocation once installed:
#   .kibana-cli/<name>.sh --since 30m --level error
set -euo pipefail

# Pin the config to the env file living next to this preset, so the preset
# works from any cwd (not only from inside the project tree).
dir=$(cd "$(dirname "$0")" && pwd)
export KIBANACLI_ENV="$dir/env"

# Locate kibana-cli: $KIBANACLI_BIN (settable in the env file) or PATH.
[[ -r "$KIBANACLI_ENV" ]] && . "$KIBANACLI_ENV"
kcli=${KIBANACLI_BIN:-$(command -v kibana-cli || true)}
[[ -n "$kcli" ]] || { echo "$(basename "$0"): kibana-cli not found — add it to PATH or set KIBANACLI_BIN in $KIBANACLI_ENV" >&2; exit 1; }

exec "$kcli" \
  --index 'CHANGE-ME-index-pattern*' \
  --filter-phrase 'CHANGE-ME.field=value' \
  --exclude-phrase 'CHANGE-ME.noisy_field=value' \
  "$@"
