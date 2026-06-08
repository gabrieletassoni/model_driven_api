# PRD: API v3 — JSON:API-compliant auto-generated REST API

## Problem Statement

API consumers working against model_driven_api's v2 API receive plain JSON responses with no standardised envelope. Filtering requires knowledge of Ransack predicate syntax (`?q[title_cont]=foo`), which leaks an internal implementation detail and couples clients to a specific gem's DSL. Pagination metadata is returned in an HTTP header (`Content-Range`) rather than the response body, making it invisible to clients that only inspect the JSON payload. There is no machine-readable contract for response shape, which hampers SDK generation and front-end tooling.

## Solution

API v3 provides a JSON:API-compliant API at `/api/v3/` that auto-generates from the same ActiveRecord Resource introspection as v2, with zero per-model boilerplate. All Resource endpoints return a `{ data: [...] }` envelope. Filtering, sorting, and pagination use the JSON:API-native query parameter conventions. A Serializer Factory generates named serializer classes lazily from each Resource's `json_attrs`, so the single source of truth for field selection is preserved. Auth and authz are shared with v2. The SQL Escape Hatch (`/api/v3/raw/sql`) is a deliberate exception to JSON:API compliance, returning a plain JSON array.

## User Stories

1. As an API consumer, I want GET /api/v3/:resource to return a JSON:API envelope with a `data` array, so that my client can use a standard JSON:API library without custom parsing.
2. As an API consumer, I want each resource object in the `data` array to include `type`, `id`, and `attributes`, so that I can identify and read records without bespoke unpacking.
3. As an API consumer, I want `attributes` to reflect the fields declared in the Resource's `json_attrs`, so that the same field selection policy applies in v2 and v3.
4. As an API consumer, I want GET /api/v3/:resource/:id to return a single JSON:API resource object, so that I can fetch a specific record.
5. As an API consumer, I want POST /api/v3/:resource to accept a JSON:API input (`{ data: { type, attributes } }`) and return the created resource as JSON:API with HTTP 201, so that creation follows the standard contract.
6. As an API consumer, I want PATCH /api/v3/:resource/:id to accept a JSON:API input and return the updated resource as JSON:API with HTTP 200, so that updates follow the standard contract.
7. As an API consumer, I want DELETE /api/v3/:resource/:id to return HTTP 204 No Content, so that deletion is unambiguous.
8. As an API consumer, I want to filter results with `?filter[field]=value` instead of Ransack predicates, so that my client is not coupled to Ransack's syntax.
9. As an API consumer, I want filter fields to be validated against the Resource's `ransackable_attributes` whitelist, so that I cannot probe arbitrary columns.
10. As an API consumer, I want to sort results with `?sort=field` (ascending) and `?sort=-field` (descending), so that I can control result order without bespoke workarounds.
11. As an API consumer, I want to paginate results with `?page[number]=N&page[size]=N`, so that I can retrieve large datasets in chunks.
12. As an API consumer, I want the index response to include a `meta.total` field with the total record count, so that I can render pagination controls without a separate count request.
13. As an API consumer, I want to receive HTTP 401 when I call any v3 endpoint without a valid JWT, so that unauthenticated access is rejected consistently.
14. As an API consumer, I want to receive HTTP 401 when my JWT has expired, so that stale tokens are rejected.
15. As a host app developer, I want to override the generated serializer for a Resource by defining `Api::V3::MyModelSerializer` before the first request, so that I can customise the JSON:API output without forking the engine.
16. As a host app developer, I want the Serializer Factory to memoize generated serializer classes, so that the cost of class generation is paid once per process, not once per request.
17. As a host app developer, I want the engine to register the `application/vnd.api+json` MIME type automatically, so that Rails parses JSON:API request bodies without manual configuration.
18. As a performance-sensitive API consumer, I want GET and POST /api/v3/raw/sql to execute a caller-supplied SELECT query and return a plain JSON array, so that I can bypass the Resource abstraction when ORM-generated SQL is insufficient.
19. As an API consumer calling the SQL Escape Hatch, I want to receive HTTP 400 with a real error message when my query is not a SELECT or is syntactically invalid, so that I can diagnose problems without guessing.
20. As an API consumer calling the SQL Escape Hatch, I want the endpoint to require a valid JWT, so that raw database access is protected.

## Implementation Decisions

- **Serializer Factory** (`Api::V3::SerializerFactory`): a class with a single class method `serializer_for(model_class)`. It checks for an existing constant (`Api::V3::ModelSerializer`) before generating; if found, it returns it (host app override). Otherwise it generates a new class that includes `JSONAPI::Serializer`, calls `set_type` with the plural resource name, and declares attributes from `json_attrs[:only]` (excluding `:id`, which jsonapi-serializer handles separately). The generated class is assigned to a named constant in the `Api::V3` namespace for cacheability.

