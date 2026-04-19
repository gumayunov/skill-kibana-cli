#!/usr/bin/env bash
#
# Create a read-only Kibana API key for kibana-cli and print the encoded value.
#
# Required env:
#   KIBANACLI_HOST            — https://logs.<host>
#   KIBANACLI_ADMIN_USER      — ES admin user (default: elastic)
#   KIBANACLI_ADMIN_PASS      — ES admin password
# Optional:
#   KIBANACLI_KEY_NAME        — API-key name (default: kibana-cli)
#   KIBANACLI_INDEX_PATTERN   — index privileges pattern (default: logstash-*)
#
# Writes a JSON response to stderr and the `encoded` value to stdout.
#
# Under the hood: POST /api/console/proxy?path=_security/api_key&method=POST,
# since Kibana 8.5 doesn't expose /api/security/api_key directly.
#
# The role_descriptor grants:
#   - cluster: monitor
#   - index logstash-*: read, view_index_metadata, monitor (for _cat/indices)
#   - Kibana app: feature_dev_tools.all (required to use /api/console/proxy)

if (( BASH_VERSINFO[0] < 4 )); then
  echo "api-key-create.sh: bash >= 4 required (found $BASH_VERSION)" >&2
  exit 1
fi
set -euo pipefail

: "${KIBANACLI_HOST:?set KIBANACLI_HOST (e.g. https://logs.example.com)}"
: "${KIBANACLI_ADMIN_PASS:?set KIBANACLI_ADMIN_PASS}"
ADMIN_USER="${KIBANACLI_ADMIN_USER:-elastic}"
KEY_NAME="${KIBANACLI_KEY_NAME:-kibana-cli}"
INDEX_PATTERN="${KIBANACLI_INDEX_PATTERN:-logstash-*}"

body=$(jq -n \
  --arg name "$KEY_NAME" \
  --arg pattern "$INDEX_PATTERN" \
  '{
    name: $name,
    role_descriptors: {
      kibana_cli_reader: {
        cluster: ["monitor"],
        index: [{names: [$pattern], privileges: ["read", "view_index_metadata", "monitor"]}],
        applications: [{
          application: "kibana-.kibana",
          privileges: ["feature_dev_tools.all"],
          resources: ["*"]
        }]
      }
    }
  }')

resp=$(curl --fail-with-body -sS \
  -u "${ADMIN_USER}:${KIBANACLI_ADMIN_PASS}" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -X POST "${KIBANACLI_HOST%/}/api/console/proxy?path=_security%2Fapi_key&method=POST" \
  -d "$body")

echo "$resp" >&2
id=$(echo "$resp" | jq -r '.id // empty')
enc=$(echo "$resp" | jq -r '.encoded // empty')
if [[ -z "$enc" ]]; then
  echo "api-key-create.sh: no encoded value in response — see stderr" >&2
  exit 1
fi
echo "api-key-create.sh: created key id=$id name=$KEY_NAME" >&2
echo "$enc"
