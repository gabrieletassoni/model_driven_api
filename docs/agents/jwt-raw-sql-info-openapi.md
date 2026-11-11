# JWT, raw SQL, info/version and OpenAPI

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (JWT and key rotation, safe SQL executor, info/version, OpenAPI self-generation). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

## JWT / token management (`lib/json_web_token.rb`)

- Expiry controlled by `SESSION_TIMEOUT_IN_MINUTES` env var (default 31 minutes).
- Secret from `Rails.application.credentials.secret_key_base` or `SECRET_KEY_BASE` env var.
- **Key rotation** (3.13.0, Odoo #5836): while `SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT` (ISO 8601) is in the future, `decode` also accepts tokens signed with `SECRET_KEY_BASE_PREVIOUS`; the sliding renewal then re-signs them with the current key. No expiry, or a past one, means the previous key is ignored. Only `JWT::VerificationError` falls back, so an expired token is never revived. Tokens are always signed with the current key. Covered by `spec/requests/api/v2/secret_key_rotation_spec.rb` and `spec/lib/json_web_token_spec.rb`.
- When `ALLOW_MULTISESSIONS=false`, every login invalidates previous tokens via `UsedToken` table. Tokens are stored and checked against `used_tokens` on each decode.

## Safe SQL executor (`lib/safe_sql_executor.rb`)

`SafeSqlExecutor.execute_select(query)` — validates that the query is a `SELECT` (or `WITH ... SELECT`), then executes. Only SELECT is allowed; DDL/DML raise `ArgumentError`.

- **v2**: The query must return a `result` key (typically via `json_agg`). Response wrapped in `{ result: … }`.
- **v3**: Returns raw rows as a plain JSON array — no `result` key required. A deliberate exception to JSON:API compliance (see ADR 0004).

## `GET /api/v2|v3/info/version`

Returns `{ version: ModelDrivenApi.app_version }` — the stripped contents of the host app's `version` file in `Rails.root` (the Thecore release convention: CI builds/deploys when it changes, and the production image is `ADD . /app`), or `null` when there is no such file. It used to return a hard-coded `"TODO: Find a Way to Dynamically Obtain It"`, so there was no way to tell which release a server runs. Covered by `spec/requests/api/v3/info_spec.rb`.

## OpenAPI / Swagger self-generation

`GET /api/v2/info/openapi` (alias `/swagger`) and `GET /api/v3/info/openapi` (alias `/swagger`) each generate a full OpenAPI 3.0 spec. Neither endpoint requires authentication.

The generation logic lives in two plain Ruby classes extracted from the info controllers:

| Class | Output |
|---|---|
| `Api::OpenApi::V2` | v2 spec: plain JSON, Ransack predicates, search endpoint, PUT, bulk ops, `result` key for SQL |
| `Api::OpenApi::V3` | v3 spec: JSON:API envelopes, `filter[field]`/`sort`/`page[number|size]` params, PATCH-only, 204 on delete |

Both inherit from `Api::OpenApi::Base` (`lib/api/open_api/base.rb`), which holds the shared type-resolution helpers: `compute_type`, `create_properties_from_model`, `integer?`, `number?`, `datetime?`.

The info controllers call:
```ruby
"paths" => Api::OpenApi::V2.new(ApplicationRecord.subclasses, request).generate
"paths" => Api::OpenApi::V3.new(ApplicationRecord.subclasses, request).generate
```

Sources in the v2 spec:
- All `ApplicationRecord` subclasses (CRUD + search + custom action paths)
- `NonCrudEndpoints` definitions registered via `self.desc`
