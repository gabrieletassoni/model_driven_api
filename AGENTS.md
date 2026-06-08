# AGENTS.md — model_driven_api

Orientation guide for AI agents working in this repository.

## What this codebase is

A Rails engine gem that auto-generates a full REST API at `/api/v2/` (plain JSON, Ransack-powered) and `/api/v3/` (JSON:API-compliant) by introspecting ActiveRecord models at runtime. No per-model controller or serializer files are needed in the host application. Authorization is delegated to CanCan; authentication is JWT-based with sliding token renewal.

## Repository map

```
app/
  commands/
    authenticate_user.rb          # simple_command: email/password → JWT
    authorize_api_request.rb      # simple_command: JWT header → User
  controllers/api/v2/
    application_controller.rb     # all CRUD logic + auth hooks (plain JSON)
    authentication_controller.rb
    auth/oauth_controller.rb      # Google/Microsoft OAuth2
    info_controller.rb            # meta endpoints (schema, openapi, heartbeat …)
    raw_controller.rb             # SELECT-only SQL; returns { result: … }
  controllers/api/v3/
    application_controller.rb     # JSON:API CRUD; inherits v2 auth + model extraction
    raw_controller.rb             # SELECT-only SQL; returns plain JSON array
config/
  routes.rb                       # /api/v2/* and /api/v3/* routes
  initializers/
    after_initialize_for_model_driven_api.rb
    cors_api_thecore.rb           # rack-cors setup
    auto_include_json.rb
    wrap_parameters.rb
    time_with_zone.rb
lib/
  model_driven_api.rb             # gem entrypoint, requires everything
  model_driven_api/
    engine.rb                     # Rails::Engine; appends migrations;
                                  # registers :json_api MIME type + parser
    version.rb                    # VERSION constant
  api/v3/
    serializer_factory.rb         # lazy JSONAPI::Serializer generation from json_attrs
  json_web_token.rb               # JWT encode/decode
  safe_sql_executor.rb            # SELECT-only SQL guard
  non_crud_endpoints.rb           # base class for Endpoints::* modules
  endpoint_validation_error.rb
  concerns/
    api_exception_management.rb          # rescue_from helpers (production only)
    model_driven_api_application_record.rb  # ransackable_* methods
    model_driven_api_user.rb             # User concern (json_attrs, used_tokens)
    model_driven_api_role.rb             # Role concern (json_attrs)
db/migrate/                       # used_tokens table migrations
docs/
  adr/
    0001-jsonapi-serializer.md    # JSON:API envelope choice
    0002-serializer-factory.md    # lazy serializer generation
    0003-jsonapi-query-params.md  # filter/sort/page over Ransack predicates
    0004-v3-raw-sql-returns-plain-json.md  # plain JSON exception for SQL endpoint
  prd-api-v3.md                   # full PRD for v3
```

## How the v2 request pipeline works

```
Request
  └─ authenticate_request       resolves @current_user from JWT or custom headers
  └─ extract_model              resolves @model from URL segment, sets @body
  └─ find_record (show/update/destroy only)  @record = @model.find(id)
  └─ action (index/show/create/update/destroy …)
       └─ authorize! via CanCan
       └─ check_for_custom_action  (if ?do= or /custom_action/ in URL)
       └─ Ransack query (index)
       └─ render json: …, status: …
  └─ response.set_header("Token", fresh_jwt)   sliding expiration
```

## How the v3 request pipeline works

```
Request
  └─ authenticate_request       (inherited from v2)
  └─ extract_model              (inherited from v2)
  └─ find_record (show/update/destroy only)  (inherited from v2)
  └─ action (index/show/create/update/destroy)
       └─ authorize! via CanCan
       └─ apply_filters (filter[field]=value, validated against ransackable_attributes)
       └─ apply_sorting (sort=field / sort=-field, comma-separated)
       └─ pagy(scope, page: N, limit: N)      Pagy 9 pagination
       └─ serializer_opts builds include: + fields: from request params
            └─ requested_includes: ?include= overrides json_attrs[:include] keys (hybrid sideloading)
            └─ sparse_fields:      ?fields[type]=f1,f2 → { type: [:f1, :f2] }
       └─ SerializerFactory.serializer_for(@model).new(records, **serializer_opts).serializable_hash
       └─ render json: { data: …, meta: { total: N } }, status: …
  └─ response.set_header("Token", fresh_jwt)   (inherited from v2)
```

