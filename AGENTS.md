# AGENTS.md — model_driven_api

Orientation guide for AI agents working in this repository.

## What this codebase is

A Rails engine gem that auto-generates a full REST API at `/api/v2/` by introspecting ActiveRecord models at runtime. No per-model controller or serializer files are needed in the host application. Authorization is delegated to CanCan; authentication is JWT-based with sliding token renewal.

## Repository map

```
app/
  commands/
    authenticate_user.rb       # simple_command: email/password → JWT
    authorize_api_request.rb   # simple_command: JWT header → User
  controllers/api/v2/
    application_controller.rb  # all CRUD logic + auth hooks
    authentication_controller.rb
    auth/oauth_controller.rb   # Google/Microsoft OAuth2
    info_controller.rb         # meta endpoints (schema, openapi, heartbeat …)
    raw_controller.rb          # SELECT-only SQL execution
  models/
    used_token.rb              # token blacklist (ALLOW_MULTISESSIONS=false)
    test_api.rb                # test model (not a real AR model)
    endpoints/test_api.rb      # example NonCrudEndpoints subclass
config/
  routes.rb                    # all /api/v2/* routes
  initializers/
    after_initialize_for_model_driven_api.rb
    cors_api_thecore.rb        # rack-cors setup
    knock.rb                   # (legacy) token config
    auto_include_json.rb
    wrap_parameters.rb
    time_with_zone.rb
lib/
  model_driven_api.rb          # gem entrypoint, requires everything
  model_driven_api/
    engine.rb                  # Rails::Engine, appends migrations
    version.rb                 # VERSION constant
  json_web_token.rb            # JWT encode/decode
  safe_sql_executor.rb         # SELECT-only SQL guard
  non_crud_endpoints.rb        # base class for Endpoints::* modules
  endpoint_validation_error.rb
  concerns/
    api_exception_management.rb       # rescue_from helpers
    model_driven_api_application_record.rb  # ransackable_* methods
    model_driven_api_user.rb          # User concern (json_attrs, used_tokens)
    model_driven_api_role.rb          # Role concern (json_attrs)
db/migrate/                    # used_tokens table migrations
```

## How the request pipeline works

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

## Where to add things

| Task | Where |
|---|---|
| Add a CRUD endpoint for a new model | Include `ModelDrivenApiApplicationRecord` in `ApplicationRecord` — the engine picks it up automatically |
| Override JSON shape for a model | Define `cattr_accessor :json_attrs; self.json_attrs = { only: […] }` on the model, or use `ModelDrivenApi.smart_merge` with a concern |
| Add a custom action (simple) | Class method `def self.custom_action_foo(params)` on the model |
| Add a custom action (with OpenAPI docs) | Subclass `NonCrudEndpoints` as `Endpoints::MyModel`, register with `self.desc`, define instance method |
| Add a new auth header type | Implement a `simple_command` class named `Authorize<HeaderName>`, register its name in `Settings.ns(:security).allowed_authorization_headers` |
| Restrict/expand CORS | `config/initializers/cors_api_thecore.rb` |

## Critical constraints

- **Do not use strong parameters** — `params` is overridden to `request.parameters`. All params are open by design; authorization is enforced by CanCan at the action level.
- **Do not call `$(...).modal()`** (not a frontend project, but noted for consistency with host app).
- **`update` and `patch` are the same method** — aliased. Do not add separate logic without aliasing it too.
- **OAuth routes are conditional** — gated on `ThecoreAuthCommons.oauth_vars?`. Never assume they are present.
- **Token blacklisting is opt-in** — only active when `ALLOW_MULTISESSIONS=false`. Code that touches `UsedToken` must not break when `ALLOW_MULTISESSIONS` is unset or `"true"`.
- **`SafeSqlExecutor` is SELECT-only** — it validates and raises `ArgumentError` on anything else. Never bypass it for the raw SQL endpoint.
- **`json_attrs` deep-merge, not replace** — always use `ModelDrivenApi.smart_merge(existing, additions)` when composing `json_attrs` across concerns; plain `merge` or `=` will silently drop fields from other concerns.

## Patterns to recognise

### NonCrudEndpoints pattern

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

### Custom action via class method

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

Tests live in `test/` (Minitest) and `spec/` (RSpec). The RSpec suite is preferred for new tests. Use `bundle exec rspec` from the submodule root.
