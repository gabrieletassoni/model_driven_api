# v3 model-specific controllers exist only when the wildcard cannot express a constraint

API v3 routes all Resource CRUD through a single wildcard (`*path`) that dispatches to `Api::V3::ApplicationController`. This is intentional — the engine's value proposition is zero per-model boilerplate. A model-specific controller in v3 is justified only when a guard or constraint cannot be expressed through the generic CRUD path.

The first case that met this bar: `Api::V3::UsersController`, which adds a `check_demoting` guard preventing a user from modifying their own `admin` or `locked` flags via PATCH. Without an explicit controller and a matching `resources :users` route, the wildcard delivers requests to the generic controller and the guard is silently bypassed — a security hole rather than a missing feature.

The guard implementation differs from its v2 counterpart: v2 checks `params[:user].keys` (plain JSON body keyed by model name); v3 checks `params.dig("data", "attributes")` (JSON:API body).

## Considered Options

- **Generic wildcard only** — rejected for any constraint that is security-relevant; the wildcard has no hook for per-model `before_action` guards.
- **Explicit controller + `resources` route for every model** — rejected; eliminates the zero-boilerplate guarantee and creates maintenance overhead for models that need no overrides.
- **Explicit controller only when a guard is needed** — chosen; preserves the zero-boilerplate default while allowing targeted overrides. The `resources` route must be placed before the wildcard in `config/routes.rb` so it takes precedence.

## Consequences

When adding a new model-specific constraint in v3: create `app/controllers/api/v3/<model>_controller.rb` inheriting from `Api::V3::ApplicationController`, add the guard as a `before_action`, and register `resources :<model>` in the v3 namespace before the wildcard routes. Do not add the controller without the explicit route — the wildcard will shadow it.

OAuth token exchange (`POST /api/v3/auth/jwt`) follows the same principle for a different reason: `Api::V3::Auth::OauthController` is a thin subclass of its v2 counterpart, exposing only `exchange_token`. The OmniAuth `callback` and `failure` actions are intentionally absent from v3 routes — the OmniAuth middleware is hardcoded to redirect to the v2 path, and duplicating those routes in v3 would require either forking the middleware registration or accepting that the callback always lands in v2 regardless of which version initiated the flow. Clients using browser-redirect OAuth initiate at the top-level `/auth/:provider` (no version prefix), making the v2 landing transparent.
