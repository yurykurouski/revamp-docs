# Tutorial: from a website to an approved email

This tutorial walks the whole pipeline through the API, the way the dashboard does it: add a business, wait for the audit and the prototype, read the result, change the page, send yourself a test email and approve the outreach. It takes about five minutes of waiting, mostly for the audit and the model.

Prerequisites: the stack is running and you have a token of an `owner` or `operator` ([getting-started.md](getting-started.md)). The script version is [`../examples/walkthrough.sh`](../examples/walkthrough.sh).

```bash
API=http://localhost:4000/api/v1
AUTH="Authorization: Bearer $TOKEN"
```

> **Safety:** step 7 queues a real email to the business's address. On a development stack use a lead whose email you own, or stop after step 6. The demo leads from `npm run db:seed` use `.test` addresses, which never deliver.

## 1. Check which model will write the page

```bash
curl -s "$API/mvp/providers" -H "$AUTH" | jq '.data | {workersOnline, defaultProvider, providers: [.providers[] | {id, available, reason}]}'
```

If `workersOnline` is `false`, start the workers (`npm run dev:workers`). A provider with `available: false` and `reason: "missing_api_key"` needs its key in `.env`. The audit itself needs no LLM key, but the design critique and the page do.

## 2. Add the business

```bash
LEAD=$(curl -s "$API/leads" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"businessName":"Smile Dental Clinic","originalUrl":"https://smile-dental.example","niche":"dental","city":"Vilnius","operatorLocale":"en"}')
echo "$LEAD" | jq '{message, id: .data.id, status: .data.lead.status, auditId: .data.auditId}'
LEAD_ID=$(echo "$LEAD" | jq -r .data.id)
```

```json
{ "message": "Lead created and audit queued successfully", "id": "6740a1f09d4e5a0012ab35aa", "status": "QUEUED", "auditId": "6740a1f09d4e5a0012ab35ab" }
```

What can go wrong here:

| Answer | Meaning | Do |
| --- | --- | --- |
| `409 LEAD_ALREADY_EXISTS` | Your studio already pursues this site | Use `error.details.leadId` |
| `400 VALIDATION_ERROR` | e.g. `businessName` shorter than 2 characters | Fix the field named in `error.message` |
| `503 AUDIT_QUEUE_UNAVAILABLE` | Redis did not accept the job; the lead is `AUDIT_FAILED` | Retry: `POST /audits/trigger {"leadId": …}` |

If another studio already audited this site, the answer says `Lead created with the audit of this site; MVP generation queued` and the lead starts at `AUDITED`.

## 3. Wait for the audit and the prototype

The audit worker opens the site in Chromium (desktop and mobile), measures LCP/CLS, runs axe-core, extracts contacts, colors and content, and asks the Vision model for a design critique. When it finishes it queues the page generation itself. Poll the lead:

```bash
until STATUS=$(curl -s "$API/leads/$LEAD_ID" -H "$AUTH" | jq -r .data.lead.status); \
      [[ "$STATUS" =~ ^(NEEDS_APPROVAL|AUDIT_FAILED)$ ]]; do
  echo "status: $STATUS"; sleep 5
done; echo "status: $STATUS"
```

`QUEUED → AUDITING → AUDITED → GENERATING → NEEDS_APPROVAL`. If it stops at `AUDIT_FAILED`, read `lead.auditError`. If it comes back to `AUDITED` with `lead.generationFailure`, the model gave no usable page: start the generation again with step 3b.

### 3b. (Optional) Generate with a chosen model

```bash
curl -s "$API/mvp/generate" -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"auditId\":\"$LEAD_ID\",\"provider\":\"anthropic\",\"forceRegenerate\":true}" | jq
```

`auditId` accepts the lead id. Without `forceRegenerate` a lead that already has an MVP answers `409 MVP_ALREADY_GENERATED`.

## 4. Read the audit and the prototype

```bash
curl -s "$API/leads/$LEAD_ID" -H "$AUTH" \
  | jq '.data.audit | {scores, webVitals, measurementErrors, contacts: .extractedContacts}'
curl -s "$API/mvp/$LEAD_ID" -H "$AUTH" \
  | jq '.data | {fullPreviewUrl, provider, modelUsed, completeness: .completenessReport.score, versions: [.versions[] | {n, kind}], grounding}'
```

