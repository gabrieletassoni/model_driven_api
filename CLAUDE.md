# CLAUDE.md — model_driven_api

This is a Rails engine gem (`model_driven_api`) that auto-generates a versioned REST API at `/api/v2/` (plain JSON, Ransack-powered) and `/api/v3/` (JSON:API-compliant) by introspecting ActiveRecord models at runtime. It lives as a git submodule inside a parent Thecore application.

## Commands

```bash
# Run specs (from inside the submodule directory)
bundle exec rspec

# Lint
bundle exec standardrb

# Release a new version:
# 1. Bump lib/model_driven_api/version.rb
# 2. Commit and push — CI builds the gem
```

## Architecture

### Entry point

`lib/model_driven_api.rb` — loads all dependencies and requires the engine. The engine (`lib/model_driven_api/engine.rb`) appends the gem's migrations to the host app and registers the `application/vnd.api+json` MIME type with a parameter parser (symbol key `:json_api` in `ActionDispatch::Request.parameter_parsers`).

`pagy` is explicitly `require`d here (alongside `kaminari`). Pagy is not auto-loaded by Bundler because it is needed the moment `Api::V3::ApplicationController` class body is evaluated — before eager loading runs. Removing `require "pagy"` from this file causes `NameError: uninitialized constant Pagy` on any rake task or server boot that loads the application.

### Controllers (`app/controllers/api/v2/`)

| File | Role |
|---|---|
| `application_controller.rb` | Base controller — auth, model extraction, all CRUD actions |
| `authentication_controller.rb` | `POST /api/v2/authenticate` — email/password → JWT |
| `auth/oauth_controller.rb` | OAuth2 callback + token exchange for Google/Microsoft |
| `info_controller.rb` | `/api/v2/info/*` — version, roles, schema, dsl, swagger, openapi, ntp, heartbeat, translations, settings |
| `raw_controller.rb` | `POST /api/v2/raw/sql` — safe SELECT-only SQL executor |

### Controllers (`app/controllers/api/v3/`)

| File | Role |
|---|---|
| `application_controller.rb` | Inherits v2 base — overrides CRUD with JSON:API envelopes, Pagy pagination, `filter[field]` filtering, `sort` ordering |
| `authentication_controller.rb` | Thin subclass of v2 auth controller — provides `POST /api/v3/authenticate` |
| `auth/oauth_controller.rb` | Thin subclass of v2 OAuth controller — exposes only `exchange_token` via `POST /api/v3/auth/jwt` (registered only when `oauth_vars?`); `callback`/`failure` stay v2-only (OmniAuth middleware is hardcoded to v2 path) |
| `info_controller.rb` | Inherits v2 info — overrides only `openapi`/`swagger` to call `Api::OpenApi::V3`; all other info actions inherited unchanged |
| `raw_controller.rb` | `GET/POST /api/v3/raw/sql` — same SELECT-only guard; returns **plain JSON array** (deliberate JSON:API exception) |
| `users_controller.rb` | Thin subclass of v3 application controller — adds `check_demoting` guard on `update`/`patch`/`destroy`; prevents a user from modifying their own `admin` or `locked` flags (same constraint as v2) |

### `Api::V2::ApplicationController` — the core

Every API request goes through `Api::V2::ApplicationController`:

1. `authenticate_request` — resolves `@current_user` via pluggable authorization headers (`Settings.ns(:security).allowed_authorization_headers`) or JWT bearer token. Writes a fresh JWT to the `Token` response header on every successful request (sliding expiration).
2. `extract_model` — resolves `@model` from `params[:ctrl]`, path, or controller name (in that order). Pulls `@body` from singular/plural model param.
3. `find_record` — called only for show/update/destroy; finds by `params[:id]`.
4. CRUD actions (`index`, `show`, `create`, `update`/`patch`, `destroy`, `update_multi`, `destroy_multi`) — all delegate authorization to CanCan (`authorize! :action, @model`).

### `Api::V3::ApplicationController` — JSON:API layer

Inherits from v2; reuses `authenticate_request`, `extract_model`, `find_record`, and all CanCan authorization. Overrides all CRUD actions:

