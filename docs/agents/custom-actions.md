# Custom actions

> Moved verbatim from `CLAUDE.md` on 2026-11-11 (custom actions in v2 and v3, public actions, PushSubscriber custom endpoints). `CLAUDE.md` points here; keep this file accurate whenever the behaviour it describes changes.

## Custom actions — v2 and v3

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
`ApplicationController#authenticate_request` checks `NonCrudEndpoints.public_action?(model, action)` and skips token validation for registered public actions. The `Endpoints::<Model>` class is force-loaded (via `constantize`) in `public_custom_action?` before the check so declarations are visible even on first request. That runs before authentication on a path segment; it is safe because ActiveSupport's `constantize` never falls back to a top-level constant, so `Endpoints::String` is a `NameError`. `config/brakeman.ignore` records Brakeman's High `UnsafeReflection` there as a false positive for this reason. CanCan authorization is also skipped for public actions. `params[:current_user_id]` is nil for these calls — do not call `User.find(params[:current_user_id])` in a public action.

## PushSubscriber custom endpoints (`app/models/endpoints/push_subscriber.rb`)

| Endpoint | Description |
|---|---|
| `GET vapid_public_key` | Public — returns VAPID public key |
| `POST subscribe` | Registers/updates a `PushSubscriber` for the current user |
| `POST send_push` | Creates and dispatches push notification(s). Accepts `push_subscriber_id` (single, sync dispatch) or `push_subscriber_ids` array (bulk, async via `PushDispatchJob`). Bulk uses `insert_all` for performance and enqueues one `PushDispatchJob` per valid subscriber. Response: single → `PushMessage` JSON; bulk → `{ created: [...], failed: [...invalid_ids] }`. |
| `POST broadcast_push` | Sends same push to **all** active subscribers (`expired_at IS NULL`). Uses `insert_all` + one `PushDispatchJob` per subscriber (async). Optional params: `message_type` (default `"communication"`), `url`, `icon`. `sender_user_id` set from `current_user_id`. Response: `{ enqueued: N }`. |
| `POST acknowledge` | Marks a `PushMessage` as `received_at` / `read_at` |

**Serialization note**: `send_push` and `acknowledge` pre-serialize the response with `PushMessage.json_attrs` (not `PushSubscriber.json_attrs`) to avoid `NoMethodError` on `user` — `PushMessage` has `sender`, not `user`.