* Scores and vitals are measured by code; a measurement that failed is absent and listed in `measurementErrors`.
* `grounding` lists facts on the page that the original site does not support. Check them before approving.
* `fullPreviewUrl` opens the published page. In a browser UI, embed it only in `<iframe sandbox="allow-scripts allow-same-origin">`.

## 5. Change the page

In your own words (the request waits for the model, up to 420 s):

```bash
MVP_ID=$(curl -s "$API/mvp/$LEAD_ID" -H "$AUTH" | jq -r .data._id)
curl -s "$API/mvp/$MVP_ID/edit" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"instruction":"Move the booking button above the services list","operatorLocale":"en"}' \
  | jq '{message, applied: .data.applied, version: .data.version}'
```

Or set colors and fonts without a model call (contrast of the text on `bg` and `surface` must be at least 4.5:1):

```bash
curl -s -X PATCH "$API/mvp/$MVP_ID/tokens" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"colors":{"primary":"#0f4c81","accent":"#f2a541","bg":"#ffffff","surface":"#f4f6f8","text":"#1b1f24"},"fonts":{"heading":"Poppins","body":"Inter"}}' \
  | jq '{message, applied: .data.applied}'
```

Go back to version 1 if you prefer it:

```bash
curl -s -X POST "$API/mvp/$MVP_ID/versions/1/restore" -H "$AUTH" | jq '{applied: .data.applied, version: .data.version}'
```

A `502 MVP_EDIT_FAILED` means nothing was published; `details.problems` lists the checks the page failed. A `504 MVP_EDIT_TIMEOUT` means reload the MVP before you try again.

## 6. Send yourself a test email

The test goes to your address, not to the business, so it needs no approval and changes nothing:

```bash
curl -s "$API/outreach/$LEAD_ID/test" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"testEmail":"you@your-studio.test","subject":"A new home page for Smile Dental Clinic","body":"Hello,\n\nwe made a faster, mobile-friendly version of your home page.\n\nBest regards"}' | jq
```

`409 SENDER_NOT_CONFIGURED` means the studio has no sender yet: the owner sets it with `PUT /organization/sender` (`{ name, address }`). Sends are simulated ([REV-221](https://linear.app/revamp-proect/issue/REV-221)): the test answers `{ to, from, subject, simulated: true }`, and after approval the recorded email is at `GET /outreach/{id}/outbox`.

## 7. Approve (or reject) the outreach

This is the Human-in-the-Loop gate: the only call that leads to an email to the business.

```bash
curl -s "$API/outreach/$LEAD_ID/approve" -H "$AUTH" -H 'Content-Type: application/json' \
  -d '{"subject":"A new home page for Smile Dental Clinic","preheader":"We rebuilt your page from your own content","body":"Hello,\n\nwe made a faster, mobile-friendly version of your home page.\n\nBest regards"}' \
  | jq '.data | {status, delayMs, campaignId}'
```

The lead becomes `SCHEDULED` and the email leaves 15–45 s later. Approving twice is harmless: the second call answers `409 LEAD_NOT_AWAITING_APPROVAL`. A lead with no email answers `409 NO_CONTACT_EMAIL`.

Not convinced by the prototype? Reject instead, before approval:

```bash
curl -s "$API/outreach/$LEAD_ID/reject" -H "$AUTH" -H 'Content-Type: application/json' -d '{"reason":"Site was rebuilt last month"}' | jq .data.status
```

## 8. Follow the engagement

The email carries an open pixel (`/track/open/{token}.gif`), a tracked link (`/track/click/{token}`) and an unsubscribe link; the prototype page sends dwell time and CTA clicks (`/track/mvp-event`). Watch the lead move on:

```bash
curl -s "$API/leads/$LEAD_ID" -H "$AUTH" | jq -r .data.lead.status   # SENT → OPENED → CLICKED → ENGAGED
curl -s "$API/leads/stats" -H "$AUTH" | jq .data.byStatus
```
