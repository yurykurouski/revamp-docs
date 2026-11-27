# Errors

## Structure

Every error, from every route, has one shape (REV-63):

```json
{
  "success": false,
  "error": {
    "code": "LEAD_NOT_AUDITABLE",
    "message": "An audit cannot be started while the lead is NEEDS_APPROVAL",
    "details": { "status": "NEEDS_APPROVAL" }
  }
}
```

| Field | Contract |
| --- | --- |
| `code` | Stable, machine-readable, one of `API_ERROR_CODES` (`@revamp/shared-types`). **Branch on this.** |
| `message` | English text for a person. May change at any time; never parse it. |
| `details` | Optional, machine-readable context; its shape per code is listed below. |

Only `errorHandler` (`apps/api/src/middlewares/errorHandler.ts`) writes error JSON. Routes throw `AppError(status, code, message, details?)`; Zod, Mongoose and body-parser errors are mapped to codes. A new code must be added to `API_ERROR_CODES`, to the `ApiErrorCode` enum in the reference, and to this page.

Two routes answer differently on purpose: `GET /health` returns its status report with `503`, and `/track/unsubscribe/{token}` returns HTML pages, because people open them in a browser.

## How a client should react

| HTTP | Meaning | Recovery |
| --- | --- | --- |
| `400` | The request is wrong | Fix the input; `details.issues` (Zod) says which field |
| `401` | No valid session | Sign in again; the dashboard signs out and goes to `/login` |
| `403` | The role does not allow it | Refresh the session context (`GET /auth/me`): the role may have changed |
| `404` | Not found **or another studio's** | Treat as gone; do not retry |
| `409` | The resource is in the wrong state | Reload it; `details.status` says its current state |
| `410` | The invitation is no longer usable | Ask the owner for a new one |
| `413` | Body over 10 MB | Send less |
| `500` | Unexpected | Retry later; the server logged it (`[Unhandled Error]`) |
| `502` | A provider failed (LLM, email, geocoding) | Retry; nothing was changed |
| `503` | A queue or provider is unavailable | The record was left in a known state; retry the action |
| `504` | A worker did not finish in time | Reload the resource before retrying: the work may still complete |

## Every code

### General (written by the error handler)

| Code | HTTP | When | `details` |
| --- | --- | --- | --- |
| `VALIDATION_ERROR` | 400 | Body, query or params fail the Zod schema; `message` is the first issue as `path: message` | `{ issues: ZodIssue[] }` |
| `INVALID_ID` | 400 | An id is not a 24-character hexadecimal ObjectId | — |
| `INVALID_JSON` | 400 | The body is not valid JSON | — |
| `PAYLOAD_TOO_LARGE` | 413 | The body exceeds 10 MB | — |
| `DUPLICATE` | 409 | A unique index rejected the write (MongoDB code 11000) | — |
| `NOT_FOUND` | 404 | No such route | — |
| `INTERNAL` | 500 | Anything unexpected; in production the message is `Internal server error` | — |

### Accounts, roles and invitations

| Code | HTTP | When |
| --- | --- | --- |
| `UNAUTHENTICATED` | 401 | No token, a wrong or expired token, or the membership/studio in it no longer exists |
| `INVALID_CREDENTIALS` | 401 | Login or join: wrong password or unknown email (indistinguishable on purpose) |
| `EMAIL_TAKEN` | 409 | Register: an account with this email exists (any letter case) |
| `FORBIDDEN` | 403 | A viewer changing data, or a non-owner on `/organization/*` |
| `ALREADY_MEMBER` | 409 | Inviting or accepting for someone who is already a member |
| `LAST_OWNER` | 409 | Demoting or removing the studio's last owner |
| `MEMBER_NOT_FOUND` | 404 | No such member in the studio |
| `INVITATION_NOT_FOUND` | 404 | Unknown invitation token or id |
| `INVITATION_EXPIRED` | 410 | Expired (7 days), used or revoked |
| `INVITATION_EMAIL_MISMATCH` | 403 | The invitation is for another address |

### Leads and audits

| Code | HTTP | When | `details` |
| --- | --- | --- | --- |
| `INVALID_URL` | 400 | `originalUrl` cannot be parsed | — |
| `LEAD_ALREADY_EXISTS` | 409 | The studio already has a lead for this site | `{ leadId }`: open that lead instead |
| `CONTACT_RIGHT_HELD` | 409 | Add lead or import: another studio holds the right to contact this business (REV-225) | `{ expiresAt }`; the other studio is never named |
| `BUSINESS_IN_COOLDOWN` | 409 | Add lead or import: a right for this business ended recently; every studio waits | `{ availableAt }` |
| `BUSINESS_OPTED_OUT` | 409 | Add lead, import or approve: the business, or its contact address under any business, asked not to be contacted (REV-225, REV-227) | — |
| `LEAD_NOT_FOUND` | 404 | No such lead in the studio | — |
| `LEAD_NOT_AUDITABLE` | 409 | Audit requested for a lead not in `QUEUED`/`AUDIT_FAILED`, or it changed meanwhile | `{ status }` |
| `AUDIT_NOT_FOUND` | 404 | No audit the studio may read | — |
| `AUDIT_QUEUE_UNAVAILABLE` | 503 | The lead was saved but the audit job was not queued within 5 s; the lead is now `AUDIT_FAILED` | `{ leadId }`: retry with `POST /audits/trigger` |