- **`index`** — `filter[field]=value` params (validated against `ransackable_attributes`), `sort=field` / `sort=-field` (comma-separated), Pagy pagination via `page[number]` + `page[size]`. Response: `{ data: […], meta: { total: N } }`.
- **`show`** — `{ data: { id:, type:, attributes: {} } }`.
- **`create`** — reads attributes from `params[:data][:attributes]`. Response: 201 + resource object.
- **`update`/`patch`** — reads attributes from `params[:data][:attributes]`. Response: 200 + resource object.
- **`destroy`** — 204 No Content.

**Sideloading (hybrid)** — default sideloads come from `json_attrs[:include]` keys. The client overrides with `?include=assoc1,assoc2`; passing `?include=` (empty string) suppresses all sideloads. Implemented in `requested_includes` / `default_includes`.

**Sparse fieldsets** — `?fields[type]=field1,field2` narrows the attributes returned per type. Passed to the serializer as `fields: { type: [:field1, :field2] }`. Implemented in `sparse_fields` / `serializer_opts`.

### `Api::V3::SerializerFactory` (`lib/api/v3/serializer_factory.rb`)

Lazily generates a named `JSONAPI::Serializer` subclass from each model's `json_attrs`. Classes are cached in the `Api::V3` namespace as `<ModelName>Serializer` after first generation.

Attribute resolution is delegated to `Api::ResourceAttributeSet.for(model_class, jattrs:)` (see below), which owns the `only:` / `except:` / `methods:` / `include:` logic in one place. The factory reads the resolved struct fields directly.

`json_attrs[:methods]` — each symbol becomes a block-form `attribute` using `object.send(method_name)`. `send` (not `public_send`) is required — `thecore_backend_commons`'s `BaseApplicationRecordConcern` injects `methods: [:assets_paths, :rich_content_html]` into every model at `after_initialize` time, and both are declared `private`. Rails `as_json` uses `send` for the same reason.

`json_attrs[:include]` — each entry is a bare symbol (`:assoc`) or a hash (`assoc: { only: [:id] }`). A nested serializer is generated as `<AssocModel>For<ParentModel>Serializer`, registered with the correct macro (`has_many`/`has_one`/`belongs_to`) from `reflect_on_all_associations`. Nested serializers are always flat — `include:` is not processed recursively — to prevent infinite loops on circular associations (e.g. `Role ↔ User`).

`extract_includes(include_spec)` is still a public class method (specs test it directly); it delegates to `Api::ResourceAttributeSet#parsed_includes`.

```ruby
serializer = Api::V3::SerializerFactory.serializer_for(Role)
# → Api::V3::RoleSerializer (generated on first call, cached afterwards)
# Also generates Api::V3::UserForRoleSerializer when Role.json_attrs[:include] contains users:
```

The `:id` field is excluded from `attributes` (the serializer handles it as the resource identifier). When all non-id attributes are stripped, the jsonapi-serializer gem omits the `:attributes` key entirely from the hash (per JSON:API spec). Use `.to_h` when asserting emptiness: `expect(attrs.to_h).to be_empty`.

### Ransack-powered search (`index`) — v2 only

`GET /api/v2/:model?q[field_predicate]=value` or `POST /api/v2/:model/search`.  
Pagination via `page` + `per`. Count-only via `count=true`.  
Field selection via `a` or `json_attrs` (mirrors Rails `as_json` DSL: `only`, `except`, `methods`, `include`).

### Custom actions — v2 and v3

Two patterns are supported, dispatched by `Api::CustomActionDispatcher.call(model, params, request)` (called from `check_for_custom_action` in both v2 and v3 controllers):

**Pattern 1 — class method on the model:**
```ruby
def self.custom_action_my_action(params)
  [{ result: "ok" }, 200]
end
```
Triggered via `GET /api/v2/my_model?do=my_action`, `GET /api/v3/my_model?do=my_action`, or with `/:id`.

