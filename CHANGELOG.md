## [Unreleased]

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