### MVP

| Code | HTTP | When | `details` |
| --- | --- | --- | --- |
| `LLM_PROVIDER_NOT_ALLOWED` | 400 | A dev-only provider requested in production | — |
| `NO_COMPLETED_AUDIT` | 404 | Generation requested, but the lead has no completed audit | — |
| `MVP_GENERATION_NOT_ALLOWED` | 409 | Generation running, outreach scheduled or sent, or the lead changed meanwhile | `{ status }` |
| `MVP_ALREADY_GENERATED` | 409 | An MVP exists and `forceRegenerate` was not set | `{ status }` |
| `MVP_NOT_FOUND` | 404 | No such MVP in the studio | — |
| `MVP_EDIT_NOT_ALLOWED` | 409 | Change, colors or restore while the lead is not `NEEDS_APPROVAL` | `{ status }` |
| `MVP_PREVIOUS_GENERATOR` | 409 | The MVP was made by the previous generator; only a regeneration applies | — |
| `MVP_VERSION_NOT_FOUND` | 404 | Restore of a version that is not stored | — |
| `MVP_VERSION_UNUSABLE` | 409 | The version no longer passes the page checks against the current audit; nothing published | `{ problems: [{ code, message }] }` |
| `MVP_EDIT_FAILED` | 502 | The worker or the model gave no usable page; nothing published | `{ reason: not_configured \| call_failed \| invalid_page, problems? }` |
| `MVP_EDIT_TIMEOUT` | 504 | No result within 420 s (change) or 120 s (colors, restore); the message says whether it may still publish | — |
| `PREVIEW_NOT_FOUND` | 404 | No published page for this slug | — |

`problems[].code` is one of `MVP_PAGE_CHECKS`: `page:parse`, `page:script`, `page:external`, `page:image`, `page:css`, `page:theme`, `page:placeholder`, `page:contact`, `page:h1`, `page:lang`.

### Outreach

| Code | HTTP | When | `details` |
| --- | --- | --- | --- |
| `LEAD_NOT_AWAITING_APPROVAL` | 409 | Approve while the lead is not `NEEDS_APPROVAL` (including a concurrent second approval) | — |
| `LEAD_NOT_REJECTABLE` | 409 | Reject after approval, or of a closed lead | — |
| `NO_CONTACT_EMAIL` | 409 | Approve a lead with no email; add one first (none is invented) | — |
| `EMAIL_QUEUE_UNAVAILABLE` | 503 | Approval written, but the send was not queued within 5 s; lead and campaign are back in `NEEDS_APPROVAL`, nothing will be sent | `{ leadId }` |
| `CONTACT_RIGHT_REQUIRED` | 409 | Approve while the studio holds no active right to contact the lead's business (expired or ended, REV-226) | `{ expiredAt }` when the studio had a right |
| `SENDER_NOT_CONFIGURED` | 409 | Approve or test send while the studio has no sender; the owner sets it with `PUT /organization/sender` | — |
| `OUTBOX_NOT_FOUND` | 404 | `GET /outreach/{id}/outbox` for a lead with no recorded email | — |
| `EMAIL_TEST_TIMEOUT` | 504 | The workers did not answer the test send within 30 s | — |
| `EMAIL_SEND_FAILED` | 502 | The workers could not render the simulated test message | — |

### Discovery

| Code | HTTP | When |
| --- | --- | --- |
| `DISCOVERY_JOB_NOT_FOUND` | 404 | Unknown job, or another studio's |
| `DISCOVERY_JOB_NOT_COMPLETED` | 409 | Import before the search finished; poll the job first |
| `GEOCODING_UNAVAILABLE` | 502 | Nominatim failed |
| `PLACE_NOT_FOUND` | 404 | No city at these coordinates |

## Validation errors in detail

```json
{
  "success": false,
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "originalUrl: Invalid url",
    "details": {
      "issues": [
        { "validation": "url", "code": "invalid_string", "message": "Invalid url", "path": ["originalUrl"] }
      ]
    }
  }
}
```

`issues` is Zod's list: `path` names the field (array indices included), `code` the kind of failure (`invalid_type`, `too_small`, `too_big`, `invalid_string`, `invalid_enum_value`, `unrecognized_keys`, `custom`, …). A form can map each issue to its field by `path[0]`.
