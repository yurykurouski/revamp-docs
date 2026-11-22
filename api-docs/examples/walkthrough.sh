#!/usr/bin/env bash
# The tutorial (guides/tutorial-lead-to-outreach.md) as one script: sign in, add a lead, wait for its prototype, read
# it and send a test email. It stops before approval, so it never emails a business.
#
#   API=http://localhost:4000/api/v1 EMAIL=demo-owner@revamp-demo.test PASSWORD=… \
#   SITE=https://smile-dental.example TEST_EMAIL=you@your-studio.test ./walkthrough.sh
#
# Needs curl and jq. Every value comes from the environment; nothing secret is stored in this file.
set -euo pipefail

API=${API:-http://localhost:4000/api/v1}
: "${EMAIL:?set EMAIL}" "${PASSWORD:?set PASSWORD}" "${SITE:?set SITE}"

say() { printf '\n== %s\n' "$*"; }

# Fails with the API's error code and message instead of a jq error
call() {
  local out
  out=$(curl -sS "$@")
  if [[ $(jq -r '.success // empty' <<<"$out") == "false" ]]; then
    jq -r '"API error \(.error.code): \(.error.message)"' <<<"$out" >&2
    return 1
  fi
  printf '%s' "$out"
}

say "Health"
curl -sS "$API/health" | jq -c .services

say "Sign in as $EMAIL"
TOKEN=$(call "$API/auth/login" -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg e "$EMAIL" --arg p "$PASSWORD" '{email:$e,password:$p}')" | jq -r .data.token)
AUTH="Authorization: Bearer $TOKEN"

say "Providers"
call "$API/mvp/providers" -H "$AUTH" | jq -c '.data | {workersOnline, providers: [.providers[] | {id, available}]}'

say "Add lead for $SITE"
BODY=$(jq -nc --arg u "$SITE" '{businessName: ($u | sub("^https?://"; "") | sub("/.*$"; "")), originalUrl: $u, niche: "other", operatorLocale: "en"}')
if ! LEAD=$(call "$API/leads" -H "$AUTH" -H 'Content-Type: application/json' -d "$BODY"); then
  echo "If the code was LEAD_ALREADY_EXISTS, set LEAD_ID to the existing lead and skip this step." >&2
  exit 1
fi
LEAD_ID=$(jq -r .data.id <<<"$LEAD")
jq -c '{message, id: .data.id, status: .data.lead.status}' <<<"$LEAD"

say "Wait for the prototype (up to 10 minutes)"
for _ in $(seq 1 120); do
  STATUS=$(call "$API/leads/$LEAD_ID" -H "$AUTH" | jq -r .data.lead.status)
  echo "status: $STATUS"
  [[ $STATUS =~ ^(NEEDS_APPROVAL|AUDIT_FAILED)$ ]] && break
  sleep 5
done
[[ $STATUS == NEEDS_APPROVAL ]] || { echo "Stopped at $STATUS; see lead.auditError / lead.generationFailure" >&2; exit 1; }

say "Audit"
call "$API/leads/$LEAD_ID" -H "$AUTH" | jq '.data.audit | {scores, webVitals, measurementErrors}'

say "Prototype"
call "$API/mvp/$LEAD_ID" -H "$AUTH" | jq '.data | {fullPreviewUrl, provider, modelUsed, versions: [.versions[]? | {n, kind}], grounding: (.grounding | length)}'

if [[ -n ${TEST_EMAIL:-} ]]; then
  say "Test email to $TEST_EMAIL"
  call "$API/outreach/$LEAD_ID/test" -H "$AUTH" -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg t "$TEST_EMAIL" '{testEmail:$t, subject:"Your new home page", body:"Hello,\n\nwe made a faster version of your home page.\n\nBest regards"}')" | jq -c .data
fi

say "Done. Approve in the dashboard, or: POST $API/outreach/$LEAD_ID/approve {subject, body}"
