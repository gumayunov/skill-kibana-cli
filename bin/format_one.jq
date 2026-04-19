# Short-line formatter for a single `_source` document.
# Consumed via `include "format_one";` from format.jq and format-full.sh.
# Exposes `short_line` and `truncate_with_id($n; $idx; $id)` plus the helpers they rely on.

# Fields excluded from k=v context (short mode).
def reserved:
  ["@timestamp","time","stream","_p","event","level","log","message","logger","timestamp"];

def kv_pairs:
  to_entries
  | map(select(
      (.key | startswith("kubernetes_") | not)
      and (.key as $k | reserved | index($k) | not)
    ))
  | sort_by(.key)
  | map("\(.key)=\(.value | if type == "string" then . else tostring end)")
  | join(" ");

def ts_short: (.["@timestamp"] // "?") | sub("\\.[0-9]+Z$"; "Z");

def level_tag:
  if .level then "[\(.level)]" else "[raw]" end;

def container: (.kubernetes_container_name // "?");

def body:
  if .event then .event
  elif .log then .log
  elif .message then .message
  else "" end;

# Pad a string on the right with spaces to at least N chars.
def pad($n):
  if length >= $n then . else . + (" " * ($n - length)) end;

def short_line:
  (ts_short) + " "
  + (level_tag | pad(6)) + " "
  + (container | pad(7)) + " "
  + body
  + (kv_pairs | if . == "" then "" else "  " + . end);

# Truncate the input string to at most $n characters, appending a marker with
# the hit's index/id so an agent can fetch the full document via kibana-cli-get.
# Marker format: " … [truncated: <maxlen>/<total> chars, id=<idx>/<id>]".
# When marker length >= $n, keep the marker anyway (output may slightly exceed $n).
def truncate_with_id($n; $idx; $id):
  if $n <= 0 or (length <= $n) then .
  else
    (. | length) as $total
    | " … [truncated: \($n)/\($total) chars, id=\($idx)/\($id)]" as $marker
    | ($n - ($marker | length)) as $keep
    | (if $keep > 0 then .[0:$keep] else "" end) + $marker
  end;
