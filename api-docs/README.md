# Revamp API documentation

Developer documentation of the Revamp REST API (`/api/v1`, `apps/api` in [Revamp-dev](https://github.com/yurykurouski/revamp-dev)): what it does, how to call it, and the exact contract of every endpoint.

| Start here | |
| --- | --- |
| New to the API | [Getting started](guides/getting-started.md): run the stack, get a token, first call (10 min) |
| Building a client | [Tutorial: from a website to an approved email](guides/tutorial-lead-to-outreach.md) |
| Looking up an endpoint | [API reference](reference/index.html) (open in a browser) or [`reference/openapi.yaml`](reference/openapi.yaml) |
| Handling a failure | [Errors](guides/errors.md): every code, its cause and recovery |

## Contents

```
api-docs/
├── README.md                     # this page: contents and documentation strategy
├── CHANGELOG.md                  # changes to the API surface, per ticket
├── reference/
│   ├── openapi.yaml              # the specification (source, OpenAPI 3.0.3)
│   ├── openapi.bundled.yaml      # the same in one file, for tools that do not follow $ref (generated)
│   ├── index.html                # static Redoc site built from the bundle (generated)
│   └── redocly.yaml              # lint rules
├── schemas/
│   └── requests.yaml             # request bodies and queries, generated from the Zod schemas
├── guides/
│   ├── getting-started.md        # setup, token, first call, envelope
│   ├── authentication.md         # JWT, public routes, roles, studio isolation, invitations, security notes
│   ├── concepts.md               # architecture, request lifecycle, lead lifecycle, async jobs, pagination,
│   │                             # idempotency, rate limits, versioning, data conventions
│   ├── errors.md                 # error structure, taxonomy of all 46 codes, recovery
│   └── tutorial-lead-to-outreach.md
├── examples/
│   ├── walkthrough.sh            # the tutorial as a runnable curl + jq script (stops before approval)
│   └── revamp.http               # requests for VS Code REST Client / JetBrains HTTP Client
└── tools/
    └── generate-request-schemas.mjs
```

The API at a glance: 45 operations on 41 paths in 11 groups (Health, Auth, Organization, Invitations, Leads, Audits, MVP, Outreach, Discovery, Tracking, Admin), 12 of them public. Every route registered in `apps/api/src/routes` is in the reference.

## Viewing the reference

* **Static site:** open `reference/index.html` in a browser. No server needed.
* **Live preview while editing:** `npx @redocly/cli@1 preview-docs reference/openapi.yaml`.
* **Swagger UI / Editor:** paste `reference/openapi.bundled.yaml` into https://editor.swagger.io to try requests against `http://localhost:4000/api/v1` (Authorize → bearer token).

## Documentation strategy

### Sources of truth

| What | Source | How the docs stay in step |
| --- | --- | --- |
| Request bodies and queries | Zod schemas in `@revamp/validation`, which the API runs on every request | `schemas/requests.yaml` is **generated** from them (`tools/generate-request-schemas.mjs`); never edited by hand |
| Response shapes | TypeScript interfaces in `@revamp/shared-types` (`ILead`, `IAudit`, `IMvpProject`, …) that the dashboard also compiles against | `components/schemas` in `openapi.yaml` mirror them by name (`Lead` ↔ `ILead`); each schema says which interface it mirrors |
| Error codes | `API_ERROR_CODES` in `@revamp/shared-types` | The `ApiErrorCode` enum and `guides/errors.md` list the same 46 codes |
| Routes and guards | `apps/api/src/routes/*.ts`, `routes/index.ts` | Each path was written from its route file; public routes match `route-auth.spec.ts` |
| Prose architecture | `blueprint.md` §5 (Russian, the system design document) | This set is the developer-facing English reference; `blueprint.md` §5 links here |

### Standards and tools

* **OpenAPI 3.0.3** (not 3.1), because the Zod converter's `openApi3` target and Redoc fully support it.
* **Redocly CLI** lints with the `recommended` ruleset (`reference/redocly.yaml`; four rules switched off, each with its reason in the file), bundles and builds the static site. The recommended rules also validate every example against its schema.
* **Mermaid** for diagrams, so they live as text next to the prose and render on GitHub.
* **Keep a Changelog** + **SemVer** for `CHANGELOG.md` and `info.version`.

### Conventions

* **Paths:** lower-case nouns, plural for collections (`/leads`, `/audits`), actions as a sub-resource verb only where the action is not CRUD (`/outreach/{id}/approve`, `/mvp/{id}/versions/{n}/restore`).
* **Fields:** `camelCase`; ids are `_id` on stored documents and `<entity>Id` in references; dates are ISO 8601 UTC.
* **Operation ids:** `verbNoun` (`createLead`, `approveOutreach`); one tag per module.
* **Schema names:** the entity without the `I` prefix of its interface (`MvpProject`); request schemas keep the Zod name without `Schema` (`CreateLead`).
* **Files:** kebab-case Markdown, one topic per guide; each guide starts with what the reader will get and ends with where to go next.
* **Examples:** realistic values from one story (Smile Dental Clinic, Pixel Studio), reserved `.example` / `.test` domains, never a real person's data or a real secret.
* **Language:** English, short sentences, the same term for the same thing (lead, studio, prototype/MVP, approval).

### Versioning

The API version is in the path (`/api/v1`); the specification version in `info.version`. Additive changes raise the minor version; a breaking change would ship as `/api/v2` and a major version. See [concepts.md › Versioning](guides/concepts.md#versioning).

### Maintenance

When a ticket changes the API:

1. Update the route and its Zod schema in Revamp-dev.
2. Regenerate the request schemas (needs `zod-to-json-schema@3.23.5` and `js-yaml@4` installed next to the tool):
   ```bash
   node tools/generate-request-schemas.mjs ../../Revamp-dev/packages/validation/dist/index.js schemas/requests.yaml
   ```
3. Edit `reference/openapi.yaml` (paths, responses, error codes) and the guide it affects.
4. Lint, bundle, build:
   ```bash
   cd reference && npx @redocly/cli@1 lint openapi.yaml && npx @redocly/cli@1 bundle openapi.yaml -o openapi.bundled.yaml && npx @redocly/cli@1 build-docs openapi.bundled.yaml -o index.html
   ```
5. Add a line to `CHANGELOG.md` with the ticket.

## Known gaps

| Gap | Impact | Plan |
| --- | --- | --- |
| Response schemas are written by hand from the TypeScript interfaces, not generated | A field added to an interface can be missing here until someone updates it | Generate them with `ts-json-schema-generator`, or move responses to Zod |
| Deep nested audit objects (`standardsChecks`, `designCritique`, `extractedContent`, …) are summarised as open objects | Their inner fields are not in the reference | Their full shape is in `database-expertise.md` §4.2; generating from types would close it |
| No contract test runs the spec against the live API | Examples are validated against the schemas, not against real responses | Add a Schemathesis or Dredd run to CI |
| No hosted docs site or shared sandbox | Readers open `index.html` locally and run the API themselves | Publish `reference/` on GitHub Pages with the production deployment (REV-211) |
| No rate limiting | Documented as missing; `/auth/login` must not be exposed as is | Add a limiter before going public |
