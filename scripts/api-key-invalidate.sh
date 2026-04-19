#!/usr/bin/env bash
#
# Invalidate all Kibana API keys with a given name.
#
# Usage:
#   api-key-invalidate.sh [<name>]
#
# Default name: kibana-cli (matches api-key-create.sh default).
#
# Required env:
#   KIBANACLI_HOST
#   KIBANACLI_ADMIN_PASS
# Optional:
#   KIBANACLI_ADMIN_USER (default: elastic)

if (( BASH_VERSINFO[0] < 4 )); then
  echo "api-key-invalidate.sh: bash >= 4 required (found $BASH_VERSION)" >&2
  exit 1
fi
set -euo pipefail

: "${KIBANACLI_HOST:?set KIBANACLI_HOST}"
: "${KIBANACLI_ADMIN_PASS:?set KIBANACLI_ADMIN_PASS}"
ADMIN_USER="${KIBANACLI_ADMIN_USER:-elastic}"
NAME="${1:-${KIBANACLI_KEY_NAME:-kibana-cli}}"

resp=$(curl --fail-with-body -sS \
  -u "${ADMIN_USER}:${KIBANACLI_ADMIN_PASS}" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "${KIBANACLI_HOST%/}/api/console/proxy?path=_security%2Fapi_key&method=DELETE" \
  -d "$(jq -n --arg n "$NAME" '{name: $n}')")

count=$(echo "$resp" | jq -r '.invalidated_api_keys // [] | length')
errs=$(echo "$resp" | jq -r '.error_count // 0')
echo "api-key-invalidate.sh: invalidated $count key(s) named '$NAME' (errors: $errs)" >&2
echo "$resp" | jq -c '{invalidated_api_keys, error_count}'
