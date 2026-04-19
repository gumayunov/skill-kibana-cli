#!/usr/bin/env bash
# Usage: service.sh <service> [extra kibana-cli flags]
#
# Prints logs for the given container name in the default namespace.
# Examples:
#   service.sh worker
#   service.sh api --since 30m --level warning
set -eu
SVC=${1:?"usage: service.sh <service> [extra flags]"}
shift
exec "$(dirname "$0")/../bin/kibana-cli" --service "$SVC" "$@"
