# JWT, raw SQL, info/version and OpenAPI

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (JWT and key rotation, safe SQL executor, info/version, OpenAPI self-generation). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

## JWT / token management (`lib/json_web_token.rb`)

- Expiry controlled by `SESSION_TIMEOUT_IN_MINUTES` env var (default 31 minutes).
- Secret from `Rails.application.credentials.secret_key_base` or `SECRET_KEY_BASE` env var.
- **Key rotation** (3.13.0, Odoo #5836): while `SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT` (ISO 8601) is in the future, `decode` also accepts tokens signed with `SECRET_KEY_BASE_PREVIOUS`; the sliding renewal then re-signs them with the current key. No expiry, or a past one, means the previous key is ignored. Only `JWT::VerificationError` falls back, so an expired token is never revived. Tokens are always signed with the current key. Covered by `spec/requests/api/v2/secret_key_rotation_spec.rb` and `spec/lib/json_web_token_spec.rb`.
- **Locked users** (3.14.0, Odoo #6051): every way to a JWT asks `User#active_for_authentication?` (thecore_auth_commons >= 3.7.0, a direct gemspec dependency; `super && !locked?`). `AuthenticateUser` raises `AccessDenied` for a locked user exactly as for a wrong password, also when LDAP authenticated them; `AuthorizeApiRequest` treats a still-valid JWT of a locked user as invalid, so the request answers 401 and the `Token` header is not renewed; the OAuth `callback` answers "User not registered". Machine2Machine tokens (thecore-spot-overrides) and ActionCable (thecore_backend_commons) ask the same predicate. Covered by `spec/requests/api/v2/locked_user_spec.rb`.
- When `ALLOW_MULTISESSIONS=false`, every login invalidates previous tokens via `UsedToken` table. Tokens are stored and checked against `used_tokens` on each decode.

## Safe SQL executor (`lib/safe_sql_executor.rb`)

`SafeSqlExecutor.execute_select(query, correlation_id:)` returns the rows as an Array of Hashes (3.15.0, host ADR 0048, Odoo #5835). `raw/sql` stays open to every authenticated user; what is restricted is what the query can do:

1. **Parser** (`pg_query` >= 6.2.5, never `normalize`): at most `RAW_SQL_MAX_QUERY_BYTES`, exactly one `SelectStmt`, and a walk of the whole tree refuses `INTO`, `FOR UPDATE/SHARE`, any `Insert/Update/Delete/MergeStmt` (CTEs included) and every `FuncCall` named in `DENIED_FUNCTIONS` (with or without schema). It is the second line, for a clear answer: SQL hidden in a string (`query_to_xml('…')`) escapes it.
2. **Execution**: its own transaction (a call inside an open transaction fails, since a savepoint can't own READ ONLY), `SET TRANSACTION READ ONLY`, `SET LOCAL` of `statement_timeout`, `lock_timeout`, `work_mem` and, only when the app is superuser, `temp_file_limit`; then `select_all` (one statement over `exec_params`, never `execute`), `ROLLBACK` always, and `pg_advisory_unlock_all()` afterwards because session advisory locks survive a rollback. Result size is checked against `RAW_SQL_MAX_RESULT_BYTES`.
3. **Errors**: `SafeSqlExecutor::Rejected` (`raw_sql_rejected`) or `Failed` (`raw_sql_failed`) with a `reason`; SQLSTATE 42501/25006 → `not_permitted`, 57014/55P03 → `timeout`, anything else → `query_error` with its `sqlstate`; a call inside an open transaction → `nested_transaction`. Every error is logged with the correlation id. PostgreSQL's message goes only to the Rails log, tagged with the request id. v2 answers 400 for everything (as always); v3 `Error#http_status`: 422, or 413 for `ResultTooLarge`. A `RAW_SQL_*` byte cap that isn't an integer falls back to its default with a warning.
4. **`RAW_SQL_ENFORCE=false`** (per installation, rollout): a `Rejected` (never a `Failed`: a timeout must not run again without limits) writes an `IntegrationLog` warning (only if the host defines `::IntegrationLog`; the gem has no such table) and reruns the query the old way (regex + `connection.execute`), whose errors the controllers answer as before.

The `thecore_raw` database role that hides secrets (Odoo #6093) is not here yet. Covered by `spec/requests/api/raw_sql_spec.rb` (non-transactional: the executor must own its transaction).

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
