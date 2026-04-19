#!/usr/bin/env bash
# Usage: errors-last.sh <duration> [extra kibana-cli flags]
#
# Prints error-level logs from the last <duration> in the default namespace.
# Examples:
#   errors-last.sh 1h
#   errors-last.sh 30m --service worker --limit 10
set -eu
DUR=${1:?"usage: errors-last.sh <duration> [extra flags]"}
shift
exec "$(dirname "$0")/../bin/kibana-cli" --level error --since "$DUR" "$@"
