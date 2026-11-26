# Request pipeline, controllers and routes

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (entry point, v2/v3 controllers, v2 Ransack search, routes summary). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

## Entry point

`lib/model_driven_api.rb` — loads all dependencies and requires the engine. The engine (`lib/model_driven_api/engine.rb`) appends the gem's migrations to the host app and registers the `application/vnd.api+json` MIME type with a parameter parser (symbol key `:json_api` in `ActionDispatch::Request.parameter_parsers`).

`pagy` is explicitly `require`d here (alongside `kaminari`). Pagy is not auto-loaded by Bundler because it is needed the moment `Api::V3::ApplicationController` class body is evaluated — before eager loading runs. Removing `require "pagy"` from this file causes `NameError: uninitialized constant Pagy` on any rake task or server boot that loads the application.

`jsonapi/serializer` is required here for the same reason: a host app gets it only transitively, so `Bundler.require` never loads it, and without the explicit require every `/api/v3` request in a host answered 500 `uninitialized constant Api::V3::SerializerFactory::JSONAPI` (until 3.11.4). The dummy app's Gemfile lists it directly, which auto-requires it and hid the bug in this gem's own specs. `spec/lib/self_contained_require_spec.rb` loads the gem in a fresh process, as a host does, and asserts its runtime dependencies are defined — add any new runtime dependency's constant there. `thecore_auth_commons` (a direct dependency since 3.14.0, for `User#active_for_authentication?`) is required explicitly too, before `thecore_backend_commons`.

## Controllers (`app/controllers/api/v2/`)

| File | Role |
|---|---|
| `application_controller.rb` | Base controller — auth, model extraction, all CRUD actions |
| `authentication_controller.rb` | `POST /api/v2/authenticate` — email/password → JWT |
| `auth/oauth_controller.rb` | OAuth2 callback for Google/Microsoft. `callback` takes the identity only from `request.env['omniauth.auth']` (set by the OmniAuth middleware on `/auth/:provider/callback`, which routes here directly, not via redirect), never from params (Odoo #5837); the token exchange `exchange_token` was removed in 3.15.0 (host Odoo #5860) |
| `info_controller.rb` | `/api/v2/info/*` — version, roles, schema, dsl, swagger, openapi, ntp, heartbeat, translations, settings |
| `raw_controller.rb` | `POST /api/v2/raw/sql` — one plain SELECT through `SafeSqlExecutor` (READ ONLY, limits, errors 400 `{error, reason}`) |

## Controllers (`app/controllers/api/v3/`)

| File | Role |
|---|---|
| `application_controller.rb` | Inherits v2 base — overrides CRUD with JSON:API envelopes, Pagy pagination, `filter[field]` filtering, `sort` ordering |
| `authentication_controller.rb` | Thin subclass of v2 auth controller — provides `POST /api/v3/authenticate` |
| `info_controller.rb` | Inherits v2 info — overrides only `openapi`/`swagger` to call `Api::OpenApi::V3`; all other info actions inherited unchanged |
| `raw_controller.rb` | `GET/POST /api/v3/raw/sql` — same `SafeSqlExecutor`, errors 422/413; returns **plain JSON array** (deliberate JSON:API exception) |
| `users_controller.rb` | Thin subclass of v3 application controller — adds `check_demoting` guard on `update`/`patch`/`destroy`; prevents a user from modifying their own `admin` or `locked` flags (same constraint as v2) |

## `Api::V2::ApplicationController` — the core

Every API request goes through `Api::V2::ApplicationController`:

1. `authenticate_request` — resolves `@current_user` via pluggable authorization headers (`Settings.ns(:security).allowed_authorization_headers`) or JWT bearer token. Writes a fresh JWT to the `Token` response header on every successful request (sliding expiration). A locked user's token is refused (401, no renewal: `docs/agents/jwt-raw-sql-info-openapi.md`).
2. `extract_model` — resolves `@model` from `params[:ctrl]`, path, or controller name (in that order). Pulls `@body` from singular/plural model param.
3. `find_record` — called only for show/update/destroy; finds by `params[:id]`.
4. CRUD actions (`index`, `show`, `create`, `update`/`patch`, `destroy`, `update_multi`, `destroy_multi`) — all delegate authorization to CanCan (`authorize! :action, @model`).

## `Api::V3::ApplicationController` — JSON:API layer

Inherits from v2; reuses `authenticate_request`, `extract_model`, `find_record`, and all CanCan authorization. Overrides all CRUD actions:

- **`index`** — `filter[field]=value` params (validated against `ransackable_attributes`), `sort=field` / `sort=-field` (comma-separated, validated against `ransortable_attributes`; other fields are ignored, host Odoo #6313), Pagy pagination via `page[number]` + `page[size]`. Response: `{ data: […], meta: { total: N } }`.
- **`show`** — `{ data: { id:, type:, attributes: {} } }`.
- **`create`** — reads attributes from `params[:data][:attributes]`. Response: 201 + resource object.
- **`update`/`patch`** — reads attributes from `params[:data][:attributes]`. Response: 200 + resource object.
- **`destroy`** — 204 No Content.

**Sideloading (hybrid)** — default sideloads come from `json_attrs[:include]` keys. The client overrides with `?include=assoc1,assoc2`; passing `?include=` (empty string) suppresses all sideloads. Implemented in `requested_includes` / `default_includes`.

**Sparse fieldsets** — `?fields[type]=field1,field2` narrows the attributes returned per type. Passed to the serializer as `fields: { type: [:field1, :field2] }`. Implemented in `sparse_fields` / `serializer_opts`.

## Ransack-powered search (`index`) — v2 only

`GET /api/v2/:model?q[field_predicate]=value` or `POST /api/v2/:model/search`.  
Pagination via `page` + `per`. Count-only via `count=true`.  
Field selection via `a` or `json_attrs` (mirrors Rails `as_json` DSL: `only`, `except`, `methods`, `include`). Either must be a hash (`?a[only][]=id`): a scalar or an array answers 400 `{"error": "The a parameter must be a hash, e.g. a[only][]=id"}` in every environment, from the `reject_non_hash_json_attrs` before_action, before anything is saved (host Odoo #6258). It runs where `reads_json_attrs?` is true: every custom action plus index, show, create and update/patch in v2 (a plain destroy renders no record), custom actions only in v3. A new action that calls `json_attrs` must be added there. What the client may ask for follows the conventions of `Api::V2::RequestJsonAttrs` (ADR 0006, host Odoo #6285): real associations only, never a hidden attribute, `methods` declared by the model or written in the app/thecore gems and run read-only; refused names are dropped and logged, the response stays 200.

## Routes summary

```
# V2 (plain JSON, Ransack-powered)
POST   /api/v2/authenticate
GET    /api/v2/info/version|roles|heartbeat|ntp|translations|schema|dsl|settings|raw_sql|swagger|openapi
GET    /api/v2/raw/sql
POST   /api/v2/raw/sql
GET    /api/v2/auth/:provider           → triggers OmniAuth
POST   /api/v2/auth/:provider/callback
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
GET    /api/v3/info/version|roles|heartbeat|ntp|translations|schema|dsl|settings|raw_sql|swagger|openapi
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