- **v3 ApplicationController** inherits from `Api::V2::ApplicationController` to reuse authentication, CanCan authz, `extract_model`, `find_record`, and `ApiExceptionManagement`. It overrides all five CRUD actions (`index`, `show`, `create`, `update`/`patch`, `destroy`) to produce JSON:API responses. `update` and `patch` are aliased (same as v2). `destroy` returns `head :no_content` (204) instead of 200.

- **Index action**: applies `filter[field]` params via `where` clauses on validated fields, applies `sort` params as `order` clauses, paginates with Pagy using `page[number]` and `page[size]`, renders via the Serializer Factory with a `meta: { total: pagy.count }` merge.

- **Create/Update input**: JSON:API bodies send attributes under `params[:data][:attributes]`. The v3 ApplicationController extracts these via a private `jsonapi_attributes` method rather than using `@body` (which v2 extracts from the model-name-keyed param).

- **Pagy integration**: `Pagy::Backend` is included in `Api::V3::ApplicationController`. Page number comes from `params.dig("page", "number")`, page size from `params.dig("page", "size")`.

- **Filter validation**: only fields present in `@model.ransackable_attributes` are applied. Unrecognised filter fields are silently ignored (no error — avoids breaking clients when a column is renamed).

- **MIME type registration**: the engine initializer registers `application/vnd.api+json` as `:json_api` and registers a body parser that reuses the standard JSON parser, so Rails automatically populates `request.parameters` from JSON:API request bodies.

- **Routes**: a `namespace :v3` block in `config/routes.rb` mirrors the v2 wildcard CRUD routes plus the raw namespace. v3 does not expose bulk update/destroy or custom action routes in this iteration.

- **SQL Escape Hatch**: already implemented (`Api::V3::RawController`). Skips `extract_model`, inherits auth from `Api::V3::ApplicationController`, returns plain JSON array via `SafeSqlExecutor.execute_select(...).to_a`, surfaces `ArgumentError` and `ActiveRecord::StatementInvalid` as 400s with real messages.

- **`lib/model_driven_api.rb`**: adds `require "api/v3/serializer_factory"` so the factory is available at engine load time.

## Testing Decisions

- **What makes a good test**: tests assert external behaviour (HTTP status, response body shape, database state) and do not test internal methods or private implementation details. The contract is the HTTP interface, not how the controller computes the response.

- **Serializer Factory unit tests** (`spec/lib/api/v3/serializer_factory_spec.rb`): test the public method `Api::V3::SerializerFactory.serializer_for(Model)`. Assert: returns a Class; assigns named constant; memoizes; includes `JSONAPI::Serializer`; serializes into correct envelope; respects `:only`; defers to explicit host-app constant when present.

- **CRUD integration tests** (`spec/requests/api/v3/articles_spec.rb`): drive the full stack through HTTP. Assert: correct status codes; JSON:API envelope structure; attribute presence; pagination meta; filter correctness; sort order; 401 without / with expired token.

- **Prior art**: v2 integration tests in `spec/requests/` (not yet written) and the existing v2 controller provide the pattern. Factories for `Article` and `User` are in `spec/factories/`. Auth header generation is in `spec/support/auth_helpers.rb`.

## Out of Scope

- Bulk update and destroy (`update_multi`, `destroy_multi`) — v2 only for now.
- Custom Actions (`?do=`, `/custom_action/`) — v2 only for now.
- JSON:API `relationships` and `included` compound documents — v3 returns flat attributes only.
- JSON:API `links` (self, pagination links) — `meta.total` is sufficient for the first iteration.
- OpenAPI/Swagger self-generation for v3 (`/api/v3/info/openapi`).
- Info endpoints (`version`, `roles`, `schema`, etc.) under `/api/v3/info/`.
- OAuth endpoints under `/api/v3/auth/`.
- The `json_attrs` per-request override via `?a=` / `?json_attrs=` query params.

## Further Notes

- The `ransackable_attributes` whitelist used for filter validation is provided by the `ModelDrivenApiApplicationRecord` concern already included in host app `ApplicationRecord`. This is the same whitelist that Ransack uses for security in v2 — reuse without exposing the predicate DSL is intentional (ADR 0003).
- Serializer classes do not exist at boot (ADR 0002 consequence). Any code that introspects `ObjectSpace` or eager-loads serializer constants at startup will not find them.
- v3 shares the JWT sliding-expiration behaviour with v2: a fresh `Token` response header is written on every successful authenticated request.
