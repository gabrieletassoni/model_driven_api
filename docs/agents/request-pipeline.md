# Request pipeline, controllers and routes

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (entry point, v2/v3 controllers, v2 Ransack search, routes summary). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

## Entry point

`lib/model_driven_api.rb` — loads all dependencies and requires the engine. The engine (`lib/model_driven_api/engine.rb`) appends the gem's migrations to the host app and registers the `application/vnd.api+json` MIME type with a parameter parser (symbol key `:json_api` in `ActionDispatch::Request.parameter_parsers`).

`pagy` is explicitly `require`d here (alongside `kaminari`). Pagy is not auto-loaded by Bundler because it is needed the moment `Api::V3::ApplicationController` class body is evaluated — before eager loading runs. Removing `require "pagy"` from this file causes `NameError: uninitialized constant Pagy` on any rake task or server boot that loads the application.

`jsonapi/serializer` is required here for the same reason: a host app gets it only transitively, so `Bundler.require` never loads it, and without the explicit require every `/api/v3` request in a host answered 500 `uninitialized constant Api::V3::SerializerFactory::JSONAPI` (until 3.11.4). The dummy app's Gemfile lists it directly, which auto-requires it and hid the bug in this gem's own specs. `spec/lib/self_contained_require_spec.rb` loads the gem in a fresh process, as a host does, and asserts its runtime dependencies are defined — add any new runtime dependency's constant there.

## Controllers (`app/controllers/api/v2/`)

| File | Role |
|---|---|
| `application_controller.rb` | Base controller — auth, model extraction, all CRUD actions |
| `authentication_controller.rb` | `POST /api/v2/authenticate` — email/password → JWT |
| `auth/oauth_controller.rb` | OAuth2 callback + token exchange for Google/Microsoft. `callback` takes the identity only from `request.env['omniauth.auth']` (set by the OmniAuth middleware on `/auth/:provider/callback`, which routes here directly, not via redirect), never from params (Odoo #5837); `exchange_token` asks the provider's userinfo endpoint and only logs in existing users |
| `info_controller.rb` | `/api/v2/info/*` — version, roles, schema, dsl, swagger, openapi, ntp, heartbeat, translations, settings |
| `raw_controller.rb` | `POST /api/v2/raw/sql` — safe SELECT-only SQL executor |

## Controllers (`app/controllers/api/v3/`)

| File | Role |
|---|---|
| `application_controller.rb` | Inherits v2 base — overrides CRUD with JSON:API envelopes, Pagy pagination, `filter[field]` filtering, `sort` ordering |
| `authentication_controller.rb` | Thin subclass of v2 auth controller — provides `POST /api/v3/authenticate` |
| `auth/oauth_controller.rb` | Thin subclass of v2 OAuth controller — exposes only `exchange_token` via `POST /api/v3/auth/jwt` (registered only when `oauth_vars?`); `callback`/`failure` stay v2-only (OmniAuth middleware is hardcoded to v2 path) |
| `info_controller.rb` | Inherits v2 info — overrides only `openapi`/`swagger` to call `Api::OpenApi::V3`; all other info actions inherited unchanged |
| `raw_controller.rb` | `GET/POST /api/v3/raw/sql` — same SELECT-only guard; returns **plain JSON array** (deliberate JSON:API exception) |
| `users_controller.rb` | Thin subclass of v3 application controller — adds `check_demoting` guard on `update`/`patch`/`destroy`; prevents a user from modifying their own `admin` or `locked` flags (same constraint as v2) |

## `Api::V2::ApplicationController` — the core

Every API request goes through `Api::V2::ApplicationController`:

1. `authenticate_request` — resolves `@current_user` via pluggable authorization headers (`Settings.ns(:security).allowed_authorization_headers`) or JWT bearer token. Writes a fresh JWT to the `Token` response header on every successful request (sliding expiration).
2. `extract_model` — resolves `@model` from `params[:ctrl]`, path, or controller name (in that order). Pulls `@body` from singular/plural model param.
3. `find_record` — called only for show/update/destroy; finds by `params[:id]`.
4. CRUD actions (`index`, `show`, `create`, `update`/`patch`, `destroy`, `update_multi`, `destroy_multi`) — all delegate authorization to CanCan (`authorize! :action, @model`).

## `Api::V3::ApplicationController` — JSON:API layer

Inherits from v2; reuses `authenticate_request`, `extract_model`, `find_record`, and all CanCan authorization. Overrides all CRUD actions:

- **`index`** — `filter[field]=value` params (validated against `ransackable_attributes`), `sort=field` / `sort=-field` (comma-separated), Pagy pagination via `page[number]` + `page[size]`. Response: `{ data: […], meta: { total: N } }`.
- **`show`** — `{ data: { id:, type:, attributes: {} } }`.
- **`create`** — reads attributes from `params[:data][:attributes]`. Response: 201 + resource object.
- **`update`/`patch`** — reads attributes from `params[:data][:attributes]`. Response: 200 + resource object.
- **`destroy`** — 204 No Content.

**Sideloading (hybrid)** — default sideloads come from `json_attrs[:include]` keys. The client overrides with `?include=assoc1,assoc2`; passing `?include=` (empty string) suppresses all sideloads. Implemented in `requested_includes` / `default_includes`.

**Sparse fieldsets** — `?fields[type]=field1,field2` narrows the attributes returned per type. Passed to the serializer as `fields: { type: [:field1, :field2] }`. Implemented in `sparse_fields` / `serializer_opts`.

## Ransack-powered search (`index`) — v2 only

`GET /api/v2/:model?q[field_predicate]=value` or `POST /api/v2/:model/search`.  
Pagination via `page` + `per`. Count-only via `count=true`.  
Field selection via `a` or `json_attrs` (mirrors Rails `as_json` DSL: `only`, `except`, `methods`, `include`).

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
