#!/usr/bin/env bash
# verify.sh — post-deploy verification, run on the GitHub self-hosted runner
# against the target node's HTTP endpoint. Exits non-zero on any failure.
#
#     bash verify.sh http://<target-ip>
#
# Checks:
#   - Service availability and Lab 1 nginx routing rules:
#     * GET  /                       -> 200
#     * GET  /tasks                  -> 200 (JSON list)
#     * POST /tasks {title}          -> 201 (creates task)
#     * POST /tasks/<id>/done        -> 200
#     * GET  /tasks/<id>/done        -> 403 (limit_except denies)
#     * PUT  /tasks                  -> 403 (limit_except denies)
#     * GET  /something/else         -> 404

set -euo pipefail

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
    echo "usage: $0 <base-url>" >&2
    exit 2
fi

PASS=0
FAIL=0

check() {
    local label="$1" method="$2" path="$3" expected="$4"
    shift 4
    local actual
    actual=$(curl -sS -o /tmp/verify.body -w "%{http_code}" \
        -X "$method" --max-time 10 "$@" "${BASE_URL}${path}" || echo "000")
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS  ${label}  -> ${actual}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  ${label}  expected=${expected} actual=${actual}"
        echo "        body: $(head -c 200 /tmp/verify.body)"
        FAIL=$((FAIL + 1))
    fi
}

echo "==> verify.sh against ${BASE_URL}"

check "index"                 GET    "/"                        200
check "list tasks"            GET    "/tasks"                   200 \
        -H "Accept: application/json"

# Create a task and grab its id for the next two checks.
create_resp="$(curl -sS -X POST "${BASE_URL}/tasks" \
    -H 'Content-Type: application/json' \
    -d '{"title":"verify-script"}')"
NEW_ID="$(echo "$create_resp" | sed -n 's/.*"id":[[:space:]]*\([0-9]*\).*/\1/p')"
if [[ -z "$NEW_ID" ]]; then
    echo "  FAIL  create task did not return an id; body=$create_resp"
    FAIL=$((FAIL + 1))
else
    echo "  PASS  create task   -> id=${NEW_ID}"
    PASS=$((PASS + 1))
fi

if [[ -n "$NEW_ID" ]]; then
    check "mark done"             POST   "/tasks/${NEW_ID}/done"   200
    check "GET on done is 403"    GET    "/tasks/${NEW_ID}/done"   403
fi

check "PUT /tasks is 403"     PUT    "/tasks"                   403 \
        -H 'Content-Type: application/json' -d '{}'
check "unknown path is 404"   GET    "/something/else"          404

echo
echo "==> ${PASS} passed, ${FAIL} failed"
[[ "$FAIL" -eq 0 ]]