## Where to add things

| Task | Where |
|---|---|
| Add a CRUD endpoint for a new model | Include `ModelDrivenApiApplicationRecord` in `ApplicationRecord` — the engine picks it up automatically for both v2 and v3 |
| Override JSON shape for a model (v2) | Define `cattr_accessor :json_attrs; self.json_attrs = { only: […] }` on the model, or use `ModelDrivenApi.smart_merge` with a concern |
| Override JSON:API attributes (v3) | Same `json_attrs[:only]` — `SerializerFactory` reads it at first request and caches the serializer class |
| Add a custom action (simple) | Class method `def self.custom_action_foo(params)` on the model — v2 only |
| Add a custom action (with OpenAPI docs) | Subclass `NonCrudEndpoints` as `Endpoints::MyModel` — v2 only |
| Add a new auth header type | Implement a `simple_command` class named `Authorize<HeaderName>`, register its name in `Settings.ns(:security).allowed_authorization_headers` |
| Restrict/expand CORS | `config/initializers/cors_api_thecore.rb` |

## Critical constraints

- **Do not use strong parameters** — `params` is overridden to `request.parameters`. All params are open by design; authorization is enforced by CanCan at the action level.
- **`update` and `patch` are the same method** — aliased. Do not add separate logic without aliasing it too.
- **OAuth routes are conditional** — gated on `ThecoreAuthCommons.oauth_vars?`. Never assume they are present.
- **Token blacklisting is opt-in** — only active when `ALLOW_MULTISESSIONS=false`. Code that touches `UsedToken` must not break when `ALLOW_MULTISESSIONS` is unset or `"true"`.
- **`SafeSqlExecutor` is SELECT-only** — it validates and raises `ArgumentError` on anything else. Never bypass it for the raw SQL endpoint.
- **`json_attrs` deep-merge, not replace** — always use `ModelDrivenApi.smart_merge(existing, additions)` when composing `json_attrs` across concerns; plain `merge` or `=` will silently drop fields from other concerns.
- **`SerializerFactory` caches by class name** — once `Api::V3::RoleSerializer` (or any `<Model>Serializer`) is set in the `Api::V3` namespace it is never regenerated. Changes to `json_attrs` at runtime are not reflected until the process restarts.
- **`SerializerFactory` handles both `only:` and `except:`** — when `json_attrs[:only]` is absent, attributes are derived from `column_names - json_attrs[:except]`. Do not assume `only:` is always set; `ModelDrivenApiRole` and `ModelDrivenApiUser` use `except:`.
- **`append_migrations` uses `==`, not `.match`** — `engine.rb` guards with `app.root.to_s == root.to_s`. A substring `.match` caused the dummy app (a subdirectory of the engine) to skip appending the gem's own migrations.
- **`ApiExceptionManagement` is production-only** — `rescue_from` handlers only register when `Rails.env.production?`. In test and development, exceptions propagate as 500s without an error body.
- **MIME type parser key is a Symbol** — `ActionDispatch::Request.parameter_parsers[:json_api]` (not `Mime[:json_api]`). The hash uses Symbol keys, not Mime::Type objects.
- **v3 raw SQL returns plain JSON** — no `result` key required, no JSON:API envelope. This is a deliberate exception to JSON:API compliance (ADR 0004).

## Patterns to recognise

### SerializerFactory (v3)

```ruby
serializer = Api::V3::SerializerFactory.serializer_for(Role)
hash = serializer.new(records, include: [:users], fields: { roles: [:name] }).serializable_hash
# { data: [{ id: "1", type: "roles", attributes: { name: "Admin" }, relationships: { users: … } }],
#   included: [{ id: "2", type: "users" }] }
```