**Pattern 2 — `NonCrudEndpoints` subclass:**
```ruby
class Endpoints::MyModel < NonCrudEndpoints
  self.desc 'MyModel', :my_action, { get: { ... openapi schema ... } }
  def my_action(params)
    [{ result: "ok" }, 200]
  end
end
```
Triggered via `GET /api/v2/my_model/custom_action/my_action` or `GET /api/v3/my_model/custom_action/my_action`, with optional `/:id`.

Place endpoint files in `app/models/endpoints/model_name.rb` in the host app.

Custom action responses in v3 are plain JSON (not JSON:API envelopes) — the dispatcher serializes via `body.to_json(json_attrs)` before returning.

**Public (unauthenticated) actions** — to declare that a `NonCrudEndpoints` action does not require a JWT token, call `public_action :action_name` in the class body:
```ruby
class Endpoints::MyModel < NonCrudEndpoints
  public_action :my_public_action   # no token required for this action
  self.desc 'MyModel', :my_public_action, { get: { ... } }
  def my_public_action(params)
    [{ result: "ok" }, 200]
  end
end
```
`ApplicationController#authenticate_request` checks `NonCrudEndpoints.public_action?(model, action)` and skips token validation for registered public actions. The `Endpoints::<Model>` class is force-loaded (via `constantize`) in `public_custom_action?` before the check so declarations are visible even on first request. CanCan authorization is also skipped for public actions. `params[:current_user_id]` is nil for these calls — do not call `User.find(params[:current_user_id])` in a public action.

### Concerns to include in host models

| Concern | Include in | Purpose |
|---|---|---|
| `ModelDrivenApiApplicationRecord` | `ApplicationRecord` | Enables `ransackable_attributes` / `ransackable_associations` |
| `ModelDrivenApiUser` | `User` | Adds `has_many :used_tokens`, default `json_attrs` |
| `ModelDrivenApiRole` | `Role` | Adds default `json_attrs` |
| `ModelDrivenApiPushSubscriber` | `PushSubscriber` | `json_attrs` includes `user: { only: [:id, :email, :name, :surname] }` |
| `ModelDrivenApiPushMessage` | `PushMessage` | `json_attrs` includes `sender: { only: [:id, :email, :name, :surname] }` |

All concerns are registered in `config/initializers/after_initialize_for_model_driven_api.rb` via `send(:include, ...)` inside `after_initialize`. New model concerns go in `lib/concerns/` following the `ModelDrivenApi<ModelName>` naming convention.

### JSON serialisation DSL (`json_attrs`)

Each model exposes `self.json_attrs` as a class-level hash with the standard Rails `as_json` keys: `:only`, `:except`, `:methods`, `:include`. The engine reads this in every v2 CRUD response. The v3 `SerializerFactory` reads `json_attrs[:only]` first, then falls back to `column_names - [:except]` if `only:` is not set. Clients can override the shape per-request via the `a` or `json_attrs` query parameter (v2 only).

Use `ModelDrivenApi.smart_merge(existing, additions)` when composing `json_attrs` across concerns — it does a deep merge that extends arrays rather than replacing them.

### JWT / token management (`lib/json_web_token.rb`)

- Expiry controlled by `SESSION_TIMEOUT_IN_MINUTES` env var (default 31 minutes).
- Secret from `Rails.application.credentials.secret_key_base` or `SECRET_KEY_BASE` env var.
- When `ALLOW_MULTISESSIONS=false`, every login invalidates previous tokens via `UsedToken` table. Tokens are stored and checked against `used_tokens` on each decode.

### Safe SQL executor (`lib/safe_sql_executor.rb`)

`SafeSqlExecutor.execute_select(query)` — validates that the query is a `SELECT` (or `WITH ... SELECT`), then executes. Only SELECT is allowed; DDL/DML raise `ArgumentError`.

- **v2**: The query must return a `result` key (typically via `json_agg`). Response wrapped in `{ result: … }`.
- **v3**: Returns raw rows as a plain JSON array — no `result` key required. A deliberate exception to JSON:API compliance (see ADR 0004).

### OpenAPI / Swagger self-generation

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

## Routes summary

