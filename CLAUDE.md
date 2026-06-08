# CLAUDE.md — model_driven_api

This is a Rails engine gem (`model_driven_api`) that auto-generates a versioned REST API at `/api/v2/` by introspecting ActiveRecord models at runtime. It lives as a git submodule inside a parent Thecore application.

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

`lib/model_driven_api.rb` — loads all dependencies and requires the engine. The engine (`lib/model_driven_api/engine.rb`) appends the gem's migrations to the host app.

### Controllers (`app/controllers/api/v2/`)

| File | Role |
|---|---|
| `application_controller.rb` | Base controller — auth, model extraction, all CRUD actions |
| `authentication_controller.rb` | `POST /api/v2/authenticate` — email/password → JWT |
| `auth/oauth_controller.rb` | OAuth2 callback + token exchange for Google/Microsoft |
| `info_controller.rb` | `/api/v2/info/*` — version, roles, schema, dsl, swagger, openapi, ntp, heartbeat, translations, settings |
| `raw_controller.rb` | `POST /api/v2/raw/sql` — safe SELECT-only SQL executor |

### `ApplicationController` — the core

Every API request goes through `Api::V2::ApplicationController`:

1. `authenticate_request` — resolves `@current_user` via pluggable authorization headers (`Settings.ns(:security).allowed_authorization_headers`) or JWT bearer token. Writes a fresh JWT to the `Token` response header on every successful request (sliding expiration).
2. `extract_model` — resolves `@model` from `params[:ctrl]`, path, or controller name (in that order). Pulls `@body` from singular/plural model param.
3. `find_record` — called only for show/update/destroy; finds by `params[:id]`.
4. CRUD actions (`index`, `show`, `create`, `update`/`patch`, `destroy`, `update_multi`, `destroy_multi`) — all delegate authorization to CanCan (`authorize! :action, @model`).

### Ransack-powered search (`index`)

`GET /api/v2/:model?q[field_predicate]=value` or `POST /api/v2/:model/search`.  
Pagination via `page` + `per`. Count-only via `count=true`.  
Field selection via `a` or `json_attrs` (mirrors Rails `as_json` DSL: `only`, `except`, `methods`, `include`).

### Custom actions

Two patterns are supported, checked in `check_for_custom_action`:

**Pattern 1 — class method on the model:**
```ruby
def self.custom_action_my_action(params)
  [{ result: "ok" }, 200]
end
```
Called via `GET /api/v2/my_model?do=my_action` or `GET /api/v2/my_model/:id?do=my_action`.

**Pattern 2 — `NonCrudEndpoints` subclass:**
```ruby
class Endpoints::MyModel < NonCrudEndpoints
  self.desc 'MyModel', :my_action, { get: { ... openapi schema ... } }
  def my_action(params)
    [{ result: "ok" }, 200]
  end
end
```
Called via `GET /api/v2/my_model/custom_action/my_action` or with `/:id`.

Place endpoint files in `app/models/endpoints/model_name.rb` in the host app.

### Concerns to include in host models

| Concern | Include in | Purpose |
|---|---|---|
| `ModelDrivenApiApplicationRecord` | `ApplicationRecord` | Enables `ransackable_attributes` / `ransackable_associations` |
| `ModelDrivenApiUser` | `User` | Adds `has_many :used_tokens`, default `json_attrs` |
| `ModelDrivenApiRole` | `Role` | Adds default `json_attrs` |

### JSON serialisation DSL (`json_attrs`)

Each model exposes `self.json_attrs` as a class-level hash with the standard Rails `as_json` keys: `:only`, `:except`, `:methods`, `:include`. The engine reads this in every CRUD response. Clients can override it per-request via the `a` or `json_attrs` query parameter.

Use `ModelDrivenApi.smart_merge(existing, additions)` when composing `json_attrs` across concerns — it does a deep merge that extends arrays rather than replacing them.

### JWT / token management (`lib/json_web_token.rb`)

- Expiry controlled by `SESSION_TIMEOUT_IN_MINUTES` env var (default 31 minutes).
- Secret from `Rails.application.credentials.secret_key_base` or `SECRET_KEY_BASE` env var.
- When `ALLOW_MULTISESSIONS=false`, every login invalidates previous tokens via `UsedToken` table. Tokens are stored and checked against `used_tokens` on each decode.

### Safe SQL executor (`lib/safe_sql_executor.rb`)

`SafeSqlExecutor.execute_select(query)` — validates that the query is a `SELECT` (or `WITH ... SELECT`), then executes. Only SELECT is allowed; DDL/DML raise `ArgumentError`. The query must return a `result` key (typically via `json_agg`).

### OpenAPI / Swagger self-generation

`GET /api/v2/info/openapi` (alias `/swagger`) generates a full OpenAPI 3.0 spec dynamically from:
- All `ApplicationRecord` subclasses (CRUD + search + custom action paths)
- `NonCrudEndpoints` definitions registered via `self.desc`

This endpoint does not require authentication.

## Routes summary

```
POST   /api/v2/authenticate
GET    /api/v2/info/version|roles|heartbeat|ntp|translations|schema|dsl|settings|swagger|openapi
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
```

## Key invariants and gotchas

- `params` is overridden to `request.parameters` — strong parameters are bypassed intentionally. Do not use `params.require(...).permit(...)` patterns.
- `extract_model` returns 404 for non-ActiveRecord models (except `TestApi`). If you need a model-less endpoint, use `skip_before_action :extract_model` in a subclass or use a root action in the host app.
- `update` and `patch` are the same method. `update_multi` and `destroy_multi` expect comma-separated ids in `params[:ids]`.
- `json_attrs` resolution priority: query param `a`/`json_attrs` > `@json_attrs` instance variable > `@model.json_attrs`.
- OAuth routes are only registered if `ThecoreAuthCommons.oauth_vars?` returns true (i.e., env vars for Google/Microsoft are set).
- The `Content-Range` header is always set on index responses; frontends that use react-admin or similar expect it.
