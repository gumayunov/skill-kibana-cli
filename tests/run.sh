#!/usr/bin/env bash
if (( BASH_VERSINFO[0] < 4 )); then
  echo "kibana-cli: bash >= 4 required (found $BASH_VERSION)" >&2
  exit 1
fi
# Minimal test runner: compares actual stdout to expected file.
set -u
cd "$(dirname "$0")"
FAIL=0
run_case() {
  local name=$1 expected=$2; shift 2
  local tmp; tmp=$(mktemp)
  "$@" >"$tmp" 2>&1 || true
  if diff -u "$expected" "$tmp" >/dev/null; then
    echo "PASS $name"
  else
    echo "FAIL $name"
    diff -u "$expected" "$tmp" | head -40 | sed 's/^/  /'
    FAIL=$((FAIL+1))
  fi
  rm -f "$tmp"
}
run_case "help" "cases/help.expected" ../bin/kibana-cli --help
run_case "format-short-structlog" "expected/structlog-short.txt" \
  jq -r -L ../bin --arg fmt short --argjson maxlen 0 -f ../bin/format.jq fixtures/structlog.json
run_case "format-short-raw" "expected/raw-stdout-short.txt" \
  jq -r -L ../bin --arg fmt short --argjson maxlen 0 -f ../bin/format.jq fixtures/raw-stdout.json
run_case "build-query" "cases/build-query.expected.sorted" \
  bash -c "../bin/kibana-cli --since 2h --to 1h --namespace myapp --service worker --level error --query 'task failed' --dump-query | jq -S ."
run_case "format-json-structlog" "expected/structlog-json.txt" \
  bash -c "jq -r -L ../bin --arg fmt json --argjson maxlen 0 -f ../bin/format.jq fixtures/structlog.json"
run_case "format-full-structlog" "expected/structlog-full.txt" \
  bash -c "MAX_LEN=0 ../bin/format-full.sh < fixtures/structlog.json"
run_case "truncate-80" "expected/long-event-short-80.txt" \
  bash -c "jq -r -L ../bin --arg fmt short --argjson maxlen 80 -f ../bin/format.jq fixtures/long-event.json"
run_case "empty-marker" "expected/no-hits-marker.txt" \
  bash -c "../bin/kibana-cli --since 1h --namespace myapp --search-response-from-file fixtures/empty-search.json"
run_case "over-limit-trailer" "expected/over-limit-trailer.txt" \
  bash -c "../bin/kibana-cli --since 1h --namespace myapp --limit 3 --search-response-from-file fixtures/over-limit.json"
run_case "get-short" "expected/structlog-short.txt" \
  bash -c "../bin/kibana-cli-get logstash-2026.04.18/fixture-doc-2 -o short --response-from-file fixtures/single-doc.json"
run_case "filter-exclude-query" "cases/filter-exclude-query.expected.sorted" \
  bash -c "../bin/kibana-cli --since 1h --namespace myapp --filter user_id=abc --filter method=GET --exclude path=/api/health --exclude user_agent=kube-probe/1.34 --dump-query | jq -S ."
run_case "custom-fields-short" "expected/custom-fields-short.txt" \
  bash -c "KIBANACLI_MESSAGE_FIELDS=msg KIBANACLI_CONTEXT_FIELDS=host,named_tags.queue,missing.field jq -r -L ../bin --arg fmt short --argjson maxlen 0 -f ../bin/format.jq fixtures/custom-fields.json"
run_case "custom-message-fields-query" "cases/custom-message-fields.expected" \
  bash -c "KIBANACLI_MESSAGE_FIELDS=msg,description ../bin/kibana-cli --since 1h --query boom --dump-query | jq -c '.query.bool.must[0].simple_query_string.fields'"
run_case "phrase-filters" "cases/phrase-filters.expected.sorted" \
  bash -c "../bin/kibana-cli --since 1h --namespace myapp --filter-phrase kubernetes.cluster_name=k8s-prod01 --filter-phrase kubernetes.container_name=app --exclude-phrase kubernetes.pod_name=canary --exclude user_agent=kube-probe/1.34 --dump-query | jq -S ."
run_case "body-passthrough" "fixtures/custom-body.json" \
  bash -c "../bin/kibana-cli --body fixtures/custom-body.json --dump-query"
run_case "advanced-query" "cases/advanced-query.expected.sorted" \
  bash -c "../bin/kibana-cli --at 2026-04-19T10:30:00Z --until 2026-04-19T11:00:00Z --namespace myapp --service api --gte status=500 --lte duration_ms=5000 --phrase 'duplicate key' --dump-query | jq -S ."
run_case "query-or-phrases-passthrough" "cases/query-or-phrases.expected" \
  bash -c "../bin/kibana-cli --since 1h --namespace myapp --query '\"timeout exceeded\" | \"deadline.reached\"' --dump-query | jq -c '.query.bool.must[0].simple_query_string'"
run_case "query-twice-error" "cases/query-twice.expected" \
  bash -c "../bin/kibana-cli --query a --query b"
run_case "phrase-twice-error" "cases/phrase-twice.expected" \
  bash -c "../bin/kibana-cli --phrase a --phrase b"
exit $(( FAIL > 0 ? 1 : 0 ))