The factory reads `json_attrs` once and generates a class that includes `JSONAPI::Serializer`:
- `only:` → column attributes directly; absent → `column_names - except:`
- `methods:` → block-form `attribute` using `object.send(method_name)` — **`send`, not `public_send`** (private methods like `assets_paths` injected by `thecore_backend_commons`)
- `include:` → nested serializer per association, registered with the correct macro from `reflect_on_all_associations`; nested serializers are flat (no recursive sideloads)

Nested serializers are cached as `<AssocModel>For<ParentModel>Serializer`. The factory never regenerates a constant once set.

### NonCrudEndpoints pattern (v2)

```ruby
class Endpoints::MyModel < NonCrudEndpoints
  self.desc 'MyModel', :my_action, {
    get: { summary: "…", tags: ["MyModel"], responses: { 200 => {…} } }
  }

  def my_action(params)
    [{ key: "value" }, 200]
  end
end
```

`NonCrudEndpoints#initialize` calls `validate_request` then dispatches to the named instance method. The `result` attribute holds the return value. The controller reads `result` after instantiation.

### Custom action via class method (v2)

```ruby
class MyModel < ApplicationRecord
  def self.custom_action_report(params)
    [{ total: count }, 200]
  end
end
```

Called at `GET /api/v2/my_models?do=report`.

### json_attrs concern composition

```ruby
module Concerns::Api::MyModel
  extend ActiveSupport::Concern
  included do
    cattr_accessor :json_attrs
    self.json_attrs = ModelDrivenApi.smart_merge((json_attrs || {}), {
      only: [:id, :name, :status],
      methods: [:computed_field],
      include: { items: { only: [:id, :code] } }
    })
  end
end
```

## Environment variables

| Variable | Default | Effect |
|---|---|---|
| `SESSION_TIMEOUT_IN_MINUTES` | `31` | JWT expiry window |
| `SECRET_KEY_BASE` | (from Rails credentials) | JWT signing key |
| `ALLOW_MULTISESSIONS` | `"true"` | `"false"` enables token blacklisting via `used_tokens` |
| `ENTRA_CLIENT_ID/SECRET/TENANT_ID` | — | Enables Microsoft OAuth routes |
| `GOOGLE_CLIENT_ID/SECRET` | — | Enables Google OAuth routes |
| `RAILS_RELATIVE_URL_ROOT` | `/` | Scope prefix for all routes |

## Testing

Tests live in `spec/` (RSpec preferred). Run `bundle exec rspec` from the submodule root.

Key spec locations:
- `spec/lib/api/v3/serializer_factory_spec.rb` — 17 unit tests for `SerializerFactory` (only:, except:, methods:, include:, nested serializers, memoization, host-app override)
- `spec/requests/api/v3/roles_spec.rb` — 26 integration tests for the full v3 CRUD + auth stack: index/show/create/patch/delete, pagination, filtering, sorting, sparse fieldsets, hybrid sideloading

### Test infrastructure gotchas

- **Schema is generated, not hand-maintained.** `test/dummy/db/schema.rb` is derived from the dependency chain migrations (`thecore_auth_commons`, `thecore_settings`, `model_driven_api`, `active_storage`). Regenerate with `RAILS_ENV=test bundle exec rake db:migrate db:schema:dump`. Never add host-app models (e.g. `Article`, `Plant`) to the dummy app; use models from the dependency chain (`Role`, `User`).
- `spec/spec_helper.rb` `before(:suite)` re-overrides `Ability#initialize` to grant `can :manage, :all`. The permissions tables exist but are empty; without this patch `ThecoreAuthCommonsCanCanCanConcern` would resolve zero abilities for every user.
- The `application/vnd.api+json` body parser must be tested via `params: payload.to_json` with `"Content-Type" => "application/vnd.api+json"` headers — RSpec request specs honour this.
