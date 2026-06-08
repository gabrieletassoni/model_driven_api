## [Unreleased]

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
