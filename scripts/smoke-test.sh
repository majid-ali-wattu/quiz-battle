#!/usr/bin/env bash
# End-to-end smoke test against a running `docker compose up` stack.
# Exits non-zero on the first failed check.
set -euo pipefail

AUTH_URL=${AUTH_URL:-http://localhost:8001}
GAME_URL=${GAME_URL:-http://localhost:8002}
FRONTEND_URL=${FRONTEND_URL:-http://localhost:5173}

wait_for() {
  # Any HTTP response (even 404/405) means the server is up; curl only fails
  # on connection errors.
  local url=$1
  for _ in $(seq 1 60); do
    if curl -s -o /dev/null "$url"; then return 0; fi
    sleep 2
  done
  echo "Timed out waiting for $url" >&2
  return 1
}

wait_for "$AUTH_URL/api/login/"
wait_for "$GAME_URL/api/rooms/"
wait_for "$FRONTEND_URL"

user="smoke_$(date +%s)"
json='Content-Type: application/json'

curl -sf -X POST "$AUTH_URL/api/register/" -H "$json" \
  -d "{\"username\":\"$user\",\"password\":\"smoke-pass-123\"}" >/dev/null
echo "register ok"

token=$(curl -sf -X POST "$AUTH_URL/api/login/" -H "$json" \
  -d "{\"username\":\"$user\",\"password\":\"smoke-pass-123\"}" | jq -er .token)
echo "login ok"

# Token issued by auth_service must be accepted by game_service (shared secret),
# and game_service must have migrated and seeded its questions on startup.
status=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$GAME_URL/api/rooms/" \
  -H "Authorization: Bearer $token")
if [ "$status" != "201" ]; then
  echo "create room returned $status, expected 201" >&2
  exit 1
fi
echo "create room ok"