```
# V2 (plain JSON, Ransack-powered)
POST   /api/v2/authenticate
GET    /api/v2/info/version|roles|heartbeat|ntp|translations|schema|dsl|settings|swagger|openapi
GET    /api/v2/raw/sql
POST   /api/v2/raw/sql
GET    /api/v2/auth/:provider           → triggers OmniAuth
POST   /api/v2/auth/:provider/callback
POST   /api/v2/auth/jwt                 → token exchange from frontend OAuth token
GET    /api/v2/:ctrl/custom_action/:action_name(/:id)
POST   /api/v2/:ctrl/custom_action/:action_name
...    (PUT/PATCH/DELETE custom actions)
POST   /api/v2/:ctrl/search
GET    /api/v2/*path(/:id)              → CRUD index / show
POST   /api/v2/*path                    → CRUD create
PUT|PATCH /api/v2/*path/:id(/multi)     → CRUD update / bulk update
DELETE /api/v2/*path/:id(/multi)        → CRUD destroy / bulk destroy

# V3 (JSON:API-compliant)
POST   /api/v3/authenticate             → same plain JSON as v2 (Token header)
POST   /api/v3/auth/jwt                 → token exchange from frontend OAuth token (registered only when oauth_vars?)
GET    /api/v3/info/version|roles|heartbeat|ntp|translations|schema|dsl|settings|swagger|openapi
GET    /api/v3/raw/sql                  → SQL escape hatch (plain JSON, not JSON:API)
POST   /api/v3/raw/sql
GET    /api/v3/:ctrl/custom_action/:action_name(/:id)
POST   /api/v3/:ctrl/custom_action/:action_name
...    (PUT/PATCH/DELETE custom actions — plain JSON response, not JSON:API)
GET|POST|PATCH|DELETE /api/v3/users(/:id) → explicit resource; guarded against self-demotion
GET    /api/v3/*path/:id               → CRUD show
GET    /api/v3/*path                   → CRUD index (filter/sort/page params)
POST   /api/v3/*path                   → CRUD create
PATCH  /api/v3/*path/:id              → CRUD update (no PUT)
DELETE /api/v3/*path/:id               → CRUD destroy (204 No Content)
```

## Key invariants and gotchas

