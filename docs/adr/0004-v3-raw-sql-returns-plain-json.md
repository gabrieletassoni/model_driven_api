# v3/raw/sql returns plain JSON, not a JSON:API envelope

API v3 is JSON:API-compliant across all Resource endpoints. The SQL Escape Hatch (`/api/v3/raw/sql`) is a deliberate exception: it returns a plain JSON array of rows, not a `data:[]` envelope. Wrapping free-form SQL results in a JSON:API envelope is meaningless — the response shape is entirely caller-controlled and is not Resource-shaped. Adding an envelope would force every client to unwrap it with no benefit. The endpoint is auth-protected and SELECT-only (enforced by `SafeSqlExecutor`), like its v2 counterpart.

## Considered Options

- **Plain JSON array** — chosen; matches caller expectations for arbitrary SQL results and avoids a useless unwrap step.
- **JSON:API envelope** — rejected; the response has no `type`, `id`, or `attributes` structure, so a JSON:API wrapper would be a facade with no semantics.
- **Drop the endpoint from v3** — rejected; the SQL Escape Hatch exists for legitimate performance use cases that the Resource abstraction cannot cover.

## Consequences

Clients consuming `/api/v3/raw/sql` must not expect a JSON:API envelope. Other v3 endpoints that also return plain JSON (not JSON:API envelopes): info endpoints (`/api/v3/info/*`) and Custom Action responses (`/api/v3/:model/custom_action/:action` and `?do=`). The JSON:API compliance guarantee applies only to the CRUD Resource endpoints.
