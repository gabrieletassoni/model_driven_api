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

5. **The `thecore_raw` role** (3.16.0, Odoo #6093, `lib/raw_sql_grants.rb`): when `RawSqlGrants.protected?`, the executor runs `SET LOCAL ROLE thecore_raw` after the limits (so `temp_file_limit` is still set as the app). It is the barrier the parser cannot be, since SQL hidden in a string (`query_to_xml`) escapes it: a denied table or column, or a revoked function reached that way, is SQLSTATE 42501 → `not_permitted`.

Covered by `spec/requests/api/raw_sql_spec.rb` and `spec/requests/api/raw_sql_grants_spec.rb` (non-transactional: the executor must own its transaction; both apply the grants first, as a deploy does).

## `thecore_raw` role and `rails thecore:db:raw_grants` (`lib/raw_sql_grants.rb`)

`RawSqlGrants.apply!` rebuilds from scratch, in one transaction, everything the role may do (host ADR 0048 §2-3):

- `thecore_raw` `NOLOGIN NOINHERIT` (and no superuser/createrole/bypassrls), created if missing;
- `USAGE` on the current schema; `REVOKE ALL` on every table and sequence (which also drops stale column grants), then `SELECT` on every table, partitioned and foreign table, except `EXCLUDED_TABLES` (`ldap_servers`, `thecore_settings`, `used_tokens`, `push_subscribers`, `action_mailbox_inbound_emails`, `integration_logs`): no privilege at all;
- on any relation with a column whose name matches `SECRET_COLUMN` (Rails' `filter_parameters` patterns without `email`: `passw secret token _key crypt salt certificate otp ssn cvv cvc`), a per-column `SELECT` that leaves those columns out. On `users` that means `SELECT *` and a whole-row `json_agg(u)` are refused. The ADR names `users`; applying it to every relation is what lets one test assert that no secret-named column anywhere is readable;
- views: only those with `security_invoker` (PostgreSQL 15+) are granted, since they read as `thecore_raw`. Any other view, and every materialized view, reads with its owner's privileges (the superuser app), so an alias (`encrypted_password AS digest`) or a view over an excluded table would slip past the column-name check: they get nothing;
- `ALTER DEFAULT PRIVILEGES … GRANT SELECT ON TABLES`, so a table created by a later migration is readable at once. Until the next run (the same deploy's `thecore:db:seed`) that grant is table-level: its secret-named columns, and a new owner-rights view, stay readable in between. Accepted, as the ADR rejected default-deny;
- `REVOKE EXECUTE … FROM PUBLIC, thecore_raw` on every `pg_catalog` overload of `SafeSqlExecutor::DENIED_FUNCTIONS`. `set_config` matters most: from a superuser session it would undo `SET LOCAL ROLE`. The app, superuser, keeps using them.

It needs a superuser connection. Without one it changes nothing, logs a warning and returns `:skipped`; the deploy goes on.

When it runs: the migration `ApplyThecoreRawGrants` the first time, then `rails thecore:db:raw_grants`, appended to the end of `thecore:db:seed`. `thecore:db:seed` runs after the migrations both in `thecore:db:init/update` and in the thecore image entrypoint (`db:migrate` then `thecore:db:seed`), so every deploy re-applies the grants and a manual change to them does not survive. The hook is added from a prerequisite (`thecore:db:raw_grants_after_seed`), which runs when every engine's rake file is loaded, so it lands after `thecore_auth_commons`' seed actions whatever the load order.

`RawSqlGrants.reasons` is `[]` when the protection is full, otherwise any of `role_missing`, `role_not_usable` (the connection cannot `SET ROLE` to it), `set_config_executable`. It is checked on every `raw/sql` call (two catalog lookups), at every `rails server` boot (`RawSqlGrants.report_at_boot` from the engine: a warning when reduced, never an exception), and by `GET /api/v2|v3/info/raw_sql`, authenticated: `{ "protection": "full" | "reduced", "reasons": [...], "enforce": true | false }`. Reduced protection still has the parser, `READ ONLY`, the limits and the rollback; only secrets stay readable.

Covered by `spec/lib/raw_sql_grants_spec.rb` (transactional: the role and grants are rolled back) and `spec/requests/api/raw_sql_grants_spec.rb`.

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
