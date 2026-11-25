## [Unreleased]

## [3.17.0] - 2026-11-25

### Security
- **`GET /api/v2|v3/info/settings` no longer returns secrets** (host Odoo #6084, host ADR 0046 point 10): a Secret setting (`ThecoreSettings::Setting.secret_key?`: `password`, `*_password`, `private_key`, `*_secret`, `*_token`, `api_key`, ...) keeps its key with a `null` value; every other setting is returned as before.
- **A model's `write_only_attributes` are never serialized by v3**: `Api::ResourceAttributeSet` (the attribute list of the JSON:API serializers, which read columns directly) leaves out whatever `model.write_only_attributes` returns, whatever `json_attrs` says. `LdapServer` declares `admin_password` (`GET /api/v3/ldap_servers/:id` returned it).
- Requires `thecore_auth_commons` >= 3.8.0: `LdapServer#admin_password` is never serialized nor ransackable (so `?a[only][]=admin_password` and `q[admin_password_start]` reveal nothing), and failed logins on `POST /api/vN/authenticate` count toward the per-IP limit (429 as JSON after 20 failures a minute, host Odoo #6052).

## [3.16.0] - 2026-11-25

### Security
- **`raw/sql` runs as the database role `thecore_raw`, which cannot read secrets** (host ADR 0048, Odoo #6093). No access to `ldap_servers`, `thecore_settings`, `used_tokens`, `push_subscribers`, `action_mailbox_inbound_emails`, `integration_logs`, nor to any column named like a secret (`passw`, `secret`, `token`, `_key`, `crypt`, `salt`, `certificate`, `otp`, …), also through SQL hidden in a string (`query_to_xml`). `EXECUTE` on `set_config` and the other side-effect functions is revoked from `PUBLIC`. Such a query answers `not_permitted` (v2 400, v3 422). Views are readable only with `security_invoker` (others read as their superuser owner), materialized views not at all. A `SELECT` that lists non-secret columns of a table answers as before; `SELECT *` or `json_agg(u)` on `users` must now list the columns (with `RAW_SQL_ENFORCE=false` it is logged and run the old way).

### Added
- `rails thecore:db:raw_grants`: idempotent, rebuilds the role and its grants (new non-secret columns become readable, new tables are readable at once), runs by itself at the end of `rails thecore:db:seed` and, the first time, from the migration `ApplyThecoreRawGrants`. It needs a superuser database user; otherwise it warns and the deploy goes on.
- `GET /api/v2|v3/info/raw_sql` (authenticated): `{ "protection": "full" | "reduced", "reasons": [...], "enforce": true | false }`. A reduced protection is also logged at every `rails server` boot.

## [3.15.0] - 2026-11-25

### Security
- **`raw/sql` runs one plain SELECT, read-only, with limits** (host ADR 0048, Odoo #5835). Every authenticated user can still call it. PostgreSQL's own parser (`pg_query` >= 6.2.5, a new dependency) accepts exactly one `SELECT` without `INTO`, `FOR UPDATE/SHARE`, data-modifying statements or side-effect functions. The query runs through `select_all` in a `READ ONLY` transaction of its own with a statement timeout, lock timeout, `work_mem` and `temp_file_limit`, is always rolled back, and leaves no session advisory lock behind. Limits: `RAW_SQL_*` ENV (README). A correct `SELECT` answers exactly as before.
- Errors are `{ "error", "reason"[, "sqlstate"] }` and never carry PostgreSQL's message: v2 400 as before, v3 422 (413 for a result over the cap) instead of 400.
- `RAW_SQL_ENFORCE=false` (per installation, while a frontend is verified): a rejected query is logged as an `IntegrationLog` warning, when the host has that model, and run the old way.
- **The OAuth token exchange `POST /api/v2/auth/jwt` and `/api/v3/auth/jwt` is removed** (host Odoo #5860), with `Api::V3::Auth::OauthController`. No frontend used it. The OmniAuth callback is unchanged.

### Fixed
- A path that names no class (`POST /api/v2/no_such_things`, or a custom action on it) answers 404 instead of 500.

## [3.14.1] - 2026-11-25

### Removed
- The example `.gitlab-ci.yml` (Ruby 3.1.2), never run since the repository lives on GitHub; CI is `.github/workflows/gempush.yml` (host Odoo #6261).

## [3.13.3] - 2026-11-24

### Fixed
- **A non-hash `a`/`json_attrs` answers 400, not 500** (host Odoo #6258). `?a=1` or `?json_attrs=1` raised `NoMethodError` in `json_attrs`, after create, update and custom actions had already saved. A `before_action` on every action that serializes through `json_attrs` (index, show, create, update/patch and all custom actions) now answers 400 `{"error": "The a parameter must be a hash, e.g. a[only][]=id"}` in every environment, before any side effect. Hash forms, an empty value and unknown parameters behave as before; a plain destroy and v3 standard actions, which never read `a`, are unaffected.

## [3.13.2] - 2026-11-24

### Fixed
- **JSON rendering with `include:` works on Rails 8.1** (host Odoo #6089). `AutoIncludeJson` wrote the sanitized includes back into the options hash it received, and Rails 8.1's JSON encoder passes `as_json` a frozen one: every `to_json`/`as_json` with `include:` raised `FrozenError` (v2 create/index, v3 authenticate, any host `record.to_json(json_attrs)`). It now passes a sanitized copy on and leaves the caller's options, often a model's shared `json_attrs`, untouched. Same output on Rails 7.2.

### Changed
- The test suite and its CI run on Rails 8.1 (`~> 8.1, >= 8.1.4.1`, minitest 5); `RAILS_VERSION=7.2` runs the same suite on 7.2.4 locally (best effort, not in CI). The gemspec names no Rails version: dual support (host ADR 0033) means its dependencies keep resolving on 7.2 too.

## [3.13.1] - 2026-10-29

### Security
- **The generic API never instantiates the class named by the path** (host Odoo #5884). `Api::ModelResolver` turned the first path segment into a class and called `.new` on it to check it was a model, so with any valid JWT `GET /api/v2/tempfiles` ran `Tempfile.new` and created a file on the server. It now only inspects the class (`safe_constantize`, then a concrete `ActiveRecord::Base` subclass); anything else still answers 404.
- `config/brakeman.ignore` documents Brakeman's High `UnsafeReflection` on `"Endpoints::#{params[:ctrl]}".constantize` in `public_custom_action?` as a false positive: ActiveSupport's `constantize` never falls back to a top-level constant, so only an existing `Endpoints::*` class can be loaded.

## [3.13.0] - 2026-10-28

### Security
- **`SECRET_KEY_BASE` can be rotated without logging app users out** (Odoo #5836) — `JsonWebToken.decode` also accepts a token signed with `SECRET_KEY_BASE_PREVIOUS`, but only until `SECRET_KEY_BASE_PREVIOUS_EXPIRES_AT` (ISO 8601; without it, or once it has passed, the previous key is ignored). Every authenticated response already renews the token with the current key, so active sessions move to the new key on their next request. Only a bad signature falls back to the previous key: an expired token stays expired. Cookies are deliberately not rotated (only admins use them, and a public old key must not keep validating forged sessions).

## [3.12.2] - 2026-10-28

### Security
- **OAuth callback takes the identity only from OmniAuth** (Odoo #5837) — `Api::V2::Auth::OauthController#callback` (and v3) read `email` from the request parameters, so a single unauthenticated `POST /api/v2/auth/<provider>/callback` with `email=` returned a JWT for that user (when OAuth env vars are set). It now reads only `request.env['omniauth.auth']`, set by the OmniAuth middleware after verifying the login with the provider, and answers 401 without it. The top-level `/auth/:provider/callback` now routes straight to the controller instead of redirecting, which used to drop that verified hash.

## [3.12.1] - 2026-10-28

### Changed
- The `POST /api/v2/authenticate` example (README, OpenAPI v2 description) no longer shows `Change#1`, the old fixed admin seed password that thecore_auth_commons 3.6.2 removed; it shows `<password>`.

## [3.9.1] - 2026-09-08

### Fixed
- **`lib/non_crud_endpoints.rb` require order** — `cattr_accessor :definitions` ran before anything guaranteed ActiveSupport's `Class` core-ext was loaded, raising `NoMethodError: undefined method 'cattr_accessor'` under the plain minitest boot path (masked under rspec, which boots the full dummy Rails app first). Now requires `active_support/core_ext/class/attribute_accessors` directly.
- Pinned `json < 3.0` in the dev `Gemfile` — json 3.0+ turns ActiveSupport's `quirks_mode:` `JSON.generate` option into a hard `ArgumentError` under Rails 7.2 (test/dev tooling only, does not affect the published gem).

## [3.9.0] - 2026-09-02

### Added
- **`ModelDrivenApiDefaultJsonAttrs`** (`lib/concerns/model_driven_api_default_json_attrs.rb`) — gives every `ApplicationRecord` subclass a default `json_attrs = { except: [] }` (all columns, no `methods`, no `include`) with no explicit `Api::ModelName` concern required, registered into `ThecoreBackendCommons::DefaultModuleRegistry` (requires `thecore_backend_commons ~> 3.5`). A model with its own `Api::ModelName` concern is unaffected — the explicit `include` always runs after and overrides the default. See `docs/agents/serialization.md` for the `instance_methods(false)`/`/info/schema`+`/info/dsl` rationale.

## [3.8.0] - 2026-06-30

### Added
- **`POST broadcast_push`** — new custom action on `Endpoints::PushSubscriber`; sends the same push notification to all active subscribers (`expired_at IS NULL`) in a single `insert_all` + one `PushDispatchJob` per subscriber (async). Accepts `title` (required), `body` (required), `message_type` (optional, default `"communication"`), `url`, `icon`, `current_user_id`. Response: `{ enqueued: N }`.
- **`send_push` bulk mode** — `push_subscriber_ids` array parameter; creates messages via `insert_all` with `returning:` for performance and enqueues one `PushDispatchJob` per valid subscriber. Invalid/inactive IDs are returned in a `failed` array. Response: `{ created: [...], failed: [...] }`.

### Fixed
- **`send_push` and `acknowledge` serialization error** — `check_for_custom_action` was serializing the response body using `PushSubscriber.json_attrs` (which includes `user`), but both actions return a `PushMessage` instance (which has `sender`, not `user`), causing `NoMethodError: undefined method 'user' for an instance of PushMessage`. Fixed by pre-serializing responses with `message.as_json(PushMessage.json_attrs)`.

## [3.7.0] - 2026-06-16

### Changed
- **`jwt` dependency bumped from `~> 2.4` to `~> 3.0`** — aligns with `web-push ~> 3.0` (the actively maintained pushpad fork of the abandoned webpush gem). jwt 3.x is backward compatible with existing `JWT.encode`/`JWT.decode` usage (no API changes needed).

## [3.6.4] - 2026-06-16

### Added

- **Public (unauthenticated) custom actions** — `NonCrudEndpoints.public_action(:action_name)` registers an action as requiring no authentication. `authenticate_request` and `authorize!` are skipped for these actions in both v2 and v3 controllers. The `Endpoints::<Model>` class is force-loaded in `public_custom_action?` so the registry is populated before the before-action chain runs.

- **Push subscription endpoints** (`app/models/endpoints/push_subscriber.rb`)
  - `GET /api/v2/push_subscribers/custom_action/vapid_public_key` — returns `{ vapid_public_key: }` from `ThecoreSettings` (ns: `:vapid`, key: `:public_key`); **no authentication required**
  - `GET /api/v3/push_subscribers/custom_action/vapid_public_key` — same, v3 prefix; no authentication required
  - `POST /api/v2/push_subscribers/custom_action/subscribe` — registers or updates a `PushSubscriber` for the authenticated user; returns 201 on create, 200 on update; re-subscribing an expired subscriber resets `expired_at` to nil; requires authentication
  - `POST /api/v2/push_subscribers/custom_action/send_push` — creates a `PushMessage` for the given `push_subscriber_id` (active subscribers only) and dispatches it via `ThecoreBackendCommons::PushNotificationService.dispatch`; returns 201 on success, 404 if subscriber not found, 422 on validation failure; requires authentication
  - `POST /api/v2/push_subscribers/custom_action/acknowledge` — marks a `PushMessage` as received (`received_at`) or read (`read_at`) based on `received: true` / `read: true` params; idempotent (only sets if nil); returns 200 on success, 404 if message not found; requires authentication

### Fixed

- **`api_error` not halting the before-action chain** — `head status && return if errors.blank?` was parsed as `head(status && return)`, causing `return` to exit `api_error` before `head` was called and leaving no response rendered. Replaced with an explicit `if/head/return` block in `lib/concerns/api_exception_management.rb`.

## [3.6.3] - 2026-06-08

### Added

- **API v3 — full feature parity with v2 surface**
  - `POST /api/v3/authenticate` — same plain JSON + `Token` header as v2 (`Api::V3::AuthenticationController`)
  - `GET /api/v3/info/*` — all info endpoints (version, heartbeat, ntp, roles, schema, dsl, translations, settings) now available under the v3 prefix via `Api::V3::InfoController` (inherits v2 unchanged)
  - `GET /api/v3/info/swagger` / `openapi` — v3-accurate OpenAPI 3.0 spec: JSON:API envelopes, `filter[field]`/`sort`/`page[number|size]` params, PATCH-only, 204 on delete, no search endpoint
  - Custom actions (`?do=` and `/custom_action/:action`) now routed and dispatched in v3; responses are plain JSON (not JSON:API envelopes)

- **JSON:API sideloading (hybrid)**
  - Default sideloads from `json_attrs[:include]`; client overrides with `?include=assoc1,assoc2`; `?include=` (empty) suppresses all sideloads
  - Nested serializers generated as `<AssocModel>For<ParentModel>Serializer`; always flat (one level) to prevent circular-association loops

- **JSON:API sparse fieldsets** — `?fields[type]=f1,f2` narrows attributes returned per resource type

- **`json_attrs[:methods]`** — virtual attributes in v3 serializers via `object.send(method_name)`; `send` (not `public_send`) supports private methods injected by `thecore_backend_commons`

- **`json_attrs[:include]`** — association entries declare relationships on the generated serializer and become default sideloads

### Changed

- **`Api::V3::SerializerFactory`** now delegates attribute resolution to `Api::ResourceAttributeSet.for(model_class)` — single source of truth for `only:`/`except:`/`methods:`/`include:` resolution shared with the OpenAPI generator
- **`extract_model`** now delegates to `Api::ModelResolver.resolve` — raises typed `Api::ModelResolver::NotFound` for non-AR classes; returns `nil` (no 404) for model-less controllers (info endpoints)
- **`check_for_custom_action`** now delegates to `Api::CustomActionDispatcher.call` — IoT workaround removed (see below)
- **OpenAPI generation extracted** from info controllers into `Api::OpenApi::Base` / `V2` / `V3`; info controllers now own only the outer spec envelope and call `.new(models, request).generate`

### Removed

- **IoT bearer-token-in-action-name workaround** — `params[:do].split("-")` used to extract a bearer token embedded in the `?do=` action name for devices unable to send `Authorization` headers. This is removed. Bearer tokens must be sent via `Authorization: Bearer <token>`. `params[:do]` is now always the literal action name.

### Internal

- `lib/api/resource_attribute_set.rb` — new `Struct`-based value object for `json_attrs` resolution
- `lib/api/model_resolver.rb` — new class encapsulating model-from-params resolution with typed error
- `lib/api/custom_action_dispatcher.rb` — new class encapsulating custom action detection and dispatch
- `lib/api/open_api/base.rb` — shared OpenAPI type helpers (`compute_type`, `create_properties_from_model`)
- `lib/api/open_api/v2.rb` — v2 OpenAPI path generator (extracted from `Api::V2::InfoController`)
- `lib/api/open_api/v3.rb` — v3 OpenAPI path generator (extracted from `Api::V3::InfoController`)
- `app/controllers/api/v2/info_controller.rb` reduced from 1435 to 129 lines
- `app/controllers/api/v3/info_controller.rb` reduced from 377 to 37 lines

## [3.0.0] - 2022-07-08

- Initial release aimed at Rails 7 and Ruby 3
