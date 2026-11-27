# API changelog

Changes to the public surface of `/api/v1`, newest first, with the Linear ticket that made each one. The format follows [Keep a Changelog](https://keepachangelog.com/); the specification version (`info.version` in `reference/openapi.yaml`) follows [SemVer](https://semver.org/). Releases before 1.0.0 were not versioned; their entries are grouped by date.

## [2.4.0] — 2026-11-28

### Added
- **The lead's contact right (REV-228).** `GET /leads` items and `GET /leads/{id}` carry `contactRight` (`{ expiresAt, active, endedAt?, endReason? }` or `null`): the studio's newest right on the lead's business, never another studio's.

## [2.3.0] — 2026-11-27

### Changed
- **An opt-out applies to every studio (REV-227).** `POST /track/unsubscribe/{token}` answers as before, but now opts the business out for all studios, stores only a SHA-256 hash of the recipient address, ends the business's contact right, moves every studio's lead for the business to `UNSUBSCRIBED` and closes their unsent campaigns.
- `POST /outreach/{id}/approve` answers `409 BUSINESS_OPTED_OUT` when the business opted out or the lead's contact address is suppressed under any business.
- `Lead.outreachError.code` gains `CONTACT_OPTED_OUT`.

## [2.2.0] — 2026-11-27

### Added
- **Outreach needs an active contact right (REV-226).** `POST /outreach/{id}/approve` answers `409 CONTACT_RIGHT_REQUIRED` (`details.expiredAt`) when the studio holds no active right for the lead's business; nothing is written or queued. Test sends need no right.
- `Lead.outreachError` (`{ code: CONTACT_RIGHT_EXPIRED, message, at }`): set when the email worker stops a send because the right ended; cleared by the next approval.

## [2.1.0] — 2026-11-27

### Added
- **Contact rights on Add lead (REV-225).** `POST /leads` and discovery import claim the studio's exclusive right to contact the business (14 days, then a 30-day cooldown for every studio). A 201 carries `data.contactRight.expiresAt`. Codes `CONTACT_RIGHT_HELD` (`details.expiresAt`), `BUSINESS_IN_COOLDOWN` (`details.availableAt`), `BUSINESS_OPTED_OUT`; none names the other studio.
- Discovery candidates carry `unavailable: { reason, until? }`; import outcomes `right_held`, `cooldown`, `opted_out` with `until`.

## [2.0.0] — 2026-11-25

### Added
- **Studio sender (REV-221).** `PUT /organization/sender` (owners) sets the name and address outreach goes out under; `GET /outreach/sender` (every role) reads it. Code `SENDER_NOT_CONFIGURED`.
- **Simulated outbox (REV-221).** `GET /outreach/{id}/outbox` returns the email recorded for a lead (`deliveryMode: SIMULATED`); nothing is delivered outside the platform. Code `OUTBOX_NOT_FOUND`.

### Changed
- **Breaking (REV-221):** `POST /outreach/{id}/test` answers `{ to, from, subject, simulated: true }` instead of `{ to, messageId, provider, sentAt }`, and `409 SENDER_NOT_CONFIGURED` when the studio has no sender.
- `POST /outreach/{id}/approve` answers `409 SENDER_NOT_CONFIGURED` when the studio has no sender; nothing is written or queued (REV-221).

### Removed
- **Breaking (REV-221):** code `EMAIL_PROVIDER_NOT_CONFIGURED` (`503`); the platform-wide email provider is gone.

## [1.0.0] — 2026-11-22

First versioned specification: `reference/openapi.yaml` (OpenAPI 3.0.3), request schemas generated from `@revamp/validation`, guides and examples.

### Added
- **Studios (REV-209, REV-210).** Every lead, MVP, campaign and event belongs to the caller's studio; another studio's record answers `404` like a missing one.
- **One lead per site and studio (REV-208).** `POST /leads` and discovery import answer `409 LEAD_ALREADY_EXISTS` with `details.leadId`. A site already audited for another studio reuses its audit: the lead starts `AUDITED`.
- **Roles and invitations (REV-207).** `/organization/members`, `/organization/invitations`, `/invitations/{token}`, `/invitations/{token}/join`, `/invitations/{token}/accept`; `invitationToken` in `POST /auth/register`. Codes `FORBIDDEN`, `ALREADY_MEMBER`, `LAST_OWNER`, `MEMBER_NOT_FOUND`, `INVITATION_NOT_FOUND`, `INVITATION_EXPIRED`, `INVITATION_EMAIL_MISMATCH`.
- **Sign-in (REV-206).** `POST /auth/register`, `POST /auth/login`, `GET /auth/me`; every non-public route needs `Authorization: Bearer`. Codes `UNAUTHENTICATED`, `INVALID_CREDENTIALS`, `EMAIL_TAKEN`.

### Changed
- **Breaking (REV-206):** routes other than the public ones answer `401` without a token.
- `POST /outreach/{id}/approve` writes the lead and the campaign in one transaction and answers `503 EMAIL_QUEUE_UNAVAILABLE` when the send cannot be queued (REV-203).
- `POST /leads` writes the lead and its audit in one transaction and answers `503 AUDIT_QUEUE_UNAVAILABLE` when the audit cannot be queued (REV-202).

## 2026-10-10

### Added
- `POST /mvp/{id}/edit` (rewritten for the model-designed page), `PATCH /mvp/{id}/tokens`, `POST /mvp/{id}/versions/{n}/restore` (REV-139). Codes `MVP_PREVIOUS_GENERATOR`, `MVP_VERSION_NOT_FOUND`, `MVP_VERSION_UNUSABLE`.

### Removed
- `PATCH /mvp/{id}/layout` and `DELETE /mvp/{id}/design`, with codes `MVP_MODEL_DESIGNED`, `MVP_LAYOUT_CHANGE_NOT_ALLOWED`, `MVP_PALETTE_CHANGE_NOT_ALLOWED`, `MVP_REBUILD_UNAVAILABLE`, `MVP_MODERNIZE_UNAVAILABLE` (REV-139, REV-141). Replacement: `PATCH /mvp/{id}/tokens` for colors and fonts, `POST /mvp/{id}/edit` for structure.

## 2026-09-27 — 2026-10-04

### Added
- SEO and standards checks on audits and MVPs (`standardsChecks`, `MvpProject.standards`) (REV-118); MVP web vitals measured on publish (`MvpProject.performance`) (REV-119).
- `POST /mvp/{id}/edit`: free-text MVP changes (REV-85).

### Changed
- **One error format (REV-63):** every error is `{ success: false, error: { code, message, details? } }` with a code from `API_ERROR_CODES`.
- **One lead state machine (REV-62):** status writes follow `LEAD_TRANSITIONS`; `POST /audits/trigger` answers `409 LEAD_NOT_AUDITABLE` outside `QUEUED`/`AUDIT_FAILED`.

## 2026-09-17 — 2026-09-26

### Added
- Discovery: `POST /discovery`, `GET /discovery/{jobId}`, `GET /discovery/reverse-geocode`, `POST /discovery/{jobId}/import` (REV-26 … REV-29, REV-35).
- `GET /mvp/providers` and `provider` / `model` on `POST /mvp/generate` (REV-32); `forceRegenerate` (REV-31); completeness report (REV-36, REV-37).
- Tracking: `/track/open`, `/track/click`, `/track/mvp-event`, `/track/unsubscribe`, `/track/revamp-tracker.js` (REV-18, REV-73).
- Leads, audits, MVP generation and the outreach approval gate (REV-6, REV-12, REV-16).

## Planned

- `PUT /outreach/{id}/draft`: save a draft without sending.
- `GET /analytics/overview`: funnel metrics, open rate, CTR.
- Request rate limiting on `/auth/*`.
