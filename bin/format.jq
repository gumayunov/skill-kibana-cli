# Top-level formatter for kibana-cli ES `_search` response.
# Variables (pass via --arg / --argjson):
#   $fmt     — "short" | "full" | "json"
#   $maxlen  — integer: truncate line to this length; 0 = no truncate
#
# Short-line helpers live in format_one.jq (shared with bin/format-full.sh).
# "full" mode is rendered by bin/format-full.sh which needs jq pretty-print
# interleaved with short lines; it is not implemented in this file.

include "format_one";

if $fmt == "json" then
  .hits.hits[] | ._source | tojson
elif $fmt == "short" then
  .hits.hits[]
  | . as $h
  | ($h._source | short_line | truncate_with_id($maxlen; $h._index; $h._id))
else
  # "full" is handled by bin/format-full.sh. Any other value is a bug.
  "format.jq: unsupported $fmt=\($fmt) (use bin/format-full.sh for full)\n" | halt_error(2)
end
