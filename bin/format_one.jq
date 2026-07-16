# Short-line formatter for a single `_source` document.
# Consumed via `include "format_one";` from format.jq and format-full.sh.
# Exposes `short_line` and `truncate_with_id($n; $idx; $id)` plus the helpers they rely on.
#
# Configurable via environment (set in the kibana-cli env file, see README):
#   KIBANACLI_MESSAGE_FIELDS — comma-separated field names to use as the line
#     body, first non-empty wins (default: event,log,message)
#   KIBANACLI_CONTEXT_FIELDS — comma-separated whitelist for the k=v context
#     tail; empty/unset = all fields except reserved ones. Dotted paths
#     (named_tags.queue) address nested objects in both variables.

# Read a possibly-nested field by dotted path; null when absent/unreachable.
def field($f): try getpath($f | split(".")) catch null;

def msg_fields:
  (env.KIBANACLI_MESSAGE_FIELDS // "") as $v
  | if $v == "" then ["event","log","message"] else ($v | split(",")) end;

# Fields excluded from k=v context (short mode): built-ins + message fields.
def reserved:
  ["@timestamp","time","stream","_p","level","logger","timestamp"] + msg_fields;

def kv_pairs:
  (env.KIBANACLI_CONTEXT_FIELDS // "") as $cf
  | if $cf == "" then
      to_entries
      | map(select(
          (.key | startswith("kubernetes_") | not)
          and (.key as $k | reserved | index($k) | not)
        ))
      | sort_by(.key)
      | map("\(.key)=\(.value | if type == "string" then . else tostring end)")
      | join(" ")
    else
      . as $src
      | ($cf | split(","))
      | map(. as $f
          | ($src | field($f)) as $v
          | select($v != null)
          | "\($f)=\($v | if type == "string" then . else tostring end)")
      | join(" ")
    end;

def ts_short: (.["@timestamp"] // "?") | sub("\\.[0-9]+Z$"; "Z");

def level_tag:
  if .level then "[\(.level)]" else "[raw]" end;

def container:
  .kubernetes_container_name
  // (.kubernetes | if type == "object" then .container_name else null end)
  // "?";

def body:
  . as $src
  | (msg_fields | map(. as $f | ($src | field($f)) | select(. != null and . != "")) | first)
  // "";

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
