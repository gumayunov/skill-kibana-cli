#!/usr/bin/env bash
# Full-format renderer for kibana-cli.
# Reads an ES `_search` response from stdin and emits, per hit:
#   <short-line>
#   ---
#   <pretty-printed _source>
# Uses jq's native pretty-printer (default 2-space indent) for the JSON block
# and reuses the short-line definitions from bin/format_one.jq.
#
# Env:
#   MAX_LEN — truncate short line to N chars (default 0 = no truncate).
if (( BASH_VERSINFO[0] < 4 )); then
  echo "format-full.sh: bash >= 4 required (found $BASH_VERSION)" >&2
  exit 1
fi
set -euo pipefail
# Silently exit when downstream (head/less/...) closes the pipe.
trap 'exit 0' PIPE

BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
MAX_LEN="${MAX_LEN:-0}"

# Stream full hits as NUL-separated compact JSON so multi-line payloads survive.
# Each record carries _index/_id/_source so the short line can embed a truncation
# marker pointing at the hit. Process substitution keeps the while loop in the
# main shell so the PIPE trap applies.
while IFS= read -r -d '' hit; do
  # Short line: wrap the single hit back into a `_search`-shaped envelope and
  # reuse format.jq so truncation logic lives in one place.
  printf '%s\n' "$hit" | jq -c '{hits: {total: {value: 1}, hits: [.]}}' \
    | jq -r -L "$BIN_DIR" --arg fmt short --argjson maxlen "$MAX_LEN" -f "$BIN_DIR/format.jq"
  printf -- '---\n'
  printf '%s\n' "$hit" | jq '._source'
done < <(jq -j '.hits.hits[] | tojson + "\u0000"')
