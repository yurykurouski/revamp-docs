# Getting started

From an empty machine to your first authenticated API call in about ten minutes. All examples use `curl` and `jq`; the same calls as a runnable script are in [`../examples/walkthrough.sh`](../examples/walkthrough.sh).

## 1. Run the stack

You need Node 20+ and Docker. In a checkout of [Revamp-dev](https://github.com/yurykurouski/revamp-dev):

```bash
npm run setup
```

```bash
npm run dev
```

`setup` (once) installs dependencies and Playwright Chromium, writes `.env` from `.env.example`, starts MongoDB, Redis and MinIO and builds the shared packages. `dev` starts the API on port 4000, the workers and the dashboard on port 5173.

Check that the API and its databases are up:

```bash
curl -s http://localhost:4000/api/v1/health | jq
```

```json
{
  "status": "ok",
  "timestamp": "2026-11-22T10:15:00.000Z",
  "services": { "api": "healthy", "mongodb": "connected", "redis": "connected" }
}
```

`503` with `"status": "degraded"` means MongoDB or Redis is not reachable; `services` says which.

## 2. Get a token

Every route except the public ones listed in [authentication.md](authentication.md) needs a bearer token. Create a studio (you become its owner):

```bash
curl -s http://localhost:4000/api/v1/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"owner@studio.test","password":"correct-horse-9","organizationName":"Pixel Studio"}' | jq
```

```json
{
  "success": true,
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9…",
    "user": { "id": "673f1b2c9d4e5a0012ab34cd", "email": "owner@studio.test" },
    "organization": { "id": "673f1b2c9d4e5a0012ab34ce", "name": "Pixel Studio" },
    "role": "owner"
  }
}
```

Or, after `npm run db:seed`, sign in as one of the demo accounts listed in the Revamp-dev README (section *Demo data and database export*):

```bash
TOKEN=$(curl -s http://localhost:4000/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"demo-owner@revamp-demo.test","password":"demo-owner-password"}' | jq -r .data.token)
```

## 3. Make an authenticated call

```bash
curl -s http://localhost:4000/api/v1/leads/stats -H "Authorization: Bearer $TOKEN" | jq
```

```json
{ "success": true, "data": { "total": 12, "byStatus": { "AUDITED": 3, "NEEDS_APPROVAL": 5, "SENT": 4 } } }
```

Without the header the answer is `401`:

```json
{ "success": false, "error": { "code": "UNAUTHENTICATED", "message": "Sign in to use the API" } }
```

## 4. Read the response envelope

| Outcome | Body |
| --- | --- |
| Success | `{ "success": true, "data": …, "message"?: …, "pagination"?: … }` |
| Error | `{ "success": false, "error": { "code": "…", "message": "…", "details"?: … } }` |

Branch on `error.code`, show `error.message` to people, and never parse the message. Every code with its meaning and recovery is in [errors.md](errors.md).

## Next steps

* [Tutorial: from a website to an approved email](tutorial-lead-to-outreach.md): the whole pipeline step by step.
* [Concepts](concepts.md): architecture, the lead lifecycle, asynchronous jobs, pagination, versioning.
* [API reference](../reference/index.html): every endpoint, parameter and schema (open in a browser).
