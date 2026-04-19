#!/usr/bin/env bash
#
# Interactive one-shot setup for kibana-cli:
#   1. Read KIBANACLI_HOST and admin password (from env or prompt).
#   2. Create API-key via api-key-create.sh.
#   3. Write ~/.config/kibana-cli/env.
#   4. Smoke-test --list-indices.
#
# Env:
#   KIBANACLI_HOST                       — e.g. https://logs.example.com (prompted if missing)
#   KIBANACLI_ADMIN_USER                 — default: elastic
#   KIBANACLI_ADMIN_PASS                 — prompted if missing (read -s)
#   KIBANACLI_DEFAULT_NAMESPACE          — prompted if missing (empty = no default)
#   KIBANACLI_KEY_NAME                   — default: kibana-cli
#   KIBANACLI_ENV                        — default: ~/.config/kibana-cli/env

if (( BASH_VERSINFO[0] < 4 )); then
  echo "setup.sh: bash >= 4 required (found $BASH_VERSION)" >&2
  exit 1
fi
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
skill_dir=$(dirname "$here")

if [[ -z "${KIBANACLI_HOST:-}" ]]; then
  read -rp "KIBANACLI_HOST (e.g. https://logs.example.com): " KIBANACLI_HOST
fi
if [[ -z "${KIBANACLI_ADMIN_PASS:-}" ]]; then
  read -rsp "Elasticsearch admin password: " KIBANACLI_ADMIN_PASS
  echo
fi
export KIBANACLI_HOST KIBANACLI_ADMIN_PASS

if [[ -z "${KIBANACLI_DEFAULT_NAMESPACE+x}" ]]; then
  read -rp "KIBANACLI_DEFAULT_NAMESPACE (kubernetes_namespace_name for --namespace default; blank = no default): " KIBANACLI_DEFAULT_NAMESPACE
fi
default_ns="${KIBANACLI_DEFAULT_NAMESPACE}"
env_file="${KIBANACLI_ENV:-$HOME/.config/kibana-cli/env}"

encoded=$("$here/api-key-create.sh")

mkdir -p "$(dirname "$env_file")"
chmod 700 "$(dirname "$env_file")"
cat > "$env_file" <<EOF
KIBANACLI_HOST=$KIBANACLI_HOST
KIBANACLI_API_KEY=$encoded
KIBANACLI_DEFAULT_NAMESPACE=$default_ns
EOF
chmod 600 "$env_file"
echo "setup.sh: wrote $env_file" >&2

echo >&2
echo "=== smoke: --list-indices (first 3 lines) ===" >&2
"$skill_dir/bin/kibana-cli" --list-indices | head -3
echo >&2
echo "=== smoke: --since 10m --limit 3 ===" >&2
"$skill_dir/bin/kibana-cli" --since 10m --limit 3 || true
echo >&2
echo "setup.sh: done. Edit $env_file to change defaults." >&2