- `params` is overridden to `request.parameters` — strong parameters are bypassed intentionally. Do not use `params.require(...).permit(...)` patterns.
- **`extract_model` delegates to `Api::ModelResolver.resolve`** — raises `Api::ModelResolver::NotFound` for non-AR classes; returns `nil` (no exception) when no class can be resolved (info/utility controllers). `not_found!` is called only in the `rescue` clause in `extract_model`, not inside the resolver itself.
- **`check_for_custom_action` delegates to `Api::CustomActionDispatcher.call`** — the dispatcher accepts `params[:do]` as the literal action name (no token extraction). Bearer tokens must be sent via the `Authorization` header. The old IoT workaround (`params[:do].split("-")` to extract a token embedded in the action name) has been removed.
- **`Api::ResourceAttributeSet.for(model_class)`** — single source of truth for resolving `json_attrs[:only]`/`[:except]`/`[:methods]`/`[:include]` into a struct. Both `SerializerFactory` and `Api::OpenApi::Base` use it; never inline this logic again.
- **`Api::OpenApi::V2` and `Api::OpenApi::V3`** — OpenAPI path generation lives in `lib/api/open_api/`, not in the info controllers. The info controllers only build the outer spec envelope (server URL, version, security) and call `.new(models, request).generate`.
- `update` and `patch` are the same method. `update_multi` and `destroy_multi` expect comma-separated ids in `params[:ids]`.
- `json_attrs` resolution priority (v2): query param `a`/`json_attrs` > `@json_attrs` instance variable > `@model.json_attrs`.
- OAuth routes are only registered if `ThecoreAuthCommons.oauth_vars?` returns true (i.e., env vars for Google/Microsoft are set). In v3, only `POST /api/v3/auth/jwt` (token exchange) is registered — `callback` and `failure` remain v2-only because OmniAuth middleware is hardcoded to the v2 path. Clients using browser-redirect OAuth initiate at the top-level `/auth/:provider` (no version prefix) which is transparent.
- **v3 explicit controllers** — most v3 resource endpoints are handled by the wildcard route → `Api::V3::ApplicationController`. A model-specific controller (e.g. `Api::V3::UsersController`) is added only when a guard or constraint cannot be expressed through the generic CRUD path. Currently: `UsersController` (self-demotion guard — checks `params.dig("data", "attributes")` for `admin`/`locked` keys, not `params[:user]` as in v2).
- The `Content-Range` header is always set on v2 index responses; frontends that use react-admin or similar expect it.
- The `application/vnd.api+json` MIME type parameter parser is registered with key `:json_api` (Symbol) in `ActionDispatch::Request.parameter_parsers` — not with a `Mime::Type` object (the hash uses Symbol keys, not MIME type objects).
- `ApiExceptionManagement` rescue_from handlers are **production-only**. In test/development, unhandled exceptions propagate as 500s without an error body.
- **`SerializerFactory` caches by class name** — once `Api::V3::RoleSerializer` (or any `<Model>Serializer`) is set in the `Api::V3` namespace it is never regenerated. Changes to `json_attrs` at runtime are not reflected until the process restarts.
- **`SerializerFactory` uses `send`, not `public_send`, for `methods:`** — `thecore_backend_commons` injects private methods (`assets_paths`, `rich_content_html`) into every model. Using `public_send` raises `NoMethodError: private method 'assets_paths' called`. This mirrors Rails `as_json` behaviour.
- **`append_migrations` uses `==`, not `.match`** — the guard in `engine.rb` compares `app.root.to_s == root.to_s`. A substring `.match` would cause the dummy app (a subdirectory of the engine) to falsely match the engine root and skip appending the gem's own migrations.
- **Custom action responses in v3 are plain JSON, not JSON:API envelopes** — the dispatcher serializes via `body.to_json(json_attrs)` before returning; the v3 action renders `json: result` without wrapping in a `{ data: … }` envelope.

## Test infrastructure

The dummy app (`test/dummy/`) isolates the engine from host-app concerns. Its schema is derived from the dependency chain — **never add host-app models or tables to the dummy app**.

- `test/dummy/db/schema.rb` — generated from the dependency chain migrations: `thecore_auth_commons` (users, roles, role_users, permissions chain, ldap_servers), `thecore_settings`, this gem's `used_tokens`, and `active_storage` tables (required because `rails/all` registers ActiveStorage `before_destroy` callbacks on `ActiveRecord::Base`). Regenerate with: `RAILS_ENV=test bundle exec rake db:migrate db:schema:dump` from the engine root.
- `spec/spec_helper.rb` — loads schema via `load`, sets `SECRET_KEY_BASE`, requires `bcrypt`, patches `Ability#initialize` in `before(:suite)` to grant `can :manage, :all`. Permissions tables exist but are empty in tests; without this patch the user would have no abilities.
- `test/dummy/config/application.rb` — stubs `action_mailbox`, `action_mailer`, `action_cable`, `assets` on `Rails::Application::Configuration`; adds dummy autoload paths; stubs `has_rich_text` (see below); pre-requires stub models before engine hooks fire.
- `spec/factories/users.rb` — uses `BCrypt::Password.create(...)` directly (no Devise).
- `spec/factories/roles.rb` — Role factory; `spec/requests/api/v3/roles_spec.rb` is the v3 integration test (26 tests against `Role`, the canonical model from `thecore_auth_commons`).

**`has_rich_text` stub** — the dummy app stubs ActionText's `has_rich_text` macro via an `ActiveSupport.on_load(:active_record)` block. The stub must actually define the named instance method (returning `nil`) so that `rich_content_html` (injected by `thecore_backend_commons`) can call `rich_content` without raising `NoMethodError`. A no-op `def has_rich_text(*); end` is insufficient.

```ruby
# test/dummy/config/application.rb — correct stub
extend(Module.new do
  def has_rich_text(*names)
    names.each { |name| define_method(name) { nil } }
  end
end) unless respond_to?(:has_rich_text)
```
